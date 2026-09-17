#!/usr/bin/env bash
# Deterministic seam-contract checks for the CDD repo's own prompts (Tier 1; issue #23).
#
# CDD's slash-commands are agentic prompts whose steps hand artifacts to each other.
# Producer and consumer must agree on each artifact's shape, and a one-sided edit can
# silently strand a downstream step. This script pins those seams with grep/diff only —
# no LLM, no API key, no flakiness — the same proven shape as command-drift-check.sh.
#
# It is a CDD-repo-only check (the meta-project guarding its own command set/docs); it is
# not shipped in template/ and does not run in downstream projects' CI. See the #23
# investigation comment for the verdict and the deferred Tier 2/3 follow-ups.
#
# Checks:
#   1. Command-name resolution — every `/cdd-*` reference across the repo's markdown
#      resolves to an existing .claude/commands/cdd-*.md, or is a whitelisted non-command
#      (shell helper, marker path, retired name) in scripts/prompt-seam-whitelist.txt.
#   2. Branch-token contract — the gh_issue_NN token produced in cdd-next-step.md is
#      consumed (-> Closes #NN) in cdd-pre-pr.md; both sides must still name it.
#   3. Path-existence linter — backticked repo-relative file paths in the command files,
#      CLAUDE.md, and README.md resolve to real files (whitelist covers downstream paths).
#   4. Required-section presence — each cdd-*.md still carries its load-bearing headings,
#      so an edit can't silently drop one.
#   5. Gate-count contract — the gate count CLAUDE.md and cdd-pre-pr.md state in prose
#      matches what `scripts/ci.sh list` actually registers, so adding a gate can't leave
#      the prose (which is what a session reads to know what it just ran) stale.
#   6. Engineering-floor practice set — every negotiable row of the template's
#      engineering-practices contract is named in cdd-bootstrap.md's engineering-floor
#      discovery bullet, so a row added or renamed there can't ship resolved by guess.
#   7. Plan-file section contract — every `## ` section cdd-plan.md writes into the plan
#      file is still named in cdd-implement.md, which reads it. The plan file is the only
#      thing crossing between the two sessions, so a one-sided rename would strand it.
#   8. Lane-marker contract — the small-change lane's routing marker is written by
#      cdd-next-step.md (`cdd-state lane`) and read by tools/cdd-worktree.sh (`.lane`),
#      which must still name /cdd-small-change on both the launch and the resume path.
#   9. Eligibility-heuristic wording — the one sentence that decides the lane is stated
#      verbatim in the process doc and in both commands that apply it. The template
#      ships no process doc to point at, so the wording is pinned instead of cited.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

REPO_CMDS=".claude/commands"
WHITELIST="scripts/prompt-seam-whitelist.txt"
PROCESS_DOC_KB="doc/knowledge_base/claude-driven-development.md"

fail=0
note() { echo "  $*" >&2; fail=1; }

whitelisted() {
  grep -vE '^[[:space:]]*(#|$)' "$WHITELIST" | grep -qxF -- "$1"
}

# --- Check 1: command-name resolution ----------------------------------------
mapfile -t md_files < <(git ls-files --cached --others --exclude-standard '*.md')
mapfile -t cmd_tokens < <(grep -hoE '/cdd-[a-z][a-z0-9-]*' "${md_files[@]}" | sort -u)

for tok in "${cmd_tokens[@]}"; do
  name="${tok#/}"
  [[ -f "$REPO_CMDS/$name.md" ]] && continue
  whitelisted "$tok" && continue
  note "dangling command reference $tok — no $REPO_CMDS/$name.md and not whitelisted:"
  grep -rnoE "$tok"'([^a-z0-9-]|$)' "${md_files[@]}" | sed 's/^/    /' >&2 || true
done

# --- Check 2: branch-token / issue-token contract ----------------------------
NEXT="$REPO_CMDS/cdd-next-step.md"
PRE="$REPO_CMDS/cdd-pre-pr.md"
grep -qF 'gh_issue_NN_' "$NEXT" \
  || note "branch-token producer broken: $NEXT no longer names the gh_issue_NN_<slug> token"
grep -qF 'gh_issue_NN' "$PRE" \
  || note "branch-token consumer broken: $PRE no longer matches the gh_issue_NN branch token"
grep -qF 'Closes #NN' "$PRE" \
  || note "branch-token consumer broken: $PRE no longer turns the token into a Closes #NN line"

