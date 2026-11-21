#!/usr/bin/env bash
# The shipped contract checker's own contract (template/scripts/practices-check.sh; process
# doc §2.12, ADR 0029): this repo's scripts/practices-check.sh is identical to it, how it is
# invoked, how it fails, and that a bootstrapped tree carries it. Its scan rules prove themselves on every run (its self-check); this covers the rest.
#
# Each case runs a copy of the checker in its own sandbox tree, against a fixture contract
# and a stub runner whose `list` mode the case controls.
#
# Usage: scripts/practices-check-assert.sh
# Takes no arguments. Requires jq (the bootstrap script refuses without it); a missing jq is
# a failure, never a skip.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$REPO_ROOT/template/scripts/practices-check.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

command -v jq >/dev/null 2>&1 || fail "jq is required and not installed"

cmp -s "$CHECKER" "$REPO_ROOT/scripts/practices-check.sh" \
  || fail "scripts/practices-check.sh differs from template/scripts/practices-check.sh; edit both alike"
pass "this repo's checker is identical to the shipped one"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# sandbox <name> <list output, or "fail">: a tree holding the checker, a valid contract
# and a stub runner `./run` whose `list` prints the given text (or exits 1).
sandbox() {
  local sb="$WORK/$1"
  mkdir -p "$sb/scripts" "$sb/doc/knowledge_base"
  cp "$CHECKER" "$sb/scripts/"
  # shellcheck disable=SC2016  # the backticks are literal markdown
  printf '# Contract\n\n## Tests — Enforced\n- Gates: `alpha`\n\n## Docs — Upheld\n' \
    > "$sb/doc/knowledge_base/engineering-practices.md"
  if [[ "$2" == fail ]]; then
    printf '#!/usr/bin/env bash\nexit 1\n' > "$sb/run"
  else
    printf '#!/usr/bin/env bash\nprintf %%s %q\n' "$2" > "$sb/run"
  fi
  chmod +x "$sb/run"
  echo "$sb"
}

# run_check <sandbox> [<arg>...]: run the checker there; sets rc and err.
run_check() {
  local sb="$1"; shift
  rc=0
  err="$(cd "$sb" && scripts/practices-check.sh "$@" 2>&1 >/dev/null)" || rc=$?
}

sb="$(sandbox noarg 'alpha')"
run_check "$sb"
[[ $rc -eq 2 ]] || fail "no argument: expected exit 2, got $rc"
pass "no argument is a usage error"

sb="$(sandbox listfail fail)"
run_check "$sb" ./run
[[ $rc -ne 0 && "$err" == *'./run list'* ]] || fail "a failing list mode: expected a failure naming './run list', got $rc: $err"
pass "a failing list mode fails, naming the command"

sb="$(sandbox listempty '')"
run_check "$sb" ./run
[[ $rc -ne 0 && "$err" == *'returned no gates'* ]] || fail "an empty list: expected 'returned no gates', got $rc: $err"
pass "an empty list fails"

sb="$(sandbox nocontract 'alpha')"
rm "$sb/doc/knowledge_base/engineering-practices.md"
run_check "$sb" ./run
[[ $rc -ne 0 && "$err" == *'not found'* ]] || fail "no contract: expected 'not found', got $rc: $err"
pass "a missing contract fails"

sb="$(sandbox valid $'alpha  the first gate\nbeta\n')"
run_check "$sb" ./run
[[ $rc -eq 0 ]] || fail "a backed contract: expected exit 0, got $rc: $err"
pass "a backed contract passes, reading the first field of each list line"

sb="$(sandbox unregistered $'beta\n')"
run_check "$sb" ./run
# shellcheck disable=SC2016  # the backticks are literal output
[[ $rc -ne 0 && "$err" == *'unregistered gate `alpha`'* ]] || fail "an unregistered gate: expected it named, got $rc: $err"
pass "a gate the list does not print fails"

# A bootstrapped tree carries the checker, and it flags the skeleton's unfilled markers.
mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/claude"   # the bootstrap refuses without one
chmod +x "$WORK/bin/claude"
PATH="$WORK/bin:$PATH" "$REPO_ROOT/tools/bootstrap-cdd-project.sh" --stage \
  --name "Practices Test" --dir practices-test --path "$WORK/render" >/dev/null \
  || fail "bootstrap --stage failed"
[[ -x "$WORK/render/scripts/practices-check.sh" ]] || fail "the rendered tree has no executable scripts/practices-check.sh"
printf '#!/usr/bin/env bash\necho test\n' > "$WORK/render/run"
chmod +x "$WORK/render/run"
run_check "$WORK/render" ./run
n="$(grep -c 'status marker not resolved' <<<"$err" || true)"
[[ $rc -ne 0 && "$n" -gt 0 ]] || fail "the skeleton contract: expected unresolved-marker findings, got $rc: $err"
pass "a bootstrapped tree carries the checker; its skeleton contract fails on $n unresolved marker(s)"
