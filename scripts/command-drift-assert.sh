#!/usr/bin/env bash
# Contract checks for scripts/command-drift-check.sh, the drift gate.
#
# Same reasoning as scripts/prompt-seam-assert.sh, applied to the other render-then-diff
# guard: asserting that the drift checker passes on a good tree proves nothing, because a
# checker whose diff silently stopped covering a file also passes, and reports "clean"
# forever. The only useful question is whether it still *fails* on a bad tree.
#
# So this script mutation-tests it: break one thing at a time in a throwaway copy of the
# tree and require the checker to notice, naming what it noticed. Each of the checker's
# six checks gets at least one mutation:
#   1. Command-set diff        — a repo command copy diverges from its template counterpart.
#   2. Command-set membership  — a command exists on only one side.
#   3. Settings JSON validity  — both settings files gain the same syntax error, so they
#      still match each other and only the jq parse can catch it.
#   4. Settings diff           — .claude/settings.json diverges from the rendered template.
#   5. Template fence rejection — a cdd-only marker appears in the template itself.
#   6. Schema-heading contracts — the process doc's handoff and plan-file schema blocks
#      each lose a heading the command file still writes.
#
# Plus four controls, which are what make the mutations mean anything:
#   - An unmutated copy must PASS. Without this, every mutation could be "detected" by a
#     checker that is simply broken and fails on everything.
#   - A whitelisted one-sided command must PASS, pinning the documented escape hatch.
#   - A whitelisted settings.json divergence must PASS, pinning the same hatch for the
#     file that has no cdd-only fence available to it (JSON carries no comments).
#   - A cdd-only fence in the *repo* copy must PASS, pinning the stripping that makes
#     CDD-meta sections possible at all.
#
# Check 3 needs jq, which the checker treats as optional; without it that one mutation is
# skipped loudly rather than silently, the same posture scripts/ci.sh takes for a gate
# whose tool is missing.
#
# The copy is of the working tree, not HEAD, so this gate tests the checker as it is right
# now rather than as it was last committed. The real tree is never mutated.
#
# Usage: scripts/command-drift-assert.sh   (no arguments; no side effects outside $TMPDIR)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MASTER="$WORK/master"
SANDBOX="$WORK/sandbox"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
skip() { echo "skip: $*"; }

CHECKER="scripts/command-drift-check.sh"
WHITELIST="scripts/command-drift-whitelist.txt"
PROCESS_DOC="doc/knowledge_base/claude-driven-development.md"
SETTINGS=".claude/settings.json"
TPL_SETTINGS="template/.claude/settings.json"
# A command the template ships, so it exists on both sides of every comparison below.
SHARED_CMD="cdd-plan.md"

# --- The throwaway tree -------------------------------------------------------
# Everything but .git, which in a worktree is a *file* pointing elsewhere — copying it
# would hand the sandbox a dangling gitdir. The checker renders the template through the
# bootstrap script rather than reading git, so the sandbox needs no repo of its own.
mkdir -p "$MASTER"
find . -mindepth 1 -maxdepth 1 ! -name .git -exec cp -a {} "$MASTER/" \; \
  || fail "could not copy the working tree into the sandbox"

fresh_sandbox() {
  rm -rf "$SANDBOX"
  cp -a "$MASTER" "$SANDBOX" || fail "could not refresh the sandbox"
}

# Runs the *sandbox's* checker (it derives its own repo root from $BASH_SOURCE, so it
# reads the mutated tree, not this one). Output lands in $OUT, status in $STATUS.
run_drift_check() {
  OUT="$("$SANDBOX/$CHECKER" 2>&1)"
  STATUS=$?
}

expect_pass() {  # expect_pass <label>
  run_drift_check
  [[ $STATUS -eq 0 ]] \
    || fail "$1: the drift check should have passed but exited $STATUS: $OUT"
  pass "$1"
}

expect_fail() {  # expect_fail <label> <needle>
  run_drift_check
  [[ $STATUS -ne 0 ]] \
    || fail "$1: the drift check passed on a deliberately broken tree — the check is not firing"
  grep -qF -- "$2" <<<"$OUT" \
    || fail "$1: the drift check failed, but not with '$2'. It reported: $OUT"
  pass "$1"
}

# Rewrite a sandbox file through an awk program. Not `sed -i`: the in-place flag differs
# between GNU and BSD sed, and this runs on contributors' hosts too.
sandbox_awk() {  # sandbox_awk <awk program> <repo-relative path>
  local prog="$1" path="$SANDBOX/$2"
  awk "$prog" "$path" > "$path.new" || fail "could not rewrite $2 in the sandbox"
  mv "$path.new" "$path" || fail "could not replace $2 in the sandbox"
}

