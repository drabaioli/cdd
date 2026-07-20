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
#
# It also runs `tools/cdd-state.sh install` and asserts the same shim contract
# for the `cdd-state` command, since that helper self-installs identically.
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

# The shim must actually resolve and dispatch from a non-interactive shell with
# only ~/.local/bin on PATH and no rc sourced — the exact case it exists for.
# `cdd-worktree-list` is side-effect-free AND changes no cwd, so it keeps a real
# source+dispatch shim; use it as the probe.
env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin" \
  bash -c 'command -v cdd-worktree-list >/dev/null && cdd-worktree-list >/dev/null 2>&1' \
  || fail "cdd-worktree-list shim did not resolve/dispatch in a non-interactive shell"
pass "cdd-worktree-list shim resolves and dispatches non-interactively"

# The cwd-changing commands (cdd-worktree, cdd-worktree-resume, cdd-worktree-done)
# must FAIL LOUDLY via the shim rather than dispatch into a subshell whose `cd`
# can't reach the caller — the regression that stranded the user in the removed
# worktree. Probe cdd-worktree-done (the regression subject): the shim exits
# before sourcing anything, so no git state is needed.
done_out="$(env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin" \
  bash -c 'cdd-worktree-done' 2>&1)" && \
  fail "cdd-worktree-done shim succeeded silently (should refuse when unsourced)"
grep -qF "must run as a sourced shell function" <<<"$done_out" \
  || fail "cdd-worktree-done shim did not print the sourced-function guidance; got: $done_out"
pass "cwd-changing shim (cdd-worktree-done) fails loudly instead of silently no-op'ing the cd"

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
  bash -c 'command -v cdd-state') \
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
  # The helper is dual-mode: executed directly it only installs, so source it and
  # call the function (the same path the PATH shim takes) to reach `seed`.
  ( cd "$REPO_ROOT" \
    && HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID=seed-probe-123 \
       bash -c 'source "$1"; cdd-state seed "$2"' _ "$STATE_HELPER" "$SEED_BRANCH" >/dev/null )
  [[ -f "$SEED_FILE" ]] || fail "seed did not write $SEED_FILE"
  got="$(jq -r '.sessions[0] | "\(.id)|\(.stage)|\(.dir)"' "$SEED_FILE")"
  [[ "$got" == "seed-probe-123|scoped|$EXPECT_DIR" ]] \
    || fail "seed session entry = '$got', expected 'seed-probe-123|scoped|$EXPECT_DIR'"
  pass "cdd-state seed records the handoff session {id, stage: scoped, dir}"

  # Without a session id (older Claude Code), seed keeps sessions empty — no guessing.
  ( cd "$REPO_ROOT" \
    && HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID='' \
       bash -c 'source "$1"; cdd-state seed "$2"' _ "$STATE_HELPER" "$SEED_BRANCH" >/dev/null )
  count="$(jq -r '.sessions | length' "$SEED_FILE")"
  [[ "$count" -eq 0 ]] || fail "seed with no session id left $count session(s), expected 0"
  pass "cdd-state seed omits the session entry when no session id is set"
else
  echo "skip: jq not found; seed assertions skipped (advisory)"
fi

echo "all install smoke checks passed"
