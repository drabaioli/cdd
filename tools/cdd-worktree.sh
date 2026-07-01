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
# The helper is a machine-global toolchain dependency, like git or gh: one install
# per machine, newest wins, install is idempotent (re-run to upgrade). Its contract
# with projects is frozen and deliberately tiny -- the three command names below
# plus the ~/.cdd/handoffs/<repo>/<branch>.md layout -- so a single current copy
# stays compatible with every project version. See the process doc section 2.8.
#
# Provides (when sourced):
#   cdd-worktree <branch>   Create a new worktree for <branch> and launch
#                               `claude` in plan mode in it with the suggested
#                               first prompt already submitted. Requires a
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
#                               GitHub, otherwise prompt), and delete the
#                               handoff file iff the branch was deleted.
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
#                               you to run /cdd-process-pr, /cdd-merge-base, or
#                               /cdd-pre-pr. With no argument, lists remote
#                               feature branches not already checked out and
#                               prompts for one. Run from the main worktree.

# Resolve the repo's default branch from origin's HEAD, falling back to "main".
# The remote is assumed to be named "origin" (see template/BOOTSTRAP.md).
cdd-worktree-default-branch() {
  local ref
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

  # The sibling worktree name is derived from $PWD; run from a feature worktree
  # this would nest names, so insist on the main worktree.
  local default_branch current_branch
  default_branch="$(cdd-worktree-default-branch)"
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  if [[ "$current_branch" != "$default_branch" ]]; then
    echo "Run this from the main worktree on '$default_branch' (current: '$current_branch')." >&2
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

  local repo_dir
  repo_dir="$(basename "$PWD")"
  local worktree_path="../${repo_dir}-${branch}"

  git worktree add -b "$branch" "$worktree_path" || return 1
  cd "$worktree_path" || return 1

  local first_prompt="Read ${handoff} and follow the Implementation prompt."
  claude --permission-mode plan "$first_prompt"
}

