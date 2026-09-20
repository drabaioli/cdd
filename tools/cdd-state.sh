#!/usr/bin/env bash
# CDD task-state helper — one shared, project-independent helper for every CDD project.
#
# Records where a task sits in its lifecycle and which Claude Code sessions have
# worked it, in a small JSON sibling of the handoff:
#
#   ~/.cdd/handoffs/<repo-name>/<branch>.state.json
#
# The slash commands call this helper at their stage transitions instead of
# hand-editing the JSON, so writes are atomic and well-formed (no malformed-JSON
# or wrong-field failure mode). The record is ADVISORY and reconstructible: it is
# only as reliable as the command steps that write it, and a consumer that finds
# it missing or stale falls back to inference. See the process doc section 2.13.
#
# Install once — copies this script to a stable home that does NOT depend on a
# live CDD checkout, and wires your shell to source it:
#
#   tools/cdd-state.sh install
#
# On a machine without a CDD checkout, fetch it to its home and install in one step:
#
#   curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/cdd-state.sh \
#     --create-dirs -o ~/.cdd/tools/cdd-state.sh \
#     && bash ~/.cdd/tools/cdd-state.sh install
#
# Provides (when sourced):
#   cdd-state seed <branch>        Create the record beside the handoff, at stage
#                                      `scoped`. Used by /cdd-next-step on the
#                                      default branch. Records the current (handoff)
#                                      session as a {id, stage, dir} entry when
#                                      $CLAUDE_CODE_SESSION_ID is set, so the handoff
#                                      session is resumable too; otherwise seeds an
#                                      empty `sessions` (older Claude Code — no id).
#   cdd-state lane <branch> <lane>  Mark which lane the task takes, `small` or
#                                      `standard` (`standard` renders null, i.e. the
#                                      default). Used by /cdd-next-step right after
#                                      `seed`, on the default branch, which is why the
#                                      branch is positional. A separate subcommand
#                                      rather than a `seed` flag so an older helper
#                                      meeting a newer /cdd-next-step fails this one
#                                      call and still keeps the seeded record.
#   cdd-state set <stage> [--pr N] Advance an existing record to <stage> (and set
#                                      the PR number with --pr). Derives repo/branch
#                                      from the current worktree. Skips silently if
#                                      the record is absent (writers never fabricate
#                                      one). Appends a {id, stage, dir} entry for
#                                      $CLAUDE_CODE_SESSION_ID unless it is empty or
#                                      already the last entry's id.
#   cdd-state set-field <x-key> <json-value> [--branch <branch>]
#                                  Set one extension field on an existing record.
#                                      The key must start with `x-`: that namespace is
#                                      reserved for extensions, and CDD's own logic
#                                      never reads it (process doc 2.13). The value is
#                                      JSON — an object, array or scalar — and an
#                                      invalid one exits 2 without writing. Defaults to
#                                      the cwd-derived record; --branch names another,
#                                      for a caller standing on the default branch. Like
#                                      `lane` it appends no session entry and writes no
#                                      per-repo marker: it annotates a task rather than
#                                      advancing it. Adding a field needs no
#                                      schema_version bump.
#   cdd-state stages               Print the lifecycle enum, least -> most advanced,
#                                      one stage per line. Read-only, needs no record
#                                      and no jq; it is the capability probe an older
#                                      helper fails (see cdd-worktree's skew check).
#
# `dir` on a session entry is the worktree root the session ran in (from
# `git rev-parse --show-toplevel`): the natural `cd` target for `claude --resume`.
#
# Every verb that writes the record (`seed`, `lane`, `set`, `set-field`) also syncs
# the handoff + plan file + record to a per-task ref `refs/cdd/<branch>` on origin
# (best-effort, advisory), so a resume on another machine can materialize them; see
# cdd-worktree-resume and shell-helpers.md.
#
# `seed` and `set` also refresh the per-repo marker `~/.cdd/handoffs/<repo>/repo.json`, which
# records this repo's main worktree and is the one artifact in that directory that
# survives task GC (see cdd-state-write-repo-marker). It is machine-local and is
# never carried on the task ref.
#
# Stages (a single enum; the record carries no separate status):
#   scoped  plan_written  implementation_done  merged  checks_passed
#   pr_open  addressed

