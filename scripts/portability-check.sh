#!/usr/bin/env bash
# Host-tool portability sweep: flag shell constructs whose behaviour depends on which
# sed, grep or awk the host happens to ship (issue #107).
#
# The gate scripts and the shipped tools/ run on hosts with different tool families:
# GNU sed/grep with gawk on the GitHub Ubuntu runner, mawk on a Debian/Ubuntu desktop,
# BSD sed/grep with BWK awk on macOS. A construct one family accepts and another reads
# differently passes on one host and fails — or silently does nothing — on the next.
# #106 was one: a backslash in an `awk -v` value, kept literal by mawk and stripped by
# gawk. Each rule below bans one such construct:
#   - sed-in-place:     `sed -i` — BSD sed takes the next argument as a backup suffix.
#   - awk-v-backslash:  a backslash in a literal `awk -v` value — gawk and mawk
#                       escape-process it differently. Dynamic values stay guarded by
#                       assert_anchor in scripts/adapter-conformance-assert.sh.
#   - gnu-bre-escape:   `\?` `\+` `\|` on a sed or grep line — GNU BRE extensions; BSD
#                       reads them literally, so the pattern silently matches nothing.
#   - grep-perl:        `grep -P` — GNU grep only, and only when built with PCRE.
#
# Exemptions: a whole-line comment is never a finding. A line that must keep a construct
# (a heredoc that mentions one, say) carries a trailing `# portability-ok: <reason>`; the
# reason is required, so a bare marker is still reported.
#
# Known limits — it is line-based: a flag on a continuation line after `sed \` is not
# seen, and values built from variables are invisible. It is a backstop for the cheap
# cases; the macOS CI job is the backstop for the rest.
#
# The rules prove themselves before every scan, the roadmap-length precedent: each rule's
# broken example is run through the real scan path and must be reported, so a rule whose
# pattern rotted cannot report "clean". This file is skipped by the scan — it necessarily
# spells every banned construct.
#
# Usage: scripts/portability-check.sh <file>...   (exit 0 clean, 1 findings, 2 usage)
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <file>..." >&2
  exit 2
fi

# One rule per line: "id|advice|broken example|ERE". The ERE is the remainder, so it may
# contain `|`; the other fields may not. @W@ is a word-start guard (POSIX ERE has no \b),
# expanded below. A quoted heredoc keeps every backslash literal, so the EREs read as
# grep -E sees them.
W='(^|[^[:alnum:]_.-])'
RULES=()
while IFS= read -r rule; do
  RULES+=("${rule//@W@/$W}")
done <<'EOF'
sed-in-place|BSD sed reads the next argument as a backup suffix; write to a temp file and cat it back (keeps the mode)|sed -i 's/a/b/' f|@W@sed([[:space:]][^|;&]*)?[[:space:]](-[A-Za-z]*i[^[:space:]]*|--in-place[^[:space:]]*)([[:space:]]|$)
awk-v-backslash|gawk and mawk escape-process -v values differently; use bracket expressions ([(]) instead of backslashes|awk -v re='^f\(\)' '$0 ~ re' f|@W@awk[[:space:]].*-v[[:space:]]*("[A-Za-z_][A-Za-z0-9_]*=[^"]*\\|'[A-Za-z_][A-Za-z0-9_]*=[^']*\\|[A-Za-z_][A-Za-z0-9_]*=("[^"]*\\|'[^']*\\|[^[:space:]"']*\\))
gnu-bre-escape|a backslash before ? + or the pipe is a GNU BRE extension; use -E, or \{0,1\} for ?|sed 's/^# \?//' f|@W@(sed|grep)[[:space:]].*\\[?+|]
grep-perl|grep -P is GNU-only; use grep -E with POSIX classes|grep -P '\d+' f|@W@grep[[:space:]]([^|;&]*[[:space:]])?(-[A-Za-z]*P[A-Za-z]*|--perl-regexp)([[:space:]]|$)
EOF

EXEMPT_RE='# portability-ok:[[:space:]]*[^[:space:]]'
COMMENT_RE='^[[:space:]]*#'

# scan_file <file>: print one finding per hit, return 1 if there was any. The single place
# the rules are applied, so the self-check below exercises the same path the scan does.
scan_file() {
  local f="$1" rule id advice example ere hit lineno text found=0
  for rule in "${RULES[@]}"; do
    IFS='|' read -r id advice example ere <<<"$rule"
    while IFS= read -r hit; do
      lineno="${hit%%:*}"
      text="${hit#*:}"
      [[ "$text" =~ $COMMENT_RE ]] && continue
      [[ "$text" =~ $EXEMPT_RE ]] && continue
      printf '%s:%s: [%s] %s\n    %s\n' "$f" "$lineno" "$id" "$advice" \
        "${text#"${text%%[![:space:]]*}"}"
      found=1
    done < <(grep -nE -- "$ere" "$f" || true)
  done
  return "$found"
}

self_check_fail() {
  echo "portability check: SELF-CHECK FAILED — $*" >&2
  exit 1
}

# Per rule: the ERE compiles, the id is unique, and a fixture run through scan_file is
# reported exactly where it should be — the bare example (line 1) and the example with a
# reasonless marker (line 4), but not the commented-out example (2) or the exempted one (3).
self_check() {
  local rule id advice example ere rc fixture out ids=" "
  fixture="$(mktemp)"
  # shellcheck disable=SC2064  # expand now: $fixture is local
  trap "rm -f '$fixture'" EXIT
  for rule in "${RULES[@]}"; do
    IFS='|' read -r id advice example ere <<<"$rule"
    [[ -n "$id" && -n "$advice" && -n "$example" && -n "$ere" ]] \
      || self_check_fail "malformed rule: $rule"
    [[ "$ids" != *" $id "* ]] || self_check_fail "duplicate rule id: $id"
    ids+="$id "
    rc=0
    grep -qE -- "$ere" </dev/null 2>/dev/null || rc=$?
    [[ $rc -ne 2 ]] || self_check_fail "[$id] its ERE does not compile: $ere"
    printf '%s\n  # %s\n%s # portability-ok: fixture\n%s # portability-ok:\n' \
      "$example" "$example" "$example" "$example" > "$fixture"
    out="$(scan_file "$fixture" | grep -F "[$id]" | cut -d: -f2 | tr '\n' ' ' || true)"
    [[ "$out" == "1 4 " ]] \
      || self_check_fail "[$id] expected findings on fixture lines 1 and 4, got: '${out:-none}' (example: $example)"
  done
  rm -f "$fixture"
  trap - EXIT
}

self_check

status=0
for f in "$@"; do
  [[ "$(basename "$f")" == portability-check.sh ]] && continue
  if [[ ! -f "$f" ]]; then
    echo "portability check: $f: no such file" >&2
    status=1
    continue
  fi
  scan_file "$f" || status=1
done

if [[ $status -eq 0 ]]; then
  echo "portability check: $# file(s) clean"
fi
exit "$status"
