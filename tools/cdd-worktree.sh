# CDD worktree helpers, used by the CDD repo itself.
#
# This is CDD's own copy of the worktree helper. The generic version, with
# placeholders, lives at template/tools/PROJECT-worktree.sh and is what new
# projects copy. If you change behaviour here, propagate to the template (and
# vice versa); unintended drift between the two is a defect.
#
# Source this file from ~/.bashrc:
#   [[ -f "$HOME/Code/cdd/tools/cdd-worktree.sh" ]] && \
#     source "$HOME/Code/cdd/tools/cdd-worktree.sh"
#
# (Adjust the path to wherever you've cloned the CDD repo.)
#
# Provides:
#   cdd-worktree <branch>   Create a new worktree for <branch> and launch
#                               `claude` in plan mode in it with the suggested
#                               first prompt already submitted. Requires a
#                               handoff file at
#                               ~/.claude-handoffs/cdd/<branch>.md (run
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
#   cdd-worktree-list       List all active handoffs in ~/.claude-handoffs/cdd/
#                               with worktree / branch / PR status. Highlights
#                               stale entries (handoff with no branch and no
#                               worktree) so they're obvious to clean up.

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
  local handoff_dir="$HOME/.claude-handoffs/${repo_name}"
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
  local handoff="$HOME/.claude-handoffs/${repo_name}/${branch}.md"

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

  # 3. Handoff deletion (only if branch was actually deleted).
  if (( branch_deleted )) && [[ -f "$handoff" ]]; then
    rm "$handoff" && echo "Removed handoff: $handoff"
  elif [[ -f "$handoff" ]]; then
    echo "Kept handoff: $handoff"
  fi

  echo "Done. In $main_path on $default_branch at $(git rev-parse --short HEAD)."
}

cdd-worktree-list() {
  # Derive repo name from the main worktree so this works from any worktree.
  local repo_name
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
  local handoff_dir="$HOME/.claude-handoffs/${repo_name}"
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
