#!/usr/bin/env bash
# Smoke for code-host adapter resolution in the worktree helpers (ADR 0010).
#
# The helpers' PR lookups and default-branch lookup go down a ladder: the project's
# .cdd/code-host, then the machine's ~/.cdd/adapters/code-host, then the built-in
# gh / git. This pins the three cases of the broken-adapter rule at every helper call
# site that consults it:
#   - missing (no file at a rung)  -> the next rung; with none at all, the built-in,
#     silently (no announcement line)
#   - installed and working        -> it serves, announced in exactly one stderr line,
#     and `gh` is never called; the project rung wins over the machine rung
#   - installed but broken (not executable; describe exits non-zero, prints non-JSON,
#     reports an unsupported contract or another capability) -> one line naming it,
#     and NO lower rung: neither a working machine adapter nor `gh` is consulted.
#     gc, done, resume and cdd-worktree stop; list reports it and shows "-" PRs
#   - verb unsupported (undeclared, or exit 3 at runtime) -> the feature is skipped:
#     gc reaps nothing and exits 0, list shows "-"
#
# Like gc-assert.sh it stands in a local bare repo for origin, gives the helpers their
# own $HOME, and stubs `gh` on PATH — here a stub that also logs every call, which is
# what proves "never falls back to gh". The stub adapters are small bash scripts that
# log their own calls the same way.
#
# Usage: scripts/code-host-ladder-assert.sh   (provisions and tears down its own temp tree)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/tools/cdd-worktree.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER" ]] || fail "helper not found: $HELPER"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the helpers read an adapter's describe with it"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
cat > "$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	name = CDD Smoke
	email = smoke@example.com
[init]
	defaultBranch = main
[commit]
	gpgsign = false
EOF

MERGED="feat_merged"   # the adapter (and the gh stub) say its PR merged
OPEN="feat_open"       # no merged PR
RESUME="feat_resume"   # a remote branch for the resume case
HOME_A="$WORK/home"
GH_LOG="$WORK/gh.log"
export GH_LOG

# Stub gh: logs every call. `auth status` succeeds; `pr list --head feat_merged` answers
# in the shape of whichever --jq the caller used (list's "#N STATE" or gc's bare state).
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1" in
  auth) exit 0 ;;
  pr)
    branch="" all="$*"
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--head" ]] && { branch="$2"; break; }
      shift
    done
    if [[ "$branch" == "feat_merged" ]]; then
      if [[ "$all" == *"number,state"* ]]; then echo "#7 MERGED"; else echo "MERGED"; fi
    fi
    exit 0 ;;
esac
exit 0
EOF
cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$WORK/bin/gh" "$WORK/bin/claude"

# make_adapter <dest> <mode> <default branch> <call log>
# Modes: working; only-default (declares default-branch alone); declared-exit3
# (declares the PR verbs but exits 3 on them); and the broken ones — nonexec,
# desc-exit1, desc-nonjson, contract99, cap-tracker.
make_adapter() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\nMODE=%q DEFAULT=%q LOG=%q\n' "$2" "$3" "$4" > "$1"
  cat >> "$1" <<'EOF'
echo "$*" >> "$LOG"
verbs='["pr-for-branch","pr-merged","default-branch"]'
case "$1" in
  describe)
    case "$MODE" in
      desc-exit1)   exit 1 ;;
      desc-nonjson) echo "not json"; exit 0 ;;
      contract99)   echo '{"capability":"code-host","contract":99,"backend":"stub","verbs":'"$verbs"'}'; exit 0 ;;
      cap-tracker)  echo '{"capability":"tracker","contract":1,"backend":"stub","ref_pattern":"^[0-9]+$","verbs":["issue-read"]}'; exit 0 ;;
      only-default) verbs='["default-branch"]' ;;
    esac
    echo '{"capability":"code-host","contract":1,"backend":"stub","verbs":'"$verbs"'}' ;;
  pr-merged)
    [[ "$MODE" == declared-exit3 ]] && exit 3
    if [[ "$2" == feat_merged ]]; then
      echo '{"branch":"feat_merged","merged":true,"ref":"42"}'
    else
      echo "{\"branch\":\"$2\",\"merged\":false}"
    fi ;;
  pr-for-branch)
    [[ "$MODE" == declared-exit3 ]] && exit 3
    if [[ "$2" == feat_merged ]]; then
      echo '[{"ref":"42","state":"merged","state_raw":"MERGED","url":"u","head":"feat_merged","base":"main"}]'
    else
      echo '[]'
    fi ;;
  default-branch) echo "{\"branch\":\"$DEFAULT\"}" ;;
  *) exit 3 ;;
