#!/usr/bin/env bash
# Tear down a Markdown Renderer demo/dogfood instance: remove its local directory
# and delete its GitHub repo.
#
# Usage:
#   demo/teardown.sh <instance>        # e.g. mdr_demo_03, or mdr
#
# Options:
#   --base DIR     Base directory the instance lives in (default: $CDD_DEMO_BASE or ~/Code).
#   --local-only   Only remove the local directory; leave the GitHub repo alone.
#                  Also skips rc-file cleanup (mirrors setup.sh --local-only behaviour).
#   --rc FILE      RC file to clean up (default: ~/.bashrc). Ignored under --local-only.
#   --yes          Skip the confirmation prompt.
#
# Deleting the GitHub repo requires the 'delete_repo' scope on your gh token:
#   gh auth refresh -s delete_repo
# Without it, `gh repo delete` fails and the local directory is still removed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=demo/lib.sh
source "$SCRIPT_DIR/lib.sh"

INSTANCE=""
BASE_ARG=""
LOCAL_ONLY=0
ASSUME_YES=0
RC_FILE="${HOME}/.bashrc"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)       BASE_ARG="${2:-}"; shift 2 ;;
    --local-only) LOCAL_ONLY=1; shift ;;
    --rc)         RC_FILE="${2:-}"; shift 2 ;;
    --yes|-y)     ASSUME_YES=1; shift ;;
    -h|--help)    grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    -*)           demo_die "unknown option: $1" ;;
    *)            [[ -z "$INSTANCE" ]] || demo_die "unexpected argument: $1"; INSTANCE="$1"; shift ;;
  esac
done

[[ -n "$INSTANCE" ]] || demo_die "usage: teardown.sh <instance> [--base DIR] [--local-only] [--rc FILE] [--yes]"

BASE="$(demo_base "$BASE_ARG")"
TARGET="$BASE/$INSTANCE"

DELETE_REMOTE=0
if (( ! LOCAL_ONLY )) && demo_remote_repo_exists "$INSTANCE"; then
  DELETE_REMOTE=1
fi

if [[ ! -d "$TARGET" ]] && (( ! DELETE_REMOTE )); then
  demo_die "nothing to do: no local dir at $TARGET and no GitHub repo '$INSTANCE'"
fi

# Guard: refuse to delete a local directory that is not a bootstrapped CDD project.
if [[ -d "$TARGET" ]] && ! demo_is_cdd_project "$TARGET"; then
  demo_die "$TARGET does not look like a CDD project (no CLAUDE.md + tools/*-worktree.sh); refusing to delete"
fi

echo "About to tear down instance '$INSTANCE':"
[[ -d "$TARGET" ]] && echo "  - remove local directory: $TARGET"
(( DELETE_REMOTE )) && echo "  - delete GitHub repo:     $INSTANCE"
echo

if (( ! ASSUME_YES )); then
  read -r -p "Proceed? [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || demo_die "aborted"
fi

# Remove the marker-guarded sourcing block from the rc file before removing the
# local directory. Skipped under --local-only (mirrors setup.sh behaviour).
if (( ! LOCAL_ONLY )); then
  RC_MARKER_BEGIN="# --- CDD demo: ${INSTANCE} BEGIN ---"
  RC_MARKER_END="# --- CDD demo: ${INSTANCE} END ---"
  if [[ -f "$RC_FILE" ]] && grep -qF "$RC_MARKER_BEGIN" "$RC_FILE"; then
    # Delete from BEGIN line to END line inclusive (works on GNU and BSD sed).
    sed -i.bak "/$(printf '%s' "$RC_MARKER_BEGIN" | sed 's/[\/&]/\\&/g')/,/$(printf '%s' "$RC_MARKER_END" | sed 's/[\/&]/\\&/g')/d" "$RC_FILE" \
      && rm -f "${RC_FILE}.bak"
    echo "Removed worktree helper block for '${INSTANCE}' from $RC_FILE"
  fi
fi

if [[ -d "$TARGET" ]]; then
  rm -rf "$TARGET"
  echo "Removed local directory: $TARGET"
fi

if (( DELETE_REMOTE )); then
  if gh repo delete "$INSTANCE" --yes; then
    echo "Deleted GitHub repo: $INSTANCE"
  else
    echo "warning: failed to delete GitHub repo '$INSTANCE'." >&2
    echo "         The 'delete_repo' scope is required: gh auth refresh -s delete_repo" >&2
    exit 1
  fi
fi
