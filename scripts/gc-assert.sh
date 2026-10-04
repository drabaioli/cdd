#!/usr/bin/env bash
# Smoke for cdd-worktree-gc: it reaps a MERGED task's artifacts (local handoff, plan
# file and state, and the remote refs/cdd/<branch>) but never a scoped-but-unstarted one.
#
# Like ref-sync-assert.sh this stands in a local `git init --bare` for origin and
# a clone with its own $HOME. PR state is the reap predicate, so a stub code-host
# adapter at the machine rung ($HOME/.cdd/adapters/code-host) answers `pr-merged`:
# feat_merged is merged, everything else is not. A `gh` stub on PATH logs any call and
# must never be reached (ADR 0012: no command calls gh for a code-host job). It asserts:
#   - with NO adapter installed, gc says so in one advisory line and reaps nothing
#     (dry-run and --force alike), and gh is never called
#   - dry-run: the merged branch is listed as "would remove", the scoped one kept,
#     and NOTHING is actually deleted
#   - --force: the merged branch's local files + remote ref are gone, while the
#     scoped branch's files + ref are untouched
#   - the per-repo marker (repo.json), written as a side effect of `cdd-state seed`,
#     survives the reap — it is what keeps the repo locatable once every task is gone
#   - the plan file (<branch>.plan.md, process doc 2.15) is reaped with the rest for a
#     merged task and left alone for a scoped one
#   - a plan file produces NO phantom row in cdd-worktree-list, even though it shares
#     the handoff's .md extension: the shared enumerator filters branch-named sidecars
#   - the head guard: a merged PR whose head_sha does not contain the local branch's tip
#     (a reused name) keeps the task; one whose head_sha is the tip, or descends from
#     it, reaps it
#
# Usage: scripts/gc-assert.sh   (provisions and tears down its own temp tree)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_WT="$REPO_ROOT/tools/cdd-worktree.sh"
HELPER_STATE="$REPO_ROOT/tools/cdd-state.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -f "$HELPER_WT" ]] || fail "helper not found: $HELPER_WT"
[[ -f "$HELPER_STATE" ]] || fail "helper not found: $HELPER_STATE"

# jq is required: the ref push under test lives behind cdd-state's jq guard. A missing
# tool is a failure, never a skip (scripts/ci.sh).
command -v jq >/dev/null 2>&1 || fail "jq is required and not installed"

# Physical path: on macOS mktemp hands out /var/..., a symlink to /private/var/..., while
# git reports the resolved path, so the path compares below would fail spuriously.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
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

MERGED="feat_merged"   # has a MERGED PR (per the gh stub) -> reap
SCOPED="feat_scoped"   # no PR yet -> keep

# Stub gh: records every call. gc must never reach it, with or without an adapter.
mkdir -p "$WORK/bin"
GH_LOG="$WORK/gh.log"
cat > "$WORK/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$GH_LOG"
exit 0
EOF
chmod +x "$WORK/bin/gh"

# Bare origin + a clone that pushes both feature branches (so ls-remote has heads).
git init --bare -q "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/seed" 2>/dev/null
(
  cd "$WORK/seed"
  echo "# seed" > README.md; git add README.md; git commit -q -m "seed"
  git push -q -u origin main
  git switch -q -c "$MERGED"; echo m > m.txt; git add m.txt; git commit -q -m m; git push -q -u origin "$MERGED"
  git switch -q -c "$SCOPED" main; echo s > s.txt; git add s.txt; git commit -q -m s; git push -q -u origin "$SCOPED"
)

HOME_A="$WORK/home"
git clone -q "$WORK/origin.git" "$WORK/machine"
handoff_dir() { printf '%s/.cdd/handoffs/%s' "$HOME_A" "$(basename "$WORK/machine")"; }
DIR="$(handoff_dir)"
mkdir -p "$DIR"

# Seed both tasks on the machine: writes local handoff + state and pushes refs/cdd/*.
run_state() {
  (
    cd "$WORK/machine"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$HOME_A" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER_STATE"
    cdd-state "$@"
  )
}
for b in "$MERGED" "$SCOPED"; do
  printf '# Task: %s\n\nbody\n' "$b" > "$DIR/$b.md"
  printf '# Plan: %s\n\n## Summary\n- body\n' "$b" > "$DIR/$b.plan.md"
  run_state seed "$b" >/dev/null 2>&1 || fail "cdd-state seed failed for $b"
  git -C "$WORK/machine" ls-remote origin "refs/cdd/$b" | grep -q "refs/cdd/$b" \
    || fail "seed did not push refs/cdd/$b"
