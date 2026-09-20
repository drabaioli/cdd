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
# The CHECKS registry below is the single source of what this script checks, the way
# ci.sh's GATES registry is for the gate sequence; `prompt-seam-check.sh list` prints it.
# Every prose restatement of the count is pinned against that registry by the last check.
#
# Usage: scripts/prompt-seam-check.sh [list]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

REPO_CMDS=".claude/commands"
WHITELIST="scripts/prompt-seam-whitelist.txt"
PROCESS_DOC_KB="doc/knowledge_base/claude-driven-development.md"
WT_HELPER="tools/cdd-worktree.sh"
NEXT="$REPO_CMDS/cdd-next-step.md"
PRE="$REPO_CMDS/cdd-pre-pr.md"

# --- Check registry -----------------------------------------------------------
# "slug|description", in run order. Each slug has one check_<slug-with-underscores>()
# function below, and prompt-seam-assert.sh pins that pairing in both directions — a
# check function nobody registered would never run, and would never be missed.
CHECKS=(
  "command-refs|every /cdd-* reference resolves to a command file or is whitelisted"
  "branch-token|the gh_issue_NN token is produced and consumed in agreement"
  "paths|backticked repo-relative file paths resolve to real files"
  "headings|each cdd-*.md still carries its load-bearing headings"
  "gate-count|the gate count stated in prose matches ci.sh's registry"
  "engineering-floor|every open practice row is named in cdd-bootstrap's discovery"
  "plan-sections|every plan-file section cdd-plan.md writes is named in cdd-implement.md"
  "lane-marker|the small-change lane's routing marker is written and read"
  "heuristic|the lane eligibility heuristic is stated verbatim everywhere"
  "check-count|the seam-check count stated in prose matches this registry"
)

fail=0
note() { echo "  $*" >&2; fail=1; }

whitelisted() {
  grep -vE '^[[:space:]]*(#|$)' "$WHITELIST" | grep -qxF -- "$1"
}

# --- Check: command-name resolution -------------------------------------------
# Every `/cdd-*` reference across the repo's markdown resolves to an existing
# .claude/commands/cdd-*.md, or is a whitelisted non-command (shell helper, marker
# path, retired name) in scripts/prompt-seam-whitelist.txt.
check_command_refs() {
  local -a md_files cmd_tokens
  local tok name
  mapfile -t md_files < <(git ls-files --cached --others --exclude-standard '*.md')
  mapfile -t cmd_tokens < <(grep -hoE '/cdd-[a-z][a-z0-9-]*' "${md_files[@]}" | sort -u)

  for tok in "${cmd_tokens[@]}"; do
    name="${tok#/}"
    [[ -f "$REPO_CMDS/$name.md" ]] && continue
    whitelisted "$tok" && continue
    note "dangling command reference $tok — no $REPO_CMDS/$name.md and not whitelisted:"
    grep -rnoE "$tok"'([^a-z0-9-]|$)' "${md_files[@]}" | sed 's/^/    /' >&2 || true
  done
  return 0
}

# --- Check: branch-token / issue-token contract -------------------------------
# The gh_issue_NN token produced in cdd-next-step.md is consumed (-> Closes #NN) in
# cdd-pre-pr.md; both sides must still name it.
check_branch_token() {
  grep -qF 'gh_issue_NN_' "$NEXT" \
    || note "branch-token producer broken: $NEXT no longer names the gh_issue_NN_<slug> token"
  grep -qF 'gh_issue_NN' "$PRE" \
    || note "branch-token consumer broken: $PRE no longer matches the gh_issue_NN branch token"
  grep -qF 'Closes #NN' "$PRE" \
    || note "branch-token consumer broken: $PRE no longer turns the token into a Closes #NN line"
  return 0
}

# --- Check: path-existence linter ---------------------------------------------
# Backticked tokens that look like a repo-relative path (contain '/', end in a known
# extension, no placeholders/globs/home/vars/brace-expansion) must resolve to a real file.
# The process doc is in scope alongside the prompts and the two root indexes: it cites ADRs
# and architecture docs by path, and a rename on either side would otherwise strand them.
check_paths() {
  local f p
  for f in "$REPO_CMDS"/cdd-*.md CLAUDE.md README.md "$PROCESS_DOC_KB"; do
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
  return 0
}

# --- Check: required-section presence per command -----------------------------
# Curated load-bearing headings. Not the full set — the seam-critical steps whose
# silent removal would break a downstream prompt.
#
# Matching is on the heading *title*: the `## ` marker and any `<N>. ` / `<N>a. ` step
# prefix are stripped from both sides, so renumbering a step is a no-op (issue #64) while
# a dropped heading still fails. The pinned entries below are therefore bare titles — a
# number left in one would be stripped along with the file's own and so could never be
# enforced, i.e. it would rot silently, which is the failure this check exists to prevent.
heading_titles() {  # heading_titles <file>
  grep -E '^## ' "$1" | sed -E 's/^## +//; s/^[0-9]+[a-z]*\. +//' || true
}

