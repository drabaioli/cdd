#!/usr/bin/env bash
# Smoke for keeping the installed CDD toolchain current (ADR 0014), offline.
#
# Sync hook (install from a CDD checkout writes post-merge + post-rewrite into it):
#   1. install from a checkout writes both hooks, executable, carrying the marker; from a
#      copy of tools/ outside any repo, or inside a repo that is not its checkout, none
#   2. a pull on the default branch that changes a helper reinstalls it: one `cdd:` line,
#      the pull still exits 0
#   3. a pull that changes nothing under tools/ prints nothing and touches no installed file
#   4. `git pull --rebase` over a local commit (the post-rewrite path) syncs too; a
#      `commit --amend` (post-rewrite too, but no pull) never installs
#   5. a pull into a linked worktree on a feature branch (the hooks dir is shared) changes
#      nothing — and, with that branch made the default, the same pull does sync, so the
#      silence is the branch check rather than a hook that never ran there
#   6. a foreign hook is left byte-identical (with a note); under core.hooksPath no hook
#      is written (with a note)
#   7. an adapter-only change on the default branch syncs the adapter library
# Self-reload (a shell that sourced the helpers before a reinstall):
#   8. a changed file is re-sourced on the next public call, which runs the new
#      definition; an unchanged one is not re-sourced — for cdd-worktree* and cdd-state
# Update (`cdd-worktree.sh update`, upstream stubbed with a local file:// repo):
#   9. behind -> "Updated", installed files now upstream's; again -> "up to date";
#      unreachable -> one line, exit 1, nothing changed. Run from the installed copy it
#      overwrites, so it also pins that bash never reads past the dispatch afterwards.
# cdd-state's loud failures:
#  10. an unknown verb and an invalid stage still exit 2, and name the update command
#
# Usage: scripts/toolchain-sync-assert.sh   (provisions and tears down its own temp tree)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# jq is required: cdd-state answers an unknown verb or stage only past its jq guard
# (case 10). A missing tool is a failure, never a skip (scripts/ci.sh).
command -v jq >/dev/null 2>&1 || fail "jq is required and not installed"

# Physical path: git hands hooks the physical top level.
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
# Everything below, hooks included, installs into this HOME.
export HOME="$WORK/home"
mkdir -p "$HOME"
unset CDD_UPSTREAM_URL

INST="$HOME/.cdd/tools"
UPSTREAM="$WORK/upstream.git"
SEED="$WORK/seed"          # where "upstream" commits are made
CHECKOUT="$WORK/cdd"       # the machine's CDD checkout

# --- fixture: an upstream carrying this tree's tools/, and a checkout of it -----
git init -q --bare "$UPSTREAM"
# A blobless clone (update's fetch) asks the server for a filter.
git -C "$UPSTREAM" config uploadpack.allowFilter true
git clone -q "$UPSTREAM" "$SEED" 2>/dev/null
cp -R "$REPO_ROOT/tools" "$SEED/tools"
echo "# cdd" > "$SEED/README.md"
git -C "$SEED" add -A
git -C "$SEED" commit -q -m seed
git -C "$SEED" push -q -u origin main
git clone -q "$UPSTREAM" "$CHECKOUT"

N=0
# upstream_change <path>...: append a line to each file in the seed, commit, push.
upstream_change() {
  N=$((N + 1))
  local f
  for f in "$@"; do printf '# upstream change %s\n' "$N" >> "$SEED/$f"; done
  git -C "$SEED" add -- "$@"
  git -C "$SEED" commit -q -m "change $N"
  git -C "$SEED" push -q origin main
}

# pull <dir> <pull args>...: output to $WORK/pull.out; sets RC.
pull() {
  local dir="$1"; shift
  RC=0
  git -C "$dir" pull -q "$@" >"$WORK/pull.out" 2>&1 || RC=$?
}
cdd_lines() { grep -c '^cdd: ' "$WORK/pull.out" || true; }