done
pass "seeded two tasks (handoff + plan + state + refs/cdd/*) on the machine"

# The per-repo marker is a side effect of every seed, and records the MAIN worktree.
[[ -f "$DIR/repo.json" ]] || fail "seed did not write the per-repo marker $DIR/repo.json"
marker_path="$(jq -r '.path' "$DIR/repo.json")"
[[ "$marker_path" == "$WORK/machine" ]] \
  || fail "repo.json .path = '$marker_path', expected '$WORK/machine'"
pass "seed wrote the per-repo marker pointing at the main worktree"

# Stub code-host adapter, installed at the machine rung once the no-adapter case is done.
install_adapter() {
  mkdir -p "$HOME_A/.cdd/adapters"
  cat > "$HOME_A/.cdd/adapters/code-host" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  describe) echo '{"capability":"code-host","contract":1,"backend":"stub","verbs":["pr-for-branch","pr-merged"]}' ;;
  pr-for-branch) echo '[]' ;;
  pr-merged)
    if [[ "$2" == "feat_merged" ]]; then
      echo '{"merged":true,"ref":"7","url":"https://example.invalid/pull/7"}'
    elif [[ "$2" == "feat_reused" ]]; then
      # An old merged PR for a reused name: its head is not the local branch's tip.
      echo '{"merged":true,"ref":"8","head_sha":"0123456789abcdef0123456789abcdef01234567"}'
    elif [[ "$2" == "feat_same" ]]; then
      echo '{"merged":true,"ref":"9","head_sha":"'"$(git rev-parse "refs/heads/$2")"'"}'
    elif [[ "$2" == "feat_ahead" ]]; then
      # The PR's head descends from the local tip: the local branch is behind its PR.
      echo '{"merged":true,"ref":"10","head_sha":"'"$(git rev-parse refs/pr-head/feat_ahead)"'"}'
    else
      echo '{"merged":false}'
    fi ;;
  *) exit 3 ;;
esac
EOF
  chmod +x "$HOME_A/.cdd/adapters/code-host"
}

run_gc() {
  (
    cd "$WORK/machine"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$HOME_A" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER_WT"
    cdd-worktree-gc "$@"
  )
}

# 0. No code-host adapter at any rung: gc cannot tell a merged task from a just-scoped
# one, so it says so in one line and reaps nothing, dry-run or --force.
for flag in "" --force; do
  out="$(run_gc $flag 2>&1)" || fail "gc ${flag:-dry-run} with no adapter exited non-zero"
  grep -q "code-host: no adapter installed; run /cdd-retrofit in this project to install one" <<<"$out" \
    || fail "gc ${flag:-dry-run} with no adapter did not print the missing-adapter line. Output:\n$out"
  grep -q '^reap ' <<<"$out" && fail "gc ${flag:-dry-run} with no adapter reaped a task. Output:\n$out"
  [[ -f "$DIR/$MERGED.md" && -f "$DIR/$MERGED.state.json" && -f "$DIR/$MERGED.plan.md" ]] \
    || fail "gc ${flag:-dry-run} with no adapter deleted local files"
  git -C "$WORK/machine" ls-remote origin "refs/cdd/$MERGED" | grep -q "refs/cdd/$MERGED" \
    || fail "gc ${flag:-dry-run} with no adapter deleted the remote ref"
done
[[ ! -s "$GH_LOG" ]] || fail "gc with no adapter called gh: $(cat "$GH_LOG")"
pass "no adapter: gc prints the missing-adapter line, reaps nothing, never calls gh"

install_adapter

# 1. Dry-run: merged -> "would remove", scoped -> "keep", and nothing deleted.
out="$(run_gc 2>&1)" || fail "gc dry-run exited non-zero"
grep -q "reap  $MERGED (MERGED): would remove" <<<"$out" \
  || fail "dry-run did not mark the merged task for reaping. Output:\n$out"
grep -q "keep  $SCOPED" <<<"$out" \
  || fail "dry-run did not keep the scoped task. Output:\n$out"
grep -q "reap  $MERGED (MERGED): would remove .*plan" <<<"$out" \
  || fail "dry-run did not list the plan file among the merged task's artifacts. Output:\n$out"
[[ -f "$DIR/$MERGED.md" && -f "$DIR/$MERGED.state.json" && -f "$DIR/$MERGED.plan.md" ]] \
  || fail "dry-run must not delete local files"
git -C "$WORK/machine" ls-remote origin "refs/cdd/$MERGED" | grep -q "refs/cdd/$MERGED" \
  || fail "dry-run must not delete the remote ref"
pass "dry-run reports the merged task, keeps the scoped one, deletes nothing"

