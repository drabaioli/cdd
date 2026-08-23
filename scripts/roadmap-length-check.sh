#!/usr/bin/env bash
# Roadmap item length: the 200-character cap on doc/knowledge_base/roadmap.md.
#
# The roadmap is simultaneously a plan, a progress log, and a context document that every
# CDD session loads, so an over-long item costs context on every future run. The bar has
# always been "an item reads like a PR title or barely more" (process doc §2.2 rule 3, and
# the roadmap's own "Annotation conventions" section), but it was convention-only — and the
# convention shipped its own escape clause grandfathering existing violations, so 46 of 94
# items had drifted past 200 characters, the worst of them to 3,872. This gate is what
# replaces that escape clause: the cap is now mechanical, and it applies to pending items
# as much as to completed ones. Detail that no longer fits goes to a GitHub issue, an ADR
# with Status: Proposed, or the handoff — see ADR 0005.
#
# The cap is 200 **raw characters of the whole line**, "- [x] " prefix included. Raw and
# whole-line was chosen over any cleverer measure (rendered width, backticks excluded,
# markdown link targets collapsed) because a cap is only useful if a session can apply it
# without running the checker, and "the length of the line" is the one rule that needs no
# explanation. Its one visible consequence is that a full relative ADR link can cost a
# third of the budget, so the convention is to cite an ADR by number ("ADR 0002") and let
# doc/architecture/index.md carry the links.
#
# Characters, not bytes, and the same answer on every host. `awk`'s length() is byte-based
# in mawk (Debian's default, not multibyte-aware) and character-based in gawk under a UTF-8
# locale, so the naive check would give two different verdicts on two contributors' machines
# — and an em dash, which the convention actually mandates, would silently cost 3 of the 200
# on one of them. So the scan runs under LC_ALL=C and strips UTF-8 continuation bytes
# (0x80-0xBF) before measuring: one byte survives per character, on any awk, in any locale.
# The self-check below pins that with a deliberately em-dash-heavy fixture.
#
# Scope is doc/knowledge_base/roadmap.md **only**, deliberately. The template's roadmap
# (template/doc/knowledge_base/roadmap.md) and the demo seed's are instructional prose
# written to be read by a human bootstrapping a project, not progress log lines, and are
# legitimately longer. Widening this gate to them would be a different decision, not a
# generalization of this one.
#
# A line "shaped like an item" is held to the cap wherever it appears, including the
# example inside the conventions section's fenced block. That is intentional: an example
# that violates the rule it illustrates is a defect, so no fenced-block exemption exists.
#
# Usage: scripts/roadmap-length-check.sh   (no arguments; no side effects)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ROADMAP="doc/knowledge_base/roadmap.md"
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

[[ -f "$ROADMAP" ]] || { echo "roadmap-length check: $ROADMAP not found" >&2; exit 1; }

fail=0
while IFS=: read -r lineno len; do
  echo "  $ROADMAP:$lineno — $len chars (cap $CAP, over by $((len - CAP)))" >&2
  fail=1
done < <(violations < "$ROADMAP")

if [[ "$fail" -ne 0 ]]; then
  echo "roadmap-length check: FAILED — items over the $CAP-character cap (see above)." >&2
  echo "  Trim to a PR-title description plus at most one short trailing clause." >&2
  echo "  Detail belongs in a GitHub issue, a Status: Proposed ADR, or the handoff (ADR 0005)." >&2
  exit 1
fi

echo "roadmap-length check: clean"