esac
EOF
  chmod 755 "$1"
  [[ "$2" == nonexec ]] && chmod 644 "$1"
  return 0
}

# Bare origin with main and three feature branches; the machine is a clone of it.
git init --bare -q "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/seed" 2>/dev/null
(
  cd "$WORK/seed"
  echo "# seed" > README.md; git add README.md; git commit -q -m "seed"
  git push -q -u origin main
  for b in "$MERGED" "$OPEN" "$RESUME"; do
    git switch -q -c "$b" main; echo "$b" > "$b.txt"; git add "$b.txt"; git commit -q -m "$b"
    git push -q -u origin "$b"
  done
)
MACHINE="$WORK/machine"
git clone -q "$WORK/origin.git" "$MACHINE"
DIR="$HOME_A/.cdd/handoffs/machine"
mkdir -p "$DIR"

PROJECT_RUNG="$MACHINE/.cdd/code-host"
MACHINE_RUNG="$HOME_A/.cdd/adapters/code-host"
PROJECT_LOG="$WORK/project-adapter.log"
MACHINE_LOG="$WORK/machine-adapter.log"

seed_handoffs() {
  for b in "$MERGED" "$OPEN"; do
    printf '# Task: %s\n' "$b" > "$DIR/$b.md"
  done
}

reset() {
  rm -rf "$MACHINE/.cdd" "$HOME_A/.cdd/adapters"
  : > "$GH_LOG"; : > "$PROJECT_LOG"; : > "$MACHINE_LOG"
  seed_handoffs
}

# run <dir> <command> <arg>... — stdout to $WORK/out, stderr to $WORK/err; sets RC.
run() {
  local dir="$1"; shift
  RC=0
  (
    cd "$dir"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$HOME_A" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER"
    "$@"
  ) >"$WORK/out" 2>"$WORK/err" </dev/null || RC=$?
}

show() { printf '\n--- stdout\n%s\n--- stderr\n%s\n' "$(cat "$WORK/out")" "$(cat "$WORK/err")"; }
stderr_lines() { grep -c . "$WORK/err" || true; }
# The list prints fixed-width columns ('%-40s  %-8s  %-8s  %-12s  %s'), and the PR
# column holds a space ("#42 MERGED"), so it is cut by position, not by field.
pr_column() {  # pr_column <branch> -> that row's PR column in cdd-worktree-list output
  awk -v b="$1" '$1 == b { print substr($0, 63, 12) }' "$WORK/out" | sed 's/ *$//'
}
# one_line_matching <grep args>... — stderr is exactly one line, and it matches.
one_line_matching() {
  [[ "$(stderr_lines)" == 1 ]] && grep -q "$@" "$WORK/err"
}

# --- 1. No adapter: the built-in rung, silently --------------------------------
reset
run "$MACHINE" cdd-worktree-default-branch
[[ $RC -eq 0 && "$(cat "$WORK/out")" == "main" ]] || fail "no adapter: default branch should be main$(show)"
[[ ! -s "$WORK/err" ]] || fail "no adapter: the built-in rung must be silent$(show)"

run "$MACHINE" cdd-worktree-gc
[[ $RC -eq 0 ]] || fail "no adapter: gc exited $RC$(show)"
grep -q "reap  $MERGED (MERGED): would remove" "$WORK/out" || fail "no adapter: gc did not reap via gh$(show)"
grep -q "keep  $OPEN" "$WORK/out" || fail "no adapter: gc did not keep $OPEN$(show)"
[[ ! -s "$WORK/err" ]] || fail "no adapter: gc must print no adapter line$(show)"
[[ -s "$GH_LOG" ]] || fail "no adapter: gc should have asked gh"
pass "no adapter: default branch from git, gc from gh, nothing announced"

# --- 2. A working project adapter serves, and gh is never called ---------------
reset
make_adapter "$PROJECT_RUNG" working trunk "$PROJECT_LOG"
announce="code-host: using adapter .cdd/code-host (stub)"

