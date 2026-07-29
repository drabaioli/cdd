#!/usr/bin/env bash
# Contract checks for scripts/prompt-seam-check.sh, the prompt-seam gate.
#
# The seam checker guards the seams between this repo's own prompts, but until now
# nothing guarded the checker. A pattern that silently stopped matching — a heading
# reworded, a grep that no longer fires — would report "clean" forever, which is
# precisely the failure mode the checker exists to prevent. Asserting that it passes
# on a good tree proves nothing; the only useful question is whether it still *fails*
# on a bad one.
#
# So this script mutation-tests it: break one seam at a time in a throwaway copy of
# the tree and require the checker to notice, naming the seam it noticed. Each of the
# checker's five checks gets one mutation:
#   1. Command-name resolution — a markdown file referencing a command that does not exist.
#   2. Branch-token contract   — cdd-pre-pr.md stops turning the token into `Closes #NN`.
#   3. Path-existence linter   — CLAUDE.md gains a backticked path to a missing file.
#   4. Required-section presence — cdd-pre-pr.md loses a load-bearing heading.
#   5. Gate-count contract     — CLAUDE.md's stated gate count stops matching `ci.sh list`.
#
# Plus two control cases, which are what make the five above mean anything:
#   - An unmutated copy must PASS. Without this, every mutation could be "detected"
#     by a checker that is simply broken and fails on everything.
#   - A dangling reference that is whitelisted must PASS, pinning the documented
#     escape hatch so it cannot rot into a check that can never be silenced.
#
# The copy is of the working tree, not HEAD, so this gate tests the checker as it is
# right now rather than as it was last committed. The real tree is never mutated.
#
# Usage: scripts/prompt-seam-assert.sh   (no arguments; no side effects outside $TMPDIR)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MASTER="$WORK/master"
SANDBOX="$WORK/sandbox"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# --- The throwaway tree -------------------------------------------------------
# Everything but .git, which in a worktree is a *file* pointing elsewhere — copying
# it would hand the sandbox a dangling gitdir. The checker's first check runs
# `git ls-files`, so the sandbox needs a repo of its own: init and stage instead.
mkdir -p "$MASTER"
find . -mindepth 1 -maxdepth 1 ! -name .git -exec cp -a {} "$MASTER/" \; \
  || fail "could not copy the working tree into the sandbox"
git -c init.defaultBranch=main init -q "$MASTER" || fail "git init failed in the sandbox"
git -C "$MASTER" add -A || fail "git add failed in the sandbox"

fresh_sandbox() {
  rm -rf "$SANDBOX"
  cp -a "$MASTER" "$SANDBOX" || fail "could not refresh the sandbox"
}

# Runs the *sandbox's* checker (it derives its own repo root from $BASH_SOURCE, so
# it reads the mutated tree, not this one). Output lands in $OUT, status in $STATUS.
run_seam_check() {
  OUT="$("$SANDBOX/scripts/prompt-seam-check.sh" 2>&1)"
  STATUS=$?
}

expect_pass() {  # expect_pass <label>
  run_seam_check
  [[ $STATUS -eq 0 ]] \
    || fail "$1: the seam check should have passed but exited $STATUS: $OUT"
  pass "$1"
}

expect_fail() {  # expect_fail <label> <needle>
  run_seam_check
  [[ $STATUS -ne 0 ]] \
    || fail "$1: the seam check passed on a deliberately broken tree — the check is not firing"
  grep -qF -- "$2" <<<"$OUT" \
    || fail "$1: the seam check failed, but not with '$2'. It reported: $OUT"
  pass "$1"
}

# Rewrite a file in the sandbox through a filter. Not `sed -i`: the in-place flag
# differs between GNU and BSD sed, and this runs on contributors' hosts too.
sandbox_sed() {  # sandbox_sed <expr> <repo-relative path>
  local expr="$1" path="$SANDBOX/$2"
  sed -E "$expr" "$path" > "$path.new" || fail "could not rewrite $2 in the sandbox"
  mv "$path.new" "$path" || fail "could not replace $2 in the sandbox"
}

CMDS=".claude/commands"

# --- Control: an unmutated copy passes ----------------------------------------
# Establishes that the sandbox faithfully reproduces a green run. Every expect_fail
# below is only meaningful because this one holds.
fresh_sandbox
expect_pass "control: an unmutated copy of the tree passes"

# --- Check 1: dangling command reference --------------------------------------
fresh_sandbox
printf 'Run /cdd-totally-bogus to do the thing.\n' > "$SANDBOX/seam-probe.md"
expect_fail "check 1 catches a dangling command reference" "dangling command reference /cdd-totally-bogus"

# --- Control: the whitelist still silences one --------------------------------
fresh_sandbox
printf 'Run /cdd-totally-bogus to do the thing.\n' > "$SANDBOX/seam-probe.md"
printf '# Assert-only probe token.\n/cdd-totally-bogus\n' >> "$SANDBOX/scripts/prompt-seam-whitelist.txt"
expect_pass "control: a whitelisted dangling reference is silenced"

# --- Check 2: branch-token contract -------------------------------------------
fresh_sandbox
sandbox_sed 's/Closes #NN/Closes the issue/g' "$CMDS/cdd-pre-pr.md"
expect_fail "check 2 catches a severed gh_issue_NN -> Closes #NN seam" \
  "no longer turns the token into a Closes #NN line"

# --- Check 3: path-existence linter -------------------------------------------
fresh_sandbox
# SC2016: the backticks are literal markdown, which is the whole point — the check
# under test only looks at backticked tokens. No shell expansion is wanted.
# shellcheck disable=SC2016
printf '\nSee `scripts/definitely-not-here.sh` for details.\n' >> "$SANDBOX/CLAUDE.md"
expect_fail "check 3 catches a backticked path to a missing file" \
  "broken path reference in CLAUDE.md"

# --- Check 4: required-section presence ---------------------------------------
fresh_sandbox
sandbox_sed '/^## 9\. Commit reconciliation edits$/d' "$CMDS/cdd-pre-pr.md"
expect_fail "check 4 catches a dropped load-bearing heading" \
  "missing required heading in $CMDS/cdd-pre-pr.md: ## 9. Commit reconciliation edits"

# --- Check 5: gate-count contract ---------------------------------------------
# Derive the true count from the registry rather than hardcoding it, so adding a
# gate does not silently turn this case into a no-op.
fresh_sandbox
count="$("$SANDBOX/scripts/ci.sh" list | grep -c .)"
[[ "$count" -gt 0 ]] || fail "check 5 setup: the sandbox runner listed no gates"
sandbox_sed "s/(^|[^0-9])$count gates/\\1$((count + 84)) gates/g" CLAUDE.md
grep -qE "(^|[^0-9])$count gates?([^a-z]|$)" "$SANDBOX/CLAUDE.md" \
  && fail "check 5 setup: CLAUDE.md still states the true gate count after mutation"
expect_fail "check 5 catches a stale gate count in the prose" \
  "gate-count drift in CLAUDE.md"

echo "prompt-seam contract: clean"