# The installed tree, as one comparable string.
snapshot() {
  ( cd "$INST" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done )
}

# --- 1. install writes the hooks only into a checkout ---------------------------
bash "$CHECKOUT/tools/cdd-worktree.sh" install >"$WORK/install.out" 2>&1 \
  || fail "install from the checkout failed: $(cat "$WORK/install.out")"
bash "$CHECKOUT/tools/cdd-state.sh" install >/dev/null 2>&1 || fail "cdd-state install failed"
HOOKS="$CHECKOUT/.git/hooks"
for h in post-merge post-rewrite; do
  [[ -f "$HOOKS/$h" && -x "$HOOKS/$h" ]] || fail "install did not write an executable $h hook"
  grep -qF "# Managed by cdd-worktree.sh install (CDD toolchain sync)" "$HOOKS/$h" \
    || fail "$h hook carries no marker line"
done
grep -qF "Installed sync hooks" "$WORK/install.out" || fail "install did not say it wrote the hooks"

mkdir -p "$WORK/plain" "$WORK/other"
cp -R "$REPO_ROOT/tools" "$WORK/plain/tools"
git init -q "$WORK/other"
mkdir -p "$WORK/other/vendor"
cp -R "$REPO_ROOT/tools" "$WORK/other/vendor/tools"
for src in "$WORK/plain/tools" "$WORK/other/vendor/tools"; do
  out="$(HOME="$WORK/home-x" bash "$src/cdd-worktree.sh" install 2>&1)" \
    || fail "install from $src failed: $out"
  grep -qF "sync hook" <<<"$out" && fail "install from a non-checkout copy ($src) touched hooks: $out"
done
[[ ! -e "$WORK/other/.git/hooks/post-merge" && ! -e "$WORK/other/.git/hooks/post-rewrite" ]] \
  || fail "install from a copy of tools/ inside an unrelated repo hooked that repo"
pass "install from a checkout writes the sync hooks; from a copy of tools/ it writes none"

# --- 2. a helper change on the default branch reinstalls -------------------------
upstream_change tools/cdd-state.sh
pull "$CHECKOUT" --no-rebase
(( RC == 0 )) || fail "pull exited $RC: $(cat "$WORK/pull.out")"
cmp -s "$INST/cdd-state.sh" "$CHECKOUT/tools/cdd-state.sh" \
  || fail "pull of a cdd-state.sh change did not reinstall it. Output: $(cat "$WORK/pull.out")"
[[ "$(cdd_lines)" -eq 1 ]] || fail "expected exactly one cdd: line. Output: $(cat "$WORK/pull.out")"
pass "a pull on the default branch that changes a helper reinstalls it, in one line"

# --- 3. a pull that leaves tools/ alone is silent and changes nothing ------------
before="$(snapshot)"
upstream_change README.md
pull "$CHECKOUT" --no-rebase
(( RC == 0 )) || fail "pull exited $RC: $(cat "$WORK/pull.out")"
[[ "$(cdd_lines)" -eq 0 ]] || fail "a README-only pull printed a cdd: line: $(cat "$WORK/pull.out")"
[[ "$(snapshot)" == "$before" ]] || fail "a README-only pull changed the install"
pass "a pull that changes no helper prints nothing and changes nothing"

# --- 4. pull --rebase over a local commit (post-rewrite) --------------------------
echo local > "$CHECKOUT/local.txt"
git -C "$CHECKOUT" add local.txt
git -C "$CHECKOUT" commit -q -m local
upstream_change tools/cdd-worktree.sh
pull "$CHECKOUT" --rebase
(( RC == 0 )) || fail "pull --rebase exited $RC: $(cat "$WORK/pull.out")"
cmp -s "$INST/cdd-worktree.sh" "$CHECKOUT/tools/cdd-worktree.sh" \
  || fail "pull --rebase did not reinstall cdd-worktree.sh. Output: $(cat "$WORK/pull.out")"
