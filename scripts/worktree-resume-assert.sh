#!/usr/bin/env bash
# End-to-end smoke for `cdd-worktree-resume` (issue #22) against a local bare repo.
#
# The real cross-machine flow is hard to exercise in CI, so this stands in a local
# `git init --bare` for `origin`: it pushes a default branch plus two feature
# branches, clones a fresh "machine B" working copy that has NO local feature
# branch / worktree, then sources the helper and asserts:
#   - `cdd-worktree-resume <branch>` creates a sibling worktree tracking
#     origin/<branch>, and does NOT launch `claude`
#   - a second `cdd-worktree-resume <branch>` detects the existing worktree and
#     returns 0
#   - `cdd-worktree-resume` with no argument lists resumable remote branches and
#     creates the selected one (fed a numbered choice on stdin)
#
# Usage: scripts/worktree-resume-assert.sh
# Takes no arguments; it provisions and tears down its own temp tree. A stubbed
# `claude` on PATH guards the "never launched" assertion: the helper must leave
# the log empty.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/tools/cdd-worktree.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER" ]] || fail "helper not found: $HELPER"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Isolate from the caller's git identity / signing config; keep runs deterministic.
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

DEFAULT_BRANCH="main"
FEATURE_A="gh_issue_99_demo"
FEATURE_B="gh_issue_100_other"

# Stub `claude` on PATH as a negative guard: the helper must never invoke it, so
# any output here (a non-empty log) is a regression.
mkdir -p "$WORK/bin"
export CLAUDE_STUB_LOG="$WORK/claude.log"
cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude $*" >> "$CLAUDE_STUB_LOG"
exit 0
EOF
chmod +x "$WORK/bin/claude"

# 1. Bare repo standing in for origin, seeded with a default + two feature branches.
git init --bare -q "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/seed" 2>/dev/null  # empty-repo warning is expected
(
  cd "$WORK/seed"
  echo "# seed" > README.md
  git add README.md
  git commit -q -m "seed"
  git push -q -u origin "$DEFAULT_BRANCH"
  git switch -q -c "$FEATURE_A"
  echo "a" > a.txt; git add a.txt; git commit -q -m "feature a"
  git push -q -u origin "$FEATURE_A"
  git switch -q -c "$FEATURE_B" "$DEFAULT_BRANCH"
  echo "b" > b.txt; git add b.txt; git commit -q -m "feature b"
  git push -q -u origin "$FEATURE_B"
)

# Run the helper in a subshell so its `cd` and `set` don't leak into the test.
# $1 = clone dir, $2 = branch arg (may be empty), $3 = stdin for discovery prompt.
run_resume() {
  (
    cd "$1"
    export PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER"
    if [[ -z "$2" ]]; then
      cdd-worktree-resume <<<"$3"
    else
      cdd-worktree-resume "$2"
    fi
  )
}

# 2. Explicit-branch resume on a fresh clone (no local feature branch/worktree).
git clone -q "$WORK/origin.git" "$WORK/repoA"
: > "$CLAUDE_STUB_LOG"
set +e
run_resume "$WORK/repoA" "$FEATURE_A" "" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "cdd-worktree-resume $FEATURE_A exited $rc"

WT_A="$WORK/repoA-$FEATURE_A"
[[ -d "$WT_A" ]] || fail "worktree not created at $WT_A"
head="$(git -C "$WT_A" rev-parse --abbrev-ref HEAD)"
[[ "$head" == "$FEATURE_A" ]] || fail "worktree HEAD is '$head', expected '$FEATURE_A'"
upstream="$(git -C "$WT_A" rev-parse --abbrev-ref "$FEATURE_A@{upstream}" 2>/dev/null || true)"
[[ "$upstream" == "origin/$FEATURE_A" ]] \
  || fail "branch upstream is '$upstream', expected 'origin/$FEATURE_A'"
[[ ! -s "$CLAUDE_STUB_LOG" ]] || fail "resume must not launch claude"
pass "explicit resume created a tracking worktree without launching claude"

# 3. Re-running on the same branch detects the existing worktree.
: > "$CLAUDE_STUB_LOG"
set +e
run_resume "$WORK/repoA" "$FEATURE_A" "" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "second cdd-worktree-resume $FEATURE_A exited $rc (expected 0)"
[[ ! -s "$CLAUDE_STUB_LOG" ]] || fail "already-exists path must not launch claude"
pass "already-exists resume returns 0 without launching claude"

# 4. Discovery mode (no argument): pick the first listed branch via stdin.
#    for-each-ref sorts refnames, so candidate 1 is the lexicographically first
#    feature branch ($FEATURE_B = gh_issue_100_other sorts before $FEATURE_A).
git clone -q "$WORK/origin.git" "$WORK/repoB"
: > "$CLAUDE_STUB_LOG"
set +e
run_resume "$WORK/repoB" "" "1" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "discovery cdd-worktree-resume exited $rc"
WT_B="$WORK/repoB-$FEATURE_B"
[[ -d "$WT_B" ]] || fail "discovery did not create worktree for first candidate ($FEATURE_B)"
head="$(git -C "$WT_B" rev-parse --abbrev-ref HEAD)"
[[ "$head" == "$FEATURE_B" ]] || fail "discovery worktree HEAD is '$head', expected '$FEATURE_B'"
pass "discovery mode resumed the selected remote branch"

echo "all worktree-resume smoke checks passed"
