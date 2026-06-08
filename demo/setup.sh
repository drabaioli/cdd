#!/usr/bin/env bash
# Create a Markdown Renderer demo (or dogfood) instance: bootstrap the CDD
# template, overlay the filled-in seed, git init, then create + push a GitHub repo.
#
# Usage:
#   demo/setup.sh                      # next free demo instance: mdr_demo_NN
#   demo/setup.sh mdr                  # the kept dogfood instance "Markdown Renderer"
#   demo/setup.sh <instance>           # a named instance
#
# Options:
#   --name "Display Name"   Override the display name (<PROJECT_NAME>).
#   --base DIR              Base directory for the instance (default: $CDD_DEMO_BASE or ~/Code).
#   --public               Create the GitHub repo public (default: private).
#   --local-only           Skip all GitHub steps and rc-file update. For tests/CI.
#   --rc FILE              RC file to update (default: ~/.bashrc). Ignored under --local-only.
#
# The instance name becomes both the slug and the directory, so each instance is
# fully self-contained (its own <slug>-worktree command and its own handoff dir).
#
# Requires: git, the CDD bootstrap script, and (unless --local-only) an authenticated gh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=demo/lib.sh
source "$SCRIPT_DIR/lib.sh"

INSTANCE=""
NAME=""
BASE_ARG=""
LOCAL_ONLY=0
VISIBILITY="--private"
RC_FILE="${HOME}/.bashrc"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       NAME="${2:-}"; shift 2 ;;
    --base)       BASE_ARG="${2:-}"; shift 2 ;;
    --public)     VISIBILITY="--public"; shift ;;
    --private)    VISIBILITY="--private"; shift ;;
    --local-only) LOCAL_ONLY=1; shift ;;
    --rc)         RC_FILE="${2:-}"; shift 2 ;;
    -h|--help)    grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    -*)           demo_die "unknown option: $1" ;;
    *)            [[ -z "$INSTANCE" ]] || demo_die "unexpected argument: $1"; INSTANCE="$1"; shift ;;
  esac
done

demo_require_cmd git
[[ -x "$BOOTSTRAP" ]] || demo_die "bootstrap script not found/executable: $BOOTSTRAP"
[[ -d "$SEED_DIR" ]] || demo_die "seed directory not found: $SEED_DIR"

BASE="$(demo_base "$BASE_ARG")"

# Resolve the instance. With no argument, auto-pick the next free numbered demo,
# checking GitHub too (unless local-only) so we don't collide with a parked repo.
if [[ -z "$INSTANCE" ]]; then
  if (( LOCAL_ONLY )); then
    INSTANCE="$(demo_next_demo_instance "$BASE" 0)"
  else
    demo_gh_ready || demo_die "gh is not installed/authenticated; run 'gh auth login' or pass --local-only"
    INSTANCE="$(demo_next_demo_instance "$BASE" 1)"
  fi
fi

[[ "$INSTANCE" =~ ^[a-z][a-z0-9_-]*$ ]] || demo_die "instance must match ^[a-z][a-z0-9_-]*\$ (got: $INSTANCE)"

SLUG="$INSTANCE"
DIR="$INSTANCE"
if [[ -z "$NAME" ]]; then
  if [[ "$INSTANCE" == "mdr" ]]; then
    NAME="Markdown Renderer"
  else
    NAME="$INSTANCE"
  fi
fi

TARGET="$BASE/$DIR"

# Preflight before we touch anything.
if [[ -e "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
  demo_die "target directory exists and is not empty: $TARGET"
fi
if (( ! LOCAL_ONLY )); then
  demo_gh_ready || demo_die "gh is not installed/authenticated; run 'gh auth login' or pass --local-only"
  if demo_remote_repo_exists "$DIR"; then
    demo_die "a GitHub repo named '$DIR' already exists for this account"
  fi
fi

echo "Creating instance '$INSTANCE'"
echo "  display name : $NAME"
echo "  location     : $TARGET"
echo "  github        : $( (( LOCAL_ONLY )) && echo 'skipped (--local-only)' || echo "create + push ($VISIBILITY)" )"
echo

# Bootstrap the template, overlay the seed, substitute identifiers, git init + scaffold commit.
"$BOOTSTRAP" --name "$NAME" --slug "$SLUG" --path "$TARGET" --overlay "$SEED_DIR"

if (( ! LOCAL_ONLY )); then
  ( cd "$TARGET" && gh repo create "$DIR" --source . --push "$VISIBILITY" )
  echo
  echo "GitHub repo created and pushed: $DIR"
fi

WORKTREE_HELPER="$TARGET/tools/${SLUG}-worktree.sh"

# Append a marker-guarded sourcing block to the rc file so the worktree helper
# is available in new shells automatically. Skipped under --local-only (CI path).
if (( ! LOCAL_ONLY )); then
  RC_MARKER_BEGIN="# --- CDD demo: ${INSTANCE} BEGIN ---"
  RC_MARKER_END="# --- CDD demo: ${INSTANCE} END ---"
  if grep -qF "$RC_MARKER_BEGIN" "$RC_FILE" 2>/dev/null; then
    echo "RC file already contains block for '${INSTANCE}': $RC_FILE (skipped)"
  else
    cat >> "$RC_FILE" <<RCBLOCK

${RC_MARKER_BEGIN}
[[ -f "${WORKTREE_HELPER}" ]] && source "${WORKTREE_HELPER}"
${RC_MARKER_END}
RCBLOCK
    echo "Updated $RC_FILE — worktree helper will be sourced in new shells."
  fi
fi

if (( LOCAL_ONLY )); then
  cat <<EOF

Done. Instance '$INSTANCE' is ready at $TARGET

Next steps:
  1. Source the worktree helper in your shell:
       [[ -f "$WORKTREE_HELPER" ]] && source "$WORKTREE_HELPER"
  2. cd "$TARGET" and run \`claude\`, then /next-step to start Phase 1.

Tear it down later with: demo/teardown.sh $INSTANCE --local-only
EOF
else
  cat <<EOF

Done. Instance '$INSTANCE' is ready at $TARGET

Next steps:
  1. Open a new shell (or run: source "$RC_FILE") so the worktree helper is active.
     Fallback — source it manually in the current shell:
       [[ -f "$WORKTREE_HELPER" ]] && source "$WORKTREE_HELPER"
  2. cd "$TARGET" and run \`claude\`, then /next-step to start Phase 1.

Tear it down later with: demo/teardown.sh $INSTANCE
EOF
fi
