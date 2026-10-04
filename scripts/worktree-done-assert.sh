#!/usr/bin/env bash
# Smoke for cdd-worktree-done's removal and branch-deletion paths.
#
# Removal:
#   - run from a subdirectory, done removes the WHOLE worktree, not that subdirectory
#   - an untracked file stops done before anything is removed, and is named
#   - a permission error (a read-only directory of ignored build output) is the only
#     failure that offers `sudo rm -rf`; "y" removes and prunes, "n" leaves it
#   - any other removal failure — a locked worktree, a path git says is not a working
#     tree — aborts with git's message, nothing deleted, and no sudo
#
# Branch resolution:
#   - merged by ancestry -> `git branch -d`, handoff removed
#   - a merged PR whose head_sha is the local tip -> force-deleted, handoff removed
#   - a merged PR whose head_sha descends from the local tip (the branch is behind its
#     PR: commits pushed from elsewhere) -> force-deleted too, fetching the head
#   - a merged PR at other commits (a reused branch name), or one reporting no
#     head_sha -> never force-deleted: the keep/delete/abort prompt
#   - no merged PR -> the prompt; abort keeps the branch
#   - a head mismatch closes no issue, even when the human deletes the branch
#
# Like issue-close-assert.sh it stands in a local bare repo for origin and gives the
# helper its own $HOME. A stub code-host adapter (the machine rung) answers pr-merged
# for the branches in $MERGED, with head_sha chosen by $HEADMODE: match (the local
# branch's tip), mismatch (a fixed foreign SHA), missing (no field), or a literal SHA
# (the PR's head on origin, ahead of the local branch). A logging `sudo`
# stub on PATH restores write permission and runs its arguments, so the sudo path runs
# without real sudo; a `git` wrapper fakes the "not a working tree" failure, which the
# top-level removal target no longer reaches through normal use.
#
# Usage: scripts/worktree-done-assert.sh   (provisions and tears down its own temp tree)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/tools/cdd-worktree.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER" ]] || fail "helper not found: $HELPER"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the helper reads the code host's pr-merged answer with it"
  exit 0
fi

# Physical path: done removes `git rev-parse --show-toplevel`, which resolves symlinks.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
# The permission case leaves read-only directories behind; restore write first.
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

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

HOME_A="$WORK/home"
SUDO_LOG="$WORK/sudo.log"
MERGED="$WORK/merged"
HEADMODE="$WORK/headmode"
FOREIGN_SHA="0123456789abcdef0123456789abcdef01234567"
export SUDO_LOG MERGED HEADMODE FOREIGN_SHA

# Stub sudo: logs the call, makes its last argument writable again, then runs it.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$SUDO_LOG"
for last; do :; done
chmod -R u+w "$last" 2>/dev/null
exec "$@"
EOF
chmod +x "$WORK/bin/sudo"

# A git wrapper, on PATH only where asked: `worktree remove` fails as on a path that is
# not a working tree; everything else is the real git.
mkdir -p "$WORK/gitwrap"
printf '#!/usr/bin/env bash\nREAL_GIT=%q\n' "$(command -v git)" > "$WORK/gitwrap/git"
cat >> "$WORK/gitwrap/git" <<'EOF'
if [[ "${1-}" == worktree && "${2-}" == remove ]]; then
  echo "fatal: '$3' is not a working tree" >&2
  exit 128
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$WORK/gitwrap/git"

mkdir -p "$HOME_A/.cdd/adapters"
cat > "$HOME_A/.cdd/adapters/code-host" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  describe) echo '{"capability":"code-host","contract":1,"backend":"stub","verbs":["pr-for-branch","pr-merged"]}' ;;
  pr-for-branch) echo '[]' ;;
  pr-merged)
    if grep -qxF -- "$2" "$MERGED" 2>/dev/null; then
      case "$(cat "$HEADMODE")" in
        match)    echo '{"merged":true,"ref":"7","head_sha":"'"$(git rev-parse "refs/heads/$2")"'"}' ;;
        mismatch) echo '{"merged":true,"ref":"7","head_sha":"'"$FOREIGN_SHA"'"}' ;;
        missing)  echo '{"merged":true,"ref":"7"}' ;;
        *)        echo '{"merged":true,"ref":"7","head_sha":"'"$(cat "$HEADMODE")"'"}' ;;
      esac
    else
      echo '{"merged":false}'
    fi ;;
  *) exit 3 ;;