# The schema version this helper writes; consumers version their parser on it.
CDD_STATE_SCHEMA_VERSION=1

# The per-repo marker's schema version, deliberately independent of the state
# record's: the two files carry unrelated shapes and can evolve apart.
CDD_REPO_MARKER_SCHEMA_VERSION=1

cdd-state-stages() {
  printf '%s\n' scoped plan_written implementation_done merged checks_passed \
                pr_open addressed
}

# The MAIN worktree of the current repo — the dirname of git's common dir, NOT
# `--show-toplevel`, which names the feature worktree when a task session asks.
# Its basename is the repo name that namespaces ~/.cdd/handoffs/<repo>/.
cdd-state-main-worktree() {
  local common_dir
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [[ -n "$common_dir" ]] || return 1
  dirname "$common_dir"
}

# Path to the state record for the current worktree's branch.
cdd-state-file() {
  local main_wt repo_name branch
  main_wt="$(cdd-state-main-worktree)" || return 1
  repo_name="$(basename "$main_wt")"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  printf '%s\n' "$HOME/.cdd/handoffs/${repo_name}/${branch}.state.json"
}

# Atomic write: render to a temp file in the same dir, then mv into place.
cdd-state-write() {
  local dest="$1" content="$2" tmp
  tmp="$(mktemp "${dest}.XXXXXX")" || return 1
  printf '%s\n' "$content" >"$tmp" && mv -f "$tmp" "$dest"
}

# Write the per-repo marker ~/.cdd/handoffs/<repo>/repo.json — {schema_version, name,
# path} — recording where this repo's MAIN worktree lives. Everything else in that
# directory is task-scoped and reaped when the task merges, so once a repo's tasks are
# all done the directory goes empty and the repo becomes unlocatable; the marker is the
# one artifact that outlives them (GC's candidate set globs *.md and *.state.json plus
# refs/cdd/*, none of which it matches). Overwrites unconditionally, so it self-heals
# when a repo moves or is re-cloned — latest writer wins, like the task ref.
#
# Advisory end-to-end, like the rest of this helper: a failing rev-parse, an unwritable
# directory, or a jq failure warns once and returns 0. It must never fail the state write
# that called it, nor a `set -e` caller (bootstrap-cdd-project.sh sources this file).
# `cdd-state` reaches it below its own jq guard; the jq branch here is what covers the
# direct callers (bootstrap) that have no guard of their own. See
# doc/architecture/shell-helpers.md.
cdd-state-write-repo-marker() {
  local main_wt repo_name dir content
  main_wt="$(cdd-state-main-worktree)" || {
    echo "cdd-state: not in a git repo; skipping repo marker (advisory)." >&2; return 0; }
  repo_name="$(basename "$main_wt")"
  dir="$HOME/.cdd/handoffs/${repo_name}"
  mkdir -p "$dir" 2>/dev/null || {
    echo "cdd-state: could not create $dir; skipping repo marker (advisory)." >&2; return 0; }
  content="$(jq -n \
    --argjson v "$CDD_REPO_MARKER_SCHEMA_VERSION" \
    --arg name "$repo_name" \
    --arg path "$main_wt" \
    '{schema_version: $v, name: $name, path: $path}' 2>/dev/null)" || {
    echo "cdd-state: could not render repo marker (jq missing/failed); skipping (advisory)." >&2
    return 0; }
  cdd-state-write "${dir}/repo.json" "$content" \
    || echo "cdd-state: could not write ${dir}/repo.json; skipping (advisory)." >&2
  return 0
}

