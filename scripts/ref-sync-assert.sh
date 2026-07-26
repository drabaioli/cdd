#!/usr/bin/env bash
# End-to-end smoke for the per-task ref sync (issue #22) against a local bare repo.
#
# The real cross-machine flow is hard to exercise in CI, so this stands in a local
# `git init --bare` for `origin` and two clones with separate $HOME dirs as
# "machine A" and "machine B". It sources both helpers (tools/cdd-state.sh and
# tools/cdd-worktree.sh) and asserts:
#   - `cdd-state seed`/`set` on machine A push refs/cdd/<branch> to origin
#   - `cdd-worktree-resume <branch>` on a fresh machine B materializes the handoff
#     (byte-for-byte) and the state record (at the advanced stage), no `claude`
#   - most-advanced-stage wins: a more-advanced ref overwrites a stale local record,
#     a more-advanced local record is kept, and a present local handoff is never
#     clobbered (it is immutable after seed)
#   - the no-ref path still resumes cleanly (materializes nothing, exits 0)
#
# Usage: scripts/ref-sync-assert.sh
# Takes no arguments; it provisions and tears down its own temp tree. Requires jq
# (the push lives under cdd-state's jq guard); without it the test skips (advisory).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_WT="$REPO_ROOT/tools/cdd-worktree.sh"
HELPER_STATE="$REPO_ROOT/tools/cdd-state.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER_WT" ]] || fail "helper not found: $HELPER_WT"
[[ -f "$HELPER_STATE" ]] || fail "helper not found: $HELPER_STATE"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; ref sync is advisory and skips without it"
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
FEATURE="feat_sync"
FEATURE_NO="feat_noref"  # pushed to origin, but never gets a refs/cdd/* ref
BASE_TASK="develop"      # a non-default base recorded at seed; must ride the ref

# Stub `claude` on PATH as a negative guard: resume must never invoke it.
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
  git switch -q -c "$FEATURE"
  echo "a" > a.txt; git add a.txt; git commit -q -m "feature"
  git push -q -u origin "$FEATURE"
  git switch -q -c "$FEATURE_NO" "$DEFAULT_BRANCH"
  echo "n" > n.txt; git add n.txt; git commit -q -m "no-ref feature"
  git push -q -u origin "$FEATURE_NO"
)

# The handoff dir is $HOME/.cdd/handoffs/<repo>/, where <repo> is the clone's own
# directory basename (derived from the git common dir). Each machine has its own
# HOME and clone, so their repo names differ — the ref is keyed only by branch.
handoff_dir() { printf '%s/.cdd/handoffs/%s' "$1" "$(basename "$2")"; }

# Run cdd-state in a clone with a given HOME. $1=clone, $2=HOME, then the command.
run_state() {
  local dir="$1" home="$2"; shift 2
  (
    cd "$dir"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$home" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER_STATE"
    cdd-state "$@"
  )
}

# Run cdd-worktree-resume in a clone with a given HOME. $1=clone, $2=HOME, $3=branch.
run_resume() {
  local dir="$1" home="$2" branch="$3"
  (
    cd "$dir"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$home" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER_WT"
    cdd-worktree-resume "$branch"
  )
}

# 2. Machine A: seed + advance, which push refs/cdd/$FEATURE to origin.
HOME_A="$WORK/homeA"
git clone -q "$WORK/origin.git" "$WORK/machineA"
DIR_A="$(handoff_dir "$HOME_A" "$WORK/machineA")"
mkdir -p "$DIR_A"
HANDOFF_A="$DIR_A/$FEATURE.md"
printf '# Task: %s\n\nScoped handoff body.\nNo trailing weirdness.\n' "$FEATURE" > "$HANDOFF_A"

run_state "$WORK/machineA" "$HOME_A" seed "$FEATURE" --base "$BASE_TASK" >/dev/null 2>&1 \
  || fail "cdd-state seed failed on machine A"
git -C "$WORK/machineA" ls-remote origin "refs/cdd/$FEATURE" | grep -q "refs/cdd/$FEATURE" \
  || fail "seed did not push refs/cdd/$FEATURE to origin"
[[ "$(jq -r '.base_branch' "$DIR_A/$FEATURE.state.json")" == "$BASE_TASK" ]] \
  || fail "seed --base did not record base_branch on machine A"
pass "seed pushed refs/cdd/$FEATURE to origin (with base_branch)"

git -C "$WORK/machineA" switch -q "$FEATURE"
run_state "$WORK/machineA" "$HOME_A" set implementation_done >/dev/null 2>&1 \
  || fail "cdd-state set failed on machine A"