cdd-worktree-done() {
  local default_branch
  default_branch="$(cdd-worktree-default-branch)"
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  if [[ -z "$branch" || "$branch" == "$default_branch" || "$branch" == "HEAD" ]]; then
    echo "Run this from the feature branch worktree, not $default_branch (current: '$branch')." >&2
    return 1
  fi

  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Worktree has uncommitted changes, aborting." >&2
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

  local feature_path="$PWD"
  # Derive repo name from the main worktree so this works from any worktree.
  local repo_name
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
  local handoff="$HOME/.cdd/handoffs/${repo_name}/${branch}.md"
  # The per-task state record (written by the slash commands) is an additive
  # sibling of the handoff; it shares the handoff's deletion lifecycle.
  local state_file="${handoff%.md}.state.json"

  cd "$main_path" || return 1
  if ! git pull --ff-only origin "$default_branch"; then
    echo "git pull failed, aborting before cleanup." >&2
    return 1
  fi

  # 1. Worktree removal (handle root-owned build artefacts).
  if ! git worktree remove "$feature_path" 2>/dev/null; then
    echo
    echo "git worktree remove failed for $feature_path."
    echo "This usually means container builds left root-owned files behind"
    echo "(e.g. build/, .cache/) that your user can't delete."
    echo "Falling back to: sudo rm -rf \"$feature_path\" && git worktree prune"
    read -r -p "Proceed with sudo rm -rf? [y/N] " reply
    if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
      echo "Aborted. Worktree left in place." >&2
      return 1
    fi
    sudo rm -rf "$feature_path" || return 1
    git worktree prune
  fi

  # 2. Branch resolution.
  local branch_deleted=0

  if git branch --merged "$default_branch" --format='%(refname:short)' | grep -qx "$branch"; then
    git branch -d "$branch" && branch_deleted=1
  else
    local pr_num=""
    if command -v gh >/dev/null 2>&1; then
      pr_num="$(gh pr list --state merged --base "$default_branch" --head "$branch" \
                  --json number --jq '.[0].number' 2>/dev/null)"
    fi
    if [[ -n "$pr_num" ]]; then
      echo "Branch '$branch' was squash-merged via PR #$pr_num, force-deleting."
      git branch -D "$branch" && branch_deleted=1
    else
      echo
      echo "Branch '$branch' is not merged into $default_branch and has no merged PR."
      echo "Unmerged commits:"
      git log "$default_branch".."$branch" --oneline
      echo
      local choice
      read -r -p "[d]elete (-D) / [k]eep / [a]bort? " choice
      case "$choice" in
        d|D)
          git branch -D "$branch" && branch_deleted=1
          ;;
        k|K)
          echo "Keeping branch '$branch'. Handoff will also be kept (in-flight task)."
          ;;
        a|A|*)
          echo "Aborted. Worktree was already removed; branch and handoff left in place." >&2
          return 1
          ;;
      esac
    fi
  fi

  # 3. Handoff + state-record deletion (only if branch was actually deleted).
  if (( branch_deleted )); then
    [[ -f "$handoff" ]] && rm "$handoff" && echo "Removed handoff: $handoff"
    [[ -f "$state_file" ]] && rm "$state_file" && echo "Removed state: $state_file"
  else
    [[ -f "$handoff" ]] && echo "Kept handoff: $handoff"
    [[ -f "$state_file" ]] && echo "Kept state: $state_file"
  fi

  echo "Done. In $main_path on $default_branch at $(git rev-parse --short HEAD)."
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

  shopt -s nullglob
  local files=( "$handoff_dir"/*.md )
  shopt -u nullglob
  if (( ${#files[@]} == 0 )); then
    echo "No handoffs in $handoff_dir."
    return 0
  fi

  local have_gh=0
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    have_gh=1
  fi

  # Snapshot worktree branches once.
  local worktree_branches
  worktree_branches="$(git worktree list --porcelain 2>/dev/null \
                        | awk '$1 == "branch" { sub("refs/heads/", "", $2); print $2 }')"

  printf '%-40s  %-8s  %-8s  %-12s  %s\n' \
         "BRANCH" "WORKTREE" "BRANCH?" "PR" "STATUS"
  printf '%-40s  %-8s  %-8s  %-12s  %s\n' \
         "------" "--------" "-------" "--" "------"

  local f branch wt br pr status
  for f in "${files[@]}"; do
    branch="$(basename "$f" .md)"

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
    if (( have_gh )); then
      local pr_line
      pr_line="$(gh pr list --head "$branch" --state all \
                   --json number,state \
                   --jq '.[0] | select(.) | "#\(.number) \(.state)"' 2>/dev/null)"
      if [[ -n "$pr_line" ]]; then
        pr="$pr_line"
      fi
    fi

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

# Recreate a worktree on an EXISTING remote branch so a task started on another
# machine can be picked up here. Unlike cdd-worktree, this requires no handoff and
# tracks the remote branch rather than creating a new one. The handoff and state
# record are local-only and are NOT synced across machines (see process doc §2.8);
# the resume-side commands (/cdd-process-pr, /cdd-merge-base, /cdd-pre-pr) read
# PR/branch state from git and gh, not the handoff, so their absence is fine.
cdd-worktree-resume() {
  local branch="${1:-}"

  # Same guard as cdd-worktree: the sibling worktree name is derived from $PWD, so
  # insist on the main worktree to avoid nesting names.
  local default_branch current_branch
  default_branch="$(cdd-worktree-default-branch)"
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  if [[ "$current_branch" != "$default_branch" ]]; then
    echo "Run this from the main worktree on '$default_branch' (current: '$current_branch')." >&2
    return 1
  fi

  if ! git fetch origin; then
    echo "git fetch origin failed, aborting." >&2
    return 1
  fi

  # Snapshot worktree branches once (reused for discovery and already-exists).
  local worktree_branches
  worktree_branches="$(git worktree list --porcelain 2>/dev/null \
                        | awk '$1 == "branch" { sub("refs/heads/", "", $2); print $2 }')"

  if [[ -z "$branch" ]]; then
    # Discovery: remote feature branches (exclude default + HEAD) not already
    # checked out as a local worktree.
    local have_gh=0
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      have_gh=1
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
      if (( have_gh )); then
        pr_line="$(gh pr list --head "${candidates[$i]}" --state all \
                     --json number,state \
                     --jq '.[0] | select(.) | " (PR #\(.number) \(.state))"' 2>/dev/null)"
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
      echo "No remote branch origin/$branch (after fetch)." >&2
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
  echo "Handoff/state were NOT transferred (they're local to the originating machine)."
  echo "Resume-side commands read PR/branch state from git and gh, so this is fine."
  echo "Next: start Claude Code here and run /cdd-process-pr, /cdd-merge-base, or /cdd-pre-pr."
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

  # Wire each shell rc that exists; create ~/.bashrc if neither exists so there
  # is always at least one entry point.
  local marker_begin="# --- CDD worktree helper (managed by cdd-worktree.sh install) BEGIN ---"
  local marker_end="# --- CDD worktree helper END ---"
  local rc rcs=()
  [[ -f "$HOME/.bashrc" ]] && rcs+=("$HOME/.bashrc")
  [[ -f "$HOME/.zshrc"  ]] && rcs+=("$HOME/.zshrc")
  if (( ${#rcs[@]} == 0 )); then
    touch "$HOME/.bashrc"
    rcs+=("$HOME/.bashrc")
  fi
  for rc in "${rcs[@]}"; do
    if grep -qF "$marker_begin" "$rc" 2>/dev/null; then
      echo "Already wired: $rc (skipped)"
    else
      cat >> "$rc" <<RCBLOCK

${marker_begin}
[[ -f "\$HOME/.cdd/tools/cdd-worktree.sh" ]] && source "\$HOME/.cdd/tools/cdd-worktree.sh"
${marker_end}
RCBLOCK
      echo "Wired: $rc"
    fi
  done

  # Also expose the cdd-worktree* commands as executables on PATH. The rc
  # `source` line above only reaches INTERACTIVE shells (a stock ~/.bashrc
  # returns early for non-interactive shells via its `case $- in *i*` guard), so
  # without these shims the commands are "command not found" in a non-interactive
  # shell (e.g. Claude Code's Bash tool). Each shim sources the helper and
  # dispatches. Interactive shells still prefer the sourced function (functions
  # shadow PATH) — which matters for `cdd-worktree`/`-resume`, whose `cd` into the
  # new worktree only takes effect in the caller's shell when run as a function;
  # the shim keeps the command resolvable, the function keeps the cwd change.
  local bin_dir="$HOME/.local/bin" cmd
  mkdir -p "$bin_dir"
  for cmd in cdd-worktree cdd-worktree-resume cdd-worktree-list cdd-worktree-done; do
    cat > "$bin_dir/$cmd" <<SHIM
#!/usr/bin/env bash
# Managed by cdd-worktree.sh install — PATH entry point so this command resolves
# in non-interactive shells too. Regenerated on each install; do not hand-edit.
source "\$HOME/.cdd/tools/cdd-worktree.sh"
$cmd "\$@"
SHIM
    chmod +x "$bin_dir/$cmd"
  done
  echo "Installed PATH shims in $bin_dir: cdd-worktree, cdd-worktree-resume, cdd-worktree-list, cdd-worktree-done"
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