# --- Check 3: path-existence linter ------------------------------------------
# Backticked tokens that look like a repo-relative path (contain '/', end in a known
# extension, no placeholders/globs/home/vars/brace-expansion) must resolve to a real file.
for f in "$REPO_CMDS"/cdd-*.md CLAUDE.md README.md; do
  # SC2016: the single quotes below are deliberate — the grep/sed patterns match
  # literal backtick characters in the markdown; no shell expansion is wanted.
  # shellcheck disable=SC2016
  while IFS= read -r p; do
    [[ -e "$p" ]] && continue
    whitelisted "$p" && continue
    note "broken path reference in $f: \`$p\`"
  done < <(grep -oE '`[^`]+`' "$f" \
             | sed -E 's/^`//; s/`$//' \
             | grep -E '/' \
             | grep -E '\.(md|sh|ya?ml|txt|json|png)$' \
             | grep -vE '[<>*~$ {}]')
done

# --- Check 4: required-section presence per command --------------------------
# Curated load-bearing headings (## lines, matched whole-line). Not the full set —
# the seam-critical steps whose silent removal would break a downstream prompt.
require_headings() {
  local file="$1"; shift
  local h
  for h in "$@"; do
    grep -qxF -- "$h" "$file" || note "missing required heading in $file: $h"
  done
}

require_headings "$REPO_CMDS/cdd-next-step.md" \
  '## 0. Mode: roadmap-driven, intent-driven, or issue-driven' \
  '## 0a. Verify the checkout is current' \
  '## 5. Draft the handoff' \
  '## 7. Write the handoff file' \
  '## 8. Print the next command'
require_headings "$REPO_CMDS/cdd-pre-pr.md" \
  '## 1. Identify changes' \
  '## 2. Build & QA' \
  '## 9. Summary' \
  '## 10. Commit reconciliation edits' \
  '## 11. Open PR (optional)'
require_headings "$REPO_CMDS/cdd-merge-base.md" \
  '## 3. Dry-run conflict assessment' \
  '## 5. Perform the merge' \
  '## 8. Summary'
require_headings "$REPO_CMDS/cdd-process-pr.md" \
  '## 4. Triage (the retained checkpoint)' \
  '## 7. Commit and push'
require_headings "$REPO_CMDS/cdd-bootstrap.md" \
  '## 1. Guided discovery' \
  '## 6. Scaffold the project (one bootstrap invocation)'
require_headings "$REPO_CMDS/cdd-quick-create.md" \
  '## 1. Scope check (the gate)' \
  '## 4. Write the deliverable (files-first)'
require_headings "$REPO_CMDS/cdd-retrofit.md" \
  '## 3. Install mode' \
  '## 4. Upgrade mode'
require_headings "$REPO_CMDS/cdd-plan.md" \
  '## 2. Explore' \
  '## 4. Print the bounded digest' \
  '## 6. Write the plan file' \
  '## 7. Print the next command'
require_headings "$REPO_CMDS/cdd-implement.md" \
  '## 1. Read the plan' \
  '## 2. Deviation rule: stop and report, never improvise' \
  '## 6. Commit'
require_headings "$REPO_CMDS/cdd-small-change.md" \
  '## 2. Confirm the task is still small (the off-ramp)' \
  '## 3. Checkpoint: approve the concrete change' \
  '## 7. Commit' \
  '## 8. Print the next command'

# --- Check 5: gate-count contract --------------------------------------------
# The runner's registry is the source of truth for how many gates there are; both
# CLAUDE.md and cdd-pre-pr.md also state the count in prose, and a pre-PR session
# reads the prose to describe what it ran. `ci.sh list` is the same interface
# ci-runner-assert.sh consumes; `list` returns before the runner does any work.
gate_count="$(./scripts/ci.sh list | grep -c .)"
for f in CLAUDE.md "$REPO_CMDS/cdd-pre-pr.md"; do
  grep -qE "(^|[^0-9])$gate_count gates?([^a-z]|$)" "$f" && continue
  note "gate-count drift in $f: scripts/ci.sh registers $gate_count gates; the file states:"
  grep -noE '[0-9]+ gates?' "$f" | sed 's/^/    /' >&2 || true
done

# --- Check 6: engineering-floor practice-set contract ------------------------
# /cdd-bootstrap resolves the engineering-practices contract from one batched discovery
# question, so the practices it asks about must be the ones the template contract
# actually carries as open. A row added to (or renamed in) the contract that the prompt
# never asks about ships resolved by guess — the one thing resolving-at-bootstrap exists
# to prevent. Negotiable means "status not plainly Enforced": a row marked `— Enforced`
# outright (documentation) is not up for discussion, and a heading with no `— <status>`
# suffix at all ("How this list grows") is not a practice row. Both sides must name the
# row identically, exactly as with the gh_issue_NN token — no mapping table here, which
# would be a third copy free to drift from both.
CONTRACT="template/doc/knowledge_base/engineering-practices.md"
BOOTSTRAP="$REPO_CMDS/cdd-bootstrap.md"
floor_bullet="$(grep -F -- '- **Engineering floor**' "$BOOTSTRAP" || true)"
if [[ -z "$floor_bullet" ]]; then
  note "engineering-floor seam broken: $BOOTSTRAP no longer carries the '- **Engineering floor**' discovery bullet"
