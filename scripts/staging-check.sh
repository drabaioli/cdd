#!/usr/bin/env bash
# Gate commands stage by name: no `git add -A`, `--all` or `.` in a command's or agent's
# shell blocks (process doc §2.11 rule 1; issue #139).
#
# A session commits only what it produced. Staging everything sweeps in whatever else sits
# in the tree — a half-finished edit, a scratch file — and in a command that pushes, that
# goes straight to the PR. /cdd-process-pr shipped exactly that until #139. The prompts are
# the instructions a session follows, so the rule is checked where it is written down.
#
# Scope: every `.md` under `.claude/commands/` and `.claude/agents/`, in this repo and in
# `template/` (globs, so a new command is covered). Not `scripts/` or `tools/`: their sandbox
# and scaffold repos are throwaway trees that legitimately stage everything.
#
# Only lines inside fenced code blocks are scanned. A fence is what a session runs; prose is
# what it reads, and the rule itself is written in prose ("never `git add -A`"), which must
# pass. Fences may be indented (a block inside a list item).
#
# Exemption: a command that stages a tree it just created — a fresh `git init`, a fresh
# worktree — has nothing else to sweep in. Such a line carries a trailing
# `# stage-all-ok: <reason>` (the `# portability-ok:` convention); the reason is required, so
# a bare marker is still reported.
#
# Known limits: an instruction outside a fence (inline code in prose, say) is not seen, nor is
# `git commit -a`. A staging command built from variables is invisible.
#
# The scan proves itself before every run, the roadmap-length precedent: a fixture with known
# hits and misses goes through the real scan path and must be reported on exactly the
# expected lines, so a rotted pattern cannot report "clean". This file is not in its own
# scope (only `.md` is), so it can spell the banned forms freely.
#
# Usage: scripts/staging-check.sh   (no arguments; no side effects)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# `git [opts] add -A|--all|.`, ended by whitespace, a shell separator or end of line — so
# `git -C dir add --all` and `git add -A && …` match, `git add ./foo` and `git add <file>` do not.
STAGE_ALL_RE='git[[:space:]]([^;&|]*[[:space:]])?add[[:space:]]+(-A|--all|\.)([[:space:];&|)]|$)'
EXEMPT_RE='# stage-all-ok:[[:space:]]*[^[:space:]]'

# fenced_lines <file>: print "<line-no>:<text>" for every line inside a fenced code block
# (the fence markers themselves excluded).
fenced_lines() {
  LC_ALL=C awk '
    /^[ \t]*```/ { in_fence = !in_fence; next }
    in_fence     { print NR ":" $0 }
  ' "$1"
}

# scan_file <file>: print one finding per hit, return 1 if there was any. The single place
# the rule is applied, so the self-check below exercises the same path the scan does.
scan_file() {
  local f="$1" hit lineno text found=0
  while IFS= read -r hit; do
    lineno="${hit%%:*}"
    text="${hit#*:}"
    [[ "$text" =~ $STAGE_ALL_RE ]] || continue
    [[ "$text" =~ $EXEMPT_RE ]] && continue
    printf '%s:%s: %s\n' "$f" "$lineno" "${text#"${text%%[![:space:]]*}"}"
    found=1
  done < <(fenced_lines "$f")
  return "$found"
}

self_check_fail() {
  echo "staging check: SELF-CHECK FAILED — $*" >&2
  exit 1
}

# Expected hits: 4 (git add -A), 5 (-C dir add --all), 6 (add .), 14 (indented fence inside
# a list item), 18 (bare marker). Not hits: 1 (prose), 7 (a named file), 8 (a ./path),
# 17 (a reasoned marker), 20 (prose after the fence closes).
self_check() {
  local fixture out
  fixture="$(mktemp)"
  # shellcheck disable=SC2064  # expand now: $fixture is local
  trap "rm -f '$fixture'" EXIT
  cat > "$fixture" <<'EOF'
Commit only the files you changed; never `git add -A`.

```bash
git add -A
git -C "$d" add --all
git add .
git add README.md
git add ./src/main.c
```

- A list item:

  ```bash
  git add -A && git commit -m x
  ```
```bash
git init && git add -A # stage-all-ok: fresh repo
git add -A # stage-all-ok:
```
git add -A
EOF
  out="$(scan_file "$fixture" | cut -d: -f2 | tr '\n' ' ' || true)"
  [[ "$out" == "4 5 6 14 18 " ]] \
    || self_check_fail "expected findings on fixture lines 4 5 6 14 18, got: '${out:-none}'"
  rm -f "$fixture"
  trap - EXIT
}

self_check

shopt -s nullglob
FILES=(.claude/commands/*.md .claude/agents/*.md template/.claude/commands/*.md template/.claude/agents/*.md)
shopt -u nullglob
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "staging check: no command or agent files found — wrong directory?" >&2
  exit 1
fi

status=0
for f in "${FILES[@]}"; do
  scan_file "$f" || status=1
done

if [[ $status -ne 0 ]]; then
  echo "staging check: stage the session's own files by path (process doc §2.11 rule 1);" \
    "a line staging a tree the command just created carries a trailing '# stage-all-ok: <reason>'" >&2
  exit 1
fi
echo "staging check: ${#FILES[@]} file(s) clean"
