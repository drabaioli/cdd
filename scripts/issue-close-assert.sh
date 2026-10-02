#!/usr/bin/env bash
# Smoke for the post-merge issue close in cdd-worktree-done and cdd-worktree-gc.
#
# Once a task's PR has merged, both commands close the issue refs recorded on the
# task's state record, through the tracker adapter's `issue-transition <ref> closed`
# (ADR 0012: with no adapter installed there is no built-in gh to fall back to). This
# pins, for both commands:
#   - no refs recorded   -> no tracker call at all, cleanup unchanged, and a broken
#     tracker adapter cannot block it
#   - a successful close -> one "closed" line per ref, record and refs/cdd removed
#   - already closed     -> a success: one info line, no warning, no close call made
#   - a failed close     -> a warning; state record, handoff, plan and refs/cdd kept,
#     the output says gc can retry, and the next gc --force does
# plus: gc's dry run lists what it would close and calls no tracker verb; gc reads refs
# from refs/cdd/<branch> when the record is not local; done closes nothing for a
# zero-commit branch with no merged PR; a broken tracker adapter stops done before the
# worktree is touched and keeps only the tasks with refs in gc; the tracker is
# announced once per run; an adapter without issue-transition skips the close in one
# line and cleanup proceeds; and the GitHub tracker adapter's issue-transition itself.
#
# And the PR link that follows a close: each ref closed now gets one comment naming the
# merged PR and its URL (from the code-host adapter's pr-merged) and a "linked" line; an
# already-closed ref gets none, so a gc retry never comments twice; a failed comment is
# one warning and changes nothing else; an adapter without issue-comment is told once
# per run; and the GitHub tracker adapter's issue-comment itself.
#
# Like code-host-ladder-assert.sh it stands in a local bare repo for origin, gives the
# helpers their own $HOME, and puts a logging `gh` stub on PATH. A stub code-host
# adapter (the machine rung) answers pr-merged for the branches in $MERGED. Where the
# GitHub tracker is wanted, the shipped GitHub adapter runs over the `gh` stub; the stub
# tracker adapters stand in for other backends. Issue state lives in two files the
# stubs share: $CLOSED (closed issues) and $FAILING (issues whose close fails), one ref
# per line. With no adapter at all, nothing may reach `gh` (see "no adapter" below).
#
# Usage: scripts/issue-close-assert.sh   (provisions and tears down its own temp tree)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/tools/cdd-worktree.sh"
GH_ADAPTER="$REPO_ROOT/tools/adapters/tracker/github.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER" ]] || fail "helper not found: $HELPER"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the helpers read the state record's issue refs with it"
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

HOME_A="$WORK/home"
GH_LOG="$WORK/gh.log"
TRACKER_LOG="$WORK/tracker.log"
CLOSED="$WORK/closed"
FAILING="$WORK/failing"
COMMENT_FAILING="$WORK/comment-failing"
MERGED="$WORK/merged"
export GH_LOG CLOSED FAILING COMMENT_FAILING MERGED

# Stub gh: logs every call. `issue view` reads $CLOSED; `issue close` fails for a ref in
# $FAILING and otherwise records the ref in $CLOSED; `issue comment` fails for a ref in
# $COMMENT_FAILING and otherwise prints the new comment's URL. `pr` answers nothing: no
# command may ask gh about PRs.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
has() { grep -qxF -- "$1" "$2" 2>/dev/null; }
case "$1" in
  auth) exit 0 ;;
  issue)
    n="$3"
    case "$2" in
      view)   if has "$n" "$CLOSED"; then echo CLOSED; else echo OPEN; fi ;;
      close)  has "$n" "$FAILING" && exit 1; echo "$n" >> "$CLOSED" ;;
      reopen) grep -vxF -- "$n" "$CLOSED" > "$CLOSED.tmp" || true; mv "$CLOSED.tmp" "$CLOSED" ;;
      comment) has "$n" "$COMMENT_FAILING" && exit 1; echo "https://github.com/o/r/issues/$n#issuecomment-1" ;;
    esac
    exit 0 ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/gh"