[[ "$(cdd_lines)" -eq 1 ]] || fail "expected exactly one cdd: line. Output: $(cat "$WORK/pull.out")"
pass "pull --rebase over a local commit syncs too (post-rewrite)"

# post-rewrite also fires on `commit --amend`, which is no pull: a helper edit amended
# into main must not install. Then drop the amend again (reset runs no hook).
before="$(snapshot)"
echo "# local edit" >> "$CHECKOUT/tools/cdd-state.sh"
out="$(git -C "$CHECKOUT" commit -q -a --amend --no-edit 2>&1)" || fail "amend failed: $out"
[[ "$(snapshot)" == "$before" ]] || fail "commit --amend on the default branch changed the install"
grep -q '^cdd: ' <<<"$out" && fail "commit --amend printed a cdd: line: $out"
git -C "$CHECKOUT" reset -q --hard 'HEAD@{1}'
pass "commit --amend (post-rewrite, no pull) never installs"

# --- 5a. a feature worktree's merge never installs ------------------------------
FEAT="$WORK/cdd-feat"
git -C "$CHECKOUT" worktree add -q -b feat "$FEAT" main 2>/dev/null
echo feat > "$FEAT/feat.txt"
git -C "$FEAT" add feat.txt
git -C "$FEAT" commit -q -m feat
before="$(snapshot)"
upstream_change tools/adapters/tracker/github.sh
pull "$FEAT" --no-rebase --no-edit origin main
(( RC == 0 )) || fail "feature pull exited $RC: $(cat "$WORK/pull.out")"
cmp -s "$FEAT/tools/adapters/tracker/github.sh" "$SEED/tools/adapters/tracker/github.sh" \
  || fail "precondition: the feature worktree did not merge the adapter change"
[[ "$(cdd_lines)" -eq 0 ]] || fail "a feature-branch merge printed a cdd: line: $(cat "$WORK/pull.out")"
[[ "$(snapshot)" == "$before" ]] || fail "a feature-branch merge changed the install"
pass "a merge into a feature worktree (shared hooks dir) changes nothing"

# --- 7. an adapter-only change on the default branch syncs the library -----------
pull "$CHECKOUT" --no-rebase --no-edit
(( RC == 0 )) || fail "pull exited $RC: $(cat "$WORK/pull.out")"
cmp -s "$INST/adapters/tracker/github.sh" "$CHECKOUT/tools/adapters/tracker/github.sh" \
  || fail "an adapter-only pull did not sync the library. Output: $(cat "$WORK/pull.out")"
[[ -x "$INST/adapters/tracker/github.sh" ]] || fail "synced adapter is not executable"
[[ "$(cdd_lines)" -eq 1 ]] || fail "expected exactly one cdd: line. Output: $(cat "$WORK/pull.out")"
pass "an adapter-only change on the default branch syncs the adapter library"

# --- 5b. the same feature pull syncs once its branch is the default ---------------
# Makes 5a non-vacuous: the hook does run in a linked worktree (where git exports
# GIT_DIR to it), and only the branch check kept it quiet there.
git -C "$CHECKOUT" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/feat
upstream_change tools/adapters/tracker/github.sh
pull "$FEAT" --no-rebase --no-edit origin main
git -C "$CHECKOUT" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
(( RC == 0 )) || fail "feature pull exited $RC: $(cat "$WORK/pull.out")"
cmp -s "$INST/adapters/tracker/github.sh" "$FEAT/tools/adapters/tracker/github.sh" \
  || fail "the hook did not sync from a linked worktree on the default branch. Output: $(cat "$WORK/pull.out")"
[[ "$(cdd_lines)" -eq 1 ]] || fail "expected exactly one cdd: line. Output: $(cat "$WORK/pull.out")"
pass "the hook runs in a linked worktree too: only the branch check keeps 5a silent"

