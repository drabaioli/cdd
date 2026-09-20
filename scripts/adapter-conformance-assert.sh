#!/usr/bin/env bash
# Contract checks for scripts/adapter-conformance-check.sh, the adapter-conformance gate.
#
# Same reasoning as scripts/prompt-seam-assert.sh and scripts/command-drift-assert.sh,
# applied to the guard that checks a capability adapter. The argument is sharper here
# than for either of those: the only subject in this tree is a CONFORMANT adapter, so
# the gate passes on every run and will keep passing whether or not it still works.
# A conformance checker's whole value is its ability to fail.
#
# So this script mutation-tests it: break one thing at a time in a throwaway copy of the
# adapter and require the checker to notice, naming what it noticed. Each of the
# checker's seven checks gets at least one mutation:
#   1. describe is hermetic      — describe authenticates; describe emits non-JSON.
#   2. describe is contract-shaped — describe lists itself in verbs; it emits a null;
#      its ref_pattern is not a valid ERE.
#   3. Declared verbs dispatch   — the adapter declares a verb it does not implement.
#   4. Unsupported verb -> 3     — an unknown verb exits 1 instead.
#   5. Usage error -> 2          — a missing argument exits 1 instead.
#   6. Missing backend -> 4      — an absent `gh` exits 1 instead.
#   7. Secret scan               — one planted secret per pattern the scan carries (a
#      token prefix, a fine-grained PAT, a PEM header, a secret-shaped assignment),
#      because the patterns are independent greps and one plant would leave three free
#      to rot unnoticed.
#
# Plus two controls, which are what make the mutations mean anything:
#   - An unmutated copy must PASS. Without this, every mutation could be "detected" by a
#     checker that is simply broken and fails on everything.
#   - An adapter that omits the optional `create_target` must PASS, pinning the other
#     direction: the checker must not have quietly started requiring an optional field.
#
# Every mutation is verified to have actually CHANGED the file before the checker runs.
# A mutation whose anchor has rotted away applies nothing, and a checker "detecting" an
# unbroken adapter would be the same false confidence this script exists to prevent.
#
# It copies the working tree's adapter, not HEAD's, so this gate tests the checker and
# the adapter as they are right now. The real tree is never mutated.
#
# Usage: scripts/adapter-conformance-assert.sh   (no arguments; no side effects outside $TMPDIR)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

CHECKER="./scripts/adapter-conformance-check.sh"
ADAPTER="tools/cdd-tracker-github.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -x "$CHECKER" ]] || fail "checker not found or not executable: $CHECKER"
[[ -x "$ADAPTER" ]] || fail "adapter not found or not executable: $ADAPTER"

# The checker skips without jq, so every expect_fail below would see a clean exit 0 and
# report a checker that has stopped firing. Skip loudly instead — the runner's posture
# for a gate whose tool is missing.
if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the checker itself skips without it, so it cannot be mutation-tested"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MASTER="$WORK/master.sh"
SUBJECT="$WORK/subject.sh"
cp "$ADAPTER" "$MASTER" || fail "could not copy $ADAPTER into the sandbox"

# --- Mutation helpers ---------------------------------------------------------
# Rewrite the master into the subject through an awk program. Not `sed -i`: the in-place
# flag differs between GNU and BSD sed, and this runs on contributors' hosts too. Each
# helper asserts the rewrite changed something, so a rotted anchor fails loudly here
# instead of producing a vacuous "detection" below.
apply() {  # apply <label> <awk arg>...
  local label="$1"; shift
  awk "$@" "$MASTER" > "$SUBJECT" || fail "$label: awk rewrite failed"
  chmod 755 "$SUBJECT"
  cmp -s "$MASTER" "$SUBJECT" &&
    fail "$label: the mutation changed nothing — its anchor no longer matches $ADAPTER"
  return 0
}

mutate_replace_line() {  # mutate_replace_line <label> <line regex> <replacement>
  # SC2016: single quotes are deliberate — $0 is awk's whole-line variable, not a shell
  # positional. The shell values ride in on -v, which is what keeps them unexpanded here.
  # shellcheck disable=SC2016
  apply "$1" -v "repl=$3" -v "pat=$2" '$0 ~ pat && !done { print repl; done = 1; next } { print }'
}

mutate_insert_after() {  # mutate_insert_after <label> <line regex> <inserted line>
  # SC2016: as above — $0 is awk's, and the shell values arrive through -v.
  # shellcheck disable=SC2016
  apply "$1" -v "ins=$3" -v "pat=$2" '{ print } $0 ~ pat && !done { print ins; done = 1 }'
}

mutate_prog() {  # mutate_prog <label> <awk program>
  apply "$1" "$2"
}

# --- Running the checker against the mutated copy -----------------------------
run_checker() {
  OUT="$("$CHECKER" "$SUBJECT" 2>&1)"
  STATUS=$?
}

expect_pass() {  # expect_pass <label>
  run_checker
  [[ $STATUS -eq 0 ]] \
    || fail "$1: the conformance check should have passed but exited $STATUS: $OUT"
  pass "$1"
}