require_headings() {  # require_headings <file> <title>...
  local file="$1"; shift
  local titles h
  titles="$(heading_titles "$file")"
  for h in "$@"; do
    grep -qxF -- "$h" <<<"$titles" || note "missing required heading in $file: $h"
  done
}

check_headings() {
  require_headings "$NEXT" \
    'Mode: roadmap-driven, intent-driven, or issue-driven' \
    'Verify the checkout is current' \
    'Draft the handoff' \
    'Write the handoff file' \
    'Print the next command'
  require_headings "$PRE" \
    'Identify changes' \
    'Build & QA' \
    'Summary' \
    'Commit reconciliation edits' \
    'Open PR (optional)'
  require_headings "$REPO_CMDS/cdd-merge-base.md" \
    'Dry-run conflict assessment' \
    'Perform the merge' \
    'Summary'
  require_headings "$REPO_CMDS/cdd-process-pr.md" \
    'Triage (the retained checkpoint)' \
    'Commit and push'
  require_headings "$REPO_CMDS/cdd-bootstrap.md" \
    'Guided discovery' \
    'Scaffold the project (one bootstrap invocation)'
  require_headings "$REPO_CMDS/cdd-quick-create.md" \
    'Scope check (the gate)' \
    'Write the deliverable (files-first)'
  require_headings "$REPO_CMDS/cdd-retrofit.md" \
    'Install mode' \
    'Upgrade mode'
  require_headings "$REPO_CMDS/cdd-plan.md" \
    'Explore' \
    'Print the bounded digest' \
    'Write the plan file' \
    'Print the next command'
  require_headings "$REPO_CMDS/cdd-implement.md" \
    'Read the plan' \
    'Deviation rule: stop and report, never improvise' \
    'Commit'
  require_headings "$REPO_CMDS/cdd-small-change.md" \
    'Confirm the task is still small (the off-ramp)' \
    'Checkpoint: approve the concrete change' \
    'Commit' \
    'Print the next command'
  return 0
}

# --- Check: gate-count contract -----------------------------------------------
# The runner's registry is the source of truth for how many gates there are; both
# CLAUDE.md and cdd-pre-pr.md also state the count in prose, and a pre-PR session
# reads the prose to describe what it ran. `ci.sh list` is the same interface
# ci-runner-assert.sh consumes; `list` returns before the runner does any work.
check_gate_count() {
  local gate_count f
  gate_count="$(./scripts/ci.sh list | grep -c .)"
  for f in CLAUDE.md "$PRE"; do
    grep -qE "(^|[^0-9])$gate_count gates?([^a-z]|$)" "$f" && continue
    note "gate-count drift in $f: scripts/ci.sh registers $gate_count gates; the file states:"
    grep -noE '[0-9]+ gates?' "$f" | sed 's/^/    /' >&2 || true
  done
  return 0
}

# --- Check: engineering-floor practice-set contract ---------------------------
# /cdd-bootstrap resolves the engineering-practices contract from one batched discovery
# question, so the practices it asks about must be the ones the template contract
# actually carries as open. A row added to (or renamed in) the contract that the prompt
# never asks about ships resolved by guess — the one thing resolving-at-bootstrap exists
# to prevent. Negotiable means "status not plainly Enforced": a row marked `— Enforced`
# outright (documentation) is not up for discussion, and a heading with no `— <status>`
# suffix at all ("How this list grows") is not a practice row. Both sides must name the
# row identically, exactly as with the gh_issue_NN token — no mapping table here, which
# would be a third copy free to drift from both.
check_engineering_floor() {
  local contract="template/doc/knowledge_base/engineering-practices.md"
  local bootstrap="$REPO_CMDS/cdd-bootstrap.md"
  local floor_bullet practice
  floor_bullet="$(grep -F -- '- **Engineering floor**' "$bootstrap" || true)"
  if [[ -z "$floor_bullet" ]]; then
    note "engineering-floor seam broken: $bootstrap no longer carries the '- **Engineering floor**' discovery bullet"
    return 0
  fi
  while IFS= read -r practice; do
    grep -qiF -- "$practice" <<<"$floor_bullet" && continue
    note "engineering-floor seam broken: $contract carries the open practice '$practice', which $bootstrap's engineering-floor bullet does not name"
  done < <(awk -F' — ' '/^## / && NF > 1 { sub(/^## /, ""); if ($NF != "Enforced") print $1 }' "$contract")
  return 0
}