# Insert a line immediately after the settings file's `"allow": [` line. Both copies take
# the identical edit where a mutation needs them to stay in agreement. The inserted text
# carries quotes of its own, so it rides an awk variable rather than the program text.
insert_after_allow() {  # insert_after_allow <line> <repo-relative path>
  local line="$1" path="$SANDBOX/$2"
  awk -v ins="$line" '{ print } /"allow": \[/ && !done { print ins; done = 1 }' "$path" \
    > "$path.new" || fail "could not rewrite $2 in the sandbox"
  mv "$path.new" "$path" || fail "could not replace $2 in the sandbox"
}

# Delete the first `## ` heading inside a schema block, keyed on its opening line.
drop_schema_heading() {  # drop_schema_heading <block marker> <repo-relative path>
  sandbox_awk "/^$1/ { in_schema = 1 } in_schema && /^## / && !dropped { dropped = 1; next } { print }" "$2"
}

# --- Control: an unmutated copy passes ----------------------------------------
fresh_sandbox
expect_pass "control: an unmutated tree passes"

# --- Check 1: command-set diff -------------------------------------------------
fresh_sandbox
printf '\nassert-only drift probe.\n' >> "$SANDBOX/.claude/commands/$SHARED_CMD"
expect_fail "check 1 catches a repo command diverging from the template" \
  "template/.claude/commands/$SHARED_CMD (rendered)"

# --- Check 2: command-set membership -------------------------------------------
fresh_sandbox
printf '# assert-only probe command\n' > "$SANDBOX/.claude/commands/cdd-probe.md"
expect_fail "check 2 catches a command present on only one side" \
  "DRIFT: cdd-probe.md exists only in .claude/commands/"

# --- Control: the command whitelist silences it --------------------------------
fresh_sandbox
printf '# assert-only probe command\n' > "$SANDBOX/.claude/commands/cdd-probe.md"
printf 'cdd-probe.md\n' >> "$SANDBOX/$WHITELIST"
expect_pass "control: a whitelisted one-sided command passes"

# --- Control: a cdd-only fence in the repo copy is stripped --------------------
fresh_sandbox
sandbox_awk 'NR == 1 { print; print "<!-- cdd-only-begin -->"; print "assert-only CDD-meta paragraph."; print "<!-- cdd-only-end -->"; next } { print }' \
  ".claude/commands/$SHARED_CMD"
expect_pass "control: a cdd-only fence in the repo copy passes"

# --- Check 5: a cdd-only marker in the template is rejected --------------------
# An empty marker pair, so stripping leaves the two sides byte-identical and the marker
# check is the only thing that can fail. A fence with content would also trip check 1.
fresh_sandbox
sandbox_awk 'NR == 1 { print; print "<!-- cdd-only-begin -->"; print "<!-- cdd-only-end -->"; next } { print }' \
  "template/.claude/commands/$SHARED_CMD"
expect_fail "check 5 catches a cdd-only marker in the template" \
  "cdd-only markers found in template/.claude/commands/"

# --- Check 4: settings divergence ----------------------------------------------
fresh_sandbox
insert_after_allow '      "Bash(true *)",' "$SETTINGS"
expect_fail "check 4 catches .claude/settings.json diverging from the template" \
  "template/.claude/settings.json (rendered)"

# --- Control: the whitelist silences it, by whole file --------------------------
fresh_sandbox
insert_after_allow '      "Bash(true *)",' "$SETTINGS"
printf '%s\n' "$SETTINGS" >> "$SANDBOX/$WHITELIST"
expect_pass "control: a whitelisted settings.json divergence passes"

# --- Check 3: settings JSON validity -------------------------------------------
# The same syntax error in both copies, so they still render identical and the diff above
# stays green: only the jq parse can catch this one, which is the point of the mutation.
if command -v jq >/dev/null 2>&1; then
  fresh_sandbox
  insert_after_allow ',' "$SETTINGS"
  insert_after_allow ',' "$TPL_SETTINGS"
  expect_fail "check 3 catches a syntax error present in both settings copies" \
    "is not valid JSON"
else
  skip "check 3 (settings JSON validity): jq not available on this host"
fi

# --- Check 6: schema-heading contracts -----------------------------------------
# Mutating the *process doc* rather than the command file, so the command-set diff stays
# clean and the schema check is the only thing that can fire.
fresh_sandbox
drop_schema_heading '# Task:' "$PROCESS_DOC"
expect_fail "check 6 catches a dropped handoff schema heading" \
  "handoff schema headings differ"

fresh_sandbox
drop_schema_heading '# Plan:' "$PROCESS_DOC"
expect_fail "check 6 catches a dropped plan-file schema heading" \
  "plan-file schema headings differ"

echo "command-drift contract: clean"
