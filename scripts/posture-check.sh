#!/usr/bin/env bash
# Dependency-posture check: every external tool CDD's shipped scripts probe for declares
# which posture it has, and the copies that must agree do (process doc §2.18, ADR 0019).
#
# Rules, each reporting every violation (not fail-fast within the gate):
#   - tag:       every non-comment line under tools/ (tools/*.sh, tools/adapters/*/*.sh)
#                that contains `command -v` ends with `# posture: <p>`, where <p> is
#                required, per-adapter or silent-equivalent. The tag is what makes a new
#                probe's posture a decision instead of an accident; the per-tool
#                assignment lives in doc/knowledge_base/engineering-practices.md.
#   - helpers:   the required-tools block (between `# --- CDD required tools BEGIN` and
#                `# --- CDD required tools END ---`) is present once and identical in
#                tools/cdd-state.sh and tools/cdd-worktree.sh. Both files define the same
#                function names, so a shell that sources both keeps whichever came last;
#                identical bodies make that harmless.
#   - installer: scripts/install-deps.sh and template/scripts/install-deps.sh are identical
#                once their project blocks (`# --- project tools BEGIN` .. `# --- project
#                tools END ---`, inclusive) are removed, and each carries both markers once.
#                The part outside the block is CDD's; this repo's copy must not drift from
#                what the template ships.
#
# A whole-line comment is never a finding. The rules prove themselves before the scan, the
# portability-check precedent: fixtures run through the real check functions must be
# reported (or accepted) as expected, so a rule that rotted cannot report "clean".
#
# Usage: scripts/posture-check.sh   (exit 0 clean, 1 findings)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TAG_RE='# posture: (required|per-adapter|silent-equivalent)[[:space:]]*$'
COMMENT_RE='^[[:space:]]*#'
HELPER_BEGIN='# --- CDD required tools BEGIN'
HELPER_END='# --- CDD required tools END ---'
PROJECT_BEGIN='# --- project tools BEGIN'
PROJECT_END='# --- project tools END ---'

# check_tags <file>...: one finding per untagged `command -v` line; returns 1 on any.
check_tags() {
  local f hit lineno text found=0
  for f in "$@"; do
    while IFS= read -r hit; do
      lineno="${hit%%:*}"
      text="${hit#*:}"
      [[ "$text" =~ $COMMENT_RE ]] && continue
      [[ "$text" =~ $TAG_RE ]] && continue
      # shellcheck disable=SC2016  # the backticks are literal text in the message
      printf '%s:%s: [tag] `command -v` without a `# posture: required|per-adapter|silent-equivalent` tag\n    %s\n' \
        "$f" "$lineno" "${text#"${text%%[![:space:]]*}"}"
      found=1
    done < <(grep -nF -- 'command -v' "$f" || true)
  done
  return "$found"
}

# marker_count <file> <marker>: how many lines start with <marker>.
marker_count() {
  awk -v m="$2" 'index($0, m) == 1 { n++ } END { print n + 0 }' "$1"
}

# block_of <file> <begin> <end>: the lines from <begin> through <end>, inclusive.
block_of() {
  awk -v b="$2" -v e="$3" 'index($0, b) == 1 { on = 1 } on { print } on && index($0, e) == 1 { on = 0 }' "$1"
}

# without_block <file> <begin> <end>: the file with that block (inclusive) removed.
without_block() {
  awk -v b="$2" -v e="$3" 'index($0, b) == 1 { on = 1 } !on { print } on && index($0, e) == 1 { on = 0 }' "$1"
}

# check_markers <file> <begin> <end>: each marker exactly once; returns 1 otherwise.
check_markers() {
  local f="$1" b="$2" e="$3" nb ne
  nb="$(marker_count "$f" "$b")"
  ne="$(marker_count "$f" "$e")"
  if [[ "$nb" != 1 || "$ne" != 1 ]]; then
    echo "$f: [markers] expected one '$b' and one '$e' line, found $nb and $ne"
    return 1
  fi
}

