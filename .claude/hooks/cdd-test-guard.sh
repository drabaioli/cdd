#!/usr/bin/env bash
# CDD's test guard: a Claude Code PreToolUse hook on the edit tools (wired in
# .claude/settings.json). It asks the human before an edit to an existing test file that the
# approved plan does not name, so a test cannot be quietly rewritten to make the code pass.
# Why: doc/architecture/adr/0033-guard-existing-tests-with-a-hook.md; the rule: CDD process
# doc, section 2.12.
#
# This file belongs to CDD and changes with it (/cdd-retrofit carries those changes over);
# do not edit it locally.
#
# Inputs, and nothing else:
#   - the hook's JSON on stdin (tool_input.file_path, or tool_input.notebook_path);
#   - the `- Test paths:` line of doc/knowledge_base/engineering-practices.md: backticked shell
#     patterns matched against the repo-relative path, `*` also matching `/`;
#   - git: a file tracked at HEAD is existing, anything else is new;
#   - the task's plan file, ~/.cdd/handoffs/<repo>/<branch>.plan.md: a file named in backticks
#     in its `## File map` (alone or as a `file:line` pointer) is approved.
# It prints a permission decision of "ask" or nothing; never "allow", never "deny". Nothing to
# guard is a silent exit 0: not in a git repo, a file outside it or in a directory not yet
# created, no contract, no declared patterns, no match, not tracked at HEAD, named in the plan.
# Needs jq and git (CDD required tools); a missing jq exits non-zero, which Claude Code treats
# as a non-blocking error, so the edit goes ahead unguarded.
set -euo pipefail

input="$(cat)"
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[[ -n "$path" ]] || exit 0

# Physical path: git reports the top level that way (macOS temp dirs sit under a symlink).
dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || exit 0
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
rel="$dir/$(basename "$path")"
rel="${rel#"$root"/}"

contract="$root/doc/knowledge_base/engineering-practices.md"
[[ -f "$contract" ]] || exit 0
# shellcheck disable=SC2016 # the backticks are literal
patterns="$(grep -m1 '^- Test paths:' "$contract" | grep -o '`[^`]*`' | tr -d '`' || true)"

matched=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  # shellcheck disable=SC2254 # the pattern is meant to glob
  case "$rel" in $p) matched=1; break ;; esac
done <<<"$patterns"
[[ -n "$matched" ]] || exit 0

git -C "$root" cat-file -e "HEAD:$rel" 2>/dev/null || exit 0

repo="$(basename "$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")")"
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD)"
plan="$HOME/.cdd/handoffs/$repo/$branch.plan.md"
if [[ -f "$plan" ]]; then
  filemap="$(awk '/^## /{inmap = ($0 ~ /^## File map[[:space:]]*$/); next} inmap' "$plan")"
  if grep -qF -e "\`$rel\`" -e "\`$rel:" <<<"$filemap"; then
    exit 0
  fi
fi

jq -n --arg reason "$rel is an existing test, and the approved plan's File map does not name it. Approve only if this change to the test is intended." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
