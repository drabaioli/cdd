#!/usr/bin/env bash
# Conformance guard for a CDD capability adapter — any capability with a published
# contract (today: tracker and docs).
#
# Checks an adapter against the contract in doc/architecture/capability-adapters.md:
# `describe` is hermetic and contract-shaped, every verb it declares dispatches to a
# real implementation, an undeclared verb exits 3, a usage error exits 2, missing
# backend tooling or configuration exits 4, and nothing secret-shaped is committed
# alongside it (process doc §2.16: CDD never stores, reads or proxies a secret).
#
# It is OFFLINE BY CONSTRUCTION, with no cooperation from the adapter: it runs the
# subject with a scrubbed environment (`env -i`, so no exported credential or backend
# coordinate reaches it) under a scratch PATH holding stub backend tools (`gh`, `curl`)
# or none at all, so nothing it invokes can reach the network or authenticate. The
# checks are backend-neutral: a `gh`-based and a curl-based adapter pass or fail them
# for the same reasons. A probe-mode environment variable was the alternative
# and was rejected — it would add permanent surface to the contract that every future
# adapter has to implement, purely to serve one gate, and it would test a code path no
# real caller ever takes.
#
# What it proves and what it does not: probing a declared verb with no arguments shows
# that dispatch REACHES an implementation, not that the implementation is CORRECT.
# Correctness needs a live call against a real backend, which the offline-only decision
# rules out on purpose — a gate that SKIPs on most hosts is a gate nobody can rely on.
# Every other check here is exact; the verb probe is a floor.
#
# The capability is read from the subject's own `describe` and selects a row of the
# per-capability table below: that capability's contract verbs, the usage-error probe
# (check 5) and the missing-backend probe (check 6). Every other check is shared.
#
# Usage: scripts/adapter-conformance-check.sh [<adapter path>]
# Defaults to the shipped tracker reference adapter. Takes an explicit path so a project
# can point it at its own .cdd/tracker or .cdd/docs. Requires jq; without it the check
# skips (advisory), matching the runner's posture for a gate whose tool is absent.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBJECT="${1:-$REPO_ROOT/tools/adapters/tracker/github.sh}"

# Per capability: the non-`describe` contract verbs (`describe` is excluded because it
# is mandatory for every adapter and is checked separately), then the check-5 probe — a
# verb that needs an argument, called without one — then the check-6 probe: a call that
# is well-formed, so it gets past argument validation and has to stop at the missing
# backend. Set by select_capability once describe has named the capability.
CONTRACT_VERBS='' USAGE_PROBE=() BACKEND_PROBE=()
select_capability() {  # select_capability <capability>
  case "$1" in
    tracker)
      CONTRACT_VERBS='["issue-read","issue-list","issue-create","issue-transition","issue-close-token"]'
      USAGE_PROBE=(issue-read)
      BACKEND_PROBE=(issue-list)
      ;;
    docs)
      CONTRACT_VERBS='["doc-search","doc-read","doc-stat"]'
      USAGE_PROBE=(doc-read)
      BACKEND_PROBE=(doc-stat 12345)
      ;;
    *) return 1 ;;
  esac
}

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$SUBJECT" ]] || fail "adapter not found: $SUBJECT"
[[ -x "$SUBJECT" ]] || fail "adapter is not executable: $SUBJECT (an adapter is discovered by \`-x\`)"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the describe shape checks need it"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- The two scratch PATHs ----------------------------------------------------
# Pass A: stub backend tools first on PATH. The stub `gh`'s `auth status` succeeds so
# a gh-based adapter proceeds past its auth gate; every other invocation fails, and
# the stub `curl` always fails with curl's own couldn't-connect code, standing in for
# a backend that cannot be reached. Nothing here touches the network.
mkdir -p "$WORK/stub" "$WORK/home"
cat > "$WORK/stub/gh" <<'STUB'
#!/usr/bin/env bash
# Stub GitHub CLI. Authenticated, and useless for anything else.
if [[ "${1-}" == "auth" && "${2-}" == "status" ]]; then
  exit 0
fi
echo "stub gh: refusing to contact the network" >&2
exit 1
STUB
cat > "$WORK/stub/curl" <<'STUB'
#!/usr/bin/env bash
# Stub curl. Every request fails as if the host were unreachable.
echo "stub curl: refusing to contact the network" >&2
exit 7
STUB
chmod 755 "$WORK/stub/gh" "$WORK/stub/curl"
STUB_PATH="$WORK/stub:$PATH"