# check_helpers <a> <b>: the required-tools blocks are present and identical.
check_helpers() {
  local a="$1" b="$2" rc=0
  check_markers "$a" "$HELPER_BEGIN" "$HELPER_END" || rc=1
  check_markers "$b" "$HELPER_BEGIN" "$HELPER_END" || rc=1
  (( rc == 0 )) || return 1
  if ! diff <(block_of "$a" "$HELPER_BEGIN" "$HELPER_END") \
            <(block_of "$b" "$HELPER_BEGIN" "$HELPER_END") >/dev/null; then
    echo "[helpers] the required-tools blocks of $a and $b differ:"
    diff <(block_of "$a" "$HELPER_BEGIN" "$HELPER_END") \
         <(block_of "$b" "$HELPER_BEGIN" "$HELPER_END") | sed 's/^/    /' || true
    return 1
  fi
}

# check_installer <repo copy> <template copy>: identical outside the project block.
check_installer() {
  local a="$1" b="$2" rc=0
  check_markers "$a" "$PROJECT_BEGIN" "$PROJECT_END" || rc=1
  check_markers "$b" "$PROJECT_BEGIN" "$PROJECT_END" || rc=1
  (( rc == 0 )) || return 1
  if ! diff <(without_block "$a" "$PROJECT_BEGIN" "$PROJECT_END") \
            <(without_block "$b" "$PROJECT_BEGIN" "$PROJECT_END") >/dev/null; then
    echo "[installer] $a and $b differ outside the project block:"
    diff <(without_block "$a" "$PROJECT_BEGIN" "$PROJECT_END") \
         <(without_block "$b" "$PROJECT_BEGIN" "$PROJECT_END") | sed 's/^/    /' || true
    return 1
  fi
}

self_check_fail() {
  echo "posture check: SELF-CHECK FAILED — $*" >&2
  exit 1
}

self_check() {
  local d out
  d="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand now: $d is local
  trap "rm -rf '$d'" EXIT

  # tag: line 1 untagged, 2 commented out, 3 tagged, 4 an unknown posture.
  printf '%s\n' \
    'if command -v jq >/dev/null; then :; fi' \
    '  # command -v jq' \
    'if command -v jq >/dev/null; then :; fi  # posture: required' \
    'if command -v jq >/dev/null; then :; fi  # posture: optional' > "$d/tags.sh"
  out="$(check_tags "$d/tags.sh" | grep -F '[tag]' | cut -d: -f2 | tr '\n' ' ' || true)"
  [[ "$out" == "1 4 " ]] || self_check_fail "[tag] expected findings on fixture lines 1 and 4, got: '${out:-none}'"

  # helpers: equal blocks pass; a changed line inside, or a missing block, fails.
  printf 'a\n%s x\nbody\n%s\nb\n' "$HELPER_BEGIN" "$HELPER_END" > "$d/h1"
  printf 'c\n%s x\nbody\n%s\n' "$HELPER_BEGIN" "$HELPER_END" > "$d/h2"
  printf 'c\n%s x\nother\n%s\n' "$HELPER_BEGIN" "$HELPER_END" > "$d/h3"
  printf 'no block\n' > "$d/h4"
  check_helpers "$d/h1" "$d/h2" >/dev/null || self_check_fail "[helpers] identical blocks were reported"
  check_helpers "$d/h1" "$d/h3" >/dev/null && self_check_fail "[helpers] differing blocks were accepted"
  check_helpers "$d/h1" "$d/h4" >/dev/null && self_check_fail "[helpers] a missing block was accepted"

  # installer: differing only inside the project block passes; outside it fails.
  printf 'top\n%s x\none\n%s\nbottom\n' "$PROJECT_BEGIN" "$PROJECT_END" > "$d/i1"
  printf 'top\n%s x\ntwo\nthree\n%s\nbottom\n' "$PROJECT_BEGIN" "$PROJECT_END" > "$d/i2"
  printf 'top\n%s x\none\n%s\nchanged\n' "$PROJECT_BEGIN" "$PROJECT_END" > "$d/i3"
  check_installer "$d/i1" "$d/i2" >/dev/null || self_check_fail "[installer] a project-block-only difference was reported"
  check_installer "$d/i1" "$d/i3" >/dev/null && self_check_fail "[installer] a difference outside the project block was accepted"

  rm -rf "$d"
  trap - EXIT
}

self_check

status=0
shopt -s nullglob
check_tags tools/*.sh tools/adapters/*/*.sh || status=1
shopt -u nullglob
check_helpers tools/cdd-state.sh tools/cdd-worktree.sh || status=1
check_installer scripts/install-deps.sh template/scripts/install-deps.sh || status=1

if [[ $status -eq 0 ]]; then
  echo "posture check: every command -v is tagged; the required-tools blocks and the install-deps scripts agree"
fi
exit "$status"