# make_tracker <dest> <mode>: a stub tracker adapter logging to $TRACKER_LOG, sharing
# the gh stub's $CLOSED / $FAILING / $COMMENT_FAILING. Modes: working; no-transition
# (does not declare issue-transition); no-comment (does not declare issue-comment);
# broken (describe exits 1).
make_tracker() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\nMODE=%q LOG=%q\n' "$2" "$TRACKER_LOG" > "$1"
  cat >> "$1" <<'EOF'
echo "$*" >> "$LOG"
has() { grep -qxF -- "$1" "$2" 2>/dev/null; }
verbs='["issue-read","issue-transition","issue-comment"]'
[[ "$MODE" == no-transition ]] && verbs='["issue-read"]'
[[ "$MODE" == no-comment ]] && verbs='["issue-read","issue-transition"]'
case "$1" in
  describe)
    [[ "$MODE" == broken ]] && exit 1
    echo '{"capability":"tracker","contract":1,"backend":"stub","ref_pattern":"^[A-Z]+-[0-9]+$","verbs":'"$verbs"'}' ;;
  issue-transition)
    if has "$2" "$FAILING"; then echo "stub: transition refused" >&2; exit 1; fi
    if has "$2" "$CLOSED"; then
      echo "{\"ref\":\"$2\",\"state\":\"closed\",\"state_raw\":\"Done\",\"changed\":false}"
    else
      echo "$2" >> "$CLOSED"
      echo "{\"ref\":\"$2\",\"state\":\"closed\",\"state_raw\":\"Done\",\"changed\":true}"
    fi ;;
  issue-comment)
    if has "$2" "$COMMENT_FAILING"; then echo "stub: comment refused" >&2; exit 1; fi
    echo "{\"ref\":\"$2\",\"url\":\"u\"}" ;;
  *) exit 3 ;;
esac
EOF
  chmod 755 "$1"
}

# make_code_host: the machine-rung code-host adapter; pr-merged says merged (PR #7) for
# the branches listed in $MERGED.
make_code_host() {
  mkdir -p "$HOME_A/.cdd/adapters"
  cat > "$HOME_A/.cdd/adapters/code-host" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  describe) echo '{"capability":"code-host","contract":1,"backend":"stub","verbs":["pr-for-branch","pr-merged"]}' ;;
  pr-for-branch) echo '[]' ;;
  pr-merged)
    if grep -qxF -- "$2" "$MERGED" 2>/dev/null; then
      echo '{"merged":true,"ref":"7","url":"https://github.com/o/r/pull/7"}'
    else
      echo '{"merged":false}'
    fi ;;
  *) exit 3 ;;
esac
EOF
  chmod 755 "$HOME_A/.cdd/adapters/code-host"
}

# use_github_tracker: bind the shipped GitHub tracker adapter at the machine rung; it
# runs over the `gh` stub on PATH.
use_github_tracker() {
  mkdir -p "$HOME_A/.cdd/adapters"
  printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$GH_ADAPTER" > "$MACHINE_TRACKER"
  chmod 755 "$MACHINE_TRACKER"
}

git init --bare -q "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/seed" 2>/dev/null
( cd "$WORK/seed"; echo "# seed" > README.md; git add README.md; git commit -q -m seed; git push -q -u origin main )
MACHINE="$WORK/machine"
git clone -q "$WORK/origin.git" "$MACHINE"
DIR="$HOME_A/.cdd/handoffs/machine"
MACHINE_TRACKER="$HOME_A/.cdd/adapters/tracker"
mkdir -p "$DIR"

reset() {
  rm -rf "$DIR" "$HOME_A/.cdd/adapters"
  mkdir -p "$DIR"
  local r
  for r in $(git -C "$WORK/origin.git" for-each-ref --format='%(refname)' refs/cdd/); do
    git -C "$WORK/origin.git" update-ref -d "$r"
  done
  : > "$GH_LOG"; : > "$TRACKER_LOG"; : > "$CLOSED"; : > "$FAILING"; : > "$COMMENT_FAILING"; : > "$MERGED"
  make_code_host
}

