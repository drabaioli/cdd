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
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

REPO_CMDS=".claude/commands"
WHITELIST="scripts/prompt-seam-whitelist.txt"

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
  '## 5. Draft the handoff' \
  '## 7. Write the handoff file' \
  '## 8. Print the next command'
require_headings "$REPO_CMDS/cdd-pre-pr.md" \
  '## 1. Identify changes' \
  '## 2. Build & QA' \
  '## 8. Summary' \
  '## 9. Commit reconciliation edits' \
  '## 10. Open PR (optional)'
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

if [[ "$fail" -ne 0 ]]; then
  echo "prompt-seam check: FAILED (see above)" >&2
  exit 1
fi
echo "prompt-seam check: clean"
