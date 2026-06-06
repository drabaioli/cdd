#!/usr/bin/env bash
# Smoke-test the bootstrapped tree at $1.
#
# Asserts that bootstrap-cdd-project.sh produced a clean tree:
#   - no <PROJECT_NAME>, <PROJECT_SLUG>, <PROJECT_DIR>, or bare PROJECT literals remain
#   - the bootstrapped worktree script passes `bash -n`
#   - BOOTSTRAP.md was not copied
#   - relative markdown links in CLAUDE.md and the roadmap resolve
#   - .claude/commands/ contains no <...> tokens outside the whitelist
#   - the baseline marker .claude/cdd-baseline is present and well-formed
#
# Usage: scripts/template-smoke-assert.sh /path/to/bootstrapped/tree

set -euo pipefail

BOOTSTRAPPED="${1:?usage: $0 <bootstrapped-tree-path>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHITELIST="$REPO_ROOT/scripts/template-smoke-whitelist.txt"

cd "$BOOTSTRAPPED"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# 1. No raw placeholders left anywhere.
for token in '<PROJECT_NAME>' '<PROJECT_SLUG>' '<PROJECT_DIR>'; do
  if grep -rn -- "$token" . ; then
    fail "found leftover $token"
  fi
  pass "no $token"
done

# Bare PROJECT, word-boundary, must not appear anywhere either.
if grep -rnE '\bPROJECT\b' . ; then
  fail "found leftover bare PROJECT"
fi
pass "no bare PROJECT"

# 2. Bootstrapped worktree script: parse-clean.
shopt -s nullglob
worktree_scripts=(tools/*-worktree.sh)
shopt -u nullglob
[[ ${#worktree_scripts[@]} -eq 1 ]] || fail "expected exactly one tools/*-worktree.sh, found ${#worktree_scripts[@]}"
bash -n "${worktree_scripts[0]}"
pass "bash -n ${worktree_scripts[0]}"

# 3. BOOTSTRAP.md must not have been copied.
[[ ! -e BOOTSTRAP.md ]] || fail "BOOTSTRAP.md was copied into the bootstrapped tree"
pass "BOOTSTRAP.md not present"

# 4. Relative markdown links in CLAUDE.md and the roadmap must resolve.
check_links() {
  local file="$1"
  local missing=0
  # Match [text](target) where target doesn't start with http, mailto, or #.
  while IFS= read -r target; do
    # Strip an anchor fragment.
    target_path="${target%%#*}"
    [[ -z "$target_path" ]] && continue
    # Resolve relative to the file's directory.
    local dir
    dir="$(dirname "$file")"
    if [[ ! -e "$dir/$target_path" ]]; then
      echo "  broken link in $file: $target" >&2
      missing=$((missing + 1))
    fi
  done < <(grep -oE '\]\([^)]+\)' "$file" \
             | sed -E 's/^\]\(//; s/\)$//' \
             | grep -vE '^(https?:|mailto:|#)')
  [[ $missing -eq 0 ]] || fail "$missing broken relative link(s) in $file"
  pass "links resolve in $file"
}

check_links CLAUDE.md
check_links doc/index.md
check_links doc/knowledge_base/roadmap.md

# 5. .claude/commands/*.md: no <...> tokens outside the whitelist.
[[ -f "$WHITELIST" ]] || fail "whitelist not found at $WHITELIST"

# Build a sorted-unique list of tokens appearing in slash commands.
mapfile -t found_tokens < <(grep -ohrE '<[^<>]+>' .claude/commands/ | sort -u)

# Whitelisted tokens: strip comments and blank lines.
mapfile -t whitelisted < <(grep -vE '^\s*(#|$)' "$WHITELIST")

unexpected=0
for tok in "${found_tokens[@]}"; do
  hit=0
  for w in "${whitelisted[@]}"; do
    if [[ "$tok" == "$w" ]]; then hit=1; break; fi
  done
  if [[ $hit -eq 0 ]]; then
    echo "  unexpected <...> token in .claude/commands/: $tok" >&2
    unexpected=$((unexpected + 1))
  fi
done
[[ $unexpected -eq 0 ]] || fail "$unexpected unexpected <...> token(s) in .claude/commands/ — update scripts/template-smoke-whitelist.txt if intentional"
pass ".claude/commands/ tokens all whitelisted"

# 6. Baseline marker: present, single line, a commit hash or "unknown".
[[ -f .claude/cdd-baseline ]] || fail ".claude/cdd-baseline marker missing"
if ! grep -qxE '[0-9a-f]{7,40}|unknown' .claude/cdd-baseline; then
  fail ".claude/cdd-baseline is not a commit hash or 'unknown': $(cat .claude/cdd-baseline)"
fi
pass ".claude/cdd-baseline marker present and well-formed"

echo "all smoke checks passed"
