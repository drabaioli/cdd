#!/usr/bin/env bash
# Render-then-diff drift check between the CDD repo's own .claude/commands/ and the
# template/.claude/commands/ it ships.
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
#   - no cdd-only markers appear in template/.claude/commands/ — they belong in the
#     repo copies only; a marker in the template would be stripped from both sides
#     of the comparison above and hide real drift.
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

if [[ "$fail" -ne 0 ]]; then
  echo "command-set drift detected" >&2
  exit 1
fi
echo "command-set drift: clean"
