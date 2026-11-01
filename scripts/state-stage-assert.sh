#!/usr/bin/env bash
# Regression guard for the PR floor on the task stage (process doc §2.13, ADR 0017).
#
# Once the state record has a PR, `cdd-state set` must never drop `.stage` below
# `pr_open`: a lower write is HELD (the stage stays put), still appends the session entry
# with the requested stage, prints one "stays" line, and still syncs the task ref. With no
# PR there is no floor, so the meaningful pre-PR regressions (`merged` after
# `checks_passed`, a re-plan to `plan_written`) keep writing.
#
# Assertions are against behaviour (the record's fields, the printed line, the ref), never
# against the helper's filter.
#
# Usage: scripts/state-stage-assert.sh
# Takes no arguments; it provisions and tears down its own temp tree. Requires jq (every
# write lives under cdd-state's jq guard); a missing jq is a failure, never a skip.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_STATE="$REPO_ROOT/tools/cdd-state.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER_STATE" ]] || fail "helper not found: $HELPER_STATE"
command -v jq >/dev/null 2>&1 || fail "jq is required and not installed"

# The caller may itself be a Claude Code session; every call below sets its own id.
unset CLAUDE_CODE_SESSION_ID

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Isolate from the caller's git identity / signing config; keep runs deterministic.
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
cat > "$GIT_CONFIG_GLOBAL" <<'GITCONFIG'
[user]
	name = CDD Smoke
	email = smoke@example.com
[init]
	defaultBranch = main
[commit]
	gpgsign = false
GITCONFIG

DEFAULT_BRANCH="main"
FEATURE="feat_floor"

# 1. Bare repo standing in for origin, plus one clone to work in.
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
)

CLONE="$WORK/machine"
HOME_DIR="$WORK/home"
git clone -q "$WORK/origin.git" "$CLONE"
git -C "$CLONE" switch -q "$FEATURE"
DIR="$HOME_DIR/.cdd/handoffs/$(basename "$CLONE")"
FILE="$DIR/$FEATURE.state.json"

# Run `cdd-state <args>` inside the clone with the throwaway HOME, as session <sid>.
# Distinct ids per call: the helper dedups only a repeat of the LAST entry's id.
run_as() {
  local sid="$1"; shift
  (
    cd "$CLONE"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME isolation is intended
    export HOME="$HOME_DIR"
    export CLAUDE_CODE_SESSION_ID="$sid"
    # shellcheck source=/dev/null
    source "$HELPER_STATE"
    cdd-state "$@"
  )
}

# Rewrite the record's stage and pr by hand (pr is raw JSON: a number or null), to put
# it in a state the commands reach by other paths.
put_record() {
  local stage="$1" pr="$2" tmp
  tmp="$(mktemp "$FILE.XXXXXX")"
  jq --arg s "$stage" --argjson p "$pr" '.stage = $s | .pr = $p' "$FILE" > "$tmp"
  mv -f "$tmp" "$FILE"
}

stage_of() { jq -r '.stage' "$FILE"; }
pr_of() { jq -r '.pr' "$FILE"; }
last_session() { jq -c '.sessions[-1] | {id, stage}' "$FILE"; }

# Exactly one line of $1 matches the fixed string $2.
one_line() { [[ "$(grep -cF -- "$2" <<<"$1" || true)" == "1" ]]; }

# 2. Seed the record (with a handoff beside it, so the ref sync has something to carry).
mkdir -p "$DIR"
printf '# Task: %s\n\nBody.\n' "$FEATURE" > "$DIR/$FEATURE.md"
run_as SEED seed "$FEATURE" --base "$DEFAULT_BRANCH" >/dev/null 2>&1 \
  || fail "cdd-state seed failed"

# 3. Reach `addressed` with pr 42 the way the commands do.
run_as P1 set pr_open --pr 42 >/dev/null 2>&1 || fail "set pr_open --pr 42 failed"
run_as P2 set addressed >/dev/null 2>&1 || fail "set addressed failed"
[[ "$(stage_of)/$(pr_of)" == "addressed/42" ]] \
  || fail "setup: expected addressed/42, got $(stage_of)/$(pr_of)"

# a. checks_passed on a record with a PR is held, the session is still recorded.
out="$(run_as S1 set checks_passed 2>/dev/null)" || fail "set checks_passed exited non-zero"
[[ "$(stage_of)" == "addressed" ]] || fail "a: checks_passed lowered the stage to $(stage_of)"
[[ "$(pr_of)" == "42" ]] || fail "a: pr changed to $(pr_of)"
[[ "$(last_session)" == '{"id":"S1","stage":"checks_passed"}' ]] \
  || fail "a: session entry not appended with the requested stage: $(last_session)"
