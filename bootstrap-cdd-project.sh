#!/usr/bin/env bash
# Bootstrap a new CDD project from the template/ directory next to this script.
#
# Usage:
#   bootstrap-cdd-project.sh \
#     --name "Display Name" \
#     --slug shell-slug \
#     --path /path/to/dir-slug
#
# The basename of --path becomes the directory slug (<PROJECT_DIR>). The path
# may be absolute or relative; it must not exist, or must be an empty directory.
#
# See template/BOOTSTRAP.md for the full procedure and the three-identifier model.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: bootstrap-cdd-project.sh --name "Display Name" --slug shell-slug --path /path/to/dir-slug

  --name  Display name; may contain spaces. E.g. "Sprint Planning Automation POC".
  --slug  Shell-command slug; lowercase, hyphens OK. Used in <slug>-worktree commands.
  --path  Path where the project will be created (absolute or relative). The basename
          becomes the directory slug. The path must not exist, or must be an empty
          directory.
EOF
  exit 2
}

PROJECT_NAME=""
PROJECT_SLUG=""
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) PROJECT_NAME="${2:-}"; shift 2 ;;
    --slug) PROJECT_SLUG="${2:-}"; shift 2 ;;
    --path) TARGET="${2:-}";       shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$PROJECT_NAME" ]] || { echo "error: --name is required" >&2; usage; }
[[ -n "$PROJECT_SLUG" ]] || { echo "error: --slug is required" >&2; usage; }
[[ -n "$TARGET"       ]] || { echo "error: --path is required" >&2; usage; }

# Derive the directory slug from the basename of --path. Strip any trailing slashes
# so `--path foo/` yields `foo`, not an empty basename.
TARGET="${TARGET%/}"
PROJECT_DIR="$(basename "$TARGET")"

# Slug and dir must be safe for shell identifiers and filesystem paths.
if ! [[ "$PROJECT_SLUG" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  echo "error: --slug must match ^[a-z][a-z0-9_-]*\$ (got: $PROJECT_SLUG)" >&2
  exit 2
fi
if ! [[ "$PROJECT_DIR" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  echo "error: basename of --path must match ^[a-z][a-z0-9_-]*\$ (got: $PROJECT_DIR)" >&2
  exit 2
fi

# Resolve template/ relative to this script's location so the script works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
[[ -d "$TEMPLATE_DIR" ]] || { echo "error: template/ not found next to script at $TEMPLATE_DIR" >&2; exit 1; }

# Refuse if target exists and is non-empty.
if [[ -e "$TARGET" ]]; then
  if [[ ! -d "$TARGET" ]]; then
    echo "error: target exists and is not a directory: $TARGET" >&2
    exit 1
  fi
  if [[ -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
    echo "error: target directory is not empty: $TARGET" >&2
    exit 1
  fi
fi

mkdir -p "$TARGET"

# Copy template tree, excluding BOOTSTRAP.md. Use rsync if available for the exclude;
# otherwise fall back to cp + rm.
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude 'BOOTSTRAP.md' "$TEMPLATE_DIR/" "$TARGET/"
else
  cp -a "$TEMPLATE_DIR/." "$TARGET/"
  rm -f "$TARGET/BOOTSTRAP.md"
fi

# Rename the worktree script before substitution.
mv "$TARGET/tools/PROJECT-worktree.sh" "$TARGET/tools/${PROJECT_SLUG}-worktree.sh"

# Substitute placeholders. Order matters:
#   1. <PROJECT_NAME>, <PROJECT_SLUG>, <PROJECT_DIR> first — angle brackets keep them unambiguous.
#   2. Bare PROJECT only inside the renamed worktree script, last.
# Use a sed delimiter unlikely to appear in any value (#); display names should be plain text.
escape_sed_repl() {
  # Escape characters special to sed's replacement side: \, &, and the delimiter (#).
  printf '%s' "$1" | sed -e 's/[\\&#]/\\&/g'
}

NAME_ESC=$(escape_sed_repl "$PROJECT_NAME")
SLUG_ESC=$(escape_sed_repl "$PROJECT_SLUG")
DIR_ESC=$(escape_sed_repl "$PROJECT_DIR")

# Walk every regular file in the target and substitute the angle-bracketed placeholders.
while IFS= read -r -d '' f; do
  sed -i \
    -e "s#<PROJECT_NAME>#${NAME_ESC}#g" \
    -e "s#<PROJECT_SLUG>#${SLUG_ESC}#g" \
    -e "s#<PROJECT_DIR>#${DIR_ESC}#g" \
    "$f"
done < <(find "$TARGET" -type f -print0)

# Bare PROJECT substitution: only inside the renamed worktree script.
# Word-boundary so we don't accidentally chew through prose containing the substring.
sed -i -E "s#\\bPROJECT\\b#${SLUG_ESC}#g" "$TARGET/tools/${PROJECT_SLUG}-worktree.sh"

# Initialise git and create the scaffold commit.
(
  cd "$TARGET"
  git init -b main >/dev/null
  git add .
  git -c commit.gpgsign=false commit -m "Initial CDD scaffold" >/dev/null
)

# Resolve the absolute target path for the printed instructions.
TARGET_ABS="$(cd "$TARGET" && pwd)"

cat <<EOF

Bootstrapped CDD project: $PROJECT_NAME
Location: $TARGET_ABS

Next steps:

  1. Add this line to your ~/.bashrc (or ~/.zshrc) and open a new shell:

       [[ -f "${TARGET_ABS}/tools/${PROJECT_SLUG}-worktree.sh" ]] && source "${TARGET_ABS}/tools/${PROJECT_SLUG}-worktree.sh"

  2. cd into $TARGET_ABS, fill in CLAUDE.md placeholders, and write the initial roadmap
     in doc/knowledge_base/roadmap.md.

  3. Run \`claude\` and invoke /next-step to start the first task.

EOF
