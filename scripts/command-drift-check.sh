#!/usr/bin/env bash
# Render-then-diff drift check between the CDD repo's own .claude/commands/ and
# .claude/settings.json and the template/.claude/ copies it ships.
#
# The template is rendered via tools/bootstrap-cdd-project.sh --stage with this repo's own
# identifier (dir "cdd"), so expected substitution drift cancels out mechanically
# and only real divergence survives. Remaining divergence is a defect unless:
#   - the file is listed in scripts/command-drift-whitelist.txt (one-sided by design), or
#   - the diverging region in the repo copy sits between `<!-- cdd-only-begin -->` and
#     `<!-- cdd-only-end -->` lines (CDD-meta content), which are stripped before the
#     comparison.
#
# Also asserts:
#   - the handoff schema headings match between the process doc (section 2.6) and
#     .claude/commands/cdd-next-step.md; the template copy of cdd-next-step.md is already
#     covered by the render-diff.
#   - the plan-file schema headings match between the process doc (section 2.15) and
#     .claude/commands/cdd-plan.md, the same way. Both carry the schema, so either can
#     drift from the other; the seam checker only pins cdd-plan.md against cdd-implement.md.
#   - no cdd-only markers appear in template/.claude/commands/ — they belong in the
#     repo copies only; a marker in the template would be stripped from both sides
#     of the comparison above and hide real drift.
#   - .claude/settings.json matches the rendered template/.claude/settings.json.
#     JSON has no cdd-only fence, so a deliberately CDD-only settings entry needs a
#     scripts/command-drift-whitelist.txt line (.claude/settings.json) instead.
#   - both settings.json files parse as JSON (when jq is present) — the template's copy
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
RENDERED_CMDS="$TMP/render/.claude/commands"

whitelisted() {
  grep -v '^[[:space:]]*#' "$WHITELIST" | grep -v '^[[:space:]]*$' | grep -qxF "$1"
}

strip_cdd_only() {
  sed '/<!-- cdd-only-begin -->/,/<!-- cdd-only-end -->/d' "$1"
}

fail=0

mapfile -t names < <(
  { ls -1 "$REPO_CMDS"; ls -1 "$RENDERED_CMDS"; } | sort -u
)

for name in "${names[@]}"; do
  if whitelisted "$name"; then
    continue
  fi
  repo_f="$REPO_CMDS/$name"
  rendered_f="$RENDERED_CMDS/$name"
  if [[ ! -f "$repo_f" ]]; then
    echo "DRIFT: $name exists only in template/.claude/commands/" >&2
    fail=1
    continue
  fi
  if [[ ! -f "$rendered_f" ]]; then
    echo "DRIFT: $name exists only in .claude/commands/" >&2
    fail=1
    continue
  fi
  if ! diff -u \
      --label "$REPO_CMDS/$name (cdd-only sections stripped)" \
      --label "template/.claude/commands/$name (rendered)" \
      <(strip_cdd_only "$repo_f") <(strip_cdd_only "$rendered_f"); then
    fail=1
  fi
done

# The shipped settings file must parse: it is generated into every bootstrapped project,
# where a stray comma silently costs the project its permissions. Opportunistic — a host
# without jq keeps the diff below rather than turning this whole gate into a SKIP.
if command -v jq >/dev/null 2>&1; then
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
if grep -rn 'cdd-only-\(begin\|end\)' template/.claude/commands/ >&2; then
  echo "ERROR: cdd-only markers found in template/.claude/commands/ (see above); they belong in the repo copies only" >&2
  fail=1
fi

# Handoff-schema consistency: print the `## ` headings inside the handoff schema block
# (from the "# Task:" line to the end of its fenced code block) and compare.
schema_headings() {
  awk '/^# Task:/ { in_schema = 1 }
       in_schema && /^## / { print }
       in_schema && /^```/ { exit }' "$1"
}

doc_schema="$(schema_headings "$PROCESS_DOC")"
cmd_schema="$(schema_headings "$REPO_CMDS/cdd-next-step.md")"
if [[ -z "$doc_schema" ]]; then
  echo "ERROR: could not locate the handoff schema block in $PROCESS_DOC" >&2
  fail=1
elif [[ "$doc_schema" != "$cmd_schema" ]]; then
  echo "DRIFT: handoff schema headings differ between $PROCESS_DOC and $REPO_CMDS/cdd-next-step.md" >&2
  diff <(printf '%s\n' "$doc_schema") <(printf '%s\n' "$cmd_schema") >&2 || true
  fail=1
fi

# Plan-file-schema consistency: the same shape, keyed on the "# Plan:" line. The seam
# checker (check 7) pins the producer against its consumer; this pins the producer
# against the process doc, which documents the same schema and can drift from it.
plan_schema_headings() {
  awk '/^# Plan:/ { in_schema = 1 }
       in_schema && /^## / { print }
       in_schema && /^```/ { exit }' "$1"
}

doc_plan="$(plan_schema_headings "$PROCESS_DOC")"
cmd_plan="$(plan_schema_headings "$REPO_CMDS/cdd-plan.md")"
if [[ -z "$doc_plan" ]]; then
  echo "ERROR: could not locate the plan-file schema block in $PROCESS_DOC" >&2
  fail=1
elif [[ "$doc_plan" != "$cmd_plan" ]]; then
  echo "DRIFT: plan-file schema headings differ between $PROCESS_DOC and $REPO_CMDS/cdd-plan.md" >&2
  diff <(printf '%s\n' "$doc_plan") <(printf '%s\n' "$cmd_plan") >&2 || true
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "command-set drift detected" >&2
  exit 1
fi
echo "command-set drift: clean"