# Sync the handoff + plan + state record to a per-task ref refs/cdd/<branch> on origin,
# so a resume on another machine can materialize them (see cdd-worktree-resume). Bundles
# whichever of the three files exist into a git tree (stable in-tree names handoff.md /
# plan.md / state.json, decoupled from the branch-named on-disk files), wraps it in a
# parentless commit, and force-pushes (advisory, latest-wins). Best-effort end-to-end:
# no origin, offline, a missing object, or a rejected push warns once and returns 0 — it must
# never fail the state write that called it. Uses plumbing only (hash-object/mktree/
# commit-tree), so it never touches the index or working tree. The commit uses a fixed
# cdd/cdd@local identity so it never depends on (or fails from) an unset user git
# identity; the SHA is irrelevant under force-push. See doc/architecture/shell-helpers.md.
cdd-state-push-ref() {
  local handoff_md="$1" state_json="$2" branch="$3"
  # The plan file (§2.15) is derived, not passed: it is the <branch>.plan.md sibling
  # of the handoff, so both callers stay two-argument. It is written after seed — by
  # /cdd-plan on approval — so the `set plan_written` push is what first carries it.
  local plan_md="${handoff_md%.md}.plan.md"
  local entries="" blob
  # Emitted in name order (handoff.md < plan.md < state.json) for readability only:
  # `git mktree` normalises entry order itself, so pre-sorting is not required.
  if [[ -f "$handoff_md" ]]; then
    blob="$(git hash-object -w "$handoff_md" 2>/dev/null)" \
      || { echo "cdd-state: could not hash handoff; skipping ref sync (advisory)." >&2; return 0; }
    entries+="100644 blob ${blob}"$'\t'"handoff.md"$'\n'
  fi
  if [[ -f "$plan_md" ]]; then
    blob="$(git hash-object -w "$plan_md" 2>/dev/null)" \
      || { echo "cdd-state: could not hash plan; skipping ref sync (advisory)." >&2; return 0; }
    entries+="100644 blob ${blob}"$'\t'"plan.md"$'\n'
  fi
  if [[ -f "$state_json" ]]; then
    blob="$(git hash-object -w "$state_json" 2>/dev/null)" \
      || { echo "cdd-state: could not hash state; skipping ref sync (advisory)." >&2; return 0; }
    entries+="100644 blob ${blob}"$'\t'"state.json"$'\n'
  fi
  [[ -z "$entries" ]] && return 0
  local tree commit
  tree="$(printf '%s' "$entries" | git mktree 2>/dev/null)" \
    || { echo "cdd-state: git mktree failed; skipping ref sync (advisory)." >&2; return 0; }
  commit="$(GIT_AUTHOR_NAME=cdd GIT_AUTHOR_EMAIL=cdd@local \
            GIT_COMMITTER_NAME=cdd GIT_COMMITTER_EMAIL=cdd@local \
            git commit-tree "$tree" -m "cdd: sync ${branch}" 2>/dev/null)" \
    || { echo "cdd-state: git commit-tree failed; skipping ref sync (advisory)." >&2; return 0; }
  if git push --force origin "${commit}:refs/cdd/${branch}" 2>/dev/null; then
    echo "Synced task ref: refs/cdd/${branch}"
  else
    echo "cdd-state: could not push refs/cdd/${branch} (no origin/offline?); state stays local (advisory)." >&2
  fi
  return 0
}

