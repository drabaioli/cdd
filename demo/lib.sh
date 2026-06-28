#!/usr/bin/env bash
# Shared helpers for the demo/ automation (setup.sh and teardown.sh).
#
# Not meant to be run directly; both scripts `source` it. Defines:
#   - REPO_ROOT / SEED_DIR             paths into the CDD repo
#   - demo_base                        resolve the base directory for instances
#   - demo_die / demo_require_cmd      small utilities
#   - demo_gh_ready                    is gh installed and authenticated?
#   - demo_remote_repo_exists NAME     does a GitHub repo of this name exist?
#   - demo_next_demo_instance BASE B   next free mdr_demo_NN (B=1 also checks GitHub)
#   - demo_is_cdd_project DIR          sentinel check before destructive ops

# Resolve repo paths relative to this file, so the scripts work from any CWD.
_DEMO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_DEMO_LIB_DIR/.." && pwd)"
# shellcheck disable=SC2034  # consumed by the scripts that source this file
SEED_DIR="$_DEMO_LIB_DIR/seed"
# shellcheck disable=SC2034  # consumed by the scripts that source this file
BOOTSTRAP="$REPO_ROOT/tools/bootstrap-cdd-project.sh"

# Numbered demo instances share this prefix; the dogfood instance is just "mdr".
DEMO_PREFIX="mdr_demo_"

demo_die() { echo "error: $*" >&2; exit 1; }

demo_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || demo_die "required command not found: $1"
}

# Base directory where instances are created. Override with --base or CDD_DEMO_BASE.
demo_base() {
  printf '%s' "${1:-${CDD_DEMO_BASE:-$HOME/Code}}"
}

# True if gh is installed and authenticated.
demo_gh_ready() {
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

# True if a GitHub repo of the given name exists for the authenticated account.
demo_remote_repo_exists() {
  local name="$1"
  demo_gh_ready || return 1
  gh repo view "$name" >/dev/null 2>&1
}

# Print the next free numbered demo instance (e.g. mdr_demo_03). Scans local dirs
# under BASE; if the second arg is "1", also scans existing GitHub repos.
demo_next_demo_instance() {
  local base="$1" check_remote="${2:-0}" max=0 n name

  if [[ -d "$base" ]]; then
    for dir in "$base/${DEMO_PREFIX}"*; do
      [[ -d "$dir" ]] || continue
      name="$(basename "$dir")"
      if [[ "$name" =~ ^${DEMO_PREFIX}([0-9]+)$ ]]; then
        n=$((10#${BASH_REMATCH[1]}))
        (( n > max )) && max=$n
      fi
    done
  fi

  if [[ "$check_remote" == "1" ]] && demo_gh_ready; then
    while IFS= read -r name; do
      if [[ "$name" =~ ^${DEMO_PREFIX}([0-9]+)$ ]]; then
        n=$((10#${BASH_REMATCH[1]}))
        (( n > max )) && max=$n
      fi
    done < <(gh repo list --limit 1000 --json name --jq '.[].name' 2>/dev/null)
  fi

  printf '%s%02d' "$DEMO_PREFIX" $((max + 1))
}

# True if DIR looks like a bootstrapped CDD project (sentinel for destructive ops).
demo_is_cdd_project() {
  local dir="$1"
  [[ -f "$dir/CLAUDE.md" && -f "$dir/.claude/cdd-baseline" ]]
}
