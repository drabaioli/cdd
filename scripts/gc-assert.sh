#!/usr/bin/env bash
# Smoke for cdd-worktree-gc: it reaps a MERGED task's artifacts (local handoff +
# state and the remote refs/cdd/<branch>) but never a scoped-but-unstarted one.
#
# Like ref-sync-assert.sh this stands in a local `git init --bare` for origin and
# a clone with its own $HOME. PR state is the reap predicate, so `gh` is stubbed on
# PATH: `gh pr list --head feat_merged ...` reports MERGED, everything else reports
# no PR. It asserts:
#   - dry-run: the merged branch is listed as "would remove", the scoped one kept,
#     and NOTHING is actually deleted
#   - --force: the merged branch's local files + remote ref are gone, while the
#     scoped branch's files + ref are untouched
#   - the per-repo marker (repo.json), written as a side effect of `cdd-state seed`,
#     survives the reap — it is what keeps the repo locatable once every task is gone
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

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the ref push under test lives behind cdd-state's jq guard"
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

MERGED="feat_merged"   # has a MERGED PR (per the gh stub) -> reap
SCOPED="feat_scoped"   # no PR yet -> keep

# Stub gh: `auth status` succeeds; `pr list --head feat_merged` reports MERGED, any
# other head reports nothing (empty -> "no PR yet"). Mirrors the --jq shape gc uses.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  pr)
    branch=""
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--head" ]] && { branch="$2"; break; }
      shift
    done
    [[ "$branch" == "feat_merged" ]] && echo "MERGED"
    exit 0 ;;
esac
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
  run_state seed "$b" >/dev/null 2>&1 || fail "cdd-state seed failed for $b"
  git -C "$WORK/machine" ls-remote origin "refs/cdd/$b" | grep -q "refs/cdd/$b" \
    || fail "seed did not push refs/cdd/$b"
done
pass "seeded two tasks (handoff + state + refs/cdd/*) on the machine"

# The per-repo marker is a side effect of every seed, and records the MAIN worktree.
[[ -f "$DIR/repo.json" ]] || fail "seed did not write the per-repo marker $DIR/repo.json"
marker_path="$(jq -r '.path' "$DIR/repo.json")"
[[ "$marker_path" == "$WORK/machine" ]] \
  || fail "repo.json .path = '$marker_path', expected '$WORK/machine'"
pass "seed wrote the per-repo marker pointing at the main worktree"

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

# 1. Dry-run: merged -> "would remove", scoped -> "keep", and nothing deleted.
out="$(run_gc 2>&1)" || fail "gc dry-run exited non-zero"
grep -q "reap  $MERGED (MERGED): would remove" <<<"$out" \
  || fail "dry-run did not mark the merged task for reaping. Output:\n$out"
grep -q "keep  $SCOPED" <<<"$out" \
  || fail "dry-run did not keep the scoped task. Output:\n$out"
[[ -f "$DIR/$MERGED.md" && -f "$DIR/$MERGED.state.json" ]] \
  || fail "dry-run must not delete local files"
git -C "$WORK/machine" ls-remote origin "refs/cdd/$MERGED" | grep -q "refs/cdd/$MERGED" \
  || fail "dry-run must not delete the remote ref"
pass "dry-run reports the merged task, keeps the scoped one, deletes nothing"

# 2. --force: merged artifacts gone; scoped artifacts untouched.
out="$(run_gc --force 2>&1)" || fail "gc --force exited non-zero"
[[ ! -f "$DIR/$MERGED.md" && ! -f "$DIR/$MERGED.state.json" ]] \
  || fail "--force did not remove the merged task's local files"
git -C "$WORK/machine" ls-remote origin "refs/cdd/$MERGED" | grep -q "refs/cdd/$MERGED" \
  && fail "--force did not delete the merged task's remote ref"
[[ -f "$DIR/$SCOPED.md" && -f "$DIR/$SCOPED.state.json" ]] \
  || fail "--force must not touch the scoped task's local files"
git -C "$WORK/machine" ls-remote origin "refs/cdd/$SCOPED" | grep -q "refs/cdd/$SCOPED" \
  || fail "--force must not delete the scoped task's remote ref"
pass "--force reaps the merged task (local + ref), leaves the scoped task intact"

# 3. The per-repo marker is not task-scoped and must survive the reap: it is what keeps
# the repo locatable once every task is merged and its artifacts are gone. Safe by
# construction (GC's candidates glob *.md / *.state.json / refs/cdd/*), pinned here.
[[ -f "$DIR/repo.json" ]] || fail "--force reaped the per-repo marker $DIR/repo.json"
pass "--force leaves the per-repo marker in place"

echo "all gc smoke checks passed"