cdd-state() {
  # `stages` is a pure read of the lifecycle enum — no record, no jq. It is answered
  # BEFORE the jq guard below so that a capability probe (cdd-worktree's skew check,
  # §2.8) reads the real answer on a host without jq instead of an empty one.
  if [[ "${1:-}" == "stages" ]]; then
    cdd-state-stages
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "cdd-state: jq not found; skipping state update (advisory)." >&2
    return 0
  fi

  local cmd="$1"; shift 2>/dev/null
  case "$cmd" in
    seed)
      local branch="$1"; shift 2>/dev/null
      # The branch is positional with no flags before it, so an option-shaped value is
      # always a mistake -- and an expensive one here: `cdd-state seed --help` used to
      # write "--help.state.json" and force-push refs/cdd/--help to the real origin,
      # which is exactly how one turned up on the shared repo.
      case "$branch" in
        -h|--help) echo "usage: cdd-state seed <branch> [--base <branch>]" >&2; return 0 ;;
        -*) echo "cdd-state seed: '$branch' looks like an option, not a branch name." >&2; return 2 ;;
      esac
      local base=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --base) base="$2"; shift 2 ;;
          *) echo "cdd-state seed: unknown arg '$1'" >&2; return 2 ;;
        esac
      done
      if [[ -z "$branch" ]]; then
        echo "usage: cdd-state seed <branch> [--base <branch>]" >&2
        return 2
      fi
      local main_wt repo_name dir
      main_wt="$(cdd-state-main-worktree)" || return 1
      repo_name="$(basename "$main_wt")"
      dir="$HOME/.cdd/handoffs/${repo_name}"
      mkdir -p "$dir"
      # Refresh the per-repo marker on every seed (advisory; never fails the seed).
      cdd-state-write-repo-marker
      # Record the handoff session (this /cdd-next-step session, on the main
      # worktree) so it is resumable too — guarded exactly like `set`'s append:
      # only when CLAUDE_CODE_SESSION_ID is set (older Claude Code → empty list,
      # don't guess). `dir` is the worktree root, the `cd` target for --resume.
      local sid="${CLAUDE_CODE_SESSION_ID:-}" toplevel sessions='[]'
      toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
      if [[ -n "$sid" ]]; then
        sessions="$(jq -n --arg id "$sid" --arg dir "$toplevel" \
          '[{id: $id, stage: "scoped", dir: $dir}]')" || return 1
      fi
      local content
      # base_branch is the task's base — the branch it was cut from and merges
      # back into (§2.13). Empty --base → null ("no base recorded"), so consumers
      # fall back to the runtime default branch. Set once here; never mutated.
      content="$(jq -n \
        --argjson v "$CDD_STATE_SCHEMA_VERSION" \
        --arg branch "$branch" \
        --arg base "$base" \
        --argjson sessions "$sessions" \
        '{schema_version: $v, branch: $branch, stage: "scoped", pr: null, base_branch: ($base | if . == "" then null else . end), sessions: $sessions}')" || return 1
      if cdd-state-write "${dir}/${branch}.state.json" "$content"; then
        echo "Seeded state: ${dir}/${branch}.state.json"
        # Land the handoff .md (immutable after seed) and the fresh state on the ref.
        cdd-state-push-ref "${dir}/${branch}.md" "${dir}/${branch}.state.json" "$branch"
      fi
      ;;
    lane)
      local branch="$1"; shift 2>/dev/null
      # Positional branch, same trap as `seed`: an option-shaped value here would
      # name a record after a flag.
      case "$branch" in
        -h|--help) echo "usage: cdd-state lane <branch> <small|standard>" >&2; return 0 ;;
        -*) echo "cdd-state lane: '$branch' looks like an option, not a branch name." >&2; return 2 ;;
      esac
      local lane="${1:-}"
      if [[ -z "$branch" || -z "$lane" ]]; then
        echo "usage: cdd-state lane <branch> <small|standard>" >&2
        return 2
      fi
      case "$lane" in
        small|standard) ;;
        *) echo "cdd-state lane: invalid lane '$lane' (one of: small standard)" >&2; return 2 ;;
      esac
      # The branch is passed in rather than derived: /cdd-next-step runs on the
      # default branch while the record belongs to the task branch.
      local main_wt repo_name file
      main_wt="$(cdd-state-main-worktree)" || return 1
      repo_name="$(basename "$main_wt")"
      file="$HOME/.cdd/handoffs/${repo_name}/${branch}.state.json"
      # Writers never fabricate a record; only `seed` (i.e. /cdd-next-step) creates one.
      if [[ ! -f "$file" ]]; then
        echo "cdd-state: no record at $file; skipping (advisory)." >&2
        return 0
      fi
      # Additive and optional, like base_branch: set once at scoping, never mutated,
      # and `standard` is written as null so absent and standard are the same state.
      # No session entry is appended — this is the same session that just seeded.
      local content
      # shellcheck disable=SC2016  # $lane is a jq variable, not a shell expansion
      content="$(jq --arg lane "$lane" \
        '.lane = ($lane | if . == "standard" then null else . end)' "$file")" \
        || { echo "cdd-state: failed to update $file" >&2; return 1; }
      if cdd-state-write "$file" "$content"; then
        echo "Lane: $(basename "$file") -> $lane"
        cdd-state-push-ref "${file%.state.json}.md" "$file" "$branch"
      fi
      ;;
    set-field)
      # `${1:-}` rather than `$1`: a caller running under `set -u` (the assertions do)
      # would die on an unbound argument before reaching the usage line below.
      local key="${1:-}"; shift 2>/dev/null
      # The key is positional, so it carries the same trap `seed` and `lane` guard:
      # an option-shaped value here would write a field literally named `--help`.
      case "$key" in
        -h|--help) echo "usage: cdd-state set-field <x-key> <json-value> [--branch <branch>]" >&2; return 0 ;;
        -*) echo "cdd-state set-field: '$key' looks like an option, not a field name." >&2; return 2 ;;
      esac
      local value="${1:-}"; shift 2>/dev/null
      local branch=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --branch) branch="$2"; shift 2 ;;
          *) echo "cdd-state set-field: unknown arg '$1'" >&2; return 2 ;;
        esac
      done
      if [[ -z "$key" || -z "$value" ]]; then
        echo "usage: cdd-state set-field <x-key> <json-value> [--branch <branch>]" >&2
        return 2
      fi
      # The `x-` prefix is enforced, not merely conventional: without it this verb is a
      # backdoor around `set`'s stage-enum validation (`set-field stage merged`). CDD's
      # own future fields get their own subcommand, the way `lane` did, so nothing is
      # lost. Relaxing this later is additive; tightening it later would break extensions.
      case "$key" in
        x-*) ;;
        *) echo "cdd-state set-field: '$key' is outside the extension namespace; keys must start with 'x-'." >&2
           return 2 ;;
      esac
      # Validate BEFORE touching the file, so a malformed value cannot leave a partial
      # record. `jq empty` and not `jq -e .`: -e reports null and false as failures, and
      # both are legitimate values here.
      if ! jq empty <<<"$value" 2>/dev/null; then
        echo "cdd-state set-field: value is not valid JSON: $value" >&2
        return 2
      fi
      # Default to the cwd-derived record (as `set` does); --branch names another one,
      # for a caller standing on the default branch (as /cdd-next-step does). The branch
      # is a flag rather than positional because the derived case is the common one.
      local file
      if [[ -n "$branch" ]]; then
        local main_wt repo_name
        main_wt="$(cdd-state-main-worktree)" || return 1
        repo_name="$(basename "$main_wt")"
        file="$HOME/.cdd/handoffs/${repo_name}/${branch}.state.json"
      else
        file="$(cdd-state-file)" || return 1
        branch="$(basename "${file%.state.json}")"
      fi
      # Writers never fabricate a record; only `seed` (i.e. /cdd-next-step) creates one.
      if [[ ! -f "$file" ]]; then
        echo "cdd-state: no record at $file; skipping (advisory)." >&2
        return 0
      fi
      # One field assignment over the existing record, so every other key — CDD's own
      # and any other extension's — rides through untouched. No session entry is
      # appended and no per-repo marker is written: this is a task-scoped annotation,
      # like `lane`, not a lifecycle transition.
      local content
      # shellcheck disable=SC2016  # $k/$v are jq variables, not shell expansions
      content="$(jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$file")" \
        || { echo "cdd-state: failed to update $file" >&2; return 1; }
      if cdd-state-write "$file" "$content"; then
        echo "Field: $(basename "$file") -> $key"
        cdd-state-push-ref "${file%.state.json}.md" "$file" "$branch"
      fi
      ;;
    set)
      local stage="$1"; shift 2>/dev/null
      local pr=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --pr) pr="$2"; shift 2 ;;
          *) echo "cdd-state set: unknown arg '$1'" >&2; return 2 ;;
        esac
      done
      if [[ -z "$stage" ]] || ! cdd-state-stages | grep -qx "$stage"; then
        echo "cdd-state set: invalid stage '$stage' (one of: $(cdd-state-stages | paste -sd' '))" >&2
        return 2
      fi
      # Refresh the per-repo marker first, deliberately BEFORE the absent-record
      # return below: the marker is per-repo, not per-task, so a repo whose records
      # have all been reaped still gets (and keeps) one. "Writers never fabricate a
      # record" is about the task record, which the branch below still respects.
      cdd-state-write-repo-marker
      local file
      file="$(cdd-state-file)" || return 1
      # Writers never fabricate a record; only `seed` (i.e. /cdd-next-step) creates one.
      if [[ ! -f "$file" ]]; then
        echo "cdd-state: no record at $file; skipping (advisory)." >&2
        return 0
      fi
      # $stage/$pr/$sid below are jq variables (passed via --arg), not shell
      # expansions, so the single-quoted filter is intentional.
      # shellcheck disable=SC2016
      local filter='.stage = $stage'
      [[ -n "$pr" ]] && filter="$filter | .pr = (\$pr | tonumber)"
      # Append this session unless CLAUDE_CODE_SESSION_ID is empty or already the
      # last entry's id (dedups repeated writes within one session). `dir` is the
      # worktree root this session ran in — the `cd` target for `claude --resume`.
      local sid="${CLAUDE_CODE_SESSION_ID:-}" toplevel
      toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
      if [[ -n "$sid" ]]; then
        filter="$filter | if (.sessions[-1].id // \"\") == \$sid then . else .sessions += [{id: \$sid, stage: \$stage, dir: \$dir}] end"
      fi
      local content
      content="$(jq \
        --arg stage "$stage" \
        --arg pr "$pr" \
        --arg sid "$sid" \
        --arg dir "$toplevel" \
        "$filter" "$file")" || { echo "cdd-state: failed to update $file" >&2; return 1; }
      if cdd-state-write "$file" "$content"; then
        echo "State: $(basename "$file") -> $stage${pr:+ (pr #$pr)}"
        # Refresh the state .json on the ref (bundling the handoff .md if present).
        # $file is <dir>/<branch>.state.json → strip the suffix for branch/handoff.
        local base="${file%.state.json}"
        cdd-state-push-ref "${base}.md" "$file" "$(basename "$base")"
      fi
      ;;
    get)
      # Read accessor for the cwd-derived record: print .<field>, empty on an
      # absent record or an absent/null field. Advisory and read-only; the jq
      # guard at the top already handles a machine without jq.
      local field="$1"
      if [[ -z "$field" ]]; then
        echo "usage: cdd-state get <field>" >&2
        return 2
      fi
      local file
      file="$(cdd-state-file)" || return 0
      [[ -f "$file" ]] || return 0
      jq -r --arg f "$field" '.[$f] // empty' "$file" 2>/dev/null || return 0
      ;;
    install|"")
      cdd-state-install "$@"
      ;;
    -h|--help|help)
      echo "usage: cdd-state {seed <branch> [--base <branch>] | lane <branch> <small|standard> | set <stage> [--pr N] | set-field <x-key> <json-value> [--branch <branch>] | get <field> | stages | install}" >&2
      ;;
    *)
      echo "usage: cdd-state {seed <branch> [--base <branch>] | lane <branch> <small|standard> | set <stage> [--pr N] | set-field <x-key> <json-value> [--branch <branch>] | get <field> | stages | install}" >&2
      return 2
      ;;
  esac
}

