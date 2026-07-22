#!/usr/bin/env bash
# Smoke for the per-task base branch: capture, read-back, and branch-cut.
#
# Against a local bare `origin` with a default (`main`) and a `develop` branch,
# it sources both helpers (tools/cdd-state.sh, tools/cdd-worktree.sh) in an
# isolated $HOME and asserts:
#   - `cdd-state seed <branch> --base <b>` records base_branch on the record
#   - `cdd-state seed <branch>` (no --base) records base_branch: null
#   - `cdd-state get base_branch` reads the value back, and prints nothing for a
#     null field or an absent record (advisory)
#   - `cdd-worktree <branch>` cuts the new branch from the recorded base
#     (develop), and falls back to the default branch when none was recorded —
#     with a stubbed `claude` guarding that the launch happens but nothing real runs
#
# Usage: scripts/base-branch-assert.sh
# Takes no arguments; provisions and tears down its own temp tree. Requires jq
# (base_branch lives under cdd-state's jq guard); without it the test skips.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_WT="$REPO_ROOT/tools/cdd-worktree.sh"
HELPER_STATE="$REPO_ROOT/tools/cdd-state.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER_WT" ]] || fail "helper not found: $HELPER_WT"
[[ -f "$HELPER_STATE" ]] || fail "helper not found: $HELPER_STATE"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; base_branch is advisory and skips without it"
  exit 0
fi

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
BASE_BRANCH="develop"
HOME_DIR="$WORK/home"

# Stub `claude` on PATH: cdd-worktree launches it last; it must run but do nothing.
mkdir -p "$WORK/bin"
export CLAUDE_STUB_LOG="$WORK/claude.log"
cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude $*" >> "$CLAUDE_STUB_LOG"
exit 0
EOF
chmod +x "$WORK/bin/claude"

# 1. Bare origin with a default branch and a develop branch cut from it. Each
#    branch carries a distinct file so we can tell which one a worktree was cut from.
git init --bare -q "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/seed" 2>/dev/null  # empty-repo warning is expected
(
  cd "$WORK/seed"
  echo "main" > main_only.txt
  git add main_only.txt
  git commit -q -m "seed main"
  git push -q -u origin "$DEFAULT_BRANCH"
  git switch -q -c "$BASE_BRANCH"
  echo "dev" > dev_only.txt
  git add dev_only.txt
  git commit -q -m "seed develop"
  git push -q -u origin "$BASE_BRANCH"
)

# The main worktree: a fresh clone (its git-dir == git-common-dir, so cdd-worktree's
# guard treats it as the main worktree). It checks out the default branch only.
git clone -q "$WORK/origin.git" "$WORK/machine"
REPO_NAME="$(basename "$WORK/machine")"
DIR="$HOME_DIR/.cdd/handoffs/$REPO_NAME"

# Run cdd-state in the main worktree with the isolated HOME. $1.. = the command.
run_state() {
  (
    cd "$WORK/machine"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$HOME_DIR" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER_STATE"
    cdd-state "$@"
  )
}

# 2. seed --base records the field; seed without --base records null.
run_state seed feat_dev --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed --base failed"
[[ "$(jq -r '.base_branch' "$DIR/feat_dev.state.json")" == "$BASE_BRANCH" ]] \
  || fail "seed --base did not record base_branch=$BASE_BRANCH"
pass "seed --base records base_branch"

run_state seed feat_default >/dev/null 2>&1 || fail "seed without --base failed"
[[ "$(jq -r '.base_branch' "$DIR/feat_default.state.json")" == "null" ]] \
  || fail "seed without --base should record base_branch: null"
pass "seed without --base records base_branch: null"

# 3. cdd-state get reads the value (from the cwd-derived, current-branch record);
#    empty for null / absent record. Use a dedicated branch so it doesn't collide
#    with the cdd-worktree names below.
run_state seed feat_get --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed feat_get failed"
(cd "$WORK/machine" && git switch -q -c feat_get)
got="$(run_state get base_branch)"
[[ "$got" == "$BASE_BRANCH" ]] \
  || fail "cdd-state get base_branch did not read back $BASE_BRANCH (got '$got')"
pass "cdd-state get base_branch reads the recorded value"

(cd "$WORK/machine" && git switch -q "$DEFAULT_BRANCH")
got_none="$(run_state get base_branch)"
[[ -z "$got_none" ]] || fail "get on the default branch (no record) should print nothing, got '$got_none'"
pass "cdd-state get prints nothing when the field/record is absent"

# 4. cdd-worktree cuts the new branch from the recorded base (develop).
#    A handoff must exist beside the state record; the dir already exists from seed.
printf '# Task: feat_dev\n\nbody\n' > "$DIR/feat_dev.md"
printf '# Task: feat_default\n\nbody\n' > "$DIR/feat_default.md"

run_worktree() {
  (
    cd "$WORK/machine"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$HOME_DIR" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER_WT"
    cdd-worktree "$1"
  )
}

: > "$CLAUDE_STUB_LOG"
run_worktree feat_dev >/dev/null 2>&1 || fail "cdd-worktree feat_dev failed"
WT_DEV="$WORK/${REPO_NAME}-feat_dev"
[[ -d "$WT_DEV" ]] || fail "cdd-worktree did not create the feat_dev worktree"
[[ -f "$WT_DEV/dev_only.txt" ]] \
  || fail "feat_dev was not cut from develop (dev_only.txt missing)"
[[ -s "$CLAUDE_STUB_LOG" ]] || fail "cdd-worktree must launch claude"
pass "cdd-worktree cuts the new branch from the recorded base (develop)"

# 5. No recorded base → falls back to the default branch (main).
: > "$CLAUDE_STUB_LOG"
run_worktree feat_default >/dev/null 2>&1 || fail "cdd-worktree feat_default failed"
WT_DEF="$WORK/${REPO_NAME}-feat_default"
[[ -d "$WT_DEF" ]] || fail "cdd-worktree did not create the feat_default worktree"
[[ -f "$WT_DEF/main_only.txt" ]] \
  || fail "feat_default should have been cut from the default branch (main_only.txt missing)"
[[ ! -f "$WT_DEF/dev_only.txt" ]] \
  || fail "feat_default (no recorded base) must not be cut from develop"
pass "cdd-worktree falls back to the default branch when no base was recorded"

echo "all base-branch smoke checks passed"
