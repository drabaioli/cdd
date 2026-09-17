#!/usr/bin/env bash
# Smoke for the cdd-state record -> cdd-worktree launch seam: everything
# /cdd-next-step records on a task (its base branch, its lane) and everything
# cdd-worktree does with that record when it cuts the branch and picks the first
# prompt. One expensive fixture, so every reader of the record is asserted here.
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
#   - `cdd-worktree` runs from a main worktree sitting on a non-default branch
#     (gitflow develop): the guard is "not a linked worktree", not "on the
#     default branch", so this must be admitted
#   - `cdd-worktree`'s FIRST PROMPT is chosen by a capability probe, not a version:
#     a worktree carrying .claude/commands/cdd-plan.md is launched on /cdd-plan as an
#     ordinary session (NOT in plan mode — the checkpoint is /cdd-plan's own approval
#     ask); one without it gets the pre-split prose prompt, in plan mode as before,
#     naming the handoff. Plus the reverse
#     skew — a retrofitted project against a cdd-state that predates `plan_written`
#     prints one warning line and still launches
#   - the small-change lane's routing marker: `cdd-state lane <branch> small` records
#     it (and `standard` records null), `cdd-worktree` launches /cdd-small-change only
#     when the marker AND the command file are both present, and every miss — no
#     marker, no command file, an older cdd-state that rejects `lane` outright —
#     degrades to /cdd-plan with the seeded record (base branch included) intact
#
# Usage: scripts/worktree-launch-assert.sh
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

# Stub `cdd-state` on PATH so the first-prompt probe's skew check has a ground truth
# to read. cdd-worktree's subshell sources only the worktree helper, so `cdd-state`
# there resolves through PATH to this stub; run_state below sources the real helper,
# whose function shadows it. CDD_STUB_STATE_MODE picks which fleet we are standing in.
cat > "$WORK/bin/cdd-state" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "stages" && "${CDD_STUB_STATE_MODE:-new}" == "new" ]]; then
  printf '%s\n' scoped plan_written implementation_done merged \
                checks_passed pr_open addressed
  exit 0
fi
# An older cdd-state has no `stages` subcommand at all: it prints usage and fails.
echo "usage: cdd-state {seed|set|get|install}" >&2
exit 2
EOF
chmod +x "$WORK/bin/cdd-state"

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
grep -qF "and follow the Implementation prompt." "$CLAUDE_STUB_LOG" \
  || fail "a project without .claude/commands/cdd-plan.md must get the pre-split prose prompt. Log: $(cat "$CLAUDE_STUB_LOG")"
grep -qF "/cdd-plan" "$CLAUDE_STUB_LOG" \
  && fail "a project without .claude/commands/cdd-plan.md must not be launched on /cdd-plan"
grep -qF -- "--permission-mode plan" "$CLAUDE_STUB_LOG" \
  || fail "the pre-split seam keeps plan mode, which was its checkpoint"
pass "cdd-worktree falls back to the default branch when no base was recorded"
pass "first prompt: a non-retrofitted project gets the pre-split prose prompt"

# 6. Guard: cdd-worktree runs from the main worktree even when it sits on a
#    non-default branch (gitflow develop). The guard is "not a linked worktree"
#    (git-dir == git-common-dir), not "on the default branch", so this is
#    admitted — the branch-name guard it replaced would have rejected it here.
(cd "$WORK/machine" && git switch -q -c "$BASE_BRANCH" "origin/$BASE_BRANCH")
run_state seed feat_gitflow --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed feat_gitflow failed"
printf '# Task: feat_gitflow\n\nbody\n' > "$DIR/feat_gitflow.md"
: > "$CLAUDE_STUB_LOG"
run_worktree feat_gitflow >/dev/null 2>&1 \
  || fail "cdd-worktree must run from a main worktree on a non-default branch (gitflow)"
