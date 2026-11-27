#!/usr/bin/env bash
# Transitional markers: every transitional piece names its removal issue (process doc §2.20).
#
# A transitional piece is marked once, on the part that goes, with TRANSITIONAL(#<issue>), so
# `git grep` lists every site one removal touches. This gate holds the format, offline and
# deterministic (ADR 0002): it cannot ask the tracker whether the issue is open — this repo's
# /cdd-pre-pr extension does that for a marker a branch adds. Why markers and upgrade stops:
# ADR 0035.
#
# Rules, over tracked text files (ADRs are record, not sites, so they are out of scope):
#   1. every TRANSITIONAL token is a numbered marker, or one of the two forms the docs use to
#      describe it: the <issue> placeholder and the [0-9]* pattern that lists the markers;
#   2. the retired seam token (the old wording the marker replaced) appears nowhere;
#   3. no marker under template/ — transitional pieces live only in CDD-repo-only files;
#   4. in .claude/commands/ and tools/, where pieces are added, a line saying "transitional" in
#      any case carries a numbered marker.
#
# Usage: scripts/transitional-check.sh   (no arguments; no side effects)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Reads "path:line:text" lines on stdin and prints "path:line: <rule>" for each violation. The
# single place the rules are expressed, so the self-check below exercises the same code path
# the real scan does.
violations() {
  awk '{
    path = $0; sub(/:.*/, "", path)
    rest = substr($0, length(path) + 2)
    lineno = rest; sub(/:.*/, "", lineno)
    text = substr(rest, length(lineno) + 2)
    where = path ":" lineno ": "
    stripped = text
    gsub(/TRANSITIONAL\(#([0-9]+|<issue>|\[0-9\]\*)\)/, "", stripped)
    if (stripped ~ /TRANSITIONAL/) print where "malformed marker, want TRANSITIONAL(#<issue>)"
    if (text ~ /DEPRECATION SEAM/) print where "retired seam token, use TRANSITIONAL(#<issue>)"
    if (path ~ /^template\// && text ~ /TRANSITIONAL/) print where "marker under template/"
    if (path ~ /^(\.claude\/commands|tools)\// && tolower(text) ~ /transitional/ \
        && text !~ /TRANSITIONAL\(#[0-9]+\)/) print where "transitional without TRANSITIONAL(#<issue>)"
  }'
}

# A guard proven only to pass is indistinguishable from one that stopped working, so prove each
# rule still bites before trusting a clean run: the three valid forms must pass, and each bad
# fixture must yield exactly its own rule.
self_check() {
  local got want
  got="$(printf '%s\n' \
    ".claude/commands/a.md:1:drop it TRANSITIONAL(#0) here" \
    "doc/a.md:2:mark it TRANSITIONAL(#<issue>)" \
    "doc/a.md:3:list: git grep -o 'TRANSITIONAL(#[0-9]*)'" \
    "doc/a.md:4:TRANSITIONAL: no issue" \
    "doc/a.md:5:TRANSITIONAL(#) empty" \
    "doc/a.md:6:TRANSITIONAL(#12a) junk" \
    "doc/a.md:7:DEPRECATION SEAM — old token" \
    "template/a.md:8:TRANSITIONAL(#0)" \
    ".claude/commands/a.md:9:a transitional step" | violations)"
  want="$(printf '%s\n' \
    "doc/a.md:4: malformed marker, want TRANSITIONAL(#<issue>)" \
    "doc/a.md:5: malformed marker, want TRANSITIONAL(#<issue>)" \
    "doc/a.md:6: malformed marker, want TRANSITIONAL(#<issue>)" \
    "doc/a.md:7: retired seam token, use TRANSITIONAL(#<issue>)" \
    "template/a.md:8: marker under template/" \
    ".claude/commands/a.md:9: transitional without TRANSITIONAL(#<issue>)")"
  if [[ "$got" != "$want" ]]; then
    echo "transitional check: SELF-CHECK FAILED — a rule no longer bites as it should." >&2
    echo "  expected:" >&2; printf '%s\n' "$want" | sed 's/^/    /' >&2
    echo "  got:" >&2; printf '%s\n' "${got:-<nothing>}" | sed 's/^/    /' >&2
    exit 1
  fi
}

self_check

rc=0
hits="$(git grep -nIi -e transitional -e 'deprecation seam' -- . \
  ':(exclude)doc/architecture/adr/' ':(exclude)scripts/transitional-check.sh')" || rc=$?
if (( rc > 1 )); then   # 1 is "no match"; anything above is git failing
  echo "transitional check: git grep failed (exit $rc)" >&2
  exit 1
fi

found=""
[[ -z "$hits" ]] || found="$(printf '%s\n' "$hits" | violations)"
if [[ -n "$found" ]]; then
  printf '%s\n' "$found" | sed 's/^/  /' >&2
  echo "transitional check: FAILED — see above. Convention: process doc §2.20." >&2
  exit 1
fi

echo "transitional check: clean"
