#!/usr/bin/env bash
# Roadmap item length: the 200-character cap, on every roadmap this repo ships.
#
# The roadmap is loaded by every CDD session, so an over-long item costs context on every
# future run. The bar ("an item reads like a PR title or barely more", process doc §2.2 rule 3)
# was convention-only, and the convention shipped an escape clause grandfathering existing
# violations — 46 of 94 items had drifted past 200 characters, the worst to 3,872. This gate
# replaces that clause: mechanical, and applied to pending items as much as completed ones.
# Detail that no longer fits goes to a GitHub issue or the handoff — see ADR 0005.
#
# The cap is 200 **raw characters of the whole line**, "- [x] " prefix included: a cap is only
# useful if a session can apply it without running the checker. Its visible consequence is that
# a full relative ADR link costs a third of the budget, hence citing "ADR 0002" by number.
#
# Characters, not bytes, and the same answer on every host: awk's length() is byte-based in
# mawk and character-based in gawk under UTF-8, and the items carry multibyte punctuation
# (§, →, ≠). So the scan runs under LC_ALL=C and strips UTF-8 continuation bytes (0x80-0xBF)
# first — one byte per character on any awk. The self-check below pins that.
#
# Scope is every roadmap the repo ships (its own, template/, demo/seed/): a file stating this
# convention has to obey it, and the template's items are inherited verbatim by every
# bootstrapped project. Trimmed detail belongs in the phase intro, which is prose and uncapped.
# A line shaped like an item is capped wherever it appears, the conventions section's own
# example included — an example that violates its rule is a defect.
#
# Usage: scripts/roadmap-length-check.sh   (no arguments; no side effects)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ROADMAPS=(
  "doc/knowledge_base/roadmap.md"
  "template/doc/knowledge_base/roadmap.md"
  "demo/seed/doc/knowledge_base/roadmap.md"
)
CAP=200

# Reads a roadmap on stdin, prints "<line-no>:<length>" for every checkbox item over the
# cap. The single place the rule is expressed, so the self-check below exercises the same
# code path the real scan does.
violations() {
  LC_ALL=C awk -v cap="$CAP" '
    /^- \[[ x]\] / {
      line = $0
      gsub(/[\200-\277]/, "", line)   # drop UTF-8 continuation bytes: 1 byte per character
      if (length(line) > cap) printf "%d:%d\n", NR, length(line)
    }'
}

# A guard proven only to pass is indistinguishable from one that stopped working: if the
# item pattern stopped matching, or the character counting silently became byte counting,
# this check would report "clean" forever and nothing would notice. So prove it still bites
# before trusting a clean run. Three fixtures: an item one character under the cap, one
# character over, and a multibyte one that is exactly at the cap in characters but well
# over it in bytes. Exactly the middle one must be caught.
self_check() {
  local pad short long multi got want
  pad="$(printf '%*s' $((CAP - 6)) '' | tr ' ' x)"   # "- [x] " is 6 chars -> line is CAP
  short="- [x] ${pad%x}"                             # CAP - 1 characters
  long="- [x] ${pad}x"                               # CAP + 1 characters
  multi="- [x] ${pad:0:$((CAP - 14))} — § ≠ —"       # CAP characters, CAP + 7 bytes
  want="2:$((CAP + 1))"
  got="$(printf '%s\n%s\n%s\n' "$short" "$long" "$multi" | violations)"
  if [[ "$got" != "$want" ]]; then
    echo "roadmap-length check: SELF-CHECK FAILED — the item matcher is broken." >&2
    echo "  expected exactly '$want' from fixtures of $((CAP - 1)), $((CAP + 1)) and $CAP characters" >&2
    echo "  (the third multibyte: $CAP characters but more than $CAP bytes)," >&2
    echo "  got: ${got:-<nothing>}" >&2
    exit 1
  fi
}

self_check

fail=0
for roadmap in "${ROADMAPS[@]}"; do
  if [[ ! -f "$roadmap" ]]; then
    echo "roadmap-length check: $roadmap not found" >&2
    fail=1
    continue
  fi
  while IFS=: read -r lineno len; do
    echo "  $roadmap:$lineno — $len chars (cap $CAP, over by $((len - CAP)))" >&2
    fail=1
  done < <(violations < "$roadmap")
done

if [[ "$fail" -ne 0 ]]; then
  echo "roadmap-length check: FAILED — items over the $CAP-character cap (see above)." >&2
  echo "  Trim to a PR-title description plus at most one short trailing clause." >&2
  echo "  Detail belongs in a GitHub issue or the handoff (ADR 0005)." >&2
  exit 1
fi

echo "roadmap-length check: clean"
