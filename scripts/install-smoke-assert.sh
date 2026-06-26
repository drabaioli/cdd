#!/usr/bin/env bash
# Smoke-test `tools/cdd-worktree.sh install` against a throwaway HOME.
#
# The installer mutates the real $HOME (rc files, ~/.cdd/), so it is never run by
# the other smoke paths. This test points it at a temp HOME instead and asserts:
#   - the helper is copied to ~/.cdd/tools/cdd-worktree.sh and is executable
#   - the handoff root ~/.cdd/handoffs/ is created
#   - ~/.bashrc is created (neither rc existed) and carries the marker-guarded
#     source line exactly once
#   - handoffs under the legacy ~/.claude-handoffs/ are migrated, originals kept
#   - a second run is idempotent (no duplicate marker block, no second copy)
#
# Usage: scripts/install-smoke-assert.sh
# Takes no arguments; it provisions and tears down its own temp HOME.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/tools/cdd-worktree.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -x "$HELPER" ]] || fail "helper not found/executable: $HELPER"

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

echo "all install smoke checks passed"