expect_fail() {  # expect_fail <label> <needle>
  run_checker
  [[ $STATUS -ne 0 ]] \
    || fail "$1: the conformance check passed on a deliberately broken adapter — the check is not firing"
  grep -qF -- "$2" <<<"$OUT" \
    || fail "$1: the conformance check failed, but not with '$2'. It reported: $OUT"
  pass "$1"
}

# --- Control: an unmutated copy passes ----------------------------------------
cp "$MASTER" "$SUBJECT"; chmod 755 "$SUBJECT"
expect_pass "control: an unmutated copy of the adapter passes"

# --- Check 1: describe is hermetic --------------------------------------------
mutate_insert_after "describe authenticates" '^verb_describe\(\) \{' '  require_gh'
expect_fail "describe that authenticates is caught" "describe with gh absent from PATH"

mutate_insert_after "describe emits non-JSON" '^verb_describe\(\) \{' '  echo "not json"'
expect_fail "describe that emits non-JSON is caught" "did not emit parseable JSON"

# --- Check 2: describe is contract-shaped -------------------------------------
mutate_replace_line "describe lists itself in verbs" '^DECLARED_VERBS=' \
  'DECLARED_VERBS='"'"'["describe","issue-read","issue-list","issue-create","issue-close-token"]'"'"''
expect_fail "describe listing itself in verbs is caught" "not contract-shaped"

mutate_replace_line "describe emits a null" "^  printf '}" \
  '  printf '"'"',"broken":null}\n'"'"''
expect_fail "describe emitting a null is caught" "emits null somewhere"

mutate_replace_line "ref_pattern is not a valid ERE" '^REF_PATTERN=' \
  'REF_PATTERN='"'"'^#?[0-9+$'"'"''
expect_fail "an unparseable ref_pattern is caught" "not a valid ERE"

# --- Check 3: every declared verb dispatches to an implementation -------------
mutate_replace_line "declares a verb it does not implement" '^DECLARED_VERBS=' \
  'DECLARED_VERBS='"'"'["issue-read","issue-list","issue-create","issue-close-token","issue-transition"]'"'"''
expect_fail "a declared-but-unimplemented verb is caught" "declared verb 'issue-transition' exits 3"

# --- Check 4: an unsupported verb exits 3 -------------------------------------
# Scoped to the line after the unknown-verb message, so the deliberate exit 3 on
# issue-transition (a different branch) is left alone.
# SC2016: $0 is awk's current line.
# shellcheck disable=SC2016
mutate_prog "unknown verb exits 1" \
  '{ if (prev ~ /unknown verb/) sub(/exit 3/, "exit 1"); print; prev = $0 }'
expect_fail "an unknown verb exiting 1 instead of 3 is caught" "expected exit 3, got 1"

# --- Check 5: a usage error exits 2 -------------------------------------------
mutate_prog "usage error exits 1" \
  '/^normalize_ref\(\) \{/ { inf = 1 } inf && /^\}/ { inf = 0 } inf { sub(/exit 2/, "exit 1") } { print }'
expect_fail "a usage error exiting 1 instead of 2 is caught" "expected exit 2, got 1"

# --- Check 6: a missing backend exits 4 ---------------------------------------
mutate_prog "missing backend exits 1" \
  '/^require_gh\(\) \{/ { inf = 1 } inf && /^\}/ { inf = 0 } inf { sub(/exit 4/, "exit 1") } { print }'
expect_fail "a missing backend exiting 1 instead of 4 is caught" "expected exit 4, got 1"

# --- Check 7: the secret scan -------------------------------------------------
# One mutation per pattern the scan carries, not one for the scan as a whole: the
# patterns are independent greps, so a single planted secret leaves the other three free
# to rot unnoticed. Each is planted inside a comment so the adapter still runs and the
# earlier checks stay green, leaving the scan as the thing that fires. The values are
# deliberately well-formed but worthless.
while IFS='|' read -r what literal; do
  mutate_insert_after "$what" '^set -euo pipefail' "# $literal"
  expect_fail "$what in the adapter is caught" "secret-shaped string"
done <<'SECRETS'
a GitHub token prefix|ghp_000000000000000000000000000000000000
a GitHub fine-grained PAT prefix|github_pat_00000000000000000000_0000000000
a PEM private-key header|-----BEGIN RSA PRIVATE KEY-----
a secret-shaped assignment|api_key = "not-a-real-secret-but-shaped-like-one"
SECRETS

# --- Control: an optional field stays optional --------------------------------
# The mirror of the mutations above. `create_target` is omit-when-underivable by the
# contract, so an adapter that never emits it is conformant — a checker that started
# requiring it would be wrong in the direction no mutation can reveal.
# SC2016: the regex matches the adapter's literal `$target` text; expanding it here
# would look for this script's own (unset) variable instead.
# shellcheck disable=SC2016
mutate_replace_line "create_target omitted" '^  if \[\[ -n "\$target" \]\]; then' '  if false; then'
expect_pass "control: an adapter omitting the optional create_target passes"

echo "adapter-conformance checker contract: clean (13 mutations, 2 controls)"