WT_GF="$WORK/${REPO_NAME}-feat_gitflow"
[[ -d "$WT_GF" ]] || fail "cdd-worktree did not create the feat_gitflow worktree"
[[ -s "$CLAUDE_STUB_LOG" ]] \
  || fail "cdd-worktree must launch claude from a non-default main worktree"
pass "cdd-worktree runs from a main worktree on a non-default branch (gitflow guard)"

# 7. First-prompt probe, retrofitted project: with .claude/commands/cdd-plan.md
#    committed on the base branch, the new worktree carries it and the helper must
#    launch Claude on /cdd-plan — as an ordinary session, not in plan mode: the
#    checkpoint is /cdd-plan's own approval ask. The probe reads the worktree it
#    just created — no marker, no recorded version.
(
  cd "$WORK/machine"
  mkdir -p .claude/commands
  printf 'Plan a task.

# Plan: <t>

## Summary
' > .claude/commands/cdd-plan.md
  git add .claude/commands/cdd-plan.md
  git commit -q -m "retrofit: add cdd-plan"
  git push -q origin "$BASE_BRANCH"
)
run_state seed feat_split --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed feat_split failed"
printf '# Task: feat_split

body
' > "$DIR/feat_split.md"
: > "$CLAUDE_STUB_LOG"
err="$(run_worktree feat_split 2>&1 >/dev/null)" || fail "cdd-worktree feat_split failed"
[[ -d "$WORK/${REPO_NAME}-feat_split" ]]   || fail "cdd-worktree did not create the feat_split worktree"
grep -qx -- "claude /cdd-plan" "$CLAUDE_STUB_LOG"   || fail "a retrofitted project must be launched on /cdd-plan alone. Log: $(cat "$CLAUDE_STUB_LOG")"
grep -qF -- "--permission-mode plan" "$CLAUDE_STUB_LOG"   && fail "the plan session must NOT be launched in plan mode. Log: $(cat "$CLAUDE_STUB_LOG")"
grep -qF "predates it" <<<"$err"   && fail "no skew warning is due when cdd-state knows plan_written. stderr: $err"
pass "first prompt: a retrofitted project is launched on /cdd-plan, no skew warning"

# 8. Reverse skew: same retrofitted project, but a cdd-state that predates the split.
#    The probe cannot cover this direction, so the helper prints exactly one warning
#    line — a visible degradation instead of a silent one — and still launches.
run_state seed feat_skew --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed feat_skew failed"
printf '# Task: feat_skew

body
' > "$DIR/feat_skew.md"
: > "$CLAUDE_STUB_LOG"
err="$(CDD_STUB_STATE_MODE=old run_worktree feat_skew 2>&1 >/dev/null)"   || fail "cdd-worktree feat_skew failed"
grep -qx -- "claude /cdd-plan" "$CLAUDE_STUB_LOG"   || fail "skew must not stop the launch. Log: $(cat "$CLAUDE_STUB_LOG")"
[[ "$(grep -c "plan/implement split" <<<"$err")" -eq 1 ]]   || fail "expected exactly one skew warning line. stderr: $err"
pass "first prompt: an outdated cdd-state produces one visible skew warning, launch proceeds"

# 9. The small-change lane's routing marker: recorded by cdd-state, read by
#    cdd-worktree to pick the launch prompt — the same record-then-launch seam as the
#    base branch and the first-prompt probe above, so it rides the same fixture. It
#    routes only when the marker AND the command file are both present; every miss
#    degrades to /cdd-plan, so a lost marker can never skip a gate.

# Seed a task (marking its lane when $3 is given), launch it, and assert which first
# prompt claude got. The routing cases below differ only in those three values.
launch_task() {
  local branch="$1" expect="$2" lane="${3:-}"
  run_state seed "$branch" --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed $branch failed"
  [[ -z "$lane" ]] || run_state lane "$branch" "$lane" >/dev/null 2>&1 \
    || fail "cdd-state lane $branch $lane failed"
  printf '# Task: %s\n\nbody\n' "$branch" > "$DIR/$branch.md"
  : > "$CLAUDE_STUB_LOG"
  run_worktree "$branch" >/dev/null 2>&1 || fail "cdd-worktree $branch failed"
  grep -qx -- "claude $expect" "$CLAUDE_STUB_LOG" \
    || fail "$branch: expected a launch on $expect alone. Log: $(cat "$CLAUDE_STUB_LOG")"
}