# Install this helper to its stable home and wire it into the user's shells.
# Run directly (`tools/cdd-state.sh install`), never sourced. Idempotent.
cdd-state-install() {
  if [[ $# -gt 0 && "$1" != "install" ]]; then
    echo "usage: cdd-state.sh [install]" >&2
    return 2
  fi

  local dest_dir="$HOME/.cdd/tools"
  local dest="$dest_dir/cdd-state.sh"
  mkdir -p "$dest_dir" "$HOME/.cdd/handoffs"

  local src
  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ "$src" != "$dest" ]]; then
    cp "$src" "$dest"
    chmod +x "$dest"
    echo "Installed helper: $dest"
  else
    echo "Helper already at $dest (running from the installed copy)."
  fi

  local marker_begin="# --- CDD state helper (managed by cdd-state.sh install) BEGIN ---"
  local marker_end="# --- CDD state helper END ---"
  # Match the ACTIVE source line (anchored to line start, so a commented-out
  # copy can't match) rather than the bare marker, so `install` can self-repair
  # a block disabled by commenting.
  # shellcheck disable=SC2016
  local active_re='^[[:space:]]*\[\[ -f "\$HOME/\.cdd/tools/cdd-state\.sh" \]\] && source'
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
      # Present but inactive (commented/mangled): strip it, then re-append below.
      # index() matches the marker substring even when the line is commented.
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
[[ -f "\$HOME/.cdd/tools/cdd-state.sh" ]] && source "\$HOME/.cdd/tools/cdd-state.sh"
${marker_end}
RCBLOCK
    echo "Wired: $rc"
  done

  # Also expose `cdd-state` as an executable on PATH. The rc `source` line above
  # only reaches INTERACTIVE shells (a stock ~/.bashrc returns early for
  # non-interactive shells via its `case $- in *i*` guard). Slash commands run
  # `cdd-state set …` from Claude Code's Bash tool, which is non-interactive — so
  # without a PATH entry the function is undefined there and every state update
  # silently no-ops. This thin shim sources the helper and dispatches, so the
  # command resolves in any shell; interactive shells still prefer the sourced
  # function (functions shadow PATH), so behaviour is identical.
  local bin_dir="$HOME/.local/bin"
  local shim="$bin_dir/cdd-state"
  mkdir -p "$bin_dir"
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
# Managed by cdd-state.sh install — thin PATH entry point so `cdd-state` resolves
# in non-interactive shells too. Regenerated on each install; do not hand-edit.
# The guards are load-bearing: without them, a missing or broken helper leaves the
# function undefined, the call below re-resolves to THIS shim through PATH, and the
# result is unbounded recursion rather than an error.
helper="$HOME/.cdd/tools/cdd-state.sh"
if [[ ! -f "$helper" ]]; then
  echo "cdd-state: helper not found at $helper; reinstall with: bash <cdd>/tools/cdd-state.sh install" >&2
  exit 127
fi
# shellcheck source=/dev/null
source "$helper"
if ! declare -F cdd-state >/dev/null 2>&1; then
  echo "cdd-state: $helper did not define cdd-state; reinstall it." >&2
  exit 127
fi
cdd-state "$@"
SHIM
  chmod +x "$shim"
  echo "Installed PATH shim: $shim"
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "Note: $bin_dir is not on your PATH; add it so cdd-state resolves everywhere." >&2 ;;
  esac

  echo "Done. Open a new shell (or 'source' your rc) so cdd-state is available."
}

# Dual-mode: when executed directly, run the installer; when sourced, only the
# functions above are defined.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cdd-state-install "$@"
fi