else
  while IFS= read -r practice; do
    grep -qiF -- "$practice" <<<"$floor_bullet" && continue
    note "engineering-floor seam broken: $CONTRACT carries the open practice '$practice', which $BOOTSTRAP's engineering-floor bullet does not name"
  done < <(awk -F' — ' '/^## / && NF > 1 { sub(/^## /, ""); if ($NF != "Enforced") print $1 }' "$CONTRACT")
fi

# --- Check 7: plan-file section contract ------------------------------------
# The plan file (process doc 2.15) is the ONLY artifact crossing from the plan session
# to the implementation session, so a section renamed on one side and not the other
# strands it silently. cdd-plan.md is the producer: its fenced `# Plan:` schema block
# names the sections. cdd-implement.md is the consumer and must still name each one.
# Same awk shape command-drift-check.sh uses for the handoff schema.
PLAN="$REPO_CMDS/cdd-plan.md"
IMPL="$REPO_CMDS/cdd-implement.md"
plan_schema_headings() {
  awk '/^# Plan:/ { in_schema = 1 }
       in_schema && /^## / { print }
       in_schema && /^```/ { exit }' "$1"
}
mapfile -t plan_sections < <(plan_schema_headings "$PLAN")
if (( ${#plan_sections[@]} == 0 )); then
  note "plan-file producer broken: $PLAN no longer carries a '# Plan:' schema block with ## sections"
else
  for h in "${plan_sections[@]}"; do
    grep -qF -- "${h#\#\# }" "$IMPL"       || note "plan-file consumer broken: section '${h#\#\# }' is written by $PLAN but no longer named in $IMPL"
  done
fi

# --- Check 8: lane-marker contract -------------------------------------------
# The small-change lane is routed by one marker on the task state record. /cdd-next-step
# is the sole producer and cdd-worktree.sh the sole consumer, on two separate paths
# (launch and resume). A one-sided edit degrades silently to the standard lane — the safe
# direction, and exactly why nothing else would ever notice. Same shape as check 2.
WT_HELPER="tools/cdd-worktree.sh"
grep -qF 'cdd-state lane' "$NEXT" \
  || note "lane-marker producer broken: $NEXT no longer writes the lane with \`cdd-state lane\`"
grep -qF "'.lane // empty'" "$WT_HELPER" \
  || note "lane-marker consumer broken: $WT_HELPER no longer reads .lane from the state record"
# Both routing paths live in their own function, so pin each one by name. Counting
# occurrences would not do: a comment, or the `-f .claude/commands/cdd-small-change.md`
# probe, satisfies a count while the route itself is gone. So: comment lines dropped,
# and the trailing `.md` form excluded, leaving only the command named as a command.
# The function header is matched as a literal string, not a regex: `awk -v` runs its own
# escape processing over the value, and implementations disagree about what survives it
# (mawk keeps `\(`, gawk strips it and warns), so a backslash here matches on one host
# and silently stops matching on the next.
lane_routes_in() {  # lane_routes_in <function-name>
  awk -v fn="$1() {" '$0 == fn { inside = 1; next } inside && /^}/ { exit } inside' \
    "$WT_HELPER" \
    | grep -v '^[[:space:]]*#' \
    | grep -q -- '/cdd-small-change\([^.]\|$\)'
}
lane_routes_in cdd-worktree \
  || note "lane-marker consumer broken: cdd-worktree() in $WT_HELPER no longer launches /cdd-small-change"
lane_routes_in cdd-worktree-resume \
  || note "lane-marker consumer broken: cdd-worktree-resume() in $WT_HELPER no longer routes a resumed task to /cdd-small-change"

# --- Check 9: eligibility-heuristic wording -----------------------------------
# The heuristic decides which lane a task takes, and it is applied twice: once by
# /cdd-next-step when it recommends, once by /cdd-small-change when it re-checks and
# decides whether to take the off-ramp. Two commands applying two different sentences is
# a silent split. It is restated rather than cited because the template ships no copy of
# the process doc, so a pointer would dangle in every downstream project.
HEURISTIC="If you can state the finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard lane."
for f in "$PROCESS_DOC_KB" "$NEXT" "$REPO_CMDS/cdd-small-change.md"; do
  grep -qF -- "$HEURISTIC" "$f" \
    || note "eligibility-heuristic drift in $f: it no longer states the lane heuristic verbatim"
done

if [[ "$fail" -ne 0 ]]; then
  echo "prompt-seam check: FAILED (see above)" >&2
  exit 1
fi
echo "prompt-seam check: clean"
