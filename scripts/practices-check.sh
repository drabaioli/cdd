#!/usr/bin/env bash
# Every Enforced row of the engineering-practices contract names a gate the project's
# check runner registers (CDD process doc, section 2.12). The check runner registers this
# script as a gate of its own.
#
# This file belongs to CDD and changes with it (/cdd-retrofit carries those changes over);
# do not edit it locally.
#
# A section runs from a `## ` heading to the next. Its status is the heading text after the
# first ` — `; a heading with none ("How this list grows") is not a practice row. The rules:
#   (a) a status containing the word Enforced needs a `Gates:` line naming at least one
#       backticked gate;
#   (b) every backticked name on a `Gates:` line is a gate the runner's `list` mode prints
#       (the first field of each line);
#   (c) only a section whose status contains Enforced carries a `Gates:` line;
#   (d) a status still a `<…>` placeholder is a finding of its own; its section is
#       otherwise not checked.
# A `Gates:` line is `Gates:` or `- Gates:` at the start of a line. A gate may back several
# rows; nothing requires every gate to back one.
#
# The scan proves itself before every run: a fixture contract and a fixture registry go
# through the real scan path and must be reported on exactly the expected lines, so a
# rotted pattern cannot report "clean".
#
# Usage: scripts/practices-check.sh <check runner command> [<arg>...]
#   Runs `<check runner command> list` from the repository root to learn the gate names.
#   Register it in the runner as a gate, passing the runner's own invocation.
set -euo pipefail

usage() {
  echo "usage: scripts/practices-check.sh <check runner command> [<arg>...]" >&2
  exit 2
}
[[ $# -gt 0 ]] || usage

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
      head = FNR; gated = 0; enforced = 0; unresolved = 0; status = ""
      at = index($0, " — ")
      if (at) status = substr($0, at + length(" — "))
      if (status ~ /^</) { print file ":" FNR ": status marker not resolved"; unresolved = 1; next }
      if (status ~ /(^|[^A-Za-z])Enforced([^A-Za-z]|$)/) { enforced = 1; n_enforced++ }
      next
    }
    /^(- )?Gates:/ {
      if (unresolved) next
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
# 21 (Gates: under Expected), 26 (Gates: under Upheld), 28 (unresolved status marker).
# Not findings: 10 (valid `- Gates:` bullet), 17 (mixed, bare `Gates:` form), 23 (Upheld,
# no gates), 29 (Gates: under the unresolved marker), 31 (no ` — ` status).
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

## Pending — <Upheld once x; Expected until then>
- Gates: <the runner gate(s)>

## How this list grows
EOF
  out="$(scan "$dir/contract" "$dir/registry" | grep -v '^enforced ' | cut -d: -f2 | tr '\n' ' ' || true)"
  [[ "$out" == "3 5 8 15 21 26 28 " ]] \
    || self_check_fail "expected findings on fixture lines 3 5 8 15 21 26 28, got: '${out:-none}'"
  rm -rf "$dir"
  trap - EXIT
}

self_check

[[ -f "$CONTRACT" ]] || { echo "practices check: $CONTRACT not found" >&2; exit 1; }

tmp="$(mktemp -d)"
# shellcheck disable=SC2064  # expand now: $tmp is local
trap "rm -rf '$tmp'" EXIT
"$@" list > "$tmp/list" || {
  echo "practices check: \`$* list\` failed — every check runner needs a list mode (CDD process doc §2.14)" >&2
  exit 1
}
awk 'NF { print $1 }' "$tmp/list" > "$tmp/registry"
[[ -s "$tmp/registry" ]] || { echo "practices check: \`$* list\` returned no gates" >&2; exit 1; }

out="$(scan "$CONTRACT" "$tmp/registry")"
findings="$(grep -v '^enforced ' <<<"$out" || true)"
if [[ -n "$findings" ]]; then
  echo "$findings" >&2
  echo "practices check: resolve each status marker; name a gate \`$* list\` prints on the" \
    "section's Gates: line, or re-mark the row Upheld (naming its mechanism) or Expected" \
    "(CDD process doc §2.12)" >&2
  exit 1
fi
echo "practices check: ${out##*enforced } Enforced section(s), all backed"