esac
EOF
chmod 755 "$HOME_A/.cdd/adapters/code-host"

git init --bare -q "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/seed" 2>/dev/null
( cd "$WORK/seed"; echo "# seed" > README.md; git add README.md; git commit -q -m seed; git push -q -u origin main )
MACHINE="$WORK/machine"
git clone -q "$WORK/origin.git" "$MACHINE"
DIR="$HOME_A/.cdd/handoffs/machine"
mkdir -p "$DIR"
: > "$MERGED"; echo match > "$HEADMODE"

# worktree <branch> [zero] — a feature worktree with a handoff; one commit unless "zero".
worktree() {
  git -C "$MACHINE" worktree add -q -b "$1" "$WORK/wt-$1" main 2>/dev/null
  printf '# Task: %s\n' "$1" > "$DIR/$1.md"
  if [[ "${2:-}" != zero ]]; then
    ( cd "$WORK/wt-$1"; echo "$1" > "$1.txt"; git add "$1.txt"; git commit -q -m "$1" )
  fi
}

# run <stdin text> <dir> <command> <arg>... — stdout to $WORK/out, stderr to $WORK/err;
# sets RC. $EXTRA_PATH, when set, goes on PATH ahead of the real tools.
run() {
  local input="$1" dir="$2"; shift 2
  printf '%s' "$input" > "$WORK/stdin"
  : > "$SUDO_LOG"
  RC=0
  (
    cd "$dir"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$HOME_A" PATH="$WORK/bin:${EXTRA_PATH:+$EXTRA_PATH:}$PATH"
    # shellcheck source=/dev/null
    source "$HELPER"
    "$@"
  ) >"$WORK/out" 2>"$WORK/err" <"$WORK/stdin" || RC=$?
}

show() { printf '\n--- stdout\n%s\n--- stderr\n%s\n--- sudo log\n%s\n' \
  "$(cat "$WORK/out")" "$(cat "$WORK/err")" "$(cat "$SUDO_LOG")"; }
has_branch() { git -C "$MACHINE" show-ref --verify --quiet "refs/heads/$1"; }
listed() { git -C "$MACHINE" worktree list --porcelain | grep -qxF "worktree $1"; }
no_sudo() { [[ ! -s "$SUDO_LOG" ]]; }

# --- removal -------------------------------------------------------------------

# 1. From a subdirectory: the whole worktree goes, not just the directory run from.
worktree a_sub zero
( cd "$WORK/wt-a_sub"; mkdir -p sub/dir; echo x > sub/dir/f; git add sub; git commit -q -m sub )
git -C "$MACHINE" merge -q --ff-only a_sub
git -C "$MACHINE" push -q origin main
run "" "$WORK/wt-a_sub/sub/dir" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "subdirectory: exited $RC$(show)"
[[ ! -e "$WORK/wt-a_sub" ]] || fail "subdirectory: the worktree root is still there$(show)"
! listed "$WORK/wt-a_sub" || fail "subdirectory: still in git worktree list$(show)"
! has_branch a_sub || fail "subdirectory: the merged branch was not deleted$(show)"
no_sudo || fail "subdirectory: sudo was called$(show)"
pass "run from a subdirectory, done removes the whole worktree"

# 2. An untracked file stops done before any removal, and is named.
worktree b_untracked
touch "$WORK/wt-b_untracked/stray.txt"
run "" "$WORK/wt-b_untracked" cdd-worktree-done
[[ $RC -eq 1 ]] || fail "untracked: expected exit 1, got $RC$(show)"
grep -q "stray.txt" "$WORK/err" || fail "untracked: the blocking file is not named$(show)"
{ [[ -f "$WORK/wt-b_untracked/stray.txt" ]] && listed "$WORK/wt-b_untracked"; } \
  || fail "untracked: the worktree was touched$(show)"
has_branch b_untracked || fail "untracked: the branch was deleted$(show)"
[[ -f "$DIR/b_untracked.md" ]] || fail "untracked: the handoff was removed$(show)"
no_sudo || fail "untracked: sudo was called$(show)"
pass "an untracked file stops done before removal, naming the file"

# 3. A permission error is the one failure that offers sudo. Root bypasses permissions,
# so the failure cannot be produced there.
if [[ "$(id -u)" == 0 ]]; then
  echo "ok: skipped the permission-error case (running as root)"