# Sanity: local record advanced.
[[ "$(jq -r '.stage' "$DIR_A/$FEATURE.state.json")" == "implementation_done" ]] \
  || fail "machine A state did not advance to implementation_done"
pass "set advanced the state and refreshed the ref"

# 3. Machine B: fresh clone materializes handoff (byte-for-byte) + advanced state.
HOME_B="$WORK/homeB"
git clone -q "$WORK/origin.git" "$WORK/machineB"
DIR_B="$(handoff_dir "$HOME_B" "$WORK/machineB")"
: > "$CLAUDE_STUB_LOG"
set +e
run_resume "$WORK/machineB" "$HOME_B" "$FEATURE" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "resume on machine B exited $rc"
[[ -f "$DIR_B/$FEATURE.md" ]] || fail "resume did not materialize the handoff"
cmp -s "$HANDOFF_A" "$DIR_B/$FEATURE.md" \
  || fail "materialized handoff differs from machine A's (not byte-for-byte)"
[[ "$(jq -r '.stage' "$DIR_B/$FEATURE.state.json")" == "implementation_done" ]] \
  || fail "materialized state is not at the advanced stage implementation_done"
[[ "$(jq -r '.base_branch' "$DIR_B/$FEATURE.state.json")" == "$BASE_TASK" ]] \
  || fail "base_branch did not ride the ref sync to machine B"
[[ ! -s "$CLAUDE_STUB_LOG" ]] || fail "resume must not launch claude"
pass "resume materialized handoff byte-for-byte, advanced state, and base_branch, no claude"

# 4. Most-advanced wins (ref ahead): a stale local record is overwritten, and a
#    pre-existing local handoff is preserved (immutable after seed).
HOME_C="$WORK/homeC"
git clone -q "$WORK/origin.git" "$WORK/machineC"
DIR_C="$(handoff_dir "$HOME_C" "$WORK/machineC")"
mkdir -p "$DIR_C"
printf 'LOCAL HANDOFF — must be preserved\n' > "$DIR_C/$FEATURE.md"
jq -n '{schema_version:1, branch:"'"$FEATURE"'", stage:"plan_approved", pr:null, sessions:[]}' \
  > "$DIR_C/$FEATURE.state.json"
set +e
run_resume "$WORK/machineC" "$HOME_C" "$FEATURE" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "resume on machine C exited $rc"
[[ "$(jq -r '.stage' "$DIR_C/$FEATURE.state.json")" == "implementation_done" ]] \
  || fail "stale local state (plan_approved) should have been overwritten by the ref"
grep -q "LOCAL HANDOFF" "$DIR_C/$FEATURE.md" \
  || fail "present local handoff must not be clobbered by the ref"
pass "ref-ahead overwrites stale local state, preserves local handoff"

# 5. Most-advanced wins (local ahead): a more-advanced local record is kept.
HOME_D="$WORK/homeD"
git clone -q "$WORK/origin.git" "$WORK/machineD"
DIR_D="$(handoff_dir "$HOME_D" "$WORK/machineD")"
mkdir -p "$DIR_D"
jq -n '{schema_version:1, branch:"'"$FEATURE"'", stage:"addressed", pr:7, sessions:[]}' \
  > "$DIR_D/$FEATURE.state.json"
set +e
run_resume "$WORK/machineD" "$HOME_D" "$FEATURE" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "resume on machine D exited $rc"
[[ "$(jq -r '.stage' "$DIR_D/$FEATURE.state.json")" == "addressed" ]] \
  || fail "more-advanced local state (addressed) should have been kept"
pass "local-ahead state record is kept over a less-advanced ref"

# 6. No-ref path: a branch with no refs/cdd/* still resumes cleanly, materializes
#    nothing, and exits 0.
HOME_E="$WORK/homeE"
git clone -q "$WORK/origin.git" "$WORK/machineE"
DIR_E="$(handoff_dir "$HOME_E" "$WORK/machineE")"
: > "$CLAUDE_STUB_LOG"
set +e
out="$(run_resume "$WORK/machineE" "$HOME_E" "$FEATURE_NO" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "no-ref resume exited $rc (expected 0)"
[[ ! -f "$DIR_E/$FEATURE_NO.state.json" ]] \
  || fail "no-ref resume must not materialize a state record"
[[ ! -f "$DIR_E/$FEATURE_NO.md" ]] \
  || fail "no-ref resume must not materialize a handoff"
grep -q "No synced task ref" <<<"$out" \
  || fail "no-ref resume should print the honest no-transfer message"
[[ ! -s "$CLAUDE_STUB_LOG" ]] || fail "no-ref resume must not launch claude"
pass "no-ref path resumes cleanly without materializing anything"

echo "all ref-sync smoke checks passed"
