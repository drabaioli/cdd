#!/usr/bin/env bash
# Render-then-diff drift check between the CDD repo's own .claude/commands/,
# .claude/agents/ and .claude/settings.json and the template/.claude/ copies it ships.
#
# The template is rendered via tools/bootstrap-cdd-project.sh --stage with this repo's own
# identifier (dir "cdd"), so expected substitution drift cancels out mechanically
# and only real divergence survives. Remaining divergence is a defect unless:
#   - the file is listed in scripts/command-drift-whitelist.txt (one-sided by design;
#     command and agent entries match by basename), or
#   - the diverging region in the repo copy sits between `<!-- cdd-only-begin -->` and
#     `<!-- cdd-only-end -->` lines (CDD-meta content), which are stripped before the
#     comparison.
#
# Also asserts:
#   - the handoff schema block is identical, line for line, between the process doc
#     (section 2.6) and .claude/commands/cdd-next-step.md; the template copy of
#     cdd-next-step.md is already covered by the render-diff.
#   - the plan-file schema block is identical between the process doc (section 2.15) and
#     .claude/commands/cdd-plan.md, the same way. Both carry the schema, so either can
#     drift from the other; the seam checker only pins cdd-plan.md against cdd-implement.md.
#   - no cdd-only markers appear in template/.claude/commands/ or template/.claude/agents/
#     — they belong in the repo copies only; a marker in the template would be
#     stripped from both sides of the comparison above and hide real drift.
#   - no file under template/ hardcodes this repo's handoff directory (handoffs/cdd):
#     rendered with dir "cdd", it is indistinguishable from handoffs/<PROJECT_DIR>.
#   - .claude/settings.json matches the rendered template/.claude/settings.json.
#     JSON has no cdd-only fence, so a deliberately CDD-only settings entry needs a
#     scripts/command-drift-whitelist.txt line (.claude/settings.json) instead.
#   - both settings.json files parse as JSON (requires jq) — the template's copy
#     is generated into every bootstrapped project, so a syntax error ships silently.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WHITELIST="scripts/command-drift-whitelist.txt"
REPO_CMDS=".claude/commands"
PROCESS_DOC="doc/knowledge_base/claude-driven-development.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

./tools/bootstrap-cdd-project.sh --stage --name "CDD" --dir cdd \
  --path "$TMP/render" >/dev/null

whitelisted() {
  grep -v '^[[:space:]]*#' "$WHITELIST" | grep -v '^[[:space:]]*$' | grep -qxF "$1"
}

strip_cdd_only() {
  sed '/<!-- cdd-only-begin -->/,/<!-- cdd-only-end -->/d' "$1"
}

fail=0

# Commands and agent definitions get the same treatment. A directory missing on one
# side reads as empty, so every file on the other side is reported as one-sided.
for sub in commands agents; do
  repo_dir=".claude/$sub"
  rendered_dir="$TMP/render/.claude/$sub"
  mapfile -t names < <(
    { ls -1 "$repo_dir" 2>/dev/null; ls -1 "$rendered_dir" 2>/dev/null; } | sort -u
  )

  for name in "${names[@]}"; do
    if whitelisted "$name"; then
      continue
    fi
    repo_f="$repo_dir/$name"
    rendered_f="$rendered_dir/$name"
    if [[ ! -f "$repo_f" ]]; then
      echo "DRIFT: $name exists only in template/.claude/$sub/" >&2
      fail=1
      continue
    fi
    if [[ ! -f "$rendered_f" ]]; then
      echo "DRIFT: $name exists only in .claude/$sub/" >&2
      fail=1
      continue
    fi
    if ! diff -u \
        --label "$repo_dir/$name (cdd-only sections stripped)" \
        --label "template/.claude/$sub/$name (rendered)" \
        <(strip_cdd_only "$repo_f") <(strip_cdd_only "$rendered_f"); then
      fail=1
    fi
  done
done

