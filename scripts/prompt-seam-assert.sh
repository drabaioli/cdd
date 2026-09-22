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
# checker's 10 checks gets at least one mutation:
#   1. Command-name resolution — a markdown file referencing a command that does not exist.
#   2. Issue-ref contract      — four cases, one per half of the seam: cdd-next-step.md
#      stops recording the refs with `cdd-state issue-refs`; cdd-pre-pr.md stops deriving
#      close lines through `issue-close-token`; for the legacy fallback, cdd-pre-pr.md
#      stops turning the branch token into `Closes #NN`; and cdd-pre-pr.md loses its §11
#      close-line block while keeping the cdd-only prose that quotes the same tokens,
#      which catches a checker pinned to its own documentation rather than to the seam.
#   3. Path-existence linter   — CLAUDE.md gains a backticked path to a missing file; and,
#      separately, the process doc does, since it is in scope for the same check.
#   4. Required-section presence — cdd-pre-pr.md loses a load-bearing heading; and,
#      separately, cdd-next-step.md loses its checkout-freshness precondition.
#   5. Gate-count contract     — CLAUDE.md's stated gate count stops matching `ci.sh list`.
#   6. Engineering-floor set    — the template contract gains a practice row that
#                                 cdd-bootstrap.md's discovery bullet does not ask about.
#   7. Plan-file section contract — cdd-implement.md stops naming a plan-file section
#      that cdd-plan.md still writes.
#   8. Lane-marker contract    — cdd-worktree.sh stops routing the resume path to
#      /cdd-small-change while still routing the launch path to it.
#   9. Eligibility heuristic   — cdd-small-change.md restates the lane heuristic in
#      words of its own instead of the pinned sentence.
#  10. Seam-check count       — a check is added to the checker's own registry without
#      updating the prose that restates how many checks there are. Self-referential, so
#      the mutation has to add a registry entry AND a check function, not just a number.
#
# Plus three control cases, which are what make the mutations above mean anything:
#   - An unmutated copy must PASS. Without this, every mutation could be "detected"
#     by a checker that is simply broken and fails on everything.
#   - A dangling reference that is whitelisted must PASS, pinning the documented
#     escape hatch so it cannot rot into a check that can never be silenced.
#   - A *renumbered* load-bearing heading must PASS, pinning the title-matching
#     tolerance so it cannot quietly regress into the old double edit.
#
# Plus one structural assertion, which is not a mutation: the check registry and the
# check functions must pair up in both directions. A check function nobody registered
# never runs, and nothing else would ever say so.
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
CHECKER="scripts/prompt-seam-check.sh"