run "$MACHINE" cdd-worktree-default-branch
[[ $RC -eq 0 && "$(cat "$WORK/out")" == "trunk" ]] || fail "working adapter: default branch should be the adapter's 'trunk'$(show)"
one_line_matching -xF "$announce" || fail "working adapter: expected exactly one announcement line$(show)"

run "$MACHINE" cdd-worktree-gc
[[ $RC -eq 0 ]] || fail "working adapter: gc exited $RC$(show)"
grep -q "reap  $MERGED (MERGED): would remove" "$WORK/out" || fail "working adapter: gc did not reap what the adapter says merged$(show)"
grep -q "keep  $OPEN (not merged" "$WORK/out" || fail "working adapter: gc did not keep $OPEN$(show)"
one_line_matching -xF "$announce" || fail "working adapter: gc should announce exactly once$(show)"

run "$MACHINE" cdd-worktree-list
[[ $RC -eq 0 ]] || fail "working adapter: list exited $RC$(show)"
[[ "$(pr_column "$MERGED")" == "#42 MERGED" ]] || fail "working adapter: list should show '#42 MERGED' for $MERGED$(show)"
[[ "$(pr_column "$OPEN")" == "-" ]] || fail "working adapter: list should show '-' for $OPEN$(show)"
[[ "$(stderr_lines)" == 1 ]] || fail "working adapter: list should announce exactly once$(show)"
[[ ! -s "$GH_LOG" ]] || fail "working adapter: gh was called: $(cat "$GH_LOG")"
pass "a working project adapter serves default-branch, gc and list; announced once; gh never called"

# --- 3. The machine rung, and the project rung winning over it -----------------
reset
make_adapter "$MACHINE_RUNG" working machine-trunk "$MACHINE_LOG"
run "$MACHINE" cdd-worktree-default-branch
[[ $RC -eq 0 && "$(cat "$WORK/out")" == "machine-trunk" ]] || fail "machine rung: expected 'machine-trunk'$(show)"
grep -qF "code-host: using adapter $MACHINE_RUNG (stub)" "$WORK/err" || fail "machine rung: announcement should name it$(show)"
make_adapter "$PROJECT_RUNG" working trunk "$PROJECT_LOG"
: > "$MACHINE_LOG"
run "$MACHINE" cdd-worktree-default-branch
[[ "$(cat "$WORK/out")" == "trunk" ]] || fail "both rungs: the project adapter should win$(show)"
[[ ! -s "$MACHINE_LOG" ]] || fail "both rungs: the machine adapter should not have been called"
[[ ! -s "$GH_LOG" ]] || fail "machine rung: gh was called: $(cat "$GH_LOG")"
pass "the machine rung serves when alone; the project rung wins when both exist"

# --- 4. A broken project adapter stops; nothing lower is consulted -------------
for mode in nonexec desc-exit1 desc-nonjson contract99 cap-tracker; do
  reset
  make_adapter "$MACHINE_RUNG" working machine-trunk "$MACHINE_LOG"
  make_adapter "$PROJECT_RUNG" "$mode" trunk "$PROJECT_LOG"

  run "$MACHINE" cdd-worktree-gc --force
  [[ $RC -ne 0 ]] || fail "broken ($mode): gc should fail$(show)"
  one_line_matching -F "code-host adapter .cdd/code-host is unusable" \
    || fail "broken ($mode): gc should print exactly one line naming the adapter$(show)"
  [[ -f "$DIR/$MERGED.md" ]] || fail "broken ($mode): gc reaped something"

  run "$MACHINE" cdd-worktree-list
  [[ $RC -eq 0 ]] || fail "broken ($mode): list should still list (exit 0)$(show)"
  grep -q "is unusable" "$WORK/err" || fail "broken ($mode): list should report the adapter$(show)"
  [[ "$(pr_column "$MERGED")" == "-" ]] || fail "broken ($mode): list should show '-' PRs$(show)"

  run "$MACHINE" cdd-worktree-default-branch
  [[ $RC -ne 0 ]] || fail "broken ($mode): default-branch should fail$(show)"

  [[ ! -s "$GH_LOG" ]] || fail "broken ($mode): gh was called: $(cat "$GH_LOG")"
  [[ ! -s "$MACHINE_LOG" ]] || fail "broken ($mode): fell through to the machine adapter"
  pass "broken project adapter ($mode): gc stops, list shows '-', default-branch fails; no lower rung"