else
  # Ignored build output in a read-only directory: git deletes ignored files, so this is
  # what a root-owned container build looks like to it. info/exclude is shared.
  echo "build/" >> "$MACHINE/.git/info/exclude"
  perm_tree() {
    worktree "$1" zero
    mkdir -p "$WORK/wt-$1/build/sub"; touch "$WORK/wt-$1/build/sub/x"
    chmod 555 "$WORK/wt-$1/build/sub"
  }

  perm_tree c_perm
  run "y" "$WORK/wt-c_perm" cdd-worktree-done
  [[ $RC -eq 0 ]] || fail "permission, y: exited $RC$(show)"
  grep -q "permission error" "$WORK/out" || fail "permission, y: the prompt should name a permission error$(show)"
  grep -qxF "rm -rf $WORK/wt-c_perm" "$SUDO_LOG" || fail "permission, y: expected sudo rm -rf on the worktree root$(show)"
  [[ ! -e "$WORK/wt-c_perm" ]] || fail "permission, y: the worktree is still there$(show)"
  ! listed "$WORK/wt-c_perm" || fail "permission, y: not pruned from git worktree list$(show)"
  pass "a permission error offers sudo rm -rf on the worktree root; y removes and prunes"

  perm_tree c_perm_n
  run "n" "$WORK/wt-c_perm_n" cdd-worktree-done
  [[ $RC -eq 1 ]] || fail "permission, n: expected exit 1, got $RC$(show)"
  [[ -d "$WORK/wt-c_perm_n" ]] || fail "permission, n: the worktree is gone$(show)"
  no_sudo || fail "permission, n: sudo was called$(show)"
  has_branch c_perm_n || fail "permission, n: the branch was deleted$(show)"
  chmod -R u+w "$WORK/wt-c_perm_n"
  pass "declining the sudo offer leaves the worktree and the branch"
fi

# 4. A locked worktree aborts with git's message: nothing deleted, no sudo.
worktree d_locked zero
git -C "$MACHINE" worktree lock --reason "smoke" "$WORK/wt-d_locked"
run "y" "$WORK/wt-d_locked" cdd-worktree-done
[[ $RC -eq 1 ]] || fail "locked: expected exit 1, got $RC$(show)"
grep -q "locked" "$WORK/err" || fail "locked: git's message should be shown$(show)"
grep -q "Nothing was deleted" "$WORK/err" || fail "locked: should say nothing was deleted$(show)"
no_sudo || fail "locked: sudo was called$(show)"
{ [[ -d "$WORK/wt-d_locked" ]] && listed "$WORK/wt-d_locked"; } || fail "locked: the worktree was touched$(show)"
has_branch d_locked || fail "locked: the branch was deleted$(show)"
git -C "$MACHINE" worktree unlock "$WORK/wt-d_locked"
pass "a locked worktree aborts with git's message, nothing deleted, no sudo"

# 5. "Not a working tree" aborts the same way.
worktree e_notwt zero
EXTRA_PATH="$WORK/gitwrap" run "y" "$WORK/wt-e_notwt" cdd-worktree-done
[[ $RC -eq 1 ]] || fail "not a working tree: expected exit 1, got $RC$(show)"
grep -q "is not a working tree" "$WORK/err" || fail "not a working tree: git's message should be shown$(show)"
no_sudo || fail "not a working tree: sudo was called$(show)"
{ [[ -d "$WORK/wt-e_notwt" ]] && listed "$WORK/wt-e_notwt"; } || fail "not a working tree: the worktree was touched$(show)"
pass "a 'not a working tree' failure aborts, nothing deleted, no sudo"

# --- branch resolution ---------------------------------------------------------

# 6. Merged by ancestry: -d, handoff removed.
worktree f_anc zero
run "" "$WORK/wt-f_anc" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "ancestry: exited $RC$(show)"
! has_branch f_anc || fail "ancestry: the branch was not deleted$(show)"
[[ ! -e "$DIR/f_anc.md" ]] || fail "ancestry: the handoff was kept$(show)"
pass "a branch merged by ancestry is deleted with its handoff"

# 7. Squash-merged, head_sha is the local tip: force-deleted.
worktree f_sq; echo f_sq >> "$MERGED"; echo match > "$HEADMODE"
run "" "$WORK/wt-f_sq" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "squash, match: exited $RC$(show)"
grep -q "squash-merged via PR #7, force-deleting" "$WORK/out" || fail "squash, match: expected the force-delete line$(show)"
! has_branch f_sq || fail "squash, match: the branch was not deleted$(show)"
[[ ! -e "$DIR/f_sq.md" ]] || fail "squash, match: the handoff was kept$(show)"
pass "a merged PR whose head is the local tip force-deletes the branch"