# 2. --force: merged artifacts gone; scoped artifacts untouched.
out="$(run_gc --force 2>&1)" || fail "gc --force exited non-zero"
[[ ! -f "$DIR/$MERGED.md" && ! -f "$DIR/$MERGED.state.json" && ! -f "$DIR/$MERGED.plan.md" ]] \
  || fail "--force did not remove the merged task's local files"
git -C "$WORK/machine" ls-remote origin "refs/cdd/$MERGED" | grep -q "refs/cdd/$MERGED" \
  && fail "--force did not delete the merged task's remote ref"
[[ -f "$DIR/$SCOPED.md" && -f "$DIR/$SCOPED.state.json" && -f "$DIR/$SCOPED.plan.md" ]] \
  || fail "--force must not touch the scoped task's local files"
git -C "$WORK/machine" ls-remote origin "refs/cdd/$SCOPED" | grep -q "refs/cdd/$SCOPED" \
  || fail "--force must not delete the scoped task's remote ref"
pass "--force reaps the merged task (handoff + plan + state + ref), leaves the scoped task intact"

# 3. The per-repo marker is not task-scoped and must survive the reap: it is what keeps
# the repo locatable once every task is merged and its artifacts are gone. Safe by
# construction (GC's candidates glob *.md and *.state.json plus refs/cdd/*, and it
# matches none of them), pinned here.
[[ -f "$DIR/repo.json" ]] || fail "--force reaped the per-repo marker $DIR/repo.json"
pass "--force leaves the per-repo marker in place"

# 4. A plan file must never surface as a task of its own. It shares the handoff's .md
# extension, so a bare *.md glob would list it as a phantom branch named
# "<branch>.plan" — the whole reason cdd-worktree-handoff-branches exists. The SCOPED
# task still has its plan file (case 2 asserted it survived), so this is the honest test.
run_list() {
  (
    cd "$WORK/machine"
    # shellcheck disable=SC2030,SC2031  # per-subshell HOME/PATH isolation is intended
    export HOME="$HOME_A" PATH="$WORK/bin:$PATH"
    # shellcheck source=/dev/null
    source "$HELPER_WT"
    cdd-worktree-list
  )
}
out="$(run_list 2>&1)" || fail "cdd-worktree-list exited non-zero"
# Data rows only: drop the adapter announcement, the header and its dashed rule. After case 2 the merged task is
# gone, so exactly one task remains — and its plan file must add nothing.
branches="$(awk '/^(BRANCH|------|code-host:)/ { next } { print $1 }' <<<"$out")"
[[ "$branches" == "$SCOPED" ]] \
  || fail "cdd-worktree-list should list exactly '$SCOPED', got: $(tr '\n' ' ' <<<"$branches"). Output:\n$out"
pass "a plan file produces no phantom row in cdd-worktree-list"

# 5. The head guard: a local branch the merged PR's head_sha does not contain is a reused
# name, so its task is kept; one whose tip IS the head, or an ancestor of it (the local
# branch behind its PR), is reaped as before.
for b in feat_reused feat_same feat_ahead; do
  git -C "$WORK/machine" branch "$b" main
  printf '# Task: %s\n' "$b" > "$DIR/$b.md"
  run_state seed "$b" >/dev/null 2>&1 || fail "cdd-state seed failed for $b"
done
git -C "$WORK/machine" update-ref refs/pr-head/feat_ahead \
  "$(git -C "$WORK/machine" commit-tree -p main -m ahead "main^{tree}")"
out="$(run_gc --force 2>&1)" || fail "gc --force (head guard) exited non-zero"
grep -q "keep  feat_reused (merged PR #8 is for other commits than local feat_reused" <<<"$out" \
  || fail "gc should keep a task whose local branch is not the merged PR's head. Output:\n$out"
[[ -f "$DIR/feat_reused.md" && -f "$DIR/feat_reused.state.json" ]] \
  || fail "gc reaped the reused-name task's files"
grep -q "reap  feat_same (MERGED): removed" <<<"$out" \
  || fail "gc should reap a task whose local branch is the merged PR's head. Output:\n$out"
[[ ! -f "$DIR/feat_same.md" ]] || fail "gc did not reap feat_same"
grep -q "reap  feat_ahead (MERGED): removed" <<<"$out" \
  || fail "gc should reap a task whose local branch is behind the merged PR's head. Output:\n$out"
pass "gc keeps a task whose local branch the merged PR's head does not contain, reaps one behind it"

[[ ! -s "$GH_LOG" ]] || fail "gc called gh: $(cat "$GH_LOG")"
pass "gh was never called"

echo "all gc smoke checks passed"