one_line "$out" "stays addressed (PR #42 open; checks_passed not recorded as stage)" \
  || fail "a: expected exactly one held line, got: $out"
pass "set checks_passed with a PR holds the stage at addressed and records the session"

# b. merged on the same record is held too.
out="$(run_as S2 set merged 2>/dev/null)" || fail "set merged exited non-zero"
[[ "$(stage_of)" == "addressed" ]] || fail "b: merged lowered the stage to $(stage_of)"
[[ "$(last_session)" == '{"id":"S2","stage":"merged"}' ]] \
  || fail "b: session entry not appended with the requested stage: $(last_session)"
one_line "$out" "stays addressed (PR #42 open; merged not recorded as stage)" \
  || fail "b: expected exactly one held line, got: $out"
pass "set merged with a PR holds the stage at addressed and records the session"

# c. A late implementation_done is held too.
out="$(run_as S3 set implementation_done 2>/dev/null)" || fail "set implementation_done exited non-zero"
[[ "$(stage_of)" == "addressed" ]] || fail "c: implementation_done lowered the stage to $(stage_of)"
[[ "$(last_session)" == '{"id":"S3","stage":"implementation_done"}' ]] \
  || fail "c: session entry not appended: $(last_session)"
pass "set implementation_done with a PR is held"

# d. No PR, no floor: merged after checks_passed still writes.
put_record checks_passed null
out="$(run_as S4 set merged 2>/dev/null)" || fail "no-PR set merged exited non-zero"
[[ "$(stage_of)" == "merged" ]] || fail "d: with no PR, merged must write; stage is $(stage_of)"
one_line "$out" "-> merged" || fail "d: expected the normal '-> merged' line, got: $out"
! grep -qF "stays" <<<"$out" || fail "d: no-PR write printed a held line: $out"
pass "with no PR, set merged after checks_passed writes merged"

# e. No PR, re-plan: implementation_done back to plan_written still writes.
put_record implementation_done null
run_as S5 set plan_written >/dev/null 2>&1 || fail "no-PR set plan_written failed"
[[ "$(stage_of)" == "plan_written" ]] || fail "e: re-plan must write plan_written; stage is $(stage_of)"
pass "with no PR, a re-plan to plan_written writes"

# f. --pr in the same call counts toward the floor.
put_record checks_passed null
out="$(run_as S6 set merged --pr 7 2>/dev/null)" || fail "set merged --pr 7 exited non-zero"
[[ "$(stage_of)" == "checks_passed" ]] || fail "f: --pr in the same call must count; stage is $(stage_of)"
[[ "$(pr_of)" == "7" ]] || fail "f: --pr 7 was not recorded; pr is $(pr_of)"
one_line "$out" "stays checks_passed (PR #7 open; merged not recorded as stage)" \
  || fail "f: expected exactly one held line, got: $out"
pass "--pr given in the same call is applied first and counts toward the floor"

# g. At or above the floor, writes are unaffected.
put_record addressed 42
run_as S7 set pr_open >/dev/null 2>&1 || fail "set pr_open failed"
[[ "$(stage_of)" == "pr_open" ]] || fail "g: set pr_open with a PR must write; stage is $(stage_of)"
run_as S8 set addressed >/dev/null 2>&1 || fail "set addressed failed"
[[ "$(stage_of)" == "addressed" ]] || fail "g: set addressed with a PR must write; stage is $(stage_of)"
pass "pr_open and addressed still write when a PR exists"

# h. A held write still syncs the task ref, carrying the appended session.
run_as S9 set checks_passed >/dev/null 2>&1 || fail "held set before ref check failed"
[[ "$(stage_of)" == "addressed" ]] || fail "h: setup: write was not held"
ref_commit="$(git -C "$CLONE" ls-remote origin "refs/cdd/$FEATURE" | cut -f1)"
[[ -n "$ref_commit" ]] || fail "h: no refs/cdd/$FEATURE on origin"
git -C "$CLONE" fetch -q origin "refs/cdd/$FEATURE:refs/cdd/$FEATURE" 2>/dev/null \
  || fail "h: could not fetch refs/cdd/$FEATURE back"
synced="$(git -C "$CLONE" show "$ref_commit:state.json")"
[[ "$(jq -c '.sessions[-1] | {id, stage}' <<<"$synced")" == '{"id":"S9","stage":"checks_passed"}' ]] \
  || fail "h: the held write's session did not ride the task ref"
[[ "$(jq -r '.stage' <<<"$synced")" == "addressed" ]] \
  || fail "h: the ref's record does not carry the held stage"
pass "a held write still syncs refs/cdd/$FEATURE with the appended session"

echo "all state-stage checks passed"