# task <branch> <refs as a JSON array, or ""> — seeds the handoff, plan and state
# record, and pushes refs/cdd/<branch> carrying the handoff and state, as cdd-state does.
task() {
  local b="$1" refs="$2" hb sb tree commit
  printf '# Task: %s\n' "$b" > "$DIR/$b.md"
  printf '# Plan: %s\n' "$b" > "$DIR/$b.plan.md"
  if [[ -n "$refs" ]]; then
    printf '{"stage":"pr_open","issue_refs":%s}\n' "$refs" > "$DIR/$b.state.json"
  else
    printf '{"stage":"pr_open"}\n' > "$DIR/$b.state.json"
  fi
  hb="$(git -C "$MACHINE" hash-object -w "$DIR/$b.md")"
  sb="$(git -C "$MACHINE" hash-object -w "$DIR/$b.state.json")"
  tree="$(printf '100644 blob %s\thandoff.md\n100644 blob %s\tstate.json\n' "$hb" "$sb" | git -C "$MACHINE" mktree)"
  commit="$(git -C "$MACHINE" commit-tree "$tree" -m "cdd: $b")"
  git -C "$MACHINE" push -q origin "$commit:refs/cdd/$b"
}

# worktree <branch> [zero] — a feature worktree for done; one commit unless "zero".
worktree() {
  git -C "$MACHINE" worktree add -q -b "$1" "$WORK/wt-$1" main 2>/dev/null
  if [[ "${2:-}" != zero ]]; then
    ( cd "$WORK/wt-$1"; echo "$1" > "$1.txt"; git add "$1.txt"; git commit -q -m "$1" )
  fi
}

merged() { echo "$1" >> "$MERGED"; }

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

show() { printf '\n--- stdout\n%s\n--- stderr\n%s\n--- gh log\n%s\n--- tracker log\n%s\n' \
  "$(cat "$WORK/out")" "$(cat "$WORK/err")" "$(cat "$GH_LOG")" "$(cat "$TRACKER_LOG")"; }
has_ref() { git -C "$WORK/origin.git" show-ref --verify --quiet "refs/cdd/$1"; }
record_kept() { [[ -f "$DIR/$1.state.json" && -f "$DIR/$1.md" && -f "$DIR/$1.plan.md" ]] && has_ref "$1"; }
record_gone() { [[ ! -e "$DIR/$1.state.json" && ! -e "$DIR/$1.md" && ! -e "$DIR/$1.plan.md" ]] && ! has_ref "$1"; }
no_issue_calls() { ! grep -q '^issue' "$GH_LOG" "$TRACKER_LOG"; }

# --- done ----------------------------------------------------------------------

# 1. No refs: no tracker call, cleanup unchanged, even with a broken tracker adapter.
reset
make_tracker "$MACHINE_TRACKER" broken
task d_norefs ""; merged d_norefs; worktree d_norefs
run "$WORK/wt-d_norefs" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, no refs: exited $RC$(show)"
record_gone d_norefs || fail "done, no refs: the record should be removed$(show)"
no_issue_calls || fail "done, no refs: a tracker call was made$(show)"
[[ ! -s "$TRACKER_LOG" ]] || fail "done, no refs: the tracker adapter was consulted$(show)"
! grep -q tracker "$WORK/err" || fail "done, no refs: the tracker should not be resolved$(show)"
pass "done, no refs: no tracker call, cleanup unchanged, a broken tracker adapter irrelevant"

# 2. A successful close through the GitHub tracker adapter, one line per ref.
reset
use_github_tracker
task d_ok '["#11","#12"]'; merged d_ok; worktree d_ok
run "$WORK/wt-d_ok" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, close: exited $RC$(show)"
for n in 11 12; do
  grep -qx "issue #$n: closed" "$WORK/out" || fail "done, close: expected a closed line for #$n$(show)"
  grep -qx "issue close $n" "$GH_LOG" || fail "done, close: gh issue close $n not called$(show)"
  grep -qxF "issue comment $n --body Closed after PR #7 merged: https://github.com/o/r/pull/7" "$GH_LOG" || fail "done, close: #$n should get the PR link comment$(show)"
  grep -qx "issue #$n: linked PR #7" "$WORK/out" || fail "done, close: expected a linked line for #$n$(show)"
done
record_gone d_ok || fail "done, close: the record should be removed$(show)"
grep -q "tracker: using adapter .*(github)" "$WORK/err" || fail "done, close: the tracker adapter should be announced$(show)"
pass "done closes each recorded issue through the GitHub adapter, links the merged PR on each, then cleans up"