# The shipped settings file must parse: it is generated into every bootstrapped project,
# where a stray comma silently costs the project its permissions. It needs jq, and a
# missing tool is a failure, never a skip (scripts/ci.sh).
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to validate the settings JSON and is not installed" >&2
  fail=1
else
  for f in .claude/settings.json template/.claude/settings.json; do
    if ! jq empty "$f" 2>&1; then
      echo "ERROR: $f is not valid JSON (see above)" >&2
      fail=1
    fi
  done
fi

# The shipped settings file: same render-then-diff, minus the cdd-only fence, which JSON
# cannot carry. A CDD-only entry would therefore need a whitelist line for the whole file.
if ! whitelisted ".claude/settings.json"; then
  if ! diff -u \
      --label ".claude/settings.json" \
      --label "template/.claude/settings.json (rendered)" \
      .claude/settings.json "$TMP/render/.claude/settings.json"; then
    fail=1
  fi
fi

# cdd-only fences belong in the repo copies only; strip_cdd_only runs on both sides,
# so a marker in the template would silently hide the fenced content from the diff.
for sub in commands agents; do
  [[ -d "template/.claude/$sub" ]] || continue
  if grep -rnE 'cdd-only-(begin|end)' "template/.claude/$sub/" >&2; then
    echo "ERROR: cdd-only markers found in template/.claude/$sub/ (see above); they belong in the repo copies only" >&2
    fail=1
  fi
done

# The render above uses this repo's own dir, `cdd`, so a template line that hardcodes
# `handoffs/cdd` where it should say `handoffs/<PROJECT_DIR>` renders identically and
# slips past every diff. Scan the template itself for this repo's handoff directory.
if grep -rnE 'handoffs/cdd([^A-Za-z0-9_-]|$)' template/ >&2; then
  echo "ERROR: this repo's handoff directory (handoffs/cdd) is hardcoded in template/ (see above); use handoffs/<PROJECT_DIR>" >&2
  fail=1
fi

# Schema consistency: print a schema block whole, from its marker line (`# Task:` or
# `# Plan:`) to the end of its fenced code block, and compare. Whole, not just its
# headings: a placeholder line drifts as easily as a heading does.
schema_block() {  # schema_block <marker> <file>
  awk -v marker="$1" 'index($0, marker) == 1 { in_schema = 1 }
       in_schema && /^```/ { exit }
       in_schema { print }' "$2"
}

doc_schema="$(schema_block '# Task:' "$PROCESS_DOC")"
cmd_schema="$(schema_block '# Task:' "$REPO_CMDS/cdd-next-step.md")"
if [[ -z "$doc_schema" ]]; then
  echo "ERROR: could not locate the handoff schema block in $PROCESS_DOC" >&2
  fail=1
elif [[ "$doc_schema" != "$cmd_schema" ]]; then
  echo "DRIFT: handoff schema block differs between $PROCESS_DOC and $REPO_CMDS/cdd-next-step.md" >&2
  diff <(printf '%s\n' "$doc_schema") <(printf '%s\n' "$cmd_schema") >&2 || true
  fail=1
fi

# Plan-file-schema consistency: the same shape, keyed on the "# Plan:" line. The seam
# checker (check 7) pins the producer against its consumer; this pins the producer
# against the process doc, which documents the same schema and can drift from it.
doc_plan="$(schema_block '# Plan:' "$PROCESS_DOC")"
cmd_plan="$(schema_block '# Plan:' "$REPO_CMDS/cdd-plan.md")"
if [[ -z "$doc_plan" ]]; then
  echo "ERROR: could not locate the plan-file schema block in $PROCESS_DOC" >&2
  fail=1
elif [[ "$doc_plan" != "$cmd_plan" ]]; then
  echo "DRIFT: plan-file schema block differs between $PROCESS_DOC and $REPO_CMDS/cdd-plan.md" >&2
  diff <(printf '%s\n' "$doc_plan") <(printf '%s\n' "$cmd_plan") >&2 || true
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "command-set drift detected" >&2
  exit 1
fi
echo "command-set drift: clean"
