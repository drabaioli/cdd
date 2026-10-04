#!/usr/bin/env bash
# CDD worktree helpers — one shared, project-independent helper for every CDD project.
#
# This single script is canonical: there is no per-project copy. The functions
# are fully repo-agnostic (repo name, default branch, and handoff dir are derived
# at runtime), so the same `cdd-worktree*` commands work in any CDD project.
#
# Install once (issue #18) — copies this script to a stable home that does NOT
# depend on a live CDD checkout, and wires your shell to source it:
#
#   tools/cdd-worktree.sh install
#
# On a machine without a CDD checkout (a fresh machine with only a downstream CDD
# project), fetch the canonical script to its home and run it in one step:
#
#   curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/cdd-worktree.sh \
#     --create-dirs -o ~/.cdd/tools/cdd-worktree.sh \
#     && bash ~/.cdd/tools/cdd-worktree.sh install
#
# (It must land on disk first; `curl ... | bash` won't work because install copies
# itself from its own file path, which a piped stdin does not provide.)
#
# Either form copies the helper to ~/.cdd/tools/cdd-worktree.sh, appends a
# marker-guarded source line to ~/.bashrc and ~/.zshrc (idempotent), and migrates
# any handoffs from the old ~/.claude-handoffs/ location. After installing, open a
# new shell; the CDD clone can then disappear and the commands still work.
#
# Run from a CDD checkout, install also copies the shipped capability adapters
# (tools/adapters/<cap>/<backend>.sh) to ~/.cdd/tools/adapters/ -- a library the
# committed .cdd/<cap> bindings exec, never a resolution-ladder rung (ADR 0011). The
# curl form above fetches only this file, so it prints the per-adapter curl form.
#
# The helper is a machine-global toolchain dependency, like git or gh: one install
# per machine, newest wins, install is idempotent (re-run to upgrade). Its contract
# with projects is frozen and deliberately tiny -- the three command names below
# plus the ~/.cdd/handoffs/<repo>/<branch>.md layout -- so a single current copy
# stays compatible with every project version. See the process doc section 2.8.
#
# Provides (when sourced):
#   cdd-worktree <branch>   Create a new worktree for <branch> and launch
#                               `claude` in it with the suggested first prompt
#                               already submitted. Requires a
#                               handoff file at
#                               ~/.cdd/handoffs/<repo-name>/<branch>.md (run
#                               /cdd-next-step first). Run from the main worktree.
#
#   cdd-worktree-done       After the feature branch has landed (or you've
#                               decided to abandon it), run this from the
#                               feature worktree to: cd to the main worktree,
#                               pull, remove the feature worktree (handling
#                               root-owned build artefacts via sudo, with
#                               confirmation), resolve the branch (safe-delete
#                               if merged, force-delete if squash-merged on
#                               the code host, otherwise prompt), close the
#                               issues recorded on the task's state record once a
#                               merged PR is confirmed (via the tracker adapter),
#                               and delete the handoff file iff the branch was
#                               deleted and every close succeeded.
#
#   cdd-worktree-list       List all active handoffs in ~/.cdd/handoffs/<repo-name>/
#                               with worktree / branch / PR status. Highlights
#                               stale entries (handoff with no branch and no
#                               worktree) so they're obvious to clean up.
#
#   cdd-worktree-resume [<branch>]
#                           Pick up a task started on another machine: recreate
#                               a worktree tracking an EXISTING remote branch
#                               (no handoff required) and cd into it, ready for
#                               you to run /cdd-implement (a task parked at
#                               plan_written), or /cdd-process-pr,
#                               /cdd-merge-base, or /cdd-pre-pr. With no
#                               argument, lists remote feature branches not
#                               already checked out and prompts for one. Run
#                               from the main worktree.
#
#   cdd-worktree-gc [--force]
#                           Reap the artifacts of FINISHED tasks: the local
#                               handoff + state record and the remote sync ref
#                               (refs/cdd/<branch>) for any task whose PR has
#                               merged, first closing the issues its state
#                               record lists (the backstop for done's close).
#                               Conservative — reaps only merged tasks (never a
#                               scoped-but-unstarted or open-PR one) and is
#                               dry-run unless --force. Needs a code-host
#                               adapter declaring pr-merged.
#
# PR lookups go through a code-host capability adapter (.cdd/code-host, then
# ~/.cdd/adapters/code-host); the default branch falls back to git. With none installed
# the PR-dependent steps skip with one line naming /cdd-retrofit (ADR 0012), and an
# installed-but-broken adapter stops the command that needs it (ADR 0010). See
# shell-helpers.md, "Code-host resolution".
# The post-merge issue close in done / gc resolves the tracker adapter the same way,
# only for a task that recorded issue refs. See shell-helpers.md, "Tracker resolution".

# Needs bash >= 4 (mapfile, local -A, ${var,,}). On bash 3.2 — stock macOS — the
# functions below would define fine and then fail mid-command, after side effects, so
# refuse up front: sourced, return before defining anything (the dispatching shims then
# report the missing function); executed, exit before install writes anything. Itself
# parseable by bash 3.2. Another shell (zsh) has no BASH_VERSION and is left as it was.
if [[ -n "${BASH_VERSION:-}" ]] && (( BASH_VERSINFO[0] < 4 )); then
  echo "cdd-worktree.sh: bash >= 4 required (found $BASH_VERSION); on macOS: brew install bash" >&2
  # shellcheck disable=SC2317  # the exit runs when executed rather than sourced
  return 1 2>/dev/null || exit 1
fi

# Resolve the capability adapter for <capability> down the ladder: the project's
# .cdd/<capability>, then the machine's ~/.cdd/adapters/<capability>; the first FILE
# present wins, so a broken project adapter never falls through to a machine one.
# Capability-generic: the post-merge issue close resolves `tracker` through it too.
#
# Publishes into the caller's scope (callers declare these `local`, and bash's dynamic
# scoping hands them to every function they call): CDD_ADAPTER (the path, empty when
# none) and CDD_ADAPTER_DESCRIBE (its describe JSON). Globals rather than stdout
# because a command substitution's subshell could not publish the describe as well.
# Returns 0 when a valid adapter serves (announcing it in one stderr line), 1 when none
# is installed (silent; callers say what they skip), 2 when one is installed but broken (after
# printing exactly one stderr line naming it and why).
cdd-worktree-adapter() {
  local cap="$1" top c path="" why="" desc="" rc=0 got
  CDD_ADAPTER="" CDD_ADAPTER_DESCRIBE=""
  # The worktree's top level, not $PWD: `done` may run from a subdirectory.
  top="$(git rev-parse --show-toplevel 2>/dev/null)"
  for c in ${top:+"$top/.cdd/$cap"} "$HOME/.cdd/adapters/$cap"; do
    [[ -e "$c" ]] && { path="$c"; break; }
  done
  [[ -z "$path" ]] && return 1

  if [[ ! -x "$path" ]]; then
    why="it is not executable"
  elif ! command -v jq >/dev/null 2>&1; then
    why="reading its describe needs jq, which is not installed"
  else
    # Keep describe's first stderr line: a failing binding says why there (e.g. a
    # shim whose adapter library is missing names the install command), and that
    # hint is only useful if it reaches the user through this one line.
    local errf errline=""
    if errf="$(mktemp 2>/dev/null)"; then
      desc="$("$path" describe 2>"$errf")" || rc=$?
      IFS= read -r errline <"$errf" || true
      rm -f "$errf"
    else
      desc="$("$path" describe 2>/dev/null)" || rc=$?
    fi
    got="$(jq -r '.capability // empty' <<<"$desc" 2>/dev/null)"
    if (( rc != 0 )); then
      why="describe exited $rc${errline:+: $errline}"
    elif ! jq -e . >/dev/null 2>&1 <<<"$desc"; then
      why="describe did not print JSON"
    elif [[ "$got" != "$cap" ]]; then
      why="describe reports capability '${got:-none}', not '$cap'"
    elif ! jq -e '.contract == 1' >/dev/null 2>&1 <<<"$desc"; then
      why="describe reports contract $(jq -c '.contract' <<<"$desc" 2>/dev/null), and only 1 is supported"
    fi
  fi
  local shown="$path"
  [[ -n "$top" ]] && shown="${path#"$top"/}"
  if [[ -n "$why" ]]; then
    echo "$cap adapter $shown is unusable: $why; fix or remove it." >&2
    return 2
  fi
  CDD_ADAPTER="$path" CDD_ADAPTER_DESCRIBE="$desc"
  echo "$cap: using adapter $shown ($(jq -r '.backend // "?"' <<<"$desc"))" >&2
  return 0
}

# Does the resolved adapter declare <verb> in describe.verbs?
cdd-worktree-adapter-has() {
  jq -e --arg v "$1" '.verbs | index($v)' >/dev/null 2>&1 <<<"${CDD_ADAPTER_DESCRIBE:-}"
}