# 3. Already closed is a success: an info line, no warning, no close call.
reset
use_github_tracker
echo 13 >> "$CLOSED"
task d_already '["#13"]'; merged d_already; worktree d_already
run "$WORK/wt-d_already" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, already closed: exited $RC$(show)"
grep -qx "issue #13: already closed" "$WORK/out" || fail "done, already closed: expected the info line$(show)"
! grep -q warning "$WORK/err" || fail "done, already closed: must not warn$(show)"
! grep -q "issue close" "$GH_LOG" || fail "done, already closed: gh issue close was called$(show)"
! grep -q "issue comment" "$GH_LOG" || fail "done, already closed: an issue CDD did not close was commented on$(show)"
record_gone d_already || fail "done, already closed: the record should be removed$(show)"
pass "done treats an already-closed issue as a success, and does not comment on it"

# 4. A failed close keeps the record and refs/cdd; the next gc --force retries it.
reset
use_github_tracker
echo 14 >> "$FAILING"
task d_fail '["#14"]'; merged d_fail; worktree d_fail
run "$WORK/wt-d_fail" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, failed close: exited $RC$(show)"
grep -q "warning: could not close issue #14" "$WORK/err" || fail "done, failed close: expected a warning$(show)"
grep -q "so cdd-worktree-gc can retry" "$WORK/out" || fail "done, failed close: should say gc can retry$(show)"
record_kept d_fail || fail "done, failed close: record, handoff, plan and refs/cdd should be kept$(show)"
: > "$FAILING"; : > "$GH_LOG"
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc retry: exited $RC$(show)"
grep -qx "issue #14: closed" "$WORK/out" || fail "gc retry: the issue should now close$(show)"
grep -q "reap  d_fail (MERGED): removed" "$WORK/out" || fail "gc retry: the task should be reaped$(show)"
record_gone d_fail || fail "gc retry: the record should be removed$(show)"
pass "done keeps the record after a failed close, and the next gc --force closes and reaps"

# 5. A zero-commit branch with no merged PR closes nothing.
reset
use_github_tracker
task d_zero '["#15"]'; worktree d_zero zero
run "$WORK/wt-d_zero" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, zero-commit: exited $RC$(show)"
grep -q "Not closing #15: no merged PR" "$WORK/out" || fail "done, zero-commit: expected the not-closing line$(show)"
! grep -q '^issue' "$GH_LOG" || fail "done, zero-commit: an issue call was made$(show)"
record_gone d_zero || fail "done, zero-commit: the record should be removed as before$(show)"
pass "done closes nothing for a merged-by-ancestry branch the code host has no merged PR for"

# 6. A tracker adapter serves: announced once, called once per ref, gh not used for issues.
reset
make_tracker "$MACHINE_TRACKER" working
echo ABC-2 >> "$CLOSED"
task d_adapter '["ABC-1","ABC-2"]'; merged d_adapter; worktree d_adapter
run "$WORK/wt-d_adapter" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, adapter: exited $RC$(show)"
grep -qx "issue ABC-1: closed" "$WORK/out" || fail "done, adapter: expected ABC-1 closed$(show)"
grep -qx "issue ABC-2: already closed" "$WORK/out" || fail "done, adapter: expected ABC-2 already closed$(show)"
[[ "$(grep -c "tracker: using adapter" "$WORK/err")" == 1 ]] || fail "done, adapter: announce exactly once$(show)"
grep -qx "issue-transition ABC-1 closed" "$TRACKER_LOG" || fail "done, adapter: issue-transition not called$(show)"
grep -qxF "issue-comment ABC-1 --body Closed after PR #7 merged: https://github.com/o/r/pull/7" "$TRACKER_LOG" || fail "done, adapter: ABC-1 should get the PR link comment$(show)"
grep -qx "issue ABC-1: linked PR #7" "$WORK/out" || fail "done, adapter: expected a linked line for ABC-1$(show)"
! grep -q "issue-comment ABC-2" "$TRACKER_LOG" || fail "done, adapter: the changed:false ABC-2 was commented on$(show)"
! grep -q '^issue' "$GH_LOG" || fail "done, adapter: gh was used for issues$(show)"
record_gone d_adapter || fail "done, adapter: the record should be removed$(show)"
pass "done closes through a tracker adapter, announced once, linking the PR only on the ref it closed"

