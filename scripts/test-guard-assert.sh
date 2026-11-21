#!/usr/bin/env bash
# The shipped test-guard hook (.claude/hooks/cdd-test-guard.sh; the drift gate holds this
# repo's copy equal to the template's): an edit to an existing test the approved plan does not
# name asks the human; everything else passes silently (why: ADR 0033). Against a throwaway
# repo and HOME, it asserts:
#   - an existing test asks, naming the path: matched by a directory pattern, by a
#     basename pattern at depth, and through NotebookEdit's notebook_path
#   - a new test file passes, also in a directory not created yet
#   - an existing non-test file, and a path outside the repo, pass
#   - a test the plan's `## File map` names passes, alone or as a `file:line` pointer; one
#     named only under another section still asks
#   - a contract carrying only the placeholder pattern, and no contract, pass
# "Pass" means no output and exit 0; "ask" means exit 0 and permissionDecision "ask".
#
# Usage: scripts/test-guard-assert.sh   (provisions and tears down its own temp tree)

# The fixtures write Markdown, whose backticks are literal.
# shellcheck disable=SC2016
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/cdd-test-guard.sh"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required and not installed" >&2; exit 1; }
[[ -f "$HOOK" ]] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }

# Physical path: on macOS mktemp hands out /var/..., a symlink to /private/var/....
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
cat > "$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	name = CDD Smoke
	email = smoke@example.com
[init]
	defaultBranch = main
[commit]
	gpgsign = false
EOF
export HOME="$WORK/home"
mkdir -p "$HOME"

PROJ="$WORK/proj"
CONTRACT="$PROJ/doc/knowledge_base/engineering-practices.md"
PLAN="$HOME/.cdd/handoffs/proj/feat.plan.md"
mkdir -p "$PROJ/doc/knowledge_base" "$PROJ/tests" "$PROJ/pkg" "$PROJ/src"
printf '# Practices\n\n## Test protection — Upheld\n\n- Test paths: `tests/*`, `*_test.go`\n' > "$CONTRACT"
echo 'def test_old(): pass' > "$PROJ/tests/old_test.py"
echo 'package pkg' > "$PROJ/pkg/a_test.go"
echo 'print(1)' > "$PROJ/src/app.py"
echo '{}' > "$PROJ/tests/nb.ipynb"
git -C "$PROJ" init -q
git -C "$PROJ" checkout -q -b feat
git -C "$PROJ" add -- doc tests pkg src
git -C "$PROJ" commit -q -m fixture

failures=0
# check <label> <expect: ask|pass> <tool> <key> <path>
check() {
  local label="$1" expect="$2" tool="$3" key="$4" path="$5" out rc=0 got
  out="$(jq -n --arg cwd "$PROJ" --arg tool "$tool" --arg key "$key" --arg path "$path" \
    '{cwd: $cwd, tool_name: $tool, tool_input: {($key): $path}}' | bash "$HOOK")" || rc=$?
  if [[ $rc -ne 0 ]]; then
    got="exit $rc"
  elif [[ -z "$out" ]]; then
    got=pass
  elif [[ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")" == ask \
     && "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$out")" == *"${path#"$PROJ"/}"* ]]; then
    got=ask
  else
    got="unexpected output: $out"
  fi
  if [[ "$got" == "$expect" ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label — expected $expect, got $got" >&2
    failures=$((failures + 1))
  fi
}

check "existing test, no plan: asks" ask Edit file_path "$PROJ/tests/old_test.py"
check "existing test matched at depth by *_test.go: asks" ask Write file_path "$PROJ/pkg/a_test.go"
check "existing test through NotebookEdit: asks" ask NotebookEdit notebook_path "$PROJ/tests/nb.ipynb"
check "new test file: passes" pass Write file_path "$PROJ/tests/new_test.py"
check "new test in a directory not created yet: passes" pass Write file_path "$PROJ/tests/sub/x.py"
check "existing non-test file: passes" pass Edit file_path "$PROJ/src/app.py"
check "path outside the repo: passes" pass Edit file_path "$WORK/elsewhere_test.go"

mkdir -p "$(dirname "$PLAN")"
printf '# Plan: x\n\n## File map\n- `tests/old_test.py` → change\n\n## Dead ends\nNone\n' > "$PLAN"
check "test the file map names: passes" pass Edit file_path "$PROJ/tests/old_test.py"
printf '# Plan: x\n\n## File map\n- `tests/old_test.py:12` → change\n\n## Dead ends\nNone\n' > "$PLAN"
check "test the file map names as file:line: passes" pass Edit file_path "$PROJ/tests/old_test.py"
printf '# Plan: x\n\n## File map\n- `src/app.py` → change\n\n## Dead ends\n- `tests/old_test.py` rejected\n' > "$PLAN"
check "test named only outside the file map: asks" ask Edit file_path "$PROJ/tests/old_test.py"
rm -f "$PLAN"

printf '# Practices\n\n- Test paths: `<test path pattern>`\n' > "$CONTRACT"
check "placeholder-only contract: passes" pass Edit file_path "$PROJ/tests/old_test.py"
rm -f "$CONTRACT"
check "no contract: passes" pass Edit file_path "$PROJ/tests/old_test.py"

if [[ $failures -gt 0 ]]; then
  echo "test-guard: $failures failure(s)" >&2
  exit 1
fi
echo "test-guard: all cases pass"