# --- Check: plan-file section contract ----------------------------------------
# The plan file (process doc 2.15) is the ONLY artifact crossing from the plan session
# to the implementation session, so a section renamed on one side and not the other
# strands it silently. cdd-plan.md is the producer: its fenced `# Plan:` schema block
# names the sections. cdd-implement.md is the consumer and must still name each one.
# Same awk shape command-drift-check.sh uses for the handoff schema.
plan_schema_headings() {  # plan_schema_headings <file>
  awk '/^# Plan:/ { in_schema = 1 }
       in_schema && /^## / { print }
       in_schema && /^```/ { exit }' "$1"
}

check_plan_sections() {
  local plan="$REPO_CMDS/cdd-plan.md"
  local impl="$REPO_CMDS/cdd-implement.md"
  local -a plan_sections
  local h
  mapfile -t plan_sections < <(plan_schema_headings "$plan")
  if (( ${#plan_sections[@]} == 0 )); then
    note "plan-file producer broken: $plan no longer carries a '# Plan:' schema block with ## sections"
    return 0
  fi
  for h in "${plan_sections[@]}"; do
    grep -qF -- "${h#\#\# }" "$impl" || note "plan-file consumer broken: section '${h#\#\# }' is written by $plan but no longer named in $impl"
  done
  return 0
}

# --- Check: lane-marker contract ----------------------------------------------
# The small-change lane is routed by one marker on the task state record. /cdd-next-step
# is the sole producer and cdd-worktree.sh the sole consumer, on two separate paths
# (launch and resume). A one-sided edit degrades silently to the standard lane — the safe
# direction, and exactly why nothing else would ever notice. Same shape as the
# branch-token check.
#
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

check_lane_marker() {
  grep -qF 'cdd-state lane' "$NEXT" \
    || note "lane-marker producer broken: $NEXT no longer writes the lane with \`cdd-state lane\`"
  grep -qF "'.lane // empty'" "$WT_HELPER" \
    || note "lane-marker consumer broken: $WT_HELPER no longer reads .lane from the state record"
  lane_routes_in cdd-worktree \
    || note "lane-marker consumer broken: cdd-worktree() in $WT_HELPER no longer launches /cdd-small-change"
  lane_routes_in cdd-worktree-resume \
    || note "lane-marker consumer broken: cdd-worktree-resume() in $WT_HELPER no longer routes a resumed task to /cdd-small-change"
  return 0
}

# --- Check: eligibility-heuristic wording -------------------------------------
# The heuristic decides which lane a task takes, and it is applied twice: once by
# /cdd-next-step when it recommends, once by /cdd-small-change when it re-checks and
# decides whether to take the off-ramp. Two commands applying two different sentences is
# a silent split. It is restated rather than cited because the template ships no copy of
# the process doc, so a pointer would dangle in every downstream project.
check_heuristic() {
  local heuristic="If you can state the finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard lane."
  local f
  for f in "$PROCESS_DOC_KB" "$NEXT" "$REPO_CMDS/cdd-small-change.md"; do
    grep -qF -- "$heuristic" "$f" \
      || note "eligibility-heuristic drift in $f: it no longer states the lane heuristic verbatim"
  done
  return 0
}

# --- Check: seam-check-count contract -----------------------------------------
# Same shape as the gate-count check, turned on this script: CHECKS above is the source
# of truth for how many seam checks there are, and four files restate that count in prose
# for four different audiences (the mutation harness, the pre-PR session, the practices
# contract, the architecture overview). Collapsing them into one was considered and
# rejected (issue #92) — as with the gate count, the restatements earn their keep, so they
# are pinned instead. Registered last, and so counts itself: it is a check, it runs, and
# `list` names it.
#
# Inherited weakness, deliberate, as with the gate count: this requires the correct count
# to be *present*, it does not forbid a stale one elsewhere in the same file.
check_check_count() {
  local n="${#CHECKS[@]}"
  local f
  for f in scripts/prompt-seam-assert.sh "$PRE" \
           doc/knowledge_base/engineering-practices.md doc/architecture/overview.md; do
    grep -qE "(^|[^0-9])$n (check|seam|case)s?([^a-z]|$)" "$f" && continue
    note "seam-count drift in $f: this checker registers $n checks; the file states:"
    grep -noE '[0-9]+ (check|seam|case)s?' "$f" | sed 's/^/    /' >&2 || true
  done
  return 0
}

# --- Dispatch -----------------------------------------------------------------
# A slug is kebab-case; its check function is snake_case, as in ci.sh.
fn_for_slug() { echo "check_${1//-/_}"; }

registry_slugs() {
  local entry
  for entry in "${CHECKS[@]}"; do
    echo "${entry%%|*}"
  done
}

# Unlike ci.sh, which runs each gate in a subshell for isolation, the checks run in the
# CURRENT shell: they report through note(), which sets the global `fail`, and a subshell
# would discard it. Do not "fix" this by wrapping the dispatch in a subshell or a pipe.
main() {
  case "${1:-}" in
    list) registry_slugs; return 0 ;;
    "")   ;;
    *)    echo "error: unknown argument: $1" >&2
          echo "usage: scripts/prompt-seam-check.sh [list]" >&2
          return 2 ;;
  esac

  local slug
  while IFS= read -r slug; do
    "$(fn_for_slug "$slug")"
  done < <(registry_slugs)

  if [[ "$fail" -ne 0 ]]; then
    echo "prompt-seam check: FAILED (see above)" >&2
    return 1
  fi
  echo "prompt-seam check: clean"
}

main "$@"