# 7. A failing adapter close keeps the record, naming the adapter's reason.
reset
make_tracker "$MACHINE_TRACKER" working
echo ABC-6 >> "$FAILING"
task d_afail '["ABC-6"]'; merged d_afail; worktree d_afail
run "$WORK/wt-d_afail" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, adapter fails: exited $RC$(show)"
grep -q "warning: could not close issue ABC-6 (exit 1).*transition refused" "$WORK/err" || fail "done, adapter fails: expected the warning$(show)"
record_kept d_afail || fail "done, adapter fails: the record should be kept$(show)"
pass "done keeps the record when the tracker adapter fails to close"

# 7b. A failed comment is one warning; the close stands and cleanup proceeds.
reset
make_tracker "$MACHINE_TRACKER" working
echo ABC-9 >> "$COMMENT_FAILING"
task d_cfail '["ABC-9"]'; merged d_cfail; worktree d_cfail
run "$WORK/wt-d_cfail" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, comment fails: exited $RC$(show)"
grep -qx "issue ABC-9: closed" "$WORK/out" || fail "done, comment fails: the close should stand$(show)"
[[ "$(grep -c "warning: could not link PR #7 on issue ABC-9 (exit 1).*comment refused" "$WORK/err")" == 1 ]] \
  || fail "done, comment fails: expected exactly one warning naming the ref$(show)"
! grep -q "linked" "$WORK/out" || fail "done, comment fails: claimed a link$(show)"
record_gone d_cfail || fail "done, comment fails: the record should still be removed$(show)"
pass "a failed PR-link comment is one warning and never keeps the record"

# 8. A broken tracker adapter stops done before the worktree is touched.
reset
task d_broken '["#16"]'; merged d_broken; worktree d_broken
make_tracker "$WORK/wt-d_broken/.cdd/tracker" broken
run "$WORK/wt-d_broken" cdd-worktree-done
[[ $RC -ne 0 ]] || fail "done, broken tracker: should fail$(show)"
[[ -d "$WORK/wt-d_broken" ]] || fail "done, broken tracker: the worktree was removed"
[[ "$(grep -c "unusable" "$WORK/err")" == 1 ]] || fail "done, broken tracker: expected exactly one line naming the adapter$(show)"
grep -q "tracker adapter .cdd/tracker is unusable" "$WORK/err" || fail "done, broken tracker: the line should name it$(show)"
record_kept d_broken || fail "done, broken tracker: the record should be untouched$(show)"
no_issue_calls || fail "done, broken tracker: fell through to gh$(show)"
rm -rf "$WORK/wt-d_broken/.cdd"
pass "a broken tracker adapter stops done before anything is touched, with no lower rung"

# --- gc ------------------------------------------------------------------------

# 9. Dry run: lists what it would close, calls no tracker verb, deletes nothing.
reset
use_github_tracker
task g_dry '["#21"]'; merged g_dry
run "$MACHINE" cdd-worktree-gc
[[ $RC -eq 0 ]] || fail "gc dry run: exited $RC$(show)"
grep -q "reap  g_dry (MERGED): would remove .*; would close #21" "$WORK/out" || fail "gc dry run: should list the close$(show)"
no_issue_calls || fail "gc dry run: a tracker call was made$(show)"
record_kept g_dry || fail "gc dry run: something was deleted$(show)"
pass "gc's dry run lists what it would close and calls no tracker verb"

# 10. --force, GitHub tracker adapter: no refs, success (record only on refs/cdd), already
# closed, failed, and an unmerged task — all in one run.
reset
use_github_tracker
echo 23 >> "$CLOSED"; echo 24 >> "$FAILING"
task g_norefs "";           merged g_norefs
task g_ok '["#22"]';        merged g_ok
task g_already '["#23"]';   merged g_already
task g_fail '["#24"]';      merged g_fail
task g_open '["#25"]'
rm "$DIR/g_ok.state.json"   # the refs now live only on refs/cdd/g_ok
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc --force: exited $RC$(show)"
record_gone g_norefs || fail "gc --force: the ref-less task should be reaped$(show)"
grep -qx "issue #22: closed" "$WORK/out" || fail "gc --force: refs read from refs/cdd should close$(show)"
record_gone g_ok || fail "gc --force: the task closed from refs/cdd should be reaped$(show)"
grep -qx "issue #23: already closed" "$WORK/out" || fail "gc --force: expected the already-closed line$(show)"
record_gone g_already || fail "gc --force: an already-closed task should be reaped$(show)"
grep -q "warning: could not close issue #24" "$WORK/err" || fail "gc --force: expected a warning for #24$(show)"
grep -q "keep  g_fail (MERGED, issue close failed" "$WORK/out" || fail "gc --force: expected a keep line for g_fail$(show)"
record_kept g_fail || fail "gc --force: a failed close should keep the task$(show)"
record_kept g_open || fail "gc --force: the unmerged task was reaped$(show)"
! grep -q "^issue .* 25" "$GH_LOG" || fail "gc --force: the unmerged task's issue was touched$(show)"
[[ "$(grep -c "issue close" "$GH_LOG")" == 2 ]] || fail "gc --force: expected two close calls (22, 24)$(show)"
grep -qxF "issue comment 22 --body Closed after PR #7 merged: https://github.com/o/r/pull/7" "$GH_LOG" || fail "gc --force: #22 should get the PR link from the code host's url$(show)"
[[ "$(grep -c "issue comment" "$GH_LOG")" == 1 ]] || fail "gc --force: only the issue gc closed should be commented on$(show)"
! grep -q "^warning" <(grep -v "#24" "$WORK/err") || fail "gc --force: unexpected warning$(show)"
pass "gc --force closes, treats already-closed as success, keeps a failed close, skips ref-less tasks"

# 11. An adapter: announced once for the whole run; changed:false read as already closed.
reset
make_tracker "$MACHINE_TRACKER" working
echo ABC-3 >> "$CLOSED"
task g_a '["ABC-1","ABC-2"]'; merged g_a
task g_b '["ABC-3"]';         merged g_b
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc, adapter: exited $RC$(show)"
[[ "$(grep -c "tracker: using adapter" "$WORK/err")" == 1 ]] || fail "gc, adapter: announce exactly once$(show)"
for line in "issue ABC-1: closed" "issue ABC-2: closed" "issue ABC-3: already closed"; do
  grep -qxF "$line" "$WORK/out" || fail "gc, adapter: expected '$line'$(show)"
done
record_gone g_a || fail "gc, adapter: g_a should be reaped$(show)"
record_gone g_b || fail "gc, adapter: g_b should be reaped$(show)"
! grep -q '^issue' "$GH_LOG" || fail "gc, adapter: gh was used for issues$(show)"
pass "gc closes through a tracker adapter, announced once per run"

# 12. An adapter without issue-transition: one line, cleanup proceeds.
reset
make_tracker "$MACHINE_TRACKER" no-transition
task g_nt '["ABC-7","ABC-8"]'; merged g_nt
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc, no issue-transition: exited $RC$(show)"
[[ "$(grep -c "does not support issue-transition" "$WORK/err")" == 1 ]] || fail "gc, no issue-transition: expected one line$(show)"
record_gone g_nt || fail "gc, no issue-transition: the task should still be reaped$(show)"
pass "an adapter without issue-transition skips the close in one line; cleanup proceeds"

# 12b. An adapter without issue-comment: closes both, says so once, cleanup proceeds.
reset
make_tracker "$MACHINE_TRACKER" no-comment
task g_nc '["ABC-10","ABC-11"]'; merged g_nc
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc, no issue-comment: exited $RC$(show)"
for r in ABC-10 ABC-11; do
  grep -qx "issue $r: closed" "$WORK/out" || fail "gc, no issue-comment: $r should close$(show)"
done
[[ "$(grep -c "does not support issue-comment" "$WORK/err")" == 1 ]] || fail "gc, no issue-comment: expected one line$(show)"
! grep -q "^warning" "$WORK/err" || fail "gc, no issue-comment: unexpected warning$(show)"
record_gone g_nc || fail "gc, no issue-comment: the task should be reaped$(show)"
pass "an adapter without issue-comment closes anyway, says so once, cleanup proceeds"

# 12c. A gc retry after a partly failed close comments only on the ref it closes now,
# with the PR's url from gc's own merge check.
reset
make_tracker "$MACHINE_TRACKER" working
echo ABC-13 >> "$FAILING"
task g_retry '["ABC-12","ABC-13"]'; merged g_retry; worktree g_retry
run "$WORK/wt-g_retry" cdd-worktree-done
record_kept g_retry || fail "gc retry, comments: done should keep the record$(show)"
: > "$FAILING"
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc retry, comments: exited $RC$(show)"
grep -qx "issue ABC-12: already closed" "$WORK/out" || fail "gc retry, comments: ABC-12 was closed by done$(show)"
grep -qx "issue ABC-13: linked PR #7" "$WORK/out" || fail "gc retry, comments: ABC-13 should be linked now$(show)"
for r in ABC-12 ABC-13; do
  [[ "$(grep -c "^issue-comment $r " "$TRACKER_LOG")" == 1 ]] || fail "gc retry, comments: $r should be commented on exactly once$(show)"
done
grep -qxF "issue-comment ABC-13 --body Closed after PR #7 merged: https://github.com/o/r/pull/7" "$TRACKER_LOG" || fail "gc retry, comments: gc should pass the PR's url$(show)"
record_gone g_retry || fail "gc retry, comments: the task should be reaped$(show)"
pass "a gc retry never comments twice, and links the PR from its own merge check"

# 13. A broken tracker adapter keeps only the tasks with refs.
reset
make_tracker "$MACHINE_TRACKER" broken
task g_refs '["#26"]'; merged g_refs
task g_none "";        merged g_none
run "$MACHINE" cdd-worktree-gc
grep -q "keep  g_refs (MERGED): tracker adapter unusable, would not reap" "$WORK/out" \
  || fail "gc dry run, broken tracker: should say it would keep$(show)"
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc, broken tracker: exited $RC$(show)"
grep -qF "keep  g_refs (MERGED, tracker adapter unusable: issues #26 not closed)" "$WORK/out" \
  || fail "gc, broken tracker: expected the keep line$(show)"
record_kept g_refs || fail "gc, broken tracker: the task with refs should be kept$(show)"
record_gone g_none || fail "gc, broken tracker: the ref-less task should still be reaped$(show)"
[[ "$(grep -c "is unusable" "$WORK/err")" == 1 ]] || fail "gc, broken tracker: expected one line naming it$(show)"
no_issue_calls || fail "gc, broken tracker: fell through to gh$(show)"
pass "a broken tracker adapter keeps the tasks with refs and reaps the rest"

# --- no adapter: skip with one line, never gh (ADR 0012) -------------------------

# 14. No tracker adapter, a merged PR: done warns naming the refs, keeps the record for
# gc, and a gc --force with still no tracker keeps the task too. gh is never called.
reset
task n_done '["#41"]'; merged n_done; worktree n_done
run "$WORK/wt-n_done" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, no tracker: exited $RC$(show)"
grep -qF "tracker: no adapter installed; run /cdd-retrofit in this project to install one; not closing #41" "$WORK/err" \
  || fail "done, no tracker: expected the missing-adapter warning naming the ref$(show)"
grep -q "so cdd-worktree-gc can retry" "$WORK/out" || fail "done, no tracker: should say gc can retry$(show)"
record_kept n_done || fail "done, no tracker: the record should be kept$(show)"
[[ ! -s "$GH_LOG" ]] || fail "done, no tracker: gh was called: $(cat "$GH_LOG")"
run "$MACHINE" cdd-worktree-gc
grep -qF "keep  n_done (MERGED): no tracker adapter, would not reap until one is installed" "$WORK/out" \
  || fail "gc dry run, no tracker: expected the keep line$(show)"
run "$MACHINE" cdd-worktree-gc --force
[[ $RC -eq 0 ]] || fail "gc, no tracker: exited $RC$(show)"
grep -qF "keep  n_done (MERGED, no tracker adapter: issues #41 not closed)" "$WORK/out" \
  || fail "gc, no tracker: expected the keep line$(show)"
record_kept n_done || fail "gc, no tracker: the task should be kept$(show)"
[[ ! -s "$GH_LOG" ]] || fail "gc, no tracker: gh was called: $(cat "$GH_LOG")"
use_github_tracker
run "$MACHINE" cdd-worktree-gc --force
grep -qx "issue #41: closed" "$WORK/out" || fail "gc, tracker installed later: the issue should now close$(show)"
record_gone n_done || fail "gc, tracker installed later: the task should be reaped$(show)"
pass "no tracker adapter: done and gc skip the close with one line, keep the record, and gc closes once one is installed"

# 15. No code-host adapter: a task with refs cannot be confirmed merged, so done warns
# and keeps the record (never silently reaps or closes), and gc reaps nothing.
reset
rm -f "$HOME_A/.cdd/adapters/code-host"
use_github_tracker
task n_ch '["#42"]'; worktree n_ch zero
run "$WORK/wt-n_ch" cdd-worktree-done
[[ $RC -eq 0 ]] || fail "done, no code host: exited $RC$(show)"
grep -qF "code-host: no adapter installed; run /cdd-retrofit in this project to install one" "$WORK/err" \
  || fail "done, no code host: expected the missing-adapter line$(show)"
grep -q "could not confirm a merged PR for 'n_ch'; not closing #42 yet" "$WORK/err" || fail "done, no code host: expected the could-not-confirm warning$(show)"
record_kept n_ch || fail "done, no code host: the record should be kept$(show)"
task n_gc '["#43"]'; merged n_gc
run "$MACHINE" cdd-worktree-gc --force
grep -qF "code-host: no adapter installed; run /cdd-retrofit in this project to install one" "$WORK/err" || fail "gc, no code host: expected the missing-adapter line$(show)"
record_kept n_gc || fail "gc, no code host: nothing may be reaped$(show)"
! grep -q "^issue" "$GH_LOG" "$TRACKER_LOG" || fail "no code host: an issue call was made$(show)"
[[ ! -s "$GH_LOG" ]] || fail "no code host: gh was called: $(cat "$GH_LOG")"
pass "no code-host adapter: done keeps the record, gc reaps nothing, nothing closes, gh never called"

# --- the GitHub tracker adapter's issue-transition ------------------------------
reset
gh_adapter() {
  RC=0
  # shellcheck disable=SC2031  # the stub PATH is meant for this one call
  PATH="$WORK/bin:$PATH" "$GH_ADAPTER" "$@" >"$WORK/out" 2>"$WORK/err" || RC=$?
}
gh_adapter issue-transition 31 closed
[[ $RC -eq 0 && "$(jq -c . "$WORK/out")" == '{"ref":"31","state":"closed","state_raw":"CLOSED","changed":true}' ]] \
  || fail "github adapter: close should report changed:true$(show)"
grep -qx "issue close 31" "$GH_LOG" || fail "github adapter: gh issue close not called$(show)"
: > "$GH_LOG"
gh_adapter issue-transition '#31' closed
[[ $RC -eq 0 && "$(jq -r .changed "$WORK/out")" == false ]] || fail "github adapter: already closed should be changed:false$(show)"
! grep -q "issue close" "$GH_LOG" || fail "github adapter: closed an already-closed issue$(show)"
gh_adapter issue-transition 31 open
[[ $RC -eq 0 && "$(jq -r .changed "$WORK/out")" == true ]] || fail "github adapter: open should report changed:true$(show)"
grep -qx "issue reopen 31" "$GH_LOG" || fail "github adapter: open should reopen$(show)"
gh_adapter issue-transition 31 bogus
[[ $RC -eq 2 ]] || fail "github adapter: a bad state should exit 2, got $RC$(show)"
pass "the GitHub tracker adapter's issue-transition closes, reopens, and no-ops when already there"

: > "$GH_LOG"
gh_adapter issue-comment 31 --body hi
[[ $RC -eq 0 && "$(jq -c . "$WORK/out")" == '{"ref":"31","url":"https://github.com/o/r/issues/31#issuecomment-1"}' ]] \
  || fail "github adapter: issue-comment should report the comment's url$(show)"
grep -qx "issue comment 31 --body hi" "$GH_LOG" || fail "github adapter: gh issue comment not called$(show)"
gh_adapter issue-comment 31
[[ $RC -eq 2 ]] || fail "github adapter: issue-comment without --body should exit 2, got $RC$(show)"
gh_adapter issue-comment
[[ $RC -eq 2 ]] || fail "github adapter: issue-comment without a ref should exit 2, got $RC$(show)"
echo 31 >> "$COMMENT_FAILING"
gh_adapter issue-comment 31 --body hi
[[ $RC -eq 1 ]] || fail "github adapter: a failed comment should exit 1, got $RC$(show)"
pass "the GitHub tracker adapter's issue-comment posts, reports the url, and rejects bad usage"

echo "all issue-close checks passed"
