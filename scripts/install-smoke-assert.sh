#!/usr/bin/env bash
# Smoke-test `tools/cdd-worktree.sh install` against a throwaway HOME.
#
# The installer mutates the real $HOME (rc files, ~/.cdd/), so it is never run by
# the other smoke paths. This test points it at a temp HOME instead and asserts:
#   - the helper is copied to ~/.cdd/tools/cdd-worktree.sh and is executable
#   - the handoff root ~/.cdd/handoffs/ is created
#   - ~/.bashrc is created (neither rc existed) and carries the marker-guarded
#     source line exactly once
#   - PATH shims for every cdd-worktree* command are written to ~/.local/bin,
#     are executable, and resolve+dispatch under a non-interactive shell (the
#     case that motivates the shims: Claude Code's Bash tool never sources ~/.bashrc)
#   - handoffs under the legacy ~/.claude-handoffs/ are migrated, originals kept
#   - a second run is idempotent (no duplicate marker block, no second copy)
#   - cdd-worktree and cdd-worktree-resume reject an option-shaped branch name (exit 2,
#     nothing created) and treat --help as usage (exit 0) — the guard whose absence had
#     `cdd-worktree --help` cutting a branch and a worktree literally called "--help"
#
# It also runs `tools/cdd-state.sh install` and asserts the same shim contract
# for the `cdd-state` command, since that helper self-installs identically, plus three
# properties of `cdd-state seed`: the recorded handoff session, the synced task ref
# refs/cdd/<branch>, and the per-repo marker repo.json — whose `path` must be the MAIN
# worktree, not the worktree the writer ran in.
#
# The gate is offline and free of side effects: the seed's ref sync pushes to `origin`, so
# the push is redirected at a throwaway bare repo. See the comment at that point for why.
#
# Usage: scripts/install-smoke-assert.sh
# Takes no arguments; it provisions and tears down its own temp HOME.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/tools/cdd-worktree.sh"
STATE_HELPER="$REPO_ROOT/tools/cdd-state.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# Disable a managed rc block by prefixing every line from BEGIN to END with "# ",
# simulating a user (or tool) commenting it out — the state `install` must detect
# and self-repair. Matches markers by substring so it works on active blocks.
comment_block() {
  local file="$1" begin="$2" end="$3" tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v b="$begin" -v e="$end" '
    index($0, b) { skip = 1 }
    skip { print "# " $0; if (index($0, e)) skip = 0; next }
    { print }
  ' "$file" > "$tmp" && mv -f "$tmp" "$file"
}

[[ -x "$HELPER" ]] || fail "helper not found/executable: $HELPER"
[[ -x "$STATE_HELPER" ]] || fail "state helper not found/executable: $STATE_HELPER"

# A truncated helper passes the -x test above (truncation preserves the mode bit) and then
# installs a 0-byte file, which surfaces a dozen lines down as the misleading "helper not
# copied". Parse both first, so a torn file -- a concurrent write, an interrupted editor --
# says what it is instead of sending the reader after a copy bug that isn't there.
bash -n "$HELPER" || fail "helper does not parse: $HELPER (truncated by a concurrent write?)"
bash -n "$STATE_HELPER" || fail "state helper does not parse: $STATE_HELPER (truncated?)"

FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT

# Seed a legacy handoff to exercise the migration branch.
mkdir -p "$FAKE_HOME/.claude-handoffs/someproj"
echo "# old handoff" > "$FAKE_HOME/.claude-handoffs/someproj/feature_x.md"

# First install. Run directly (never sourced) with the temp HOME.
HOME="$FAKE_HOME" "$HELPER" install >/dev/null

DEST="$FAKE_HOME/.cdd/tools/cdd-worktree.sh"
[[ -f "$DEST" && -x "$DEST" ]] || fail "helper not copied (or not executable) to $DEST"
pass "helper copied to ~/.cdd/tools/ and executable"

[[ -d "$FAKE_HOME/.cdd/handoffs" ]] || fail "handoff root ~/.cdd/handoffs not created"
pass "handoff root created"

[[ -f "$FAKE_HOME/.bashrc" ]] || fail ".bashrc not created when no rc existed"
markers=$(grep -cF "CDD worktree helper (managed by cdd-worktree.sh install) BEGIN" "$FAKE_HOME/.bashrc")
[[ "$markers" -eq 1 ]] || fail "expected exactly one marker block in .bashrc, found $markers"
# The installed line is a literal `source "$HOME/..."`; match it verbatim.
# shellcheck disable=SC2016
grep -qF 'source "$HOME/.cdd/tools/cdd-worktree.sh"' "$FAKE_HOME/.bashrc" \
  || fail ".bashrc missing the source line"
