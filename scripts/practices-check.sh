#!/usr/bin/env bash
# Every Enforced row of this repo's engineering-practices contract names a gate the check
# runner registers (process doc §2.12; issue #89). Why: ADR 0028.
#
# Scope: `doc/knowledge_base/engineering-practices.md` only — not the template's skeleton
# (its rows are placeholders) nor the demo seed (no runner).
#
# A section runs from a `## ` heading to the next. Its status is the heading text after the
# first ` — `; a heading with none ("How this list grows") is not a practice row. The rules:
#   (a) a status containing the word Enforced needs a `Gates:` line naming at least one
#       backticked gate;
#   (b) every backticked name on a `Gates:` line is a gate `./scripts/ci.sh list` registers;
#   (c) only a section whose status contains Enforced carries a `Gates:` line.
# A `Gates:` line is `Gates:` or `- Gates:` at the start of a line. A gate may back several
# rows; nothing requires every gate to back one.
#
# The scan proves itself before every run, the staging-check precedent: a fixture contract
# and a fixture registry go through the real scan path and must be reported on exactly the
# expected lines, so a rotted pattern cannot report "clean".
#
# Usage: scripts/practices-check.sh   (no arguments; no side effects)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONTRACT=doc/knowledge_base/engineering-practices.md

# scan <contract> <registry-file>: print "<file>:<line>: <finding>" per finding, then a last
# line "enforced <n>". The single place the rules are applied, so the self-check below
# exercises the same path the real run does.
scan() {
  LC_ALL=C awk -v file="$1" '
    NR == FNR { registered[$0] = 1; next }
    function close_section() {
      if (enforced && !gated) print file ":" head ": Enforced section names no gate"
    }
    /^## / {
      close_section()
      head = FNR; gated = 0; enforced = 0; status = ""
      at = index($0, " — ")
      if (at) status = substr($0, at + length(" — "))
      if (status ~ /(^|[^A-Za-z])Enforced([^A-Za-z]|$)/) { enforced = 1; n_enforced++ }
      next
    }
    /^(- )?Gates:/ {
      if (!enforced) { print file ":" FNR ": Gates: line under a section not marked Enforced"; next }
      rest = $0
      while (match(rest, /`[^`]*`/)) {
        name = substr(rest, RSTART + 1, RLENGTH - 2)
        rest = substr(rest, RSTART + RLENGTH)
        gated = 1
        if (!(name in registered)) print file ":" FNR ": unregistered gate `" name "`"
      }
    }
    END { close_section(); print "enforced " n_enforced + 0 }
  ' "$2" "$1"
}

self_check_fail() {
  echo "practices check: SELF-CHECK FAILED — $*" >&2
  exit 1
}

# Expected findings: 3 (Enforced, no Gates: line), 5 (Enforced, `Gates: none`),
# 8 (mixed Enforced; Expected, no Gates: line), 15 (unregistered `gamma`),
# 21 (Gates: under Expected), 26 (Gates: under Upheld).
# Not findings: 10 (valid `- Gates:` bullet), 17 (mixed, bare `Gates:` form), 23 (Upheld,
# no gates), 28 (no ` — ` status).
self_check() {
  local dir out
  dir="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand now: $dir is local
  trap "rm -rf '$dir'" EXIT
  printf 'alpha\nbeta\n' > "$dir/registry"
  cat > "$dir/contract" <<'EOF'
# Fixture

## No gate — Enforced

## Empty gates — Enforced
- Gates: none

## Mixed no gate — Enforced (x); Expected (y)

## Valid — Enforced
- Gates: `alpha`, `beta`

## Unknown — Enforced
- Gates: `alpha`
- Gates: `gamma`

## Mixed valid — Upheld (x); Enforced (y)
Gates: `beta`

## Expected row — Expected
- Gates: `alpha`

## Upheld row — Upheld

## Upheld gated — Upheld
- Gates: `alpha`

## How this list grows
EOF
  out="$(scan "$dir/contract" "$dir/registry" | grep -v '^enforced ' | cut -d: -f2 | tr '\n' ' ' || true)"
  [[ "$out" == "3 5 8 15 21 26 " ]] \
    || self_check_fail "expected findings on fixture lines 3 5 8 15 21 26, got: '${out:-none}'"
  rm -rf "$dir"
  trap - EXIT
}

self_check

registry="$(mktemp)"
# shellcheck disable=SC2064  # expand now: $registry is local
trap "rm -f '$registry'" EXIT
./scripts/ci.sh list | awk '{ print $1 }' > "$registry"
[[ -s "$registry" ]] || { echo "practices check: ./scripts/ci.sh list returned no gates" >&2; exit 1; }

out="$(scan "$CONTRACT" "$registry")"
findings="$(grep -v '^enforced ' <<<"$out" || true)"
if [[ -n "$findings" ]]; then
  echo "$findings" >&2
  echo "practices check: name a gate ./scripts/ci.sh list registers on the section's Gates: line," \
    "or re-mark the row Upheld (naming its mechanism) or Expected (ADR 0028)" >&2
  exit 1
fi
echo "practices check: ${out##*enforced } Enforced section(s), all backed"