# --- 6. foreign hooks and core.hooksPath ------------------------------------------
git clone -q "$UPSTREAM" "$WORK/cdd2"
printf '#!/bin/sh\necho mine\n' > "$WORK/cdd2/.git/hooks/post-merge"
cp "$WORK/cdd2/.git/hooks/post-merge" "$WORK/foreign.orig"
out="$(HOME="$WORK/home-6" bash "$WORK/cdd2/tools/cdd-worktree.sh" install 2>&1)" \
  || fail "install beside a foreign hook failed: $out"
cmp -s "$WORK/cdd2/.git/hooks/post-merge" "$WORK/foreign.orig" \
  || fail "install modified a foreign post-merge hook"
grep -qF "is not CDD's" <<<"$out" || fail "no note about the foreign hook: $out"
grep -qF "# Managed by cdd-worktree.sh install" "$WORK/cdd2/.git/hooks/post-rewrite" \
  || fail "the free post-rewrite slot was not written beside a foreign post-merge"

git clone -q "$UPSTREAM" "$WORK/cdd3"
git -C "$WORK/cdd3" config core.hooksPath "$WORK/userhooks"
out="$(HOME="$WORK/home-6" bash "$WORK/cdd3/tools/cdd-worktree.sh" install 2>&1)" \
  || fail "install under core.hooksPath failed: $out"
for h in post-merge post-rewrite; do
  [[ ! -e "$WORK/cdd3/.git/hooks/$h" && ! -e "$WORK/userhooks/$h" ]] \
    || fail "install wrote a $h hook under core.hooksPath"
done
grep -qF "core.hooksPath" <<<"$out" || fail "no note about core.hooksPath: $out"
pass "a foreign hook is left byte-identical, and core.hooksPath gets no hook (each with a note)"

# --- 8. self-reload ---------------------------------------------------------------
RELOAD="$WORK/reload"
mkdir -p "$RELOAD" "$HOME/.cdd/handoffs/cdd"
: > "$HOME/.cdd/handoffs/cdd/probe.md"

# reload_probe <file> <helper fn> <stub body> <edit> <call>: source a fresh copy of the
# installed <file>, stub <helper fn> in the shell (a re-source restores the real one),
# apply <edit> to the copy ($1 inside it), then run <call>. Prints its output.
reload_probe() {
  local file="$1" fn="$2" stub="$3" edit="$4" call="$5"
  cp "$INST/$file" "$RELOAD/$file"
  # shellcheck disable=SC2016  # $1 expands in the probe shell
  ( cd "$CHECKOUT" && bash --norc --noprofile -c \
      'source "$1"; '"$fn"'() { '"$stub"'; }; '"$edit"'; '"$call" _ "$RELOAD/$file" </dev/null 2>&1 )
}

# shellcheck disable=SC2016  # the edits expand in the probe shell
{
  out="$(reload_probe cdd-worktree.sh cdd-worktree-no-adapter 'echo SHELL-STUB >&2' ':' cdd-worktree-list)"
  grep -qx SHELL-STUB <<<"$out" || fail "an unchanged helper was re-sourced (the stub is gone): $out"
  out="$(reload_probe cdd-worktree.sh cdd-worktree-no-adapter 'echo SHELL-STUB >&2' 'echo "# touched" >> "$1"' cdd-worktree-list)"
  grep -qF "SHELL-STUB" <<<"$out" && fail "a changed helper was not re-sourced: $out"
  grep -qF "code-host: no adapter installed" <<<"$out" || fail "the reloaded cdd-worktree-list did not run: $out"
  out="$(reload_probe cdd-worktree.sh cdd-worktree-no-adapter : 'echo "cdd-worktree-list() { echo SENTINEL-WT; }" >> "$1"' cdd-worktree-list)"
  [[ "$out" == "SENTINEL-WT" ]] || fail "cdd-worktree-list did not re-dispatch to the new definition, silently; got: $out"

  out="$(reload_probe cdd-state.sh cdd-state-stages 'echo SHELL-STUB' ':' 'cdd-state stages')"
  [[ "$out" == "SHELL-STUB" ]] || fail "an unchanged cdd-state was re-sourced: $out"
  out="$(reload_probe cdd-state.sh cdd-state-stages 'echo SHELL-STUB' 'echo "# touched" >> "$1"' 'cdd-state stages')"
  grep -qx plan_written <<<"$out" || fail "a changed cdd-state was not re-sourced: $out"
  out="$(reload_probe cdd-state.sh cdd-state-stages : 'echo "cdd-state() { echo SENTINEL-ST; }" >> "$1"' 'cdd-state stages')"
  [[ "$out" == "SENTINEL-ST" ]] || fail "cdd-state did not re-dispatch to the new definition, silently; got: $out"
}
pass "a changed helper is re-sourced on the next call and runs the new code; an unchanged one is not"