# 9a. The record: `small` writes the marker and nothing else, `standard` writes null
#     (absent and standard are the same state), an unknown value is rejected outright.
run_state seed feat_rec --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed feat_rec failed"
run_state lane feat_rec small >/dev/null 2>&1 || fail "cdd-state lane feat_rec small failed"
[[ "$(jq -r '.lane' "$DIR/feat_rec.state.json")" == "small" ]] || fail "lane did not record small"
[[ "$(jq -r '.base_branch' "$DIR/feat_rec.state.json")" == "$BASE_BRANCH" ]] \
  || fail "cdd-state lane must leave base_branch untouched"
run_state lane feat_rec standard >/dev/null 2>&1 || fail "cdd-state lane ... standard failed"
[[ "$(jq -r '.lane' "$DIR/feat_rec.state.json")" == "null" ]] || fail "standard should record null"
run_state lane feat_rec bogus >/dev/null 2>&1 && fail "lane must reject a value outside {small, standard}"
pass "cdd-state lane records small / clears to null / rejects anything else"

# 9b. Marker but no command file — cdd-small-change.md is not on develop yet, so the
#     project cannot run the lane and the helper must stay on /cdd-plan.
launch_task feat_lane /cdd-plan small
pass "lane routing: the marker alone does not route — the command file must exist too"

# 9c. Ship the command file, then both halves of the AND: marker + file routes, and
#     the same project without a marker is untouched (9b's mirror). The lane's session
#     is an ordinary one — its checkpoint is /cdd-small-change's own approval ask.
(
  cd "$WORK/machine"
  printf 'Make a small, pre-stated change.\n' > .claude/commands/cdd-small-change.md
  git add .claude/commands/cdd-small-change.md
  git commit -q -m "ship cdd-small-change"
  git push -q origin "$BASE_BRANCH"
)
launch_task feat_small /cdd-small-change small
grep -qF -- "--permission-mode plan" "$CLAUDE_STUB_LOG" \
  && fail "the small-change session must NOT be launched in plan mode. Log: $(cat "$CLAUDE_STUB_LOG")"
pass "lane routing: marker + command file launches /cdd-small-change, not in plan mode"

launch_task feat_nolane /cdd-plan
pass "lane routing: no marker is the standard lane, exactly as before"

# 9d. Skew: a cdd-state predating the lane rejects `lane` as an unknown subcommand —
#     the reason it is a subcommand and not a `seed` flag. The failure must stay
#     isolated to that one call, leaving a record 9b has already shown routes to
#     /cdd-plan. The PATH stub is that older helper (it fails everything but `stages`).
run_state seed feat_oldstate --base "$BASE_BRANCH" >/dev/null 2>&1 || fail "seed feat_oldstate failed"
(
  # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
  export HOME="$HOME_DIR" PATH="$WORK/bin:$PATH"
  cd "$WORK/machine" && cdd-state lane feat_oldstate small
) >/dev/null 2>&1 \
  && fail "the stubbed older cdd-state should have rejected the lane subcommand"
[[ "$(jq -r '.base_branch' "$DIR/feat_oldstate.state.json")" == "$BASE_BRANCH" ]] \
  || fail "a rejected lane call must leave the seeded record and its base branch intact"
[[ "$(jq -r '.lane // "absent"' "$DIR/feat_oldstate.state.json")" == "absent" ]] \
  || fail "a rejected lane call must not have written a marker"
pass "lane routing: an older cdd-state rejects only the lane call, keeping the record"

echo "all worktree-launch smoke checks passed"