pass ".bashrc wired with a single marker-guarded source line"

# PATH shims: one per worktree command, executable. These are what make the
# commands resolve in non-interactive shells (Claude Code's Bash tool), where
# the rc `source` line above never runs.
for cmd in cdd-worktree cdd-worktree-resume cdd-worktree-list cdd-worktree-done; do
  shim="$FAKE_HOME/.local/bin/$cmd"
  [[ -f "$shim" && -x "$shim" ]] || fail "worktree shim missing/not executable: $shim"
done
pass "cdd-worktree* PATH shims written to ~/.local/bin and executable"

# The shim must resolve and dispatch from a non-interactive shell with only ~/.local/bin on
# PATH and no rc sourced — the case it exists for. `cdd-worktree-list` is side-effect-free
# and changes no cwd, so it keeps a real source+dispatch shim; use it as the probe.
#
# `--norc --noprofile </dev/null` is load-bearing. `env -i` clears the environment but bash
# still reads `$HOME/.bashrc` for a *non-interactive* shell whenever it decides stdin is a
# network connection (its remote-shell heuristic). `$FAKE_HOME/.bashrc` is the file `install`
# just wrote, which sources the helper — so every cdd-* name becomes a shell function and the
# probes below stop testing shims. Redirecting stdin defeats the heuristic; --norc makes it
# unconditional. Both, so neither is load-bearing alone.
NOSHELLRC=(bash --norc --noprofile)

# Pin the no-rc property itself: drop --norc or the stdin redirect and every probe below goes
# green again, passing for the reason it exists to rule out. In the probe shell a cdd-* name
# must resolve to a FILE (the shim), never to a function.
rc_leak="$(env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin" \
  "${NOSHELLRC[@]}" -c 'type -t cdd-worktree-list' </dev/null 2>&1)"
[[ "$rc_leak" == "file" ]] \
  || fail "probe shell sourced a shell rc: cdd-worktree-list is a '$rc_leak', not the PATH shim"
pass "probe shell sources no rc (shim names resolve to files, not functions)"

env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin" \
  "${NOSHELLRC[@]}" -c 'command -v cdd-worktree-list >/dev/null && cdd-worktree-list >/dev/null 2>&1' \
  </dev/null \
  || fail "cdd-worktree-list shim did not resolve/dispatch in a non-interactive shell"
pass "cdd-worktree-list shim resolves and dispatches non-interactively"

# The cwd-changing commands (cdd-worktree, cdd-worktree-resume, cdd-worktree-done) must FAIL
# LOUDLY via the shim rather than dispatch into a subshell whose `cd` can't reach the caller.
# Probe cdd-worktree-done: its shim exits before sourcing anything, so no git state is needed.
# Same no-rc requirement as above, or the probe reaches the real function instead.
done_out="$(env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin" \
  "${NOSHELLRC[@]}" -c 'cdd-worktree-done' </dev/null 2>&1)" && \
  fail "cdd-worktree-done shim succeeded silently (should refuse when unsourced)"
grep -qF "must run as a sourced shell function" <<<"$done_out" \
  || fail "cdd-worktree-done shim did not print the sourced-function guidance; got: $done_out"
pass "cwd-changing shim (cdd-worktree-done) fails loudly instead of silently no-op'ing the cd"

# The worktree commands reject option-shaped arguments too, not just `cdd-state seed`
# (asserted further down): without the guard, `cdd-worktree --help` took "--help" as the
# branch and cut a branch and sibling worktree called that. Probed as sourced FUNCTIONS, since
# the cwd-changing shims refuse before sourcing anything and would never reach the guard.
#
# Assert the pair (exit 2, the guard's own message): both commands have later refusals of
# their own that also exit non-zero, so status alone would pass for the wrong reason. The
# throwaway repo plus a handoff named for the bad argument makes "no branch, no sibling
# directory" bite too — without the guard, cdd-worktree reaches branch creation.
OPT_ROOT="$FAKE_HOME/optguard"
mkdir -p "$OPT_ROOT/repo"
git init -q "$OPT_ROOT/repo"
mkdir -p "$FAKE_HOME/.cdd/handoffs/repo"
: > "$FAKE_HOME/.cdd/handoffs/repo/--bogus.md"