# --- Structural: the registry and the check functions agree -------------------
# The registry is only load-bearing if it is exhaustive both ways: a slug with no body
# is a check that cannot run, and a body with no slug is a check that silently never
# runs — the second being the failure that would leave the seam-count check passing on
# a checker that quietly stopped doing something. Same idiom as ci-runner-assert.sh's
# gate pairing, against the real checker rather than the sandbox.
mapfile -t slugs < <("./$CHECKER" list)
[[ ${#slugs[@]} -gt 0 ]] || fail "$CHECKER list printed no checks"

for slug in "${slugs[@]}"; do
  fn="check_${slug//-/_}"
  grep -qE "^${fn}\(\) \{" "$CHECKER" \
    || fail "check '$slug' has no ${fn}() function in $CHECKER"
done
pass "${#slugs[@]} checks listed, each with a matching check function"

while IFS= read -r fn; do
  slug="${fn#check_}"
  slug="${slug//_/-}"
  printf '%s\n' "${slugs[@]}" | grep -qxF -- "$slug" \
    || fail "orphan function ${fn}() in $CHECKER: '$slug' is not in the check registry"
done < <(grep -oE '^check_[a-z_]+\(\)' "$CHECKER" | sed 's/()$//')
pass "no orphan check functions"

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

# --- Check 2: issue-ref and branch-token contract ------------------------------
# Each half gets its own case, so a checker that kept only one of the needles is caught.
# The rewrites are global (/g) because cdd-pre-pr.md names each token more than once;
# the checker strips `cdd-only` regions before grepping, so the triage prose that
# describes this check is out of scope either way — which the last case below pins.
fresh_sandbox
sandbox_sed 's/cdd-state issue-refs/cdd-state note-refs/g' "$CMDS/cdd-next-step.md"
expect_fail "check 2 catches a producer that stops recording the issue refs" \
  "no longer records the refs with cdd-state issue-refs"

fresh_sandbox
sandbox_sed 's/issue-close-token/issue-closing-phrase/g' "$CMDS/cdd-pre-pr.md"
expect_fail "check 2 catches a consumer that stops deriving close lines" \
  "no longer derives close lines via issue-close-token"

fresh_sandbox
sandbox_sed 's/Closes #NN/Closes the issue/g' "$CMDS/cdd-pre-pr.md"
expect_fail "check 2 catches a severed gh_issue_NN -> Closes #NN seam" \
  "no longer turns the token into a Closes #NN line"

# The consumer half must be pinned to the §11 block that does the work, not to the
# cdd-only triage prose that merely quotes the same six tokens while describing this
# check. Deleting §11 outright, leaving that prose untouched, is the mutation that
# tells the two apart: a checker grepping the raw file would report clean.
fresh_sandbox
# shellcheck disable=SC2016  # `$d` is sed's last-line address, not a shell expansion
sandbox_sed '/^\*\*Close lines\.\*\* The body carries one close line per reference/,$d' \
  "$CMDS/cdd-pre-pr.md"
expect_fail "check 2 is not satisfied by its own cdd-only documentation" \
  "no longer reads the refs back with cdd-state get issue_refs"

# --- Check 3: path-existence linter -------------------------------------------
fresh_sandbox
# SC2016: the backticks are literal markdown, which is the whole point — the check
# under test only looks at backticked tokens. No shell expansion is wanted.
# shellcheck disable=SC2016
printf '\nSee `scripts/definitely-not-here.sh` for details.\n' >> "$SANDBOX/CLAUDE.md"
expect_fail "check 3 catches a backticked path to a missing file" \
  "broken path reference in CLAUDE.md"

# The process doc cites ADRs and architecture docs by path and is in scope for the same
# check, so its half gets its own case: dropping it from the file list would otherwise
# leave the CLAUDE.md mutation above still passing.
fresh_sandbox
# shellcheck disable=SC2016
printf '\nSee `doc/architecture/adr/9999-not-a-real-adr.md` for details.\n' \
  >> "$SANDBOX/doc/knowledge_base/claude-driven-development.md"
expect_fail "check 3 covers the process doc, not just the prompts and root indexes" \
  "broken path reference in doc/knowledge_base/claude-driven-development.md"

# --- Check 4: required-section presence ---------------------------------------
fresh_sandbox
sandbox_sed '/^## 10\. Commit reconciliation edits$/d' "$CMDS/cdd-pre-pr.md"
expect_fail "check 4 catches a dropped load-bearing heading" \
  "missing required heading in $CMDS/cdd-pre-pr.md: Commit reconciliation edits"

# The freshness precondition is a stop-the-session gate with no downstream artifact of its
# own, so nothing else in the workflow would notice its removal — hence its own case.
fresh_sandbox
sandbox_sed '/^## 0a\. Verify the checkout is current$/d' "$CMDS/cdd-next-step.md"
expect_fail "check 4 catches a dropped checkout-freshness precondition" \
  "missing required heading in $CMDS/cdd-next-step.md: Verify the checkout is current"

# --- Control: a renumbered heading still passes --------------------------------
# Headings are pinned by title, not by step number (issue #64), so inserting a step
# above a load-bearing one must be a no-op. Without this control the tolerance could
# regress to number matching and nothing would notice until the next renumbering.
fresh_sandbox
sandbox_sed 's/^## 10\. Commit reconciliation edits$/## 12. Commit reconciliation edits/' \
  "$CMDS/cdd-pre-pr.md"
grep -qF '## 12. Commit reconciliation edits' "$SANDBOX/$CMDS/cdd-pre-pr.md" \
  || fail "renumber control setup: cdd-pre-pr.md was not renumbered in the sandbox"
expect_pass "control: a renumbered load-bearing heading still passes"

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

# --- Check 6: engineering-floor practice set -----------------------------------
# Add an open practice row to the template contract without teaching /cdd-bootstrap to
# ask about it. This is the realistic failure: the contract is where a new practice
# naturally gets written down, and the discovery bullet is the side that gets forgotten.
fresh_sandbox
printf '\n## Seam probe practice — Expected\n\nAssert-only probe row.\n' \
  >> "$SANDBOX/template/doc/knowledge_base/engineering-practices.md"
expect_fail "check 6 catches a contract practice the bootstrap discovery never asks about" \
  "carries the open practice 'Seam probe practice'"

# --- Check 7: plan-file section contract --------------------------------------
# Rename the section on the CONSUMER side only: cdd-plan.md keeps writing
# `## Dead ends` into the plan file while cdd-implement.md stops naming it, which is
# exactly the one-sided edit that would strand the plan silently.
fresh_sandbox
sandbox_sed 's/Dead ends/Abandoned leads/g' "$CMDS/cdd-implement.md"
grep -qF 'Dead ends' "$SANDBOX/$CMDS/cdd-implement.md" \
  && fail "check 7 setup: cdd-implement.md still names the section after mutation"
expect_fail "check 7 catches a plan-file section the consumer stopped naming" \
  "section 'Dead ends' is written by"

# --- Check 8: lane-marker contract --------------------------------------------
# Sever the CONSUMER's resume path only, leaving the launch path intact. That is the
# realistic one-sided edit — and the one nothing else would catch, because a lane that
# stops routing degrades to the standard lane, which looks like a working workflow.
fresh_sandbox
sandbox_sed 's|run /cdd-small-change|run /cdd-plan|' tools/cdd-worktree.sh
expect_fail "check 8 catches a lane consumer that stopped routing on one path" \
  "no longer routes a resumed task to /cdd-small-change"

# --- Check 9: eligibility-heuristic wording -----------------------------------
# Reword the heuristic in one of the two commands that apply it. Both still read
# sensibly on their own, which is exactly why a split would go unnoticed.
fresh_sandbox
sandbox_sed 's|If you can state the finished diff in one sentence|If the change is only a few lines|' \
  "$CMDS/cdd-small-change.md"
expect_fail "check 9 catches a command that reworded the lane heuristic" \
  "it no longer states the lane heuristic verbatim"

# --- Check 10: seam-check count ------------------------------------------------
# Self-referential, so the mutation is a real check rather than an edited number: give
# the sandbox checker one more registry entry and a matching no-op body, and the four
# prose sites (this file among them) are now one short. Two insertion points, hence awk
# and not sandbox_sed: the function has to land *before* `main "$@"`, since a definition
# after it is parsed too late to run, and a `\n` in a sed replacement is GNU-only.
sandbox_add_probe_check() {
  local path="$SANDBOX/scripts/prompt-seam-check.sh"
  awk '
    /^CHECKS=\(/ && !entry { print; print "  \"seam-probe|assert-only probe check\""; entry = 1; next }
    /^main / && !body { print "check_seam_probe() { :; }"; print ""; body = 1 }
    { print }
  ' "$path" > "$path.new" || fail "could not add the probe check to the sandbox checker"
  mv "$path.new" "$path" || fail "could not replace the sandbox checker"
  chmod +x "$path" || fail "could not restore the sandbox checker's exec bit"
}

fresh_sandbox
sandbox_add_probe_check
"$SANDBOX/scripts/prompt-seam-check.sh" list | grep -qxF seam-probe \
  || fail "check 10 setup: the probe check is not in the sandbox registry"
expect_fail "check 10 catches a check added without updating the prose" \
  "seam-count drift in"

echo "prompt-seam contract: clean"