# Pass B: backend tooling genuinely absent. Built as a minimal bin directory rather
# than by filtering the caller's PATH, because `gh` and `curl` live in /usr/bin on a
# GitHub Actions runner — dropping that directory would take git, sed and grep with it.
mkdir -p "$WORK/nobackend"
for tool in bash sh env git sed grep basename dirname head tail cat tr cut printf; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  # Absolute paths only: a shell that resolves a name to itself (an alias, a function)
  # would otherwise produce a self-referential symlink that silently resolves to nothing.
  [[ "$src" == /* ]] && ln -sf "$src" "$WORK/nobackend/$tool"
done
NOBACKEND_PATH="$WORK/nobackend"
for tool in gh curl wget; do
  PATH="$NOBACKEND_PATH" command -v "$tool" >/dev/null 2>&1 &&
    fail "the no-backend scratch PATH still resolves \`$tool\`; the exit-4 assertions would be vacuous"
done

# Run the subject with a given PATH and an otherwise EMPTY environment; echo its exit
# code. The scrub is what keeps the verdict host-independent: without it, a caller who
# happens to have JIRA_API_TOKEN or GH_TOKEN exported would hand the subject exactly
# the configuration the exit-4 and hermeticity checks assume is absent. Never lets a
# non-zero exit abort this script — the exit code IS the observation.
probe() {  # probe <path> <arg>...
  local path="$1"; shift
  local rc=0
  env -i PATH="$path" HOME="$WORK/home" "$SUBJECT" "$@" >"$WORK/out" 2>"$WORK/err" || rc=$?
  printf '%s' "$rc"
}

expect_exit() {  # expect_exit <want> <path> <label> <arg>...
  local want="$1" path="$2" label="$3"; shift 3
  local got
  got="$(probe "$path" "$@")"
  [[ "$got" == "$want" ]] || {
    echo "  stderr: $(head -2 "$WORK/err" | tr '\n' ' ')" >&2
    fail "$label: expected exit $want, got $got"
  }
}

# --- 1. describe is hermetic --------------------------------------------------
# No network, no auth, always exit 0 — checked with backend tooling absent entirely and
# the environment scrubbed, which is the strongest available form of "it needed nothing
# from the backend".
expect_exit 0 "$NOBACKEND_PATH" "describe with backend tooling absent and the environment scrubbed" describe
cp "$WORK/out" "$WORK/describe.json"
jq -e . "$WORK/describe.json" >/dev/null 2>&1 ||
  fail "describe did not emit parseable JSON on stdout: $(head -c 200 "$WORK/describe.json")"
pass "describe is hermetic: exit 0 and parseable JSON with backend tooling absent and the environment scrubbed"

# --- 2. describe is contract-shaped -------------------------------------------
CAPABILITY="$(jq -r '.capability | if type == "string" then . else "" end' "$WORK/describe.json")"
select_capability "$CAPABILITY" ||
  fail "describe.capability is '$CAPABILITY', not a capability with a published contract (tracker, docs); describe is not contract-shaped"
jq -e --argjson contract_verbs "$CONTRACT_VERBS" '
  (.contract | type == "number" and . == floor and . >= 1)
  and (.backend | type == "string" and length > 0)
  and (.ref_pattern | type == "string" and length > 0)
  and (.verbs | type == "array" and length > 0 and all(type == "string"))
  and (.verbs | index("describe") == null)
  and ((.verbs - $contract_verbs) | length == 0)
  and ((has("link_pattern") | not) or (.link_pattern | type == "string" and length > 0))
' "$WORK/describe.json" >/dev/null || {
  jq -c . "$WORK/describe.json" >&2
  fail "describe is not contract-shaped (see doc/architecture/capability-adapters.md)"
}

# Omit-don't-null: an absent field means "unsupported", so a null anywhere is a bug.
[[ "$(jq -c '[.. | select(. == null)] | length' "$WORK/describe.json")" == "0" ]] ||
  fail "describe emits null somewhere; the contract says omit an unsupported field, never null it"

# ref_pattern has to be an ERE the caller can actually dispatch on. grep exits 2 on a
# malformed pattern and 0/1 on a well-formed one, matched or not.
REF_PATTERN="$(jq -r '.ref_pattern' "$WORK/describe.json")"
grep_rc=0
printf '' | grep -E "$REF_PATTERN" >/dev/null 2>&1 || grep_rc=$?
[[ "$grep_rc" -le 1 ]] || fail "describe.ref_pattern is not a valid ERE: $REF_PATTERN"
# link_pattern is optional (docs only today); when present it gets the same test.
if [[ "$(jq -r 'has("link_pattern")' "$WORK/describe.json")" == true ]]; then
  LINK_PATTERN="$(jq -r '.link_pattern' "$WORK/describe.json")"
  grep_rc=0
  printf '' | grep -E "$LINK_PATTERN" >/dev/null 2>&1 || grep_rc=$?
  [[ "$grep_rc" -le 1 ]] || fail "describe.link_pattern is not a valid ERE: $LINK_PATTERN"
fi
pass "describe is contract-shaped ($CAPABILITY, ref_pattern $REF_PATTERN, $(jq -r '.verbs | length' "$WORK/describe.json") verbs declared, no nulls)"

# --- 3. every declared verb dispatches to an implementation -------------------
# Invoked with no arguments under the stub, each must exit something other than 3.
# This is only meaningful because the contract requires dispatch to precede backend
# work: an adapter that authenticated before parsing would exit 4 here for reasons
# that say nothing about dispatch, and is non-conformant by construction.
while IFS= read -r verb; do
  rc="$(probe "$STUB_PATH" "$verb")"
  [[ "$rc" == "3" ]] &&
    fail "declared verb '$verb' exits 3 (unsupported); describe.verbs claims it is implemented"
  pass "declared verb '$verb' dispatches (exit $rc, not 3)"
done < <(jq -r '.verbs[]' "$WORK/describe.json")

# --- 4. an unsupported verb exits 3 -------------------------------------------
# Two cases: a verb the contract defines but this backend does not declare, and a verb
# that is not in the contract at all. Both are "not supported by this backend" = 3.
while IFS= read -r verb; do
  expect_exit 3 "$STUB_PATH" "undeclared contract verb '$verb'" "$verb"
  pass "undeclared contract verb '$verb' exits 3"
done < <(jq -r --argjson contract_verbs "$CONTRACT_VERBS" '$contract_verbs - .verbs | .[]' "$WORK/describe.json")

expect_exit 3 "$STUB_PATH" "a verb that is not in the contract at all" definitely-not-a-verb
pass "an unknown verb exits 3"

# --- 5. a usage error exits 2 -------------------------------------------------
# Distinct from 3 (wrong verb) and from 4 (no credentials), and reached without either.
expect_exit 2 "$STUB_PATH" "${USAGE_PROBE[*]} with no argument" "${USAGE_PROBE[@]}"
expect_exit 2 "$NOBACKEND_PATH" "${USAGE_PROBE[*]} with no argument and backend tooling absent" "${USAGE_PROBE[@]}"
pass "a usage error exits 2, before any backend contact"

# --- 6. a missing backend exits 4 with an actionable line ---------------------
# Missing tooling (a gh-based adapter) or missing configuration (an env-configured
# one): with both absent, either reason must surface as 4, never as 1.
expect_exit 4 "$NOBACKEND_PATH" "${BACKEND_PROBE[*]} with backend tooling absent and the environment scrubbed" "${BACKEND_PROBE[@]}"
[[ -s "$WORK/err" ]] || fail "exit 4 carried no message on stderr; the contract requires an actionable one"
pass "a missing backend exits 4: $(head -1 "$WORK/err")"

# --- 7. nothing secret-shaped is committed ------------------------------------
# §2.16: an adapter carries coordinates only — it may name an environment variable,
# never contain one. Scans the adapter itself and any committed .cdd/ alongside it.
scan_targets=("$SUBJECT")
if [[ -d "$REPO_ROOT/.cdd" ]]; then
  while IFS= read -r f; do scan_targets+=("$f"); done < <(find "$REPO_ROOT/.cdd" -type f)
fi
secret_patterns=(
  'gh[pousr]_[A-Za-z0-9]{16,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AT[AC]TT[A-Za-z0-9_=-]{40,}'
  'Authorization:[[:space:]]*Basic[[:space:]]+[A-Za-z0-9+/=]{16,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY'
  '(password|passwd|secret|token|api[_-]?key)[[:space:]]*=[[:space:]]*.[^"'"'"']{8,}'
)
for pattern in "${secret_patterns[@]}"; do
  # `-e` is load-bearing: the PEM pattern starts with `-----`, which grep would
  # otherwise parse as a bundle of options and then match nothing at all.
  if grep -nEI -e "$pattern" "${scan_targets[@]}" >"$WORK/hits" 2>/dev/null; then
    cat "$WORK/hits" >&2
    fail "secret-shaped string in an adapter or under .cdd/ (pattern: $pattern)"
  fi
done
pass "no secret-shaped strings in ${#scan_targets[@]} scanned file(s)"

echo "adapter conformance: $SUBJECT satisfies the $CAPABILITY contract (offline)"