# Runs the sourced $cmd with $arg in the throwaway repo and echoes its output plus a
# trailing "STATUS:<exit>". The rejected exit code travels in that line rather than in the
# function's own status, so nothing here trips `set -e`: `bash -c` ends on the echo.
probe_opt_guard() {  # probe_opt_guard <cmd> <arg>
  local cmd="$1" arg="$2"
  ( cd "$OPT_ROOT/repo" || exit 1
    # shellcheck disable=SC2016  # $1 is a `bash -c` positional parameter, not ours
    HOME="$FAKE_HOME" "${NOSHELLRC[@]}" -c \
      'source "$1"; '"$cmd"' '"$arg"'; echo "STATUS:$?"' _ "$HELPER" </dev/null 2>&1 )
}

for cmd in cdd-worktree cdd-worktree-resume; do
  opt_out="$(probe_opt_guard "$cmd" --bogus)"
  grep -qF "$cmd: '--bogus' looks like an option, not a branch name." <<<"$opt_out" \
    || fail "$cmd '--bogus' did not print the option guard; got: $opt_out"
  grep -qF "STATUS:2" <<<"$opt_out" \
    || fail "$cmd '--bogus' did not exit 2; got: $opt_out"

  # `--help` is the same shape but a legitimate request: usage, exit 0, still no branch.
  help_out="$(probe_opt_guard "$cmd" --help)"
  grep -qF "usage: $cmd" <<<"$help_out" \
    || fail "$cmd --help did not print usage; got: $help_out"
  grep -qF "STATUS:0" <<<"$help_out" \
    || fail "$cmd --help did not exit 0; got: $help_out"
done

for bad_arg in --bogus --help; do
  git -C "$OPT_ROOT/repo" rev-parse --verify -q "refs/heads/$bad_arg" >/dev/null \
    && fail "an option-shaped argument ('$bad_arg') was cut as a branch"
  [[ ! -e "$OPT_ROOT/repo$bad_arg" && ! -e "$OPT_ROOT/$bad_arg" ]] \
    || fail "an option-shaped argument ('$bad_arg') created a worktree directory"
done
pass "cdd-worktree/-resume reject an option-shaped branch (exit 2) and honour --help (exit 0)"

[[ -f "$FAKE_HOME/.cdd/handoffs/someproj/feature_x.md" ]] \
  || fail "legacy handoff not migrated to ~/.cdd/handoffs/"
[[ -f "$FAKE_HOME/.claude-handoffs/someproj/feature_x.md" ]] \
  || fail "legacy handoff original was removed (should be left in place)"
pass "legacy handoff migrated, original left in place"

# Second install must be idempotent: still one marker block, no error.
HOME="$FAKE_HOME" "$HELPER" install >/dev/null
markers=$(grep -cF "CDD worktree helper (managed by cdd-worktree.sh install) BEGIN" "$FAKE_HOME/.bashrc")
[[ "$markers" -eq 1 ]] || fail "second install duplicated the marker block (found $markers)"
pass "second install is idempotent (no duplicate marker block)"

# Self-repair: a managed block that is present but DISABLED (commented out) must be
# rewritten as an active source line on re-install — the case a bare marker grep
# could not see, which left a user whose block got commented unable to re-enable it.
WT_BEGIN="# --- CDD worktree helper (managed by cdd-worktree.sh install) BEGIN ---"
WT_END="# --- CDD worktree helper END ---"
# shellcheck disable=SC2016
WT_ACTIVE='^[[:space:]]*\[\[ -f "\$HOME/\.cdd/tools/cdd-worktree\.sh" \]\] && source'
comment_block "$FAKE_HOME/.bashrc" "$WT_BEGIN" "$WT_END"
grep -qE "$WT_ACTIVE" "$FAKE_HOME/.bashrc" \
  && fail "precondition: block still active after comment_block"
HOME="$FAKE_HOME" "$HELPER" install >/dev/null
grep -qE "$WT_ACTIVE" "$FAKE_HOME/.bashrc" \
  || fail "install did not self-repair a disabled worktree block to an active source line"
markers=$(grep -cF "CDD worktree helper (managed by cdd-worktree.sh install) BEGIN" "$FAKE_HOME/.bashrc")
[[ "$markers" -eq 1 ]] || fail "self-repair left more than one worktree marker block (found $markers)"
pass "install self-repairs a disabled worktree block (active again, still single)"

