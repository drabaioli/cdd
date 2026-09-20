#!/usr/bin/env bash
# Regression guard for extension fields on the state record (process doc §2.13).
#
# The point is NOT that `cdd-state set-field` works — it is that a foreign top-level
# key survives every verb that rewrites the record. That property is free today,
# because `set`, `lane` and `set-field` all build a jq filter of field *assignments*
# over the existing file; it would be silently lost the day one of them is refactored
# into a rebuild-from-scratch form. So the assertions below are written against
# behaviour ("both foreign keys are still byte-identical after this write"), never
# against the current filter.
#
# The record is seeded with two foreign keys: an `x-` field written through the new
# verb, and a hand-written non-`x-` key standing in for a field a NEWER CDD writes and
# this helper knows nothing about. Both must round-trip.
#
# Also covered: value round-trip by JSON type (null included, as a present null-valued
# field), CDD's own fields untouched, every rejection leaving the file byte-identical,
# never fabricating an absent record, --branch vs cwd-derivation targeting different
# records, and the write reaching refs/cdd/<branch> on origin.
#
# Usage: scripts/state-extension-assert.sh
# Takes no arguments; it provisions and tears down its own temp tree. Requires jq
# (every write lives under cdd-state's jq guard); without it the test skips (advisory).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_STATE="$REPO_ROOT/tools/cdd-state.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER_STATE" ]] || fail "helper not found: $HELPER_STATE"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; state writes are advisory and skip without it"
  exit 0
fi

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
FEATURE="feat_ext"
OTHER="feat_other"     # a second task, targeted only through --branch
ABSENT="feat_norecord" # a branch that never gets a record

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
DIR="$HOME_DIR/.cdd/handoffs/$(basename "$CLONE")"
FILE="$DIR/$FEATURE.state.json"
FILE_OTHER="$DIR/$OTHER.state.json"

# Run cdd-state inside the clone with the throwaway HOME. Echoes the exit status of
# the call itself, never the subshell's setup.
run_state() {
  (
    cd "$CLONE"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME isolation is intended
    export HOME="$HOME_DIR"
    # shellcheck source=/dev/null
    source "$HELPER_STATE"
    cdd-state "$@"
  )
}

# Exit status of a call expected to fail, with output swallowed.
status_of() {
  set +e
  run_state "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc"
}

# A JSON value, normalised so nested key order cannot cause a false failure.
field_of() { jq -S -c --arg k "$2" '.[$k]' "$1"; }

# 2. Seed the record on the feature branch, then put two foreign keys on it.
mkdir -p "$DIR"
printf '# Task: %s\n\nBody.\n' "$FEATURE" > "$DIR/$FEATURE.md"
git -C "$CLONE" switch -q "$FEATURE"
run_state seed "$FEATURE" --base "$DEFAULT_BRANCH" >/dev/null 2>&1 \
  || fail "cdd-state seed failed"

X_KEY="x-tracker"
X_VALUE='{"backend":"jira","ref":"PROJ-114","links":["a","b"],"n":3,"deep":{"z":1,"a":null}}'
run_state set-field "$X_KEY" "$X_VALUE" >/dev/null 2>&1 \
  || fail "set-field failed on a seeded record"
[[ "$(field_of "$FILE" "$X_KEY")" == "$(jq -S -c . <<<"$X_VALUE")" ]] \
  || fail "set-field did not store the value verbatim: $(field_of "$FILE" "$X_KEY")"
pass "set-field wrote a nested object value verbatim"

# The second foreign key is written by hand, with no `x-` prefix: it stands in for a
# field a NEWER CDD writes, which this helper must also pass through rather than drop.
FUTURE_KEY="future_cdd_field"
FUTURE_VALUE='{"written_by":"a newer cdd","v":2}'
tmp="$(mktemp "$FILE.XXXXXX")"
jq --arg k "$FUTURE_KEY" --argjson v "$FUTURE_VALUE" '.[$k] = $v' "$FILE" > "$tmp"
mv -f "$tmp" "$FILE"

X_WANT="$(field_of "$FILE" "$X_KEY")"
FUTURE_WANT="$(field_of "$FILE" "$FUTURE_KEY")"

# Both foreign keys survive, byte-identical, and schema_version is untouched.
assert_survives() {
  local after="$1"
  [[ "$(field_of "$FILE" "$X_KEY")" == "$X_WANT" ]] \
    || fail "$after dropped or changed '$X_KEY' (got: $(field_of "$FILE" "$X_KEY"))"
  [[ "$(field_of "$FILE" "$FUTURE_KEY")" == "$FUTURE_WANT" ]] \
    || fail "$after dropped or changed '$FUTURE_KEY' (got: $(field_of "$FILE" "$FUTURE_KEY"))"
  [[ "$(jq -r '.schema_version' "$FILE")" == "1" ]] \
    || fail "$after changed schema_version (extension fields need no version bump)"
}

# 3. The core assertion: every rewriting verb preserves both foreign keys.
run_state lane "$FEATURE" small >/dev/null 2>&1 || fail "cdd-state lane failed"
assert_survives "lane"
run_state set plan_written >/dev/null 2>&1 || fail "cdd-state set failed"
assert_survives "set <stage>"
run_state set pr_open --pr 42 >/dev/null 2>&1 || fail "cdd-state set --pr failed"
assert_survives "set <stage> --pr"
run_state set-field x-second '"another"' >/dev/null 2>&1 || fail "second set-field failed"
assert_survives "a second set-field"
pass "both foreign keys survived lane, set, set --pr and a second set-field"