done

# --- 5. An unsupported verb skips the feature ----------------------------------
for mode in only-default declared-exit3; do
  reset
  make_adapter "$PROJECT_RUNG" "$mode" trunk "$PROJECT_LOG"
  run "$MACHINE" cdd-worktree-gc --force
  [[ $RC -eq 0 ]] || fail "unsupported ($mode): gc should exit 0$(show)"
  grep -q "does not support pr-merged" "$WORK/err" || fail "unsupported ($mode): gc should say why it skipped$(show)"
  [[ -f "$DIR/$MERGED.md" ]] || fail "unsupported ($mode): gc reaped something"
  run "$MACHINE" cdd-worktree-list
  [[ $RC -eq 0 && "$(pr_column "$MERGED")" == "-" ]] || fail "unsupported ($mode): list should show '-'$(show)"
  [[ ! -s "$GH_LOG" ]] || fail "unsupported ($mode): gh was called: $(cat "$GH_LOG")"
  pass "unsupported pr verbs ($mode): gc reaps nothing and exits 0, list shows '-'"
done

# --- 6. resume and cdd-worktree stop before creating anything ------------------
reset
make_adapter "$MACHINE_RUNG" desc-exit1 main "$MACHINE_LOG"
run "$MACHINE" cdd-worktree-resume "$RESUME"
[[ $RC -ne 0 ]] || fail "broken adapter: resume should fail$(show)"
[[ ! -e "$WORK/machine-$RESUME" ]] || fail "broken adapter: resume created a worktree"
grep -q "is unusable" "$WORK/err" || fail "broken adapter: resume should name the adapter$(show)"

printf '# Task: feat_new\n' > "$DIR/feat_new.md"
run "$MACHINE" cdd-worktree feat_new
[[ $RC -ne 0 ]] || fail "broken adapter: cdd-worktree should fail$(show)"
[[ ! -e "$WORK/machine-feat_new" ]] || fail "broken adapter: cdd-worktree created a worktree"
git -C "$MACHINE" show-ref --verify --quiet refs/heads/feat_new && fail "broken adapter: cdd-worktree created a branch"
rm -f "$DIR/feat_new.md"
pass "a broken adapter stops resume and cdd-worktree before any worktree exists"

# --- 7. done: a broken adapter aborts first; a working one force-deletes -------
reset
git -C "$MACHINE" worktree add -q "$WORK/machine-$OPEN" "$OPEN" 2>/dev/null
make_adapter "$WORK/machine-$OPEN/.cdd/code-host" desc-nonjson main "$PROJECT_LOG"
run "$WORK/machine-$OPEN" cdd-worktree-done
[[ $RC -ne 0 ]] || fail "broken adapter: done should fail$(show)"
[[ -d "$WORK/machine-$OPEN" ]] || fail "broken adapter: done removed the worktree"
grep -q "is unusable" "$WORK/err" || fail "broken adapter: done should name the adapter$(show)"
pass "a broken adapter stops done before the worktree is touched"

reset
git -C "$MACHINE" worktree add -q "$WORK/machine-$MERGED" "$MERGED" 2>/dev/null
make_adapter "$MACHINE_RUNG" working main "$MACHINE_LOG"
run "$WORK/machine-$MERGED" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "working adapter: done exited $RC$(show)"
grep -q "squash-merged via PR #42" "$WORK/out" || fail "working adapter: done should trust the adapter's pr-merged$(show)"
git -C "$MACHINE" show-ref --verify --quiet "refs/heads/$MERGED" && fail "working adapter: done left the branch"
[[ ! -f "$DIR/$MERGED.md" ]] || fail "working adapter: done left the handoff"
grep -q "^pr-merged $MERGED --base main" "$MACHINE_LOG" || fail "working adapter: done did not call pr-merged --base main"
[[ ! -s "$GH_LOG" ]] || fail "working adapter: done called gh: $(cat "$GH_LOG")"
pass "done force-deletes a branch the adapter says merged, without gh"

echo "all code-host ladder checks passed"