# --- 9. update against a stub upstream --------------------------------------------
# The appended line runs only if bash reads the installed script past its dispatch
# after update has overwritten it, so its absence pins the dispatch's explicit exit.
N=$((N + 1))
printf 'echo READ-PAST-DISPATCH\n' >> "$SEED/tools/cdd-worktree.sh"
printf '# upstream change %s\n' "$N" >> "$SEED/tools/cdd-state.sh"
git -C "$SEED" commit -q -am "change $N"
git -C "$SEED" push -q origin main

RC=0
out="$(CDD_UPSTREAM_URL="file://$UPSTREAM" bash "$INST/cdd-worktree.sh" update 2>&1)" || RC=$?
(( RC == 0 )) || fail "update exited $RC: $out"
grep -qF "Updated the CDD helpers from upstream main" <<<"$out" || fail "update did not say it updated: $out"
grep -qF READ-PAST-DISPATCH <<<"$out" && fail "bash read the overwritten script past its dispatch: $out"
cmp -s "$INST/cdd-worktree.sh" "$SEED/tools/cdd-worktree.sh" || fail "update did not install upstream's cdd-worktree.sh"
cmp -s "$INST/cdd-state.sh" "$SEED/tools/cdd-state.sh" || fail "update did not install upstream's cdd-state.sh"

RC=0
out="$(CDD_UPSTREAM_URL="file://$UPSTREAM" bash "$INST/cdd-worktree.sh" update 2>&1)" || RC=$?
(( RC == 0 )) || fail "update (current) exited $RC: $out"
[[ "$out" == "CDD helpers are up to date with upstream main." ]] || fail "update (current) said: $out"

before="$(snapshot)"
RC=0
out="$(CDD_UPSTREAM_URL="file://$WORK/no-such.git" bash "$INST/cdd-worktree.sh" update 2>&1)" || RC=$?
(( RC != 0 )) || fail "update from an unreachable upstream exited 0: $out"
if [[ "$(wc -l <<<"$out")" -ne 1 ]] || ! grep -qF "could not fetch" <<<"$out"; then
  fail "update from an unreachable upstream should print one line; got: $out"
fi
[[ "$(snapshot)" == "$before" ]] || fail "update from an unreachable upstream changed the install"
pass "update: behind -> updated, current -> up to date, unreachable -> one line and nothing changed"

# --- 10. cdd-state's loud failures name the update command -------------------------
state_fails() {  # state_fails <cdd-state arg>...
  local out
  # shellcheck disable=SC2016  # $1 expands in the probe shell
  out="$(cd "$CHECKOUT" && bash --norc --noprofile -c \
    'source "$1"; shift; cdd-state "$@"; echo "STATUS:$?"' _ "$REPO_ROOT/tools/cdd-state.sh" "$@" </dev/null 2>&1)"
  grep -qx "STATUS:2" <<<"$out" || fail "cdd-state $* did not exit 2: $out"
  grep -qF "cdd-worktree.sh update" <<<"$out" || fail "cdd-state $* did not name the update command: $out"
}
state_fails frobnicate
state_fails set no_such_stage
pass "cdd-state's unknown-verb and invalid-stage errors still exit 2 and name the update command"

echo "all toolchain sync checks passed"
