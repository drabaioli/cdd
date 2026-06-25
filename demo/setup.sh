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
#   --local-only           Skip all GitHub steps and the worktree-helper install. For tests/CI.
#
# The instance name becomes the directory, so each instance gets its own handoff dir
# (~/.cdd/handoffs/<instance>/). The worktree helper is the shared, project-independent
# `cdd-worktree`, installed once — not a per-instance script.
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       NAME="${2:-}"; shift 2 ;;
    --base)       BASE_ARG="${2:-}"; shift 2 ;;
    --public)     VISIBILITY="--public"; shift ;;
    --private)    VISIBILITY="--private"; shift ;;
    --local-only) LOCAL_ONLY=1; shift ;;
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
"$BOOTSTRAP" --name "$NAME" --path "$TARGET" --overlay "$SEED_DIR"

if (( ! LOCAL_ONLY )); then
  ( cd "$TARGET" && gh repo create "$DIR" --source . --push "$VISIBILITY" )
  echo
  echo "GitHub repo created and pushed: $DIR"
fi

CDD_WORKTREE="$REPO_ROOT/tools/cdd-worktree.sh"

# Install the shared, project-independent worktree helper once (idempotent). This
# wires ~/.bashrc and ~/.zshrc to source ~/.cdd/tools/cdd-worktree.sh, so the
# `cdd-worktree` command is available for every CDD project — including this
# instance. Skipped under --local-only (CI path: no environment side effects).
if (( ! LOCAL_ONLY )); then
  "$CDD_WORKTREE" install
fi

if (( LOCAL_ONLY )); then
  cat <<EOF

Done. Instance '$INSTANCE' is ready at $TARGET

Next steps:
  1. Install the shared worktree helper once (if you haven't already):
       $CDD_WORKTREE install
  2. cd "$TARGET" and run \`claude\`, then /cdd-next-step to start Phase 1.

Tear it down later with: demo/teardown.sh $INSTANCE --local-only
EOF
else
  cat <<EOF

Done. Instance '$INSTANCE' is ready at $TARGET

Next steps:
  1. Open a new shell so the \`cdd-worktree\` command is active (the install above
     wired your ~/.bashrc and ~/.zshrc).
  2. cd "$TARGET" and run \`claude\`, then /cdd-next-step to start Phase 1.

Tear it down later with: demo/teardown.sh $INSTANCE
EOF
fi