# 4. CDD's own fields are untouched by set-field.
own_fields() { jq -S -c '{schema_version, branch, stage, pr, base_branch, lane, sessions}' "$FILE"; }
before="$(own_fields)"
run_state set-field x-third '[1,2,3]' >/dev/null 2>&1 || fail "set-field x-third failed"
[[ "$(own_fields)" == "$before" ]] \
  || fail "set-field changed CDD's own fields: $before -> $(own_fields)"
pass "set-field left schema_version/branch/stage/pr/base_branch/lane/sessions untouched"

# 5. Value round-trip by JSON type. `null` lands as a PRESENT null-valued field —
#    absent and null carry distinct meaning in this record (`pr`, `lane`), so removal
#    is deliberately not what `null` means.
for pair in 'x-obj:{"a":[1,{"b":null}]}' 'x-arr:[1,"two",null,true]' 'x-str:"a string"' 'x-num:4.5' 'x-bool:false' 'x-nul:null'; do
  key="${pair%%:*}"; value="${pair#*:}"
  run_state set-field "$key" "$value" >/dev/null 2>&1 \
    || fail "set-field rejected a valid JSON value: $key = $value"
  [[ "$(field_of "$FILE" "$key")" == "$(jq -S -c . <<<"$value")" ]] \
    || fail "$key did not round-trip: wrote $value, read $(field_of "$FILE" "$key")"
done
[[ "$(jq 'has("x-nul")' "$FILE")" == "true" ]] \
  || fail "set-field <key> null must leave a present null-valued field, not an absent one"
pass "object, array, string, number, boolean and null values all round-trip (null stays present)"

# 6. Rejections, each leaving the record byte-identical.
BEFORE="$WORK/before.json"
assert_rejected() {
  local want="$1" desc="$2"; shift 2
  cp "$FILE" "$BEFORE"
  local rc; rc="$(status_of "$@")"
  [[ "$rc" == "$want" ]] || fail "$desc: expected exit $want, got $rc"
  cmp -s "$BEFORE" "$FILE" || fail "$desc: the record was modified (it must not be)"
}
assert_rejected 2 "a non-x- key" set-field stage merged
assert_rejected 2 "a non-x- key (sessions)" set-field sessions '[]'
assert_rejected 2 "an invalid JSON value" set-field x-bad '{not json'
assert_rejected 2 "an empty value" set-field x-bad ''
assert_rejected 2 "a missing value" set-field x-bad
assert_rejected 2 "a missing key" set-field
assert_rejected 2 "an option-shaped key" set-field --branch "$FEATURE"
assert_rejected 2 "an unknown flag" set-field x-ok '1' --nope v
assert_rejected 0 "--help" set-field --help
pass "every rejection exits as documented and leaves the record byte-identical"
[[ "$(jq 'has("stage") and .stage == "pr_open"' "$FILE")" == "true" ]] \
  || fail 'a rejected "set-field stage merged" must not have touched .stage'
pass "set-field is not a backdoor around set's stage validation"

# 7. Never fabricates a record.
rc="$(status_of set-field x-foo '1' --branch "$ABSENT")"
[[ "$rc" == "0" ]] || fail "set-field on an absent record should exit 0 (advisory), got $rc"
[[ ! -f "$DIR/$ABSENT.state.json" ]] \
  || fail "set-field fabricated a record at $DIR/$ABSENT.state.json"
pass "set-field never fabricates an absent record"

# 8. --branch targets the named record; cwd-derivation targets the current branch's.
printf '# Task: %s\n\nBody.\n' "$OTHER" > "$DIR/$OTHER.md"
run_state seed "$OTHER" --base "$DEFAULT_BRANCH" >/dev/null 2>&1 || fail "seed $OTHER failed"
run_state set-field x-who '"by-branch-flag"' --branch "$OTHER" >/dev/null 2>&1 \
  || fail "set-field --branch failed"
run_state set-field x-who '"by-cwd"' >/dev/null 2>&1 || fail "set-field (cwd) failed"
[[ "$(jq -r '.["x-who"]' "$FILE_OTHER")" == "by-branch-flag" ]] \
  || fail "--branch did not target $OTHER's record"
[[ "$(jq -r '.["x-who"]' "$FILE")" == "by-cwd" ]] \
  || fail "cwd-derivation did not target $FEATURE's record"
[[ "$(jq 'has("x-tracker")' "$FILE_OTHER")" == "false" ]] \
  || fail "the two records leaked into each other"
pass "--branch and cwd-derivation target their own records, with no crossover"

# 9. The write reaches the task ref on origin.
run_state set-field x-synced '"yes"' >/dev/null 2>&1 || fail "set-field before ref check failed"
ref_commit="$(git -C "$CLONE" ls-remote origin "refs/cdd/$FEATURE" | cut -f1)"
[[ -n "$ref_commit" ]] || fail "set-field did not push refs/cdd/$FEATURE to origin"
git -C "$CLONE" fetch -q origin "refs/cdd/$FEATURE:refs/cdd/$FEATURE" 2>/dev/null \
  || fail "could not fetch refs/cdd/$FEATURE back"
[[ "$(git -C "$CLONE" show "$ref_commit:state.json" | jq -r '.["x-synced"]')" == "yes" ]] \
  || fail "the extension field did not ride the task ref"
pass "set-field synced the record to refs/cdd/$FEATURE, extension field included"

echo "all state-extension checks passed"