# Run <verb> <arg>... on the resolved adapter ($CDD_ADAPTER). Its stdout lands in
# CDD_ADAPTER_OUT and its first stderr line in CDD_ADAPTER_ERR (globals, as above, so
# the call needs no subshell). Returns 0 ok; 3 when the verb is unsupported (absent
# from describe.verbs, or the adapter said 3), which callers treat as "no answer",
# silently; anything else is the adapter's failure code, for cdd-worktree-adapter-warn.
cdd-worktree-adapter-call() {
  local errf rc=0
  CDD_ADAPTER_OUT="" CDD_ADAPTER_ERR=""
  cdd-worktree-adapter-has "$1" || return 3
  errf="$(mktemp)" || return 1
  CDD_ADAPTER_OUT="$("$CDD_ADAPTER" "$@" 2>"$errf")" || rc=$?
  CDD_ADAPTER_ERR="$(head -1 "$errf")"
  rm -f "$errf"
  return "$rc"
}

cdd-worktree-adapter-warn() {  # cdd-worktree-adapter-warn <verb> <exit code>
  echo "warning: $1 failed (exit $2) via ${CDD_ADAPTER}${CDD_ADAPTER_ERR:+: $CDD_ADAPTER_ERR}; treating it as no answer." >&2
}

# Whether a merged PR's head commit <head> contains the local tip <tip>: it is the tip,
# or descends from it, so the PR merged every local commit. A branch behind its PR
# (fixes pushed from another machine, a commit made in the web UI) is still this
# branch's; a reused name's old PR does not contain the new commits. A head not present
# locally is fetched once, best-effort; still absent, it does not contain the tip.
cdd-worktree-tip-in-head() {
  local tip="$1" head="$2"
  [[ "${tip,,}" == "${head,,}" ]] && return 0
  git cat-file -e "${head}^{commit}" 2>/dev/null \
    || git fetch -q origin "$head" >/dev/null 2>&1 || return 1
  git merge-base --is-ancestor "$tip" "$head" 2>/dev/null
}