# The task-state helper self-installs identically; assert its shim contract too.
HOME="$FAKE_HOME" "$STATE_HELPER" install >/dev/null
STATE_SHIM="$FAKE_HOME/.local/bin/cdd-state"
[[ -f "$STATE_SHIM" && -x "$STATE_SHIM" ]] || fail "cdd-state shim missing/not executable: $STATE_SHIM"
# Resolution under a non-interactive, PATH-only shell is the property that keeps
# `cdd-state set …` from silently no-oping when Claude Code's Bash tool runs it.
resolved=$(env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin" \
  "${NOSHELLRC[@]}" -c 'command -v cdd-state' </dev/null) \
  || fail "cdd-state shim did not resolve in a non-interactive shell"
[[ "$resolved" == "$STATE_SHIM" ]] || fail "cdd-state resolved to '$resolved', expected the shim $STATE_SHIM"
pass "cdd-state PATH shim written and resolves non-interactively"

# The cdd-state installer shares the self-repair guard; assert it too.
ST_BEGIN="# --- CDD state helper (managed by cdd-state.sh install) BEGIN ---"
ST_END="# --- CDD state helper END ---"
# shellcheck disable=SC2016
ST_ACTIVE='^[[:space:]]*\[\[ -f "\$HOME/\.cdd/tools/cdd-state\.sh" \]\] && source'
comment_block "$FAKE_HOME/.bashrc" "$ST_BEGIN" "$ST_END"
grep -qE "$ST_ACTIVE" "$FAKE_HOME/.bashrc" \
  && fail "precondition: state block still active after comment_block"
HOME="$FAKE_HOME" "$STATE_HELPER" install >/dev/null
grep -qE "$ST_ACTIVE" "$FAKE_HOME/.bashrc" \
  || fail "install did not self-repair a disabled state block to an active source line"
markers=$(grep -cF "CDD state helper (managed by cdd-state.sh install) BEGIN" "$FAKE_HOME/.bashrc")
[[ "$markers" -eq 1 ]] || fail "self-repair left more than one state marker block (found $markers)"
pass "install self-repairs a disabled state block (active again, still single)"

# `cdd-state seed` must record the handoff session (issue #51): with a session id
# in the environment, the seeded record's first `sessions[]` entry is the current
# session at stage `scoped`, carrying `dir` = the worktree root. Run it from this
# repo (a real git repo) against FAKE_HOME so the record lands under the temp tree.
# Guarded on jq, like the helper itself.
if command -v jq >/dev/null 2>&1; then
  SEED_BRANCH="issue51_seed_probe"
  # The record path uses the repo name derived from git's common-dir (the main
  # worktree), not this checkout's basename — mirror the helper's derivation.
  REPO_NAME="$(cd "$REPO_ROOT" && basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
  SEED_FILE="$FAKE_HOME/.cdd/handoffs/$REPO_NAME/$SEED_BRANCH.state.json"
  EXPECT_DIR="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel)"

  # `cdd-state seed` pushes refs/cdd/<branch> to `origin` — the repo's REAL remote, so this
  # gate used to make live SSH round-trips and force-publish a test fixture to GitHub on every
  # run. Point it at a throwaway bare repo instead: offline, deterministic, no side effects.
  # Overriding `remote.origin.pushurl` (not the fetch URL) is the narrowest lever — the
  # helper's own `git push --force origin ...` is untouched, so the real path still runs.
  # GIT_CONFIG_* outranks the runner's GIT_CONFIG_GLOBAL and ci.sh sets no GIT_CONFIG_COUNT.
  FAKE_ORIGIN="$FAKE_HOME/origin.git"
  git init -q --bare "$FAKE_ORIGIN"
  PUSH_TO_FAKE=(
    GIT_CONFIG_COUNT=1
    GIT_CONFIG_KEY_0=remote.origin.pushurl
    GIT_CONFIG_VALUE_0="$FAKE_ORIGIN"
  )
  # The helper is dual-mode: executed directly it only installs, so source it and
  # call the function (the same path the PATH shim takes) to reach `seed`.
  # SC2016: the single quotes are deliberate -- $1/$2 are `bash -c` positional parameters,
  # bound from the trailing arguments, not variables to expand here.
  # shellcheck disable=SC2016
  ( cd "$REPO_ROOT" \
    && env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID=seed-probe-123 "${PUSH_TO_FAKE[@]}" \
       bash -c 'source "$1"; cdd-state seed "$2"' _ "$STATE_HELPER" "$SEED_BRANCH" >/dev/null )
  [[ -f "$SEED_FILE" ]] || fail "seed did not write $SEED_FILE"
  got="$(jq -r '.sessions[0] | "\(.id)|\(.stage)|\(.dir)"' "$SEED_FILE")"
  [[ "$got" == "seed-probe-123|scoped|$EXPECT_DIR" ]] \
    || fail "seed session entry = '$got', expected 'seed-probe-123|scoped|$EXPECT_DIR'"
  pass "cdd-state seed records the handoff session {id, stage: scoped, dir}"

  # The push is now observable, so assert it instead of leaving it an unchecked side effect.
  git -C "$FAKE_ORIGIN" rev-parse --verify -q "refs/cdd/$SEED_BRANCH" >/dev/null \
    || fail "seed did not sync refs/cdd/$SEED_BRANCH to origin"
  pass "cdd-state seed syncs the task ref to origin (a throwaway one: no network, no side effects)"

  # Without a session id (older Claude Code), seed keeps sessions empty — no guessing.
  # shellcheck disable=SC2016  # as above: `bash -c` positional parameters
  ( cd "$REPO_ROOT" \
    && env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID='' "${PUSH_TO_FAKE[@]}" \
       bash -c 'source "$1"; cdd-state seed "$2"' _ "$STATE_HELPER" "$SEED_BRANCH" >/dev/null )
  count="$(jq -r '.sessions | length' "$SEED_FILE")"
  [[ "$count" -eq 0 ]] || fail "seed with no session id left $count session(s), expected 0"
  pass "cdd-state seed omits the session entry when no session id is set"

  # An option-shaped branch is rejected before anything is written or pushed. `cdd-state
  # seed --help` used to take "--help" as the branch, write --help.state.json, and
  # force-push refs/cdd/--help to the REAL origin -- which is how one appeared on the
  # shared repo. Assert both halves: no record, and no ref in the throwaway origin.
  for bad_arg in --help --bogus; do
    # `|| true`: a rejected argument exits non-zero by design, and this script runs under
    # `set -e`. What is asserted is the absence of effects, not the exit status.
    # shellcheck disable=SC2016  # $1/$2 are `bash -c` positional parameters
    ( cd "$REPO_ROOT" \
      && env HOME="$FAKE_HOME" "${PUSH_TO_FAKE[@]}" \
         "${NOSHELLRC[@]}" -c 'source "$1"; cdd-state seed "$2"' _ "$STATE_HELPER" "$bad_arg" \
         </dev/null >/dev/null 2>&1 ) || true
    [[ ! -f "$FAKE_HOME/.cdd/handoffs/$REPO_NAME/$bad_arg.state.json" ]] \
      || fail "cdd-state seed '$bad_arg' wrote a state record for an option-shaped branch"
    if git -C "$FAKE_ORIGIN" rev-parse --verify -q "refs/cdd/$bad_arg" >/dev/null; then
      fail "cdd-state seed '$bad_arg' pushed refs/cdd/$bad_arg"
    fi
  done
  pass "cdd-state seed rejects an option-shaped branch without writing or pushing"

  # The per-repo marker (issue #58) records the MAIN worktree, not the worktree the
  # writer ran in. This assertion only bites when the two differ — i.e. whenever the
  # check runs from a feature worktree, which is the case that regresses if someone
  # swaps the derivation for `git rev-parse --show-toplevel`.
  MARKER="$FAKE_HOME/.cdd/handoffs/$REPO_NAME/repo.json"
  MAIN_WT="$(cd "$REPO_ROOT" && dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  [[ -f "$MARKER" ]] || fail "seed did not write the per-repo marker $MARKER"
  got="$(jq -r '"\(.schema_version)|\(.name)|\(.path)"' "$MARKER")"
  [[ "$got" == "1|$REPO_NAME|$MAIN_WT" ]] \
    || fail "repo.json = '$got', expected '1|$REPO_NAME|$MAIN_WT'"
  if [[ "$MAIN_WT" != "$EXPECT_DIR" ]]; then
    pass "cdd-state seed writes repo.json with the MAIN worktree ($MAIN_WT), not this worktree ($EXPECT_DIR)"
  else
    pass "cdd-state seed writes repo.json {schema_version, name, path} (run from the main worktree)"
  fi
else
  echo "skip: jq not found; seed assertions skipped (advisory)"
fi

echo "all install smoke checks passed"
