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
# `cdd-worktree-list` is side-effect-free, so use it as the probe.
env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin" \
  bash -c 'command -v cdd-worktree-list >/dev/null && cdd-worktree-list >/dev/null 2>&1' \
  || fail "cdd-worktree-list shim did not resolve/dispatch in a non-interactive shell"
pass "cdd-worktree shim resolves and dispatches non-interactively"

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

echo "all install smoke checks passed"