# Ask the code host whether <branch> merged into <base> through a PR: the caller's
# resolved adapter (CDD_ADAPTER). Prints "<PR number> <PR url>" on one line (the url may
# be absent: an adapter need not report it) whenever the PR merged. With <tip> (the
# local branch's full SHA) the PR's reported head_sha must contain it
# (cdd-worktree-tip-in-head), since a branch name can be reused and its old merged PR is
# then not this branch's. Returns:
#   0  merged (and, with <tip>, its head contains <tip>)
#   1  the host answered "not merged"
#   2  it could not answer (no adapter, a failing call, an unsupported verb); the caller
#      says why when none resolved
#   4  merged, but the adapter reported no head_sha to check against <tip>
#   5  merged, but the PR's head does not contain <tip>
# 4 and 5 print one stderr line each.
cdd-worktree-merged-pr() {
  local branch="$1" base="$2" tip="${3:-}" rc=0 head line
  [[ -n "${CDD_ADAPTER:-}" ]] || return 2
  cdd-worktree-adapter-call pr-merged "$branch" --base "$base" || rc=$?
  if (( rc == 0 )); then
    [[ "$(jq -r '.merged' <<<"$CDD_ADAPTER_OUT" 2>/dev/null)" == "true" ]] || return 1
    line="$(jq -r '"\(.ref // "?") \(.url // "")"' <<<"$CDD_ADAPTER_OUT")"
    printf '%s\n' "$line"
    [[ -z "$tip" ]] && return 0
    head="$(jq -r '.head_sha // empty' <<<"$CDD_ADAPTER_OUT" 2>/dev/null)"
    if [[ -z "$head" ]]; then
      echo "pr-merged reported no head commit for '$branch'; cannot confirm PR #${line%% *} is this branch's." >&2
      return 4
    fi
    if ! cdd-worktree-tip-in-head "$tip" "$head"; then
      echo "PR #${line%% *} merged head ${head:0:12}, which does not contain local '$branch' at ${tip:0:12}." >&2
      return 5
    fi
    return 0
  fi
  (( rc != 3 )) && cdd-worktree-adapter-warn pr-merged "$rc"
  return 2
}

# The one-line "nothing installed" notice for <capability>, naming what the caller skips
# (<skipped>, may be empty). The wording is shared with the command prompts (ADR 0012).
cdd-worktree-no-adapter() {  # cdd-worktree-no-adapter <capability> [<skipped>]
  echo "$1: no adapter installed; run /cdd-retrofit in this project to install one${2:+; $2}." >&2
}

# Read the issue refs recorded on <branch>'s state record into the caller's
# CDD_ISSUE_REFS array (declared `local -a` by the caller, like CDD_ADAPTER): the local
# record <state_file> when present, else the copy on origin's refs/cdd/<branch> — a
# read-only fetch, so a dry run may use it. Empty when neither exists or none is
# recorded. Returns 2 when a record mentions issue_refs but jq is missing to read it,
# which callers treat as a close that cannot happen yet: the record is kept.
cdd-worktree-issue-refs() {
  local branch="$1" state_file="$2" json=""
  CDD_ISSUE_REFS=()
  if [[ -f "$state_file" ]]; then
    json="$(cat "$state_file")"
  elif git fetch --quiet origin "refs/cdd/$branch" 2>/dev/null; then
    json="$(git show FETCH_HEAD:state.json 2>/dev/null)"
  fi
  [[ -z "$json" ]] && return 0
  if ! command -v jq >/dev/null 2>&1; then
    grep -q '"issue_refs"' <<<"$json" && return 2
    return 0
  fi
  mapfile -t CDD_ISSUE_REFS < <(jq -r '.issue_refs[]? | strings' <<<"$json" 2>/dev/null)
  return 0
}

# Resolve the tracker adapter into the caller's CDD_TRACKER / CDD_TRACKER_DESCRIBE /
# CDD_TRACKER_RC (0 adapter, 1 none installed, 2 broken), inside a scope of its
# own: both callers hold the code-host adapter in CDD_ADAPTER*, and gc keeps asking it
# pr-merged after a close, so the tracker must not overwrite it. The resolver's own
# line is the one announcement; callers resolve at most once per run.
cdd-worktree-resolve-tracker() {
  local CDD_ADAPTER="" CDD_ADAPTER_DESCRIBE="" rc=0
  cdd-worktree-adapter tracker || rc=$?
  CDD_TRACKER="$CDD_ADAPTER" CDD_TRACKER_DESCRIBE="$CDD_ADAPTER_DESCRIBE" CDD_TRACKER_RC="$rc"
}

# Close each <ref> through the tracker the caller resolved (CDD_TRACKER*): the adapter's
# `issue-transition <ref> closed`. One outcome line per ref
# — closed, already closed (a success: the PR's close line usually got there first), or
# a warning. An adapter without issue-transition skips the rest in one line; retrying
# would never help, so that is not a failure. Returns 1 when any ref failed, so the
# caller keeps the task's record and refs/cdd/<branch> for a later gc to retry.
#
# <pr-ref> and <pr-url> name the merged PR (either may be ""); each ref closed now — not
# one already closed, so a gc retry never comments twice — gets a comment linking it,
# via cdd-worktree-link-pr. Best-effort: a comment never affects the return code.
cdd-worktree-close-issues() {  # cdd-worktree-close-issues <pr-ref> <pr-url> <ref>...
  local CDD_ADAPTER="$CDD_TRACKER" CDD_ADAPTER_DESCRIBE="$CDD_TRACKER_DESCRIBE"
  local CDD_ADAPTER_OUT="" CDD_ADAPTER_ERR="" ref rc failed=0
  local pr="$1" pr_url="$2" CDD_LINK_UNSUPPORTED=0
  shift 2
  if [[ -n "$CDD_ADAPTER" ]]; then
    while (( $# )); do
      ref="$1" rc=0
      cdd-worktree-adapter-call issue-transition "$ref" closed || rc=$?
      if (( rc == 0 )); then
        if [[ "$(jq -r '.changed' <<<"$CDD_ADAPTER_OUT" 2>/dev/null)" == "false" ]]; then
          echo "issue $ref: already closed"
        else
          echo "issue $ref: closed"
          cdd-worktree-link-pr "$ref" "$pr" "$pr_url"
        fi
      elif (( rc == 3 )); then
        echo "tracker $CDD_ADAPTER does not support issue-transition; not closing $*." >&2
        return "$failed"
      else
        echo "warning: could not close issue $ref (exit $rc) via ${CDD_ADAPTER}${CDD_ADAPTER_ERR:+: $CDD_ADAPTER_ERR}" >&2
        failed=1
      fi
      shift
    done
    return "$failed"
  fi

  cdd-worktree-no-adapter tracker "not closing $*"
  return 1
}

# Comment on <ref>, just closed, that the merged PR closed it: the tracker adapter's
# `issue-comment` (CDD_ADAPTER, as scoped by cdd-worktree-close-issues; callers only
# reach it with one). One line. Without issue-comment the adapter is told once per
# close-issues call (CDD_LINK_UNSUPPORTED, its local) and the rest are skipped. Never
# fails: a missing link is not worth keeping a task's record for.
cdd-worktree-link-pr() {  # cdd-worktree-link-pr <ref> <pr-ref> <pr-url>
  local ref="$1" pr="$2" url="$3" label body rc=0
  [[ "$pr" == "?" ]] && pr=""
  [[ -z "$pr" && -z "$url" ]] && return 0
  label="PR${pr:+ #$pr}"
  if [[ -n "$url" ]]; then
    body="Closed after $label merged: $url"
  else
    body="Closed after $label merged."
  fi
  if [[ -n "$CDD_ADAPTER" ]]; then
    (( CDD_LINK_UNSUPPORTED )) && return 0
    cdd-worktree-adapter-call issue-comment "$ref" --body "$body" || rc=$?
    if (( rc == 0 )); then
      echo "issue $ref: linked $label"
    elif (( rc == 3 )); then
      CDD_LINK_UNSUPPORTED=1
      echo "tracker $CDD_ADAPTER does not support issue-comment; not linking $label on the issues it closes." >&2
    else
      echo "warning: could not link $label on issue $ref (exit $rc) via ${CDD_ADAPTER}${CDD_ADAPTER_ERR:+: $CDD_ADAPTER_ERR}" >&2
    fi
  fi
  return 0
}

# Resolve the repo's default branch: the code-host adapter's `default-branch` when one
# serves, else origin's HEAD, falling back to "main". The remote is assumed to be
# named "origin" (see template/BOOTSTRAP.md). With --resolved, reuse the caller's
# already-resolved adapter (CDD_ADAPTER, possibly empty) instead of resolving again,
# so a command announces its adapter once. Returns 1 when the adapter is broken.
cdd-worktree-default-branch() {
  local ref rc=0 branch=""
  if [[ "${1:-}" != "--resolved" ]]; then
    local CDD_ADAPTER="" CDD_ADAPTER_DESCRIBE="" CDD_ADAPTER_OUT="" CDD_ADAPTER_ERR=""
    cdd-worktree-adapter code-host || rc=$?
    if (( rc == 2 )); then return 1; fi
  fi
  if [[ -n "${CDD_ADAPTER:-}" ]]; then
    # Git is the repository itself, not a lower backend rung: an adapter with no
    # answer (unsupported, failed) still leaves origin/HEAD as the honest fallback.
    rc=0
    cdd-worktree-adapter-call default-branch || rc=$?
    if (( rc == 0 )); then
      branch="$(jq -r '.branch // empty' <<<"$CDD_ADAPTER_OUT" 2>/dev/null)"
    elif (( rc != 3 )); then
      cdd-worktree-adapter-warn default-branch "$rc"
    fi
    [[ -n "$branch" ]] && { printf '%s\n' "$branch"; return 0; }
  fi
  if ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${ref#origin/}"
  else
    printf 'main\n'
  fi
}

cdd-worktree() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "usage: cdd-worktree <branch>" >&2
    return 1
  fi
  # An option-shaped argument is never a branch name, and these commands take the branch
  # positionally with no flags in front of it. Without this guard `cdd-worktree --help`
  # took "--help" AS the branch and went on to cut a branch and a worktree called that;
  # the sibling state helper did the same and force-pushed refs/cdd/--help to origin.
  case "$branch" in
    -h|--help) echo "usage: cdd-worktree <branch>" >&2; return 0 ;;
    -*) echo "cdd-worktree: '$branch' looks like an option, not a branch name." >&2; return 2 ;;
  esac

  # The sibling worktree name is derived from $PWD; run from a feature worktree
  # this would nest names, so insist on the main worktree. git-dir == git-common-dir
  # only in the main worktree (a linked worktree's git-dir is .git/worktrees/<name>),
  # so this allows a gitflow main worktree sitting on a non-default branch.
  local git_dir common_dir
  git_dir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  if [[ "$git_dir" != "$common_dir" ]]; then
    echo "Run this from the main worktree, not a feature worktree." >&2
    return 1
  fi

  # Derive repo name from the main worktree so this works from any worktree.
  local repo_name
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
  local handoff_dir="$HOME/.cdd/handoffs/${repo_name}"
  local handoff="${handoff_dir}/${branch}.md"
  if [[ ! -f "$handoff" ]]; then
    echo "No handoff file at $handoff" >&2
    echo "Run /cdd-next-step in an exploratory session first to produce one." >&2
    return 1
  fi

  # Cut the new branch from the task's recorded base branch (§2.13), falling back
  # to the default branch when none was recorded. Prefer a local base branch, else
  # origin/<base> (fetched best-effort); an unresolved base drops to current HEAD.
  local base_branch="" start_point=""
  if command -v jq >/dev/null 2>&1 && [[ -f "${handoff_dir}/${branch}.state.json" ]]; then
    base_branch="$(jq -r '.base_branch // empty' "${handoff_dir}/${branch}.state.json" 2>/dev/null)"
  fi
  # Only here does the code-host adapter get resolved, and only when no base was
  # recorded; a broken one stops before any branch or worktree is created.
  if [[ -z "$base_branch" ]]; then
    base_branch="$(cdd-worktree-default-branch)" || return 1
  fi
  if git show-ref --verify --quiet "refs/heads/$base_branch"; then
    start_point="$base_branch"
  else
    git fetch --quiet origin "$base_branch" 2>/dev/null || true
    git show-ref --verify --quiet "refs/remotes/origin/$base_branch" && start_point="origin/$base_branch"
  fi
  [[ -z "$start_point" ]] \
    && echo "Base branch '$base_branch' not found locally or on origin; cutting from current HEAD." >&2

  local repo_dir
  repo_dir="$(basename "$PWD")"
  local worktree_path="../${repo_dir}-${branch}"

  echo "Cutting '$branch' from ${start_point:-current HEAD}."
  local -a start=()
  [[ -n "$start_point" ]] && start=("$start_point")
  git worktree add -b "$branch" "$worktree_path" "${start[@]}" || return 1
  cd "$worktree_path" || return 1

  # Capability probe, not a version check (§2.8): ask the worktree whether this
  # project has the plan/implement split. No marker to go stale.
  local -a launch=("/cdd-plan")
  if [[ -f .claude/commands/cdd-plan.md ]]; then
    # Reverse skew the probe cannot see: an installed cdd-state predating the split
    # would reject `set plan_written` and stall the task silently.
    if ! cdd-state stages 2>/dev/null | grep -qx plan_written; then
      echo "This project uses the plan/implement split, but your cdd-state helper is" >&2
      echo "missing or predates it. Reinstall: ./tools/cdd-state.sh install" >&2
    fi
    # Lane routing (§2.13): a task the human declared small at scoping replaces
    # plan+implement with the single /cdd-small-change session. Every miss — no jq,
    # no record, no marker, a project that ships no such command — leaves the
    # /cdd-plan default, so a missing marker can never skip a gate. $handoff_dir is
    # absolute, so it still resolves after the cd into the new worktree.
    local lane=""
    if command -v jq >/dev/null 2>&1 && [[ -f "${handoff_dir}/${branch}.state.json" ]]; then
      lane="$(jq -r '.lane // empty' "${handoff_dir}/${branch}.state.json" 2>/dev/null)"
    fi
    [[ "$lane" == "small" && -f .claude/commands/cdd-small-change.md ]] \
      && launch=("/cdd-small-change")
  else
    # DEPRECATION SEAM: pre-split flow, whose checkpoint was plan mode. Remove once
    # every project is retrofitted (issue #90); needs `## Implementation prompt`.
    launch=(--permission-mode plan "Read ${handoff} and follow the Implementation prompt.")
  fi
  claude "${launch[@]}"
}

cdd-worktree-done() {
  # Resolve the code-host adapter before anything else: a broken one must stop the
  # command before the cd, the pull, or the worktree removal below.
  local CDD_ADAPTER="" CDD_ADAPTER_DESCRIBE="" CDD_ADAPTER_OUT="" CDD_ADAPTER_ERR="" rc=0
  cdd-worktree-adapter code-host || rc=$?
  if (( rc == 2 )); then return 1; fi
  # No code host: merged-PR detection is skipped, so a branch git cannot prove merged
  # falls to the keep/delete/abort prompt below rather than being reaped silently.
  (( rc == 1 )) && cdd-worktree-no-adapter code-host "not detecting merged PRs; unmerged branches ask before deletion"
  local default_branch
  default_branch="$(cdd-worktree-default-branch --resolved)"
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  if [[ -z "$branch" || "$branch" == "$default_branch" || "$branch" == "HEAD" ]]; then
    echo "Run this from the feature branch worktree, not $default_branch (current: '$branch')." >&2
    return 1
  fi

  # Untracked files count too: `git worktree remove` would refuse them later anyway, and
  # refusing here names them before anything has moved. Porcelain paths are relative to
  # the worktree root, whatever the cwd.
  local dirty n
  dirty="$(git status --porcelain)" || return 1
  if [[ -n "$dirty" ]]; then
    echo "Worktree has uncommitted changes or untracked files, aborting:" >&2
    head -n 10 <<<"$dirty" >&2
    n="$(wc -l <<<"$dirty")"
    (( n > 10 )) && echo "… and $(( n - 10 )) more" >&2
    return 1
  fi

  local main_path
  main_path="$(git worktree list --porcelain | awk -v ref="refs/heads/$default_branch" '
    $1 == "worktree" { path = $2 }
    $1 == "branch"   && $2 == ref { print path; exit }
  ')"
  if [[ -z "$main_path" ]]; then
    echo "Could not locate a worktree checked out on $default_branch, aborting." >&2
    return 1
  fi

  # The worktree's top level, not $PWD: run from a subdirectory, $PWD would name only it.
  local feature_path
  feature_path="$(git rev-parse --show-toplevel)" || return 1
  # A locked worktree would refuse the removal in step 3, after the issues are closed;
  # refuse it here instead, before anything has moved. The lock is the `locked` file in
  # this worktree's own git dir (its content is the reason, possibly empty).
  local lock_file
  lock_file="$(git rev-parse --absolute-git-dir)/locked" || return 1
  if [[ -f "$lock_file" ]]; then
    local lock_reason
    lock_reason="$(head -n 1 "$lock_file")"
    echo "Worktree $feature_path is locked${lock_reason:+ ($lock_reason)}." >&2
    echo "Unlock it first (git worktree unlock \"$feature_path\"). Nothing was deleted." >&2
    return 1
  fi
  # Derive repo name from the main worktree so this works from any worktree.
  local repo_name
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
  local handoff="$HOME/.cdd/handoffs/${repo_name}/${branch}.md"
  # The per-task state record (written by the slash commands) is an additive
  # sibling of the handoff; it shares the handoff's deletion lifecycle. So does the
  # plan file (§2.15).
  local state_file="${handoff%.md}.state.json"
  local plan_file="${handoff%.md}.plan.md"

  # The task's issue refs, read now: the state record and refs/cdd/<branch> carrying
  # them are deleted below. Only a task that recorded refs resolves the tracker, so a
  # broken tracker adapter never blocks one that did not; when it is broken it stops
  # here, before the cd, the pull or the worktree removal, as a broken code host does.
  # Resolving before the cd also finds the feature worktree's own .cdd/tracker; every
  # call through it happens before that worktree is removed (see "Order" below).
  local -a CDD_ISSUE_REFS=()
  local CDD_TRACKER="" CDD_TRACKER_DESCRIBE="" CDD_TRACKER_RC="" refs_unread=0
  cdd-worktree-issue-refs "$branch" "$state_file" || refs_unread=1
  if (( ${#CDD_ISSUE_REFS[@]} )); then
    cdd-worktree-resolve-tracker
    if (( CDD_TRACKER_RC == 2 )); then return 1; fi
  fi

  cd "$main_path" || return 1
  if ! git pull --ff-only origin "$default_branch"; then
    echo "git pull failed, aborting before cleanup." >&2
    return 1
  fi

  # Order: decide the branch's fate and close its issues BEFORE removing the worktree.
  # The adapters may be bound at the project rung inside the feature worktree (often a
  # relative .cdd/ symlink into the worktree's own tools/adapters/), so every adapter
  # call has to happen while it still exists. Deciding before destroying also means an
  # abort at the prompt leaves everything in place.

  # 1. Branch resolution. The branch is only marked for deletion here (a branch checked
  # out in a worktree cannot be deleted); step 4 deletes it. Closing the task's issues
  # needs a merged PR the code host confirms: git's ancestry alone also holds for an
  # abandoned zero-commit branch, so on that path a task with refs asks the code host
  # too. The PR must also be THIS branch's: its reported head commit has to contain the
  # local tip (a reused branch name's old merged PR does not), so an unknown head counts
  # as unconfirmed and one that does not contain it as no merged PR — neither
  # force-deletes.
  local delete_mode="" branch_deleted=0 pr_merged=0 pr_unknown=0 pr_mismatch=0 pr_num="" pr_url="" pr_line="" prc tip
  tip="$(git rev-parse --verify -q "refs/heads/$branch")"

  if git branch --merged "$default_branch" --format='%(refname:short)' | grep -qx "$branch"; then
    delete_mode=-d
    if (( ${#CDD_ISSUE_REFS[@]} )); then
      prc=0
      pr_line="$(cdd-worktree-merged-pr "$branch" "$default_branch" "$tip")" || prc=$?
      (( prc == 0 )) && pr_merged=1
      (( prc == 2 || prc == 4 )) && pr_unknown=1
      (( prc == 5 )) && pr_mismatch=1
    fi
  else
    prc=0
    pr_line="$(cdd-worktree-merged-pr "$branch" "$default_branch" "$tip")" || prc=$?
    pr_num="${pr_line%% *}"
    (( prc == 2 || prc == 4 )) && pr_unknown=1
    (( prc == 5 )) && pr_mismatch=1
    if (( prc == 0 )); then
      echo "Branch '$branch' was squash-merged via PR #$pr_num, force-deleting."
      delete_mode=-D
      pr_merged=1
    else
      echo
      if (( prc == 5 )); then
        echo "Branch '$branch' is not merged into $default_branch; merged PR #$pr_num is for other commits than its tip, so it was not force-deleted."
      elif (( prc == 4 )); then
        echo "Branch '$branch' is not merged into $default_branch; PR #$pr_num merged, but the code host did not report its head commit, so it cannot be confirmed as this branch's."
      elif (( prc == 2 )); then
        echo "Branch '$branch' is not merged into $default_branch, and no merged PR could be confirmed."
      else
        echo "Branch '$branch' is not merged into $default_branch and has no merged PR."
      fi
      echo "Unmerged commits:"
      git log "$default_branch".."$branch" --oneline
      echo
      local choice
      read -r -p "[d]elete (-D) / [k]eep / [a]bort? " choice
      case "$choice" in
        d|D)
          delete_mode=-D
          ;;
        k|K)
          echo "Keeping branch '$branch'. Handoff will also be kept (in-flight task)."
          ;;
        a|A|*)
          echo "Aborted. Nothing was removed: worktree, branch and handoff left in place." >&2
          return 1
          ;;
      esac
    fi
  fi

  # 2. Close the task's issues (only once a merged PR is confirmed, and only for a
  # branch about to be deleted). A close that failed, or could not be attempted yet,
  # keeps the record and refs/cdd/<branch> — the only carriers of the refs — so
  # cdd-worktree-gc can retry it. If step 3 then fails, the issues stay closed and
  # step 3 says so; a re-run finds them already closed and posts no second link.
  local keep_for_gc=0 closed_note=""
  if [[ -n "$delete_mode" ]]; then
    if (( refs_unread )); then
      echo "warning: the state record lists issue refs, but reading them needs jq; not closing them." >&2
      keep_for_gc=1
    elif (( ${#CDD_ISSUE_REFS[@]} )); then
      if (( pr_merged )); then
        # "<number> <url>": the url is whatever follows the first space, possibly nothing.
        pr_num="${pr_line%% *}"
        [[ "$pr_line" == *" "* ]] && pr_url="${pr_line#* }"
        cdd-worktree-close-issues "$pr_num" "$pr_url" "${CDD_ISSUE_REFS[@]}" || keep_for_gc=1
        closed_note="The issue close above has already run; re-run cdd-worktree-done once the worktree can be removed (a closed issue reads as already closed, and is not linked twice)."
      elif (( pr_unknown )); then
        echo "warning: could not confirm a merged PR for '$branch'; not closing ${CDD_ISSUE_REFS[*]} yet." >&2
        keep_for_gc=1
      elif (( pr_mismatch )); then
        echo "Not closing ${CDD_ISSUE_REFS[*]}: merged PR #${pr_line%% *} is for other commits than '$branch'."
      else
        echo "Not closing ${CDD_ISSUE_REFS[*]}: no merged PR for '$branch'."
      fi
    fi
  fi

  # 3. Worktree removal. No adapter is called past this point. sudo is offered ONLY for
  # a permission error (root-owned build artefacts, which git deletes as ignored
  # files); any other failure — a path that is not a worktree, a lock taken since the
  # check above — aborts with nothing deleted locally. LC_ALL=C because git's and
  # strerror's messages are localized, and the match below reads them.
  local rm_err
  if ! rm_err="$(LC_ALL=C git worktree remove "$feature_path" 2>&1)"; then
    case "$rm_err" in
      *"Permission denied"*|*"Operation not permitted"*) ;;
      *)
        echo "git worktree remove failed for $feature_path: $rm_err" >&2
        if [[ -n "$closed_note" ]]; then
          echo "Worktree left in place; nothing local was deleted. $closed_note" >&2
        else
          echo "Nothing was deleted; worktree left in place." >&2
        fi
        return 1
        ;;
    esac
    echo
    echo "git worktree remove hit a permission error for $feature_path:"
    echo "  $(head -n 1 <<<"$rm_err")"
    echo "This usually means container builds left root-owned files behind"
    echo "(e.g. build/, .cache/) that your user can't delete."
    echo "Falling back to: sudo rm -rf \"$feature_path\" && git worktree prune"
    read -r -p "Proceed with sudo rm -rf? [y/N] " reply
    if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
      echo "Aborted. Worktree left in place.${closed_note:+ $closed_note}" >&2
      return 1
    fi
    if ! sudo rm -rf "$feature_path"; then
      [[ -n "$closed_note" ]] && echo "$closed_note" >&2
      return 1
    fi
    git worktree prune
  fi

  # 4. Delete the branch as decided in step 1.
  if [[ -n "$delete_mode" ]]; then
    git branch "$delete_mode" "$branch" && branch_deleted=1
  fi

  # 5. Delete the handoff, plan and state record — only if the branch was actually
  # deleted and no issue close is pending.
  if (( branch_deleted && ! keep_for_gc )); then
    [[ -f "$handoff" ]] && rm "$handoff" && echo "Removed handoff: $handoff"
    [[ -f "$plan_file" ]] && rm "$plan_file" && echo "Removed plan: $plan_file"
    [[ -f "$state_file" ]] && rm "$state_file" && echo "Removed state: $state_file"
    # Best-effort: drop the per-task sync ref on origin so refs/cdd/* doesn't
    # accumulate. Advisory — a failed delete (no such ref, offline) never blocks.
    if git push origin --delete "refs/cdd/$branch" 2>/dev/null; then
      echo "Removed remote task ref: refs/cdd/$branch"
    fi
  else
    [[ -f "$handoff" ]] && echo "Kept handoff: $handoff"
    [[ -f "$plan_file" ]] && echo "Kept plan: $plan_file"
    [[ -f "$state_file" ]] && echo "Kept state: $state_file"
    (( keep_for_gc )) \
      && echo "Kept state record and refs/cdd/$branch so cdd-worktree-gc can retry closing the issue(s)."
  fi

  echo "Done. In $main_path on $default_branch at $(git rev-parse --short HEAD)."
}

# Print the task branches that have a handoff in $1, one per line.
#
# THE ONE PLACE that reads the handoff directory (§2.15): a bare *.md glob matches
# <branch>.plan.md too, and basename'ing that yields a phantom "<branch>.plan" task.
# Both callers (cdd-worktree-list, cdd-worktree-gc) go through here rather than
# repeating the filter.
cdd-worktree-handoff-branches() {
  local dir="$1" f
  shopt -s nullglob
  for f in "$dir"/*.md; do
    [[ "$f" == *.plan.md ]] && continue
    basename "$f" .md
  done
  shopt -u nullglob
}

cdd-worktree-list() {
  # Derive repo name from the main worktree so this works from any worktree.
  local repo_name
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
  local handoff_dir="$HOME/.cdd/handoffs/${repo_name}"
  if [[ ! -d "$handoff_dir" ]]; then
    echo "No handoff directory at $handoff_dir."
    return 0
  fi

  local branches=()
  mapfile -t branches < <(cdd-worktree-handoff-branches "$handoff_dir")
  if (( ${#branches[@]} == 0 )); then
    echo "No handoffs in $handoff_dir."
    return 0
  fi

  # A broken code-host adapter is reported (by the resolver) but does not stop a
  # read-only listing: its PR column just shows "-". With none installed it says so once.
  local CDD_ADAPTER="" CDD_ADAPTER_DESCRIBE="" CDD_ADAPTER_OUT="" CDD_ADAPTER_ERR=""
  local adapter_rc=0 use_adapter=0 warned=0 crc
  cdd-worktree-adapter code-host || adapter_rc=$?
  (( adapter_rc == 0 )) && use_adapter=1
  (( adapter_rc == 1 )) && cdd-worktree-no-adapter code-host "no PR status shown"

  # Snapshot worktree branches once.
  local worktree_branches
  worktree_branches="$(git worktree list --porcelain 2>/dev/null \
                        | awk '$1 == "branch" { sub("refs/heads/", "", $2); print $2 }')"

  printf '%-40s  %-8s  %-8s  %-12s  %s\n' \
         "BRANCH" "WORKTREE" "BRANCH?" "PR" "STATUS"
  printf '%-40s  %-8s  %-8s  %-12s  %s\n' \
         "------" "--------" "-------" "--" "------"

  local branch wt br pr status
  for branch in "${branches[@]}"; do
    if grep -qx "$branch" <<<"$worktree_branches"; then
      wt="yes"
    else
      wt="no"
    fi

    if git show-ref --verify --quiet "refs/heads/$branch"; then
      br="yes"
    else
      br="no"
    fi

    pr="-"
    local pr_line=""
    if (( use_adapter )); then
      crc=0
      cdd-worktree-adapter-call pr-for-branch "$branch" || crc=$?
      if (( crc == 0 )); then
        # Upcased NORMALIZED state, so the *MERGED* status test below holds for any backend.
        pr_line="$(jq -r '.[0] | select(.) | "#\(.ref) \(.state|ascii_upcase)"' \
                     <<<"$CDD_ADAPTER_OUT" 2>/dev/null)"
      elif (( crc == 3 )); then
        use_adapter=0
      elif (( ! warned )); then
        cdd-worktree-adapter-warn pr-for-branch "$crc"
        warned=1
      fi
    fi
    [[ -n "$pr_line" ]] && pr="$pr_line"

    if [[ "$wt" == "no" && "$br" == "no" ]]; then
      status="STALE, safe to remove handoff"
    elif [[ "$pr" == *MERGED* && "$wt" == "no" ]]; then
      status="merged, run cdd-worktree-done from worktree (or rm handoff)"
    elif [[ "$wt" == "yes" ]]; then
      status="active"
    else
      status="branch present, no worktree"
    fi

    printf '%-40s  %-8s  %-8s  %-12s  %s\n' \
           "$branch" "$wt" "$br" "$pr" "$status"
  done
}

# Garbage-collect the artifacts of FINISHED tasks: the local handoff, plan file and
# state record, and the remote sync ref refs/cdd/<branch>. This is the safety net for
# the cleanup in cdd-worktree-done never running, its remote-ref delete failing while
# offline, or a task resumed on several machines leaving materialized copies behind on
# every machine but the one where `done` ran. It reaps ONLY tasks whose PR has merged — the
# same signal cdd-worktree-done trusts — so it never touches a task that is merely
# scoped-but-unstarted (the handoff and ref exist before the branch does, §2.6/§2.13)
# or one with an open PR: those are indistinguishable from a finished task by ref or
# branch presence alone, and only the PR state tells them apart. Before reaping a
# merged task it closes the issues its state record lists — the backstop for the same
# close in cdd-worktree-done — and a failed close keeps the task for the next run.
# When the branch still exists locally and the merged PR's reported head_sha does not
# contain its tip (cdd-worktree-tip-in-head), the name was reused and the task is
# kept; with no local branch or no head_sha there is nothing to compare, and gc trusts
# the PR state as before.
# Dry-run by default (it lists what it would close, and calls no tracker verb);
# --force actually closes and deletes. Needs a code-host adapter to read PR state;
# without one a merged task can't be told from a fresh one, so it reaps nothing (one
# advisory line, ADR 0012). See shell-helpers.md.
cdd-worktree-gc() {
  local force=0
  case "${1:-}" in
    --force|-f) force=1 ;;
    "") ;;
    *) echo "usage: cdd-worktree-gc [--force]" >&2; return 2 ;;
  esac

  # A broken code-host adapter stops GC outright: it deletes things, and without the
  # adapter's answer it cannot tell a merged task from a scoped one.
  local CDD_ADAPTER="" CDD_ADAPTER_DESCRIBE="" CDD_ADAPTER_OUT="" CDD_ADAPTER_ERR="" rc=0
  cdd-worktree-adapter code-host || rc=$?
  if (( rc == 2 )); then return 1; fi

  if [[ -z "$CDD_ADAPTER" ]]; then
    cdd-worktree-no-adapter code-host "a merged task cannot be told from a just-scoped one, so nothing is reaped (advisory)"
    return 0
  fi
  if ! cdd-worktree-adapter-has pr-merged; then
    echo "cdd-worktree-gc: $CDD_ADAPTER does not support pr-merged, so a merged task cannot" >&2
    echo "be told from a just-scoped one; nothing can be safely reaped. Skipping (advisory)." >&2
    return 0
  fi

  local repo_name
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")" || return 1
  local handoff_dir="$HOME/.cdd/handoffs/${repo_name}"

  # Candidate branches = local handoff/state basenames ∪ remote refs/cdd/* names.
  # Plans need no glob: a task with a plan always has a handoff.
  # Track which refs exist on origin so the reap reports and acts accurately.
  local -A seen=() has_ref=()
  local f branch ref
  while IFS= read -r branch; do
    [[ -n "$branch" ]] && seen["$branch"]=1
  done < <(cdd-worktree-handoff-branches "$handoff_dir")
  shopt -s nullglob
  for f in "$handoff_dir"/*.state.json; do seen["$(basename "$f" .state.json)"]=1; done
  shopt -u nullglob
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    branch="${ref#refs/cdd/}"
    seen["$branch"]=1
    has_ref["$branch"]=1
  done < <(git ls-remote origin 'refs/cdd/*' 2>/dev/null | awk '{print $2}')

  if (( ${#seen[@]} == 0 )); then
    echo "No task artifacts found (no local handoffs, no refs/cdd/* on origin)."
    return 0
  fi

  # The tracker is resolved lazily, at the first merged task that recorded issue refs,
  # and once per run: a broken tracker adapter then keeps only the tasks with refs,
  # and a run with none never touches the tracker at all.
  local CDD_TRACKER="" CDD_TRACKER_DESCRIBE="" CDD_TRACKER_RC="" closing
  local -a CDD_ISSUE_REFS=()
  local reaped=0 kept=0 pr_state pr_ref pr_url pr_head pr_tip handoff plan state items joined
  for branch in "${!seen[@]}"; do
    pr_ref="" pr_url=""
    rc=0
    cdd-worktree-adapter-call pr-merged "$branch" || rc=$?
    if (( rc == 0 )); then
      pr_state="not merged"
      if [[ "$(jq -r '.merged' <<<"$CDD_ADAPTER_OUT" 2>/dev/null)" == "true" ]]; then
        pr_state="MERGED"
        pr_ref="$(jq -r '.ref // ""' <<<"$CDD_ADAPTER_OUT")"
        pr_url="$(jq -r '.url // ""' <<<"$CDD_ADAPTER_OUT")"
        # A local branch the merged PR's head does not contain: the name was reused,
        # and that PR is not this task's.
        pr_head="$(jq -r '.head_sha // empty' <<<"$CDD_ADAPTER_OUT")"
        pr_tip="$(git rev-parse --verify -q "refs/heads/$branch" 2>/dev/null)"
        if [[ -n "$pr_head" && -n "$pr_tip" ]] && ! cdd-worktree-tip-in-head "$pr_tip" "$pr_head"; then
          pr_state="merged PR #$pr_ref is for other commits than local $branch"
        fi
      fi
    elif (( rc == 3 && reaped + kept == 0 )); then
      # Declared but unsupported at runtime, on the first call: nothing has been
      # reaped yet, so skipping the whole run is still honest.
      echo "cdd-worktree-gc: $CDD_ADAPTER does not support pr-merged, so a merged task cannot" >&2
      echo "be told from a just-scoped one; nothing can be safely reaped. Skipping (advisory)." >&2
      return 0
    elif (( rc == 3 )); then
      # Unsupported only after earlier calls answered: some tasks may already be
      # reaped, so keep this one and let the run finish with its summary.
      echo "warning: pr-merged unsupported for $branch via ${CDD_ADAPTER}; keeping it." >&2
      pr_state="PR state unknown"
    else
      cdd-worktree-adapter-warn pr-merged "$rc"
      pr_state="PR state unknown"
    fi
    if [[ "$pr_state" != "MERGED" ]]; then
      kept=$(( kept + 1 ))
      echo "keep  $branch (${pr_state:-no PR yet} — in-flight or scoped, not reaped)"
      continue
    fi

    # Merged → finished → close its issues, then reap the local handoff/plan/state
    # and the remote ref.
    handoff="${handoff_dir}/${branch}.md"
    plan="${handoff_dir}/${branch}.plan.md"
    state="${handoff_dir}/${branch}.state.json"
    CDD_ISSUE_REFS=() closing=""
    if [[ -f "$state" || -n "${has_ref[$branch]:-}" ]] \
       && ! cdd-worktree-issue-refs "$branch" "$state"; then
      kept=$(( kept + 1 ))
      echo "keep  $branch (MERGED, issue refs recorded but reading them needs jq; not reaped)"
      continue
    fi
    if (( ${#CDD_ISSUE_REFS[@]} )); then
      [[ -z "$CDD_TRACKER_RC" ]] && cdd-worktree-resolve-tracker
      if (( CDD_TRACKER_RC == 2 )); then
        kept=$(( kept + 1 ))
        if (( force )); then
          echo "keep  $branch (MERGED, tracker adapter unusable: issues ${CDD_ISSUE_REFS[*]} not closed)"
        else
          echo "keep  $branch (MERGED): tracker adapter unusable, would not reap until it is fixed"
        fi
        continue
      fi
      if (( CDD_TRACKER_RC == 1 )); then
        kept=$(( kept + 1 ))
        if (( force )); then
          echo "keep  $branch (MERGED, no tracker adapter: issues ${CDD_ISSUE_REFS[*]} not closed)"
        else
          echo "keep  $branch (MERGED): no tracker adapter, would not reap until one is installed"
        fi
        cdd-worktree-no-adapter tracker "not closing ${CDD_ISSUE_REFS[*]}"
        continue
      fi
      if (( ! force )); then
        closing="; would close ${CDD_ISSUE_REFS[*]}"
      elif ! cdd-worktree-close-issues "$pr_ref" "$pr_url" "${CDD_ISSUE_REFS[@]}"; then
        kept=$(( kept + 1 ))
        echo "keep  $branch (MERGED, issue close failed; kept so the next gc retries)"
        continue
      fi
    fi
    reaped=$(( reaped + 1 ))
    items=()
    [[ -f "$handoff" ]] && items+=("handoff")
    [[ -f "$plan" ]] && items+=("plan")
    [[ -f "$state" ]] && items+=("state")
    [[ -n "${has_ref[$branch]:-}" ]] && items+=("refs/cdd/$branch")
    joined="$(IFS=,; echo "${items[*]}")"
    if (( force )); then
      [[ -f "$handoff" ]] && rm -f "$handoff"
      [[ -f "$plan" ]] && rm -f "$plan"
      [[ -f "$state" ]] && rm -f "$state"
      [[ -n "${has_ref[$branch]:-}" ]] && git push origin --delete "refs/cdd/$branch" 2>/dev/null
      echo "reap  $branch (MERGED): removed ${joined:-nothing present}"
    else
      echo "reap  $branch (MERGED): would remove ${joined:-nothing present}${closing}"
    fi
  done

  echo
  if (( force )); then
    echo "GC complete: reaped $reaped finished task(s), kept $kept."
  else
    echo "GC dry-run: would reap $reaped finished task(s), keep $kept. Re-run with --force to delete."
  fi
}

# Ordered CDD lifecycle stages, least → most advanced. Source of truth is
# cdd-state.sh's `cdd-state-stages`; mirrored here by hand (the two helpers are
# separate self-installing files). Prints the index of $1, or -1 when unknown.
cdd-worktree-stage-index() {
  local stage="$1" i=0 s
  for s in scoped plan_written implementation_done merged checks_passed \
           pr_open addressed; do
    [[ "$s" == "$stage" ]] && { printf '%s\n' "$i"; return 0; }
    i=$(( i + 1 ))
  done
  printf '%s\n' -1
}

# Atomically materialize FETCH_HEAD:<intree> to <dest>, preserving exact bytes
# (streams git show to a temp file in the same dir, then mv -f — no command
# substitution, so no trailing-newline mangling). Returns non-zero if the path is
# absent from the tree or the write fails.
cdd-worktree-extract() {
  local intree="$1" dest="$2" tmp
  tmp="$(mktemp "${dest}.XXXXXX")" || return 1
  if git show "FETCH_HEAD:${intree}" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dest"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Fetch the per-task ref refs/cdd/<branch> from origin and materialize the handoff,
# plan file and state record into ~/.cdd/handoffs/<repo>/. Advisory and best-effort:
# returns 0 when a ref was found (having printed what it did), 1 when there is no ref
# (offline, no origin, or none pushed) so the caller keeps the honest no-transfer
# messaging. Heuristics: the handoff .md is immutable after seed, so it is written only
# when absent locally; the state .json follows most-advanced-stage-wins (compare .stage
# indices, keep the further-along side), falling back to write-only-if-absent when jq
# is unavailable. Never clobbers a more-advanced local record. The plan file is mutable
# (the human may edit it before implementing), so it cannot use the handoff's rule; it
# travels WITH the state record instead — taken when absent locally, or when the ref's
# record won the stage comparison. See shell-helpers.md.
cdd-worktree-materialize-ref() {
  local branch="$1"
  git fetch origin "refs/cdd/$branch" 2>/dev/null || return 1
  git rev-parse --quiet --verify FETCH_HEAD >/dev/null 2>&1 || return 1

  local repo_name dir
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")" || return 1
  dir="$HOME/.cdd/handoffs/${repo_name}"
  mkdir -p "$dir"
  local handoff_dest="${dir}/${branch}.md"
  local state_dest="${dir}/${branch}.state.json"
  local plan_dest="${dir}/${branch}.plan.md"

  # Handoff: immutable after seed → materialize only when absent locally.
  if [[ ! -f "$handoff_dest" ]] && git cat-file -e FETCH_HEAD:handoff.md 2>/dev/null; then
    cdd-worktree-extract handoff.md "$handoff_dest" \
      && echo "Materialized handoff: $handoff_dest"
  fi

  # Plan file (§2.15): mutable, so it rides with the state record rather than with the
  # handoff. `take_plan` records the verdict the state comparison below reaches; the
  # extraction happens after it, so both files land on the same decision.
  local take_plan=0
  [[ ! -f "$plan_dest" ]] && take_plan=1

  # State record: most-advanced-stage wins.
  if git cat-file -e FETCH_HEAD:state.json 2>/dev/null; then
    if [[ ! -f "$state_dest" ]]; then
      cdd-worktree-extract state.json "$state_dest" \
        && echo "Materialized state record: $state_dest"
    elif command -v jq >/dev/null 2>&1; then
      local ref_stage local_stage ref_idx local_idx
      ref_stage="$(git show FETCH_HEAD:state.json 2>/dev/null | jq -r '.stage // empty' 2>/dev/null)"
      local_stage="$(jq -r '.stage // empty' "$state_dest" 2>/dev/null)"
      ref_idx="$(cdd-worktree-stage-index "$ref_stage")"
      local_idx="$(cdd-worktree-stage-index "$local_stage")"
      if (( ref_idx > local_idx )); then
        take_plan=1
        cdd-worktree-extract state.json "$state_dest" \
          && echo "Updated state record from ref (stage ${local_stage:-?} -> ${ref_stage:-?})."
      else
        echo "Kept local state record (stage ${local_stage:-?} >= synced ${ref_stage:-?})."
      fi
    else
      echo "Kept local state record (jq unavailable to compare stages)."
    fi
  fi

  if (( take_plan )) && git cat-file -e FETCH_HEAD:plan.md 2>/dev/null; then
    cdd-worktree-extract plan.md "$plan_dest" \
      && echo "Materialized plan: $plan_dest"
  elif [[ -f "$plan_dest" ]]; then
    echo "Kept local plan: $plan_dest"
  fi
  return 0
}

# Recreate a worktree on an EXISTING remote branch so a task started on another
# machine can be picked up here. Unlike cdd-worktree, this requires no handoff and
# tracks the remote branch rather than creating a new one. If the originating machine
# synced a per-task ref (refs/cdd/<branch>, see cdd-state), the handoff, plan file and
# state record are fetched and materialized here before launch (most-advanced-stage
# wins, advisory — a missing ref just means nothing to transfer); the resume-side commands
# (/cdd-process-pr, /cdd-merge-base, /cdd-pre-pr) read PR/branch state from git and
# the code host, not the handoff, so its absence is still fine.
cdd-worktree-resume() {
  local branch="${1:-}"
  # No argument is the discovery mode, so only option-shaped input is rejected here.
  case "$branch" in
    -h|--help) echo "usage: cdd-worktree-resume [<branch>]" >&2; return 0 ;;
    -?*) echo "cdd-worktree-resume: '$branch' looks like an option, not a branch name." >&2; return 2 ;;
  esac

  # A broken code-host adapter stops the resume before anything is fetched or created.
  local CDD_ADAPTER="" CDD_ADAPTER_DESCRIBE="" CDD_ADAPTER_OUT="" CDD_ADAPTER_ERR="" rc=0
  cdd-worktree-adapter code-host || rc=$?
  if (( rc == 2 )); then return 1; fi

  # Same guard as cdd-worktree: the sibling worktree name is derived from $PWD, so
  # insist on the main worktree to avoid nesting names.
  local default_branch current_branch
  default_branch="$(cdd-worktree-default-branch --resolved)"
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  if [[ "$current_branch" != "$default_branch" ]]; then
    echo "Run this from the main worktree on '$default_branch' (current: '$current_branch')." >&2
    return 1
  fi

  # --prune drops stale remote-tracking refs for branches deleted on the remote
  # (GitHub deletes the head branch when a PR merges), so discovery lists exactly
  # what still exists on origin — the default branch plus live feature branches.
  if ! git fetch --prune origin; then
    echo "git fetch --prune origin failed, aborting." >&2
    return 1
  fi

  # Snapshot worktree branches once (reused for discovery and already-exists).
  local worktree_branches
  worktree_branches="$(git worktree list --porcelain 2>/dev/null \
                        | awk '$1 == "branch" { sub("refs/heads/", "", $2); print $2 }')"

  if [[ -z "$branch" ]]; then
    # Discovery: remote feature branches (exclude default + HEAD) not already
    # checked out as a local worktree. The fetch above pruned merged-and-deleted
    # branches, so what remains is the set of live branches shown on GitHub.
    local use_adapter=0 crc
    if [[ -n "$CDD_ADAPTER" ]]; then
      use_adapter=1
    else
      cdd-worktree-no-adapter code-host "no PR status shown"
    fi

    # Iterate full refnames and strip the full prefix: the short form of the
    # origin/HEAD symref is "origin/HEAD" on older git but just "origin" on
    # newer git, which would slip past a "$rb" == HEAD check and become a bogus
    # candidate. The full refname (refs/remotes/origin/HEAD) is stable.
    local candidates=() rb
    while IFS= read -r rb; do
      rb="${rb#refs/remotes/origin/}"
      [[ "$rb" == "HEAD" || "$rb" == "$default_branch" ]] && continue
      grep -qx "$rb" <<<"$worktree_branches" && continue
      candidates+=("$rb")
    done < <(git for-each-ref --format='%(refname)' refs/remotes/origin 2>/dev/null)

    if (( ${#candidates[@]} == 0 )); then
      echo "No remote feature branches to resume (all are local worktrees or none exist)." >&2
      return 1
    fi

    echo "Remote branches available to resume:"
    local i pr_line
    for i in "${!candidates[@]}"; do
      pr_line=""
      if (( use_adapter )); then
        crc=0
        cdd-worktree-adapter-call pr-for-branch "${candidates[$i]}" || crc=$?
        if (( crc == 0 )); then
          pr_line="$(jq -r '.[0] | select(.) | " (PR #\(.ref) \(.state|ascii_upcase))"' \
                       <<<"$CDD_ADAPTER_OUT" 2>/dev/null)"
        else
          (( crc == 3 )) || cdd-worktree-adapter-warn pr-for-branch "$crc"
          use_adapter=0
        fi
      fi
      printf '  %2d) %s%s\n' "$(( i + 1 ))" "${candidates[$i]}" "$pr_line"
    done

    local choice
    read -r -p "Select a branch [1-${#candidates[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#candidates[@]} )); then
      echo "Invalid selection: '$choice'." >&2
      return 1
    fi
    branch="${candidates[$(( choice - 1 ))]}"
  else
    if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      echo "No remote branch origin/$branch (after fetch --prune)." >&2
      echo "It may have been merged and deleted on the remote, or never pushed." >&2
      echo "Use 'cdd-worktree-resume' with no argument to list resumable branches." >&2
      return 1
    fi
  fi

  # Already checked out as a worktree? Point the user at it and stop.
  if grep -qx "$branch" <<<"$worktree_branches"; then
    local existing
    existing="$(git worktree list --porcelain 2>/dev/null | awk -v ref="refs/heads/$branch" '
      $1 == "worktree" { path = $2 }
      $1 == "branch"   && $2 == ref { print path; exit }
    ')"
    echo "Branch '$branch' is already checked out at: ${existing:-<unknown>}" >&2
    return 0
  fi

  local repo_dir
  repo_dir="$(basename "$PWD")"
  local worktree_path="../${repo_dir}-${branch}"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    # Local branch already exists (no worktree yet): attach it.
    git worktree add "$worktree_path" "$branch" || return 1
  else
    # Create a local branch tracking the existing remote branch.
    git worktree add --track -b "$branch" "$worktree_path" "origin/$branch" || return 1
  fi
  cd "$worktree_path" || return 1

  echo
  echo "Resumed worktree for '$branch' on origin/$branch (now in $worktree_path)."
  # Fetch + materialize the handoff/plan/state from refs/cdd/<branch> if it was synced.
  if ! cdd-worktree-materialize-ref "$branch"; then
    echo "No synced task ref (refs/cdd/$branch); handoff/plan/state not transferred."
    echo "Resume-side commands read PR/branch state from git and the code host, so this is fine."
  fi
  # A task parked at plan_written has an approved plan on disk and no code yet, so it
  # resumes into the implementation half of the split rather than into a review-side
  # command. Read the record directly rather than shelling out to cdd-state: this
  # helper already derives the same path in cdd-worktree, and staying self-contained
  # keeps the two separately-installed helpers independent at runtime.
  local stage="" lane="" repo_name_r state_r
  repo_name_r="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
  state_r="$HOME/.cdd/handoffs/${repo_name_r}/${branch}.state.json"
  if command -v jq >/dev/null 2>&1 && [[ -f "$state_r" ]]; then
    stage="$(jq -r '.stage // empty' "$state_r" 2>/dev/null)"
    lane="$(jq -r '.lane // empty' "$state_r" 2>/dev/null)"
  fi
  # The lane test comes first: a small-change task that has not been built yet sits at
  # `scoped`, which would otherwise fall through to the review-side guidance and send
  # the user to open a PR on a task with no work in it. A small task that took the
  # off-ramp into /cdd-plan is at `plan_written` and falls through correctly.
  if [[ "$lane" == "small" && "$stage" == "scoped" && -f .claude/commands/cdd-small-change.md ]]; then
    echo "Next: start Claude Code here and run /cdd-small-change (this task is on the small-change lane)."
  elif [[ "$stage" == "plan_written" ]]; then
    echo "Next: start Claude Code here and run /cdd-implement (the plan is approved and on disk)."
  else
    echo "Next: start Claude Code here and run /cdd-process-pr, /cdd-merge-base, or /cdd-pre-pr."
  fi
}

# Install this helper to its stable home and wire it into the user's shells.
# Run directly (`tools/cdd-worktree.sh install`), never sourced. Idempotent.
cdd-worktree-install() {
  if [[ $# -gt 0 && "$1" != "install" ]]; then
    echo "usage: cdd-worktree.sh [install]" >&2
    return 2
  fi

  local dest_dir="$HOME/.cdd/tools"
  local dest="$dest_dir/cdd-worktree.sh"
  mkdir -p "$dest_dir" "$HOME/.cdd/handoffs"

  # Copy this running script to the stable home, unless we're already it.
  local src
  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ "$src" != "$dest" ]]; then
    cp "$src" "$dest"
    chmod +x "$dest"
    echo "Installed helper: $dest"
  else
    echo "Helper already at $dest (running from the installed copy)."
  fi

  # Copy the shipped capability adapters beside it, as a machine-global LIBRARY at
  # ~/.cdd/tools/adapters/<cap>/<backend>.sh -- deliberately not a resolution-ladder
  # rung (that is ~/.cdd/adapters/<cap>), so installing binds no project. A project
  # binds by committing a .cdd/<cap> shim that execs a library file (ADR 0011).
  # Newest wins: shipped files are overwritten, nothing is deleted. Nothing to copy
  # when running from the installed copy (the library is already its sibling); a
  # note when no library results (a curl-only install fetches this one file).
  local src_dir lib_dir="$dest_dir/adapters" a rel lib_count=0
  src_dir="$(dirname "$src")"
  if [[ "$src_dir" != "$dest_dir" && -d "$src_dir/adapters" ]]; then
    shopt -s nullglob
    for a in "$src_dir"/adapters/*/*.sh; do
      rel="${a#"$src_dir"/adapters/}"
      mkdir -p "$lib_dir/$(dirname "$rel")"
      cp "$a" "$lib_dir/$rel"
      chmod +x "$lib_dir/$rel"
      lib_count=$((lib_count + 1))
    done
    shopt -u nullglob
    echo "Installed adapter library: $lib_dir ($lib_count adapter(s))"
  elif [[ ! -d "$lib_dir" ]]; then
    echo "Note: no adapters/ beside $src, so no adapter library is installed. A project binding (.cdd/<cap>) needs it; fetch each adapter it names with:" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/adapters/<cap>/<backend>.sh --create-dirs -o ~/.cdd/tools/adapters/<cap>/<backend>.sh && chmod +x ~/.cdd/tools/adapters/<cap>/<backend>.sh" >&2
  fi

  # Wire each shell rc that exists; create ~/.bashrc if neither exists so there
  # is always at least one entry point.
  local marker_begin="# --- CDD worktree helper (managed by cdd-worktree.sh install) BEGIN ---"
  local marker_end="# --- CDD worktree helper END ---"
  # Match the ACTIVE source line (anchored to line start, so a commented-out
  # copy can't match) rather than the bare marker, so `install` can tell a live
  # block from one disabled by commenting and re-enable the latter.
  # shellcheck disable=SC2016
  local active_re='^[[:space:]]*\[\[ -f "\$HOME/\.cdd/tools/cdd-worktree\.sh" \]\] && source'
  local rc rcs=()
  [[ -f "$HOME/.bashrc" ]] && rcs+=("$HOME/.bashrc")
  [[ -f "$HOME/.zshrc"  ]] && rcs+=("$HOME/.zshrc")
  if (( ${#rcs[@]} == 0 )); then
    touch "$HOME/.bashrc"
    rcs+=("$HOME/.bashrc")
  fi
  for rc in "${rcs[@]}"; do
    if grep -qE "$active_re" "$rc" 2>/dev/null; then
      echo "Already wired: $rc (skipped)"
      continue
    fi
    if grep -qF "$marker_begin" "$rc" 2>/dev/null; then
      # A managed block is present but inactive: strip it, then re-append a
      # fresh active block below. index() matches the marker even when the
      # line is commented ("## # --- … BEGIN ---" still contains the marker).
      local tmp
      tmp="$(mktemp "${rc}.XXXXXX")" || return 1
      awk -v b="$marker_begin" -v e="$marker_end" '
        index($0, b) { skip = 1 }
        skip && index($0, e) { skip = 0; next }
        skip { next }
        { print }
      ' "$rc" > "$tmp" && mv -f "$tmp" "$rc"
      echo "Repaired disabled CDD block in $rc"
    fi
    cat >> "$rc" <<RCBLOCK

${marker_begin}
[[ -f "\$HOME/.cdd/tools/cdd-worktree.sh" ]] && source "\$HOME/.cdd/tools/cdd-worktree.sh"
${marker_end}
RCBLOCK
    echo "Wired: $rc"
  done

  # Expose the commands on PATH too: the rc `source` line only reaches
  # interactive shells, so a non-interactive shell (e.g. Claude Code's Bash
  # tool) would otherwise get "command not found". The three cwd-changing
  # commands ship a shim that FAILS LOUDLY instead of dispatching — a shim runs
  # in a subshell and can't change the caller's cwd, so dispatching would
  # silently strand the caller. cdd-worktree-list changes no cwd, so it keeps a
  # real source+dispatch shim.
  local bin_dir="$HOME/.local/bin" cmd
  mkdir -p "$bin_dir"
  for cmd in cdd-worktree cdd-worktree-resume cdd-worktree-done; do
    cat > "$bin_dir/$cmd" <<SHIM
#!/usr/bin/env bash
# Managed by cdd-worktree.sh install — cwd-changing command; do not hand-edit.
# Reaching this shim means '$cmd' is not loaded as a function, so its 'cd' can't
# take effect (a subshell can't change its parent's cwd). Refuse loudly.
echo "$cmd must run as a sourced shell function, not via the PATH shim." >&2
echo "It changes your shell's working directory, which a subshell cannot do." >&2
echo "Fix: open a new shell, or 'source ~/.cdd/tools/cdd-worktree.sh', then re-run." >&2
echo "If your shell rc CDD block was disabled: bash ~/.cdd/tools/cdd-worktree.sh install" >&2
exit 1
SHIM
    chmod +x "$bin_dir/$cmd"
  done
  # These two change no cwd, so they get a real source+dispatch shim.
  for cmd in cdd-worktree-list cdd-worktree-gc; do
    cat > "$bin_dir/$cmd" <<SHIM
#!/usr/bin/env bash
# Managed by cdd-worktree.sh install — PATH entry point so this command resolves
# in non-interactive shells too. Regenerated on each install; do not hand-edit.
# The guards are load-bearing: without them, a missing or broken helper leaves the
# function undefined, the call below re-resolves to THIS shim through PATH, and the
# result is unbounded recursion rather than an error.
helper="\$HOME/.cdd/tools/cdd-worktree.sh"
if [[ ! -f "\$helper" ]]; then
  echo "$cmd: helper not found at \$helper; reinstall with: bash <cdd>/tools/cdd-worktree.sh install" >&2
  exit 127
fi
# shellcheck source=/dev/null
source "\$helper"
if ! declare -F $cmd >/dev/null 2>&1; then
  echo "$cmd: \$helper did not define $cmd; reinstall it." >&2
  exit 127
fi
$cmd "\$@"
SHIM
    chmod +x "$bin_dir/$cmd"
  done
  echo "Installed PATH shims in $bin_dir: cdd-worktree-list, cdd-worktree-gc (dispatch); cdd-worktree, cdd-worktree-resume, cdd-worktree-done (refuse-if-unsourced)"
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "Note: $bin_dir is not on your PATH; add it so the cdd-worktree* commands resolve everywhere." >&2 ;;
  esac

  # Migrate handoffs from the old location: copy each project subtree that isn't
  # already present, leaving the originals in place.
  local old="$HOME/.claude-handoffs"
  if [[ -d "$old" ]]; then
    local migrated=0 proj name
    shopt -s nullglob
    for proj in "$old"/*/; do
      name="$(basename "$proj")"
      [[ -e "$HOME/.cdd/handoffs/$name" ]] && continue
      cp -r "$proj" "$HOME/.cdd/handoffs/$name" && migrated=1
    done
    shopt -u nullglob
    if (( migrated )); then
      echo "Migrated handoffs from $old/ to ~/.cdd/handoffs/ (originals left in place)."
    fi
  fi

  echo "Done. Open a new shell (or 'source' your rc) so cdd-worktree* are available."
}

# Dual-mode: when executed directly, run the installer; when sourced, only the
# functions above are defined.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cdd-worktree-install "$@"
fi
