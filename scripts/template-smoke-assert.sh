#!/usr/bin/env bash
# Smoke-test the bootstrapped tree at $1.
#
# Asserts that tools/bootstrap-cdd-project.sh produced a clean tree:
#   - no <PROJECT_NAME> or <PROJECT_DIR> literals remain
#   - BOOTSTRAP.md was not copied
#   - relative markdown links in CLAUDE.md and the roadmap resolve
#   - .claude/commands/ and .claude/agents/ contain no <...> tokens outside the whitelist
#   - .claude/agents/cdd-researcher.md is present, and every shipped agent definition
#     names its tools and none that can write, run a shell or spawn subagents
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
for token in '<PROJECT_NAME>' '<PROJECT_DIR>'; do
  if grep -rn -- "$token" . ; then
    fail "found leftover $token"
  fi
  pass "no $token"
done

# 2. BOOTSTRAP.md must not have been copied.
[[ ! -e BOOTSTRAP.md ]] || fail "BOOTSTRAP.md was copied into the bootstrapped tree"
pass "BOOTSTRAP.md not present"

# 2a. No per-project worktree helper: it is a single shared, self-installing
# script (cdd-worktree.sh install), never rendered into a project. Guards against
# accidentally reintroducing a per-project helper to the template.
shopt -s nullglob
worktree_helpers=(tools/*-worktree.sh)
shopt -u nullglob
[[ ${#worktree_helpers[@]} -eq 0 ]] || fail "rendered a per-project worktree helper (${worktree_helpers[*]}); the helper is shared, installed once via 'cdd-worktree.sh install'"
pass "no per-project worktree helper rendered"

# 3. Relative markdown links in CLAUDE.md, the overview, and the roadmap must resolve.
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
check_links doc/knowledge_base/project-overview.md
check_links doc/knowledge_base/roadmap.md

# 4. .claude/commands/*.md and .claude/agents/*.md: no <...> tokens outside the whitelist.
[[ -f "$WHITELIST" ]] || fail "whitelist not found at $WHITELIST"

# Build a sorted-unique list of tokens appearing in slash commands and agent definitions.
token_dirs=(.claude/commands/)
[[ -d .claude/agents ]] && token_dirs+=(.claude/agents/)
mapfile -t found_tokens < <(grep -ohrE '<[^<>]+>' "${token_dirs[@]}" | sort -u)

# Whitelisted tokens: strip comments and blank lines.
mapfile -t whitelisted < <(grep -vE '^\s*(#|$)' "$WHITELIST")

unexpected=0
for tok in "${found_tokens[@]}"; do
  hit=0
  for w in "${whitelisted[@]}"; do
    if [[ "$tok" == "$w" ]]; then hit=1; break; fi
  done
  if [[ $hit -eq 0 ]]; then
    echo "  unexpected <...> token in ${token_dirs[*]}: $tok" >&2
    unexpected=$((unexpected + 1))
  fi
done
[[ $unexpected -eq 0 ]] || fail "$unexpected unexpected <...> token(s) in ${token_dirs[*]} — update scripts/template-smoke-whitelist.txt if intentional"
pass "${token_dirs[*]} tokens all whitelisted"

# 4a. Shipped agent definitions are read-only. CDD ships only read-only agents today
# (process doc §2.17), so a future write-capable agent changes this assertion
# deliberately rather than slipping through. The `tools:` frontmatter line is the
# enforcement, and an omitted one inherits every tool — so a missing line fails too.
[[ -f .claude/agents/cdd-researcher.md ]] || fail ".claude/agents/cdd-researcher.md missing from the bootstrapped tree"
for agent in .claude/agents/*.md; do
  tools_line="$(awk 'NR == 1 && /^---$/ { fm = 1; next }
                     fm && /^---$/ { exit }
                     fm && /^tools:/ { print; exit }' "$agent")"
  [[ -n "$tools_line" ]] || fail "$agent has no tools: frontmatter line, so it would inherit every tool"
  for t in Write Edit MultiEdit NotebookEdit Bash Agent Task; do
    if grep -qwF -- "$t" <<<"${tools_line#tools:}"; then
      fail "$agent grants the write-capable tool $t ($tools_line); shipped agents are read-only"
    fi
  done
done
pass ".claude/agents/ definitions are all read-only"

# 5. Baseline marker: present, single line, a commit hash or "unknown".
[[ -f .claude/cdd-baseline ]] || fail ".claude/cdd-baseline marker missing"
if ! grep -qxE '[0-9a-f]{7,40}|unknown' .claude/cdd-baseline; then
  fail ".claude/cdd-baseline is not a commit hash or 'unknown': $(cat .claude/cdd-baseline)"
fi
pass ".claude/cdd-baseline marker present and well-formed"

echo "all smoke checks passed"