# 7b. Squash-merged, the PR's head is ahead of the local tip (a commit pushed from
# another clone, never fetched here): it contains every local commit, so force-deleted.
worktree f_behind
git -C "$WORK/wt-f_behind" push -q origin f_behind
( cd "$WORK/seed"; git fetch -q origin f_behind; git checkout -q -b f_behind FETCH_HEAD
  echo more > more.txt; git add more.txt; git commit -q -m more; git push -q origin f_behind; git checkout -q main )
ahead="$(git -C "$WORK/seed" rev-parse refs/heads/f_behind)"
! git -C "$MACHINE" cat-file -e "$ahead^{commit}" 2>/dev/null || fail "behind: fixture already has the PR head"
echo f_behind >> "$MERGED"; echo "$ahead" > "$HEADMODE"
run "" "$WORK/wt-f_behind" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "squash, behind: exited $RC$(show)"
grep -q "squash-merged via PR #7, force-deleting" "$WORK/out" || fail "squash, behind: expected the force-delete line$(show)"
! has_branch f_behind || fail "squash, behind: the branch was not deleted$(show)"
pass "a merged PR whose head descends from the local tip force-deletes the branch"

# 8. Merged PR at other commits (a reused name): the prompt; keep keeps everything.
worktree f_mm; echo f_mm >> "$MERGED"; echo mismatch > "$HEADMODE"
tip="$(git -C "$MACHINE" rev-parse refs/heads/f_mm)"
run "k" "$WORK/wt-f_mm" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "squash, mismatch: exited $RC$(show)"
grep -q "merged PR #7 is for other commits than its tip" "$WORK/out" || fail "squash, mismatch: expected the mismatch line$(show)"
grep -q "${FOREIGN_SHA:0:12}.*${tip:0:12}" "$WORK/err" || fail "squash, mismatch: both commits should be named$(show)"
! grep -q "force-deleting" "$WORK/out" || fail "squash, mismatch: force-deleted$(show)"
has_branch f_mm || fail "squash, mismatch: the branch was deleted$(show)"
[[ -f "$DIR/f_mm.md" ]] || fail "squash, mismatch: the handoff was removed$(show)"
pass "a merged PR at other commits than the tip falls to the prompt, never force-deletes"

# 9. Merged PR with no head_sha: unconfirmed, the prompt.
worktree f_nohead; echo f_nohead >> "$MERGED"; echo missing > "$HEADMODE"
run "k" "$WORK/wt-f_nohead" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "squash, no head: exited $RC$(show)"
grep -q "did not report its head commit" "$WORK/out" || fail "squash, no head: expected the unconfirmed line$(show)"
has_branch f_nohead || fail "squash, no head: the branch was deleted$(show)"
[[ -f "$DIR/f_nohead.md" ]] || fail "squash, no head: the handoff was removed$(show)"
pass "a merged PR reporting no head commit falls to the prompt"

# 10. No merged PR: the prompt; abort keeps the branch.
worktree f_open
run "a" "$WORK/wt-f_open" cdd-worktree-done
[[ $RC -eq 1 ]] || fail "unmerged, abort: expected exit 1, got $RC$(show)"
grep -q "has no merged PR" "$WORK/out" || fail "unmerged, abort: expected the no-merged-PR line$(show)"
has_branch f_open || fail "unmerged, abort: the branch was deleted$(show)"
[[ -f "$DIR/f_open.md" ]] || fail "unmerged, abort: the handoff was removed$(show)"
pass "an unmerged branch falls to the prompt, and abort keeps it"

# 11. A head mismatch closes no issue, even when the human deletes the branch.
worktree f_mmd; echo f_mmd >> "$MERGED"; echo mismatch > "$HEADMODE"
printf '{"stage":"pr_open","issue_refs":["#5"]}\n' > "$DIR/f_mmd.state.json"
run "d" "$WORK/wt-f_mmd" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "mismatch, delete: exited $RC$(show)"
! has_branch f_mmd || fail "mismatch, delete: the branch should be deleted by the human's choice$(show)"
grep -qF "Not closing #5: merged PR #7 is for other commits than 'f_mmd'." "$WORK/out" \
  || fail "mismatch, delete: expected the not-closing line$(show)"
pass "a head mismatch closes no issue, even when the branch is deleted"

echo "all worktree-done checks passed"
