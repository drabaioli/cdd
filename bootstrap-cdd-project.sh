#!/usr/bin/env bash
# Bootstrap a new CDD project from the template/ directory next to this script.
#
# Usage:
#   bootstrap-cdd-project.sh \
#     --name "Display Name" \
#     --slug shell-slug \
#     --path /path/to/dir-slug \
#     [--overlay /path/to/seed ...] \
#     [--stage --dir dir-slug] [--template-dir DIR]
#
# The basename of --path becomes the directory slug (<PROJECT_DIR>). The path
# may be absolute or relative; it must not exist, or must be an empty directory.
#
# --overlay DIR (repeatable) copies DIR over the template tree before placeholder
# substitution, so overlaid files are substituted too. Used by the demo/ subsystem
# to lay a filled-in seed project over the generic template. Order is preserved:
# later overlays win over earlier ones and over the template.
#
# --stage renders the substituted template only: no git init, no scaffold commit.
# Used by /retrofit to stage a render that is then merged into an existing project.
# Because a staging path's basename is typically a throwaway tmp name, --dir is
# required with --stage to supply the real <PROJECT_DIR> value.
#
# --template-dir DIR substitutes from DIR instead of the template/ next to this
# script. Used by /retrofit upgrade mode to render an old template snapshot
# (extracted via `git show`) through the same substitution path.
#
# In both modes the script writes a one-line baseline marker, .claude/cdd-baseline,
# holding the CDD repo commit hash the template was rendered from (or "unknown"
# when this script does not live in a git checkout). /retrofit upgrade mode uses
# it as the three-way merge base.
#
# See template/BOOTSTRAP.md for the full procedure and the three-identifier model.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: bootstrap-cdd-project.sh --name "Display Name" --slug shell-slug --path /path/to/dir-slug [--overlay DIR ...] [--stage --dir dir-slug] [--template-dir DIR]

  --name          Display name; may contain spaces. E.g. "Sprint Planning Automation POC".
  --slug          Shell-command slug; lowercase, hyphens OK. Used in <slug>-worktree commands.
  --path          Path where the project will be created (absolute or relative). The basename
                  becomes the directory slug. The path must not exist, or must be an empty
                  directory.
  --overlay       Directory copied over the template before substitution (repeatable). Lets a
                  filled-in seed override template files; overlaid files are substituted too.
  --stage         Render-only mode: substitute into --path but skip git init and the scaffold
                  commit. Requires --dir. Used by /retrofit to stage a render for merging
                  into an existing project.
  --dir           Override the directory slug (<PROJECT_DIR>) instead of deriving it from the
                  basename of --path. Required with --stage.
  --template-dir  Substitute from this directory instead of the template/ next to the script.
                  Used by /retrofit upgrade mode to render an old template snapshot.
EOF
  exit 2
}

PROJECT_NAME=""
PROJECT_SLUG=""
TARGET=""
OVERLAYS=()
STAGE=""
DIR_OVERRIDE=""
TEMPLATE_DIR_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)         PROJECT_NAME="${2:-}";          shift 2 ;;
    --slug)         PROJECT_SLUG="${2:-}";          shift 2 ;;
    --path)         TARGET="${2:-}";                shift 2 ;;
    --overlay)      OVERLAYS+=("${2:-}");           shift 2 ;;
    --stage)        STAGE=1;                        shift ;;
    --dir)          DIR_OVERRIDE="${2:-}";          shift 2 ;;
    --template-dir) TEMPLATE_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$PROJECT_NAME" ]] || { echo "error: --name is required" >&2; usage; }
[[ -n "$PROJECT_SLUG" ]] || { echo "error: --slug is required" >&2; usage; }
[[ -n "$TARGET"       ]] || { echo "error: --path is required" >&2; usage; }
if [[ -n "$STAGE" && -z "$DIR_OVERRIDE" ]]; then
  echo "error: --stage requires --dir (a staging path's basename is not the real <PROJECT_DIR>)" >&2
  usage
fi

# Derive the directory slug from the basename of --path (or take the --dir
# override). Strip any trailing slashes so `--path foo/` yields `foo`, not an
# empty basename.
TARGET="${TARGET%/}"
PROJECT_DIR="${DIR_OVERRIDE:-$(basename "$TARGET")}"

# Slug and dir must be safe for shell identifiers and filesystem paths.
if ! [[ "$PROJECT_SLUG" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  echo "error: --slug must match ^[a-z][a-z0-9_-]*\$ (got: $PROJECT_SLUG)" >&2
  exit 2
fi
if ! [[ "$PROJECT_DIR" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  if [[ -n "$DIR_OVERRIDE" ]]; then
    echo "error: --dir must match ^[a-z][a-z0-9_-]*\$ (got: $PROJECT_DIR)" >&2
  else
    echo "error: basename of --path must match ^[a-z][a-z0-9_-]*\$ (got: $PROJECT_DIR)" >&2
  fi
  exit 2
fi

# Resolve template/ relative to this script's location so the script works from
# any CWD; --template-dir overrides it (e.g. an old template snapshot).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR_OVERRIDE:-$SCRIPT_DIR/template}"
[[ -d "$TEMPLATE_DIR" ]] || { echo "error: template dir not found: $TEMPLATE_DIR" >&2; exit 1; }

# Validate overlay directories up front so we fail before touching the target.
for overlay in "${OVERLAYS[@]}"; do
  [[ -d "$overlay" ]] || { echo "error: --overlay dir not found: $overlay" >&2; exit 1; }
done

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

# Overlay any seed directories over the template tree, in order. Overlaid files
# overwrite template files of the same path; substitution below covers them all.
for overlay in "${OVERLAYS[@]}"; do
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$overlay/" "$TARGET/"
  else
    cp -a "$overlay/." "$TARGET/"
  fi
done

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

# Write the baseline marker: the CDD repo commit this render came from. /retrofit
# upgrade mode uses it as the three-way merge base. "unknown" when the script is
# run outside a git checkout (e.g. shipped standalone).
mkdir -p "$TARGET/.claude"
CDD_BASELINE="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
printf '%s\n' "$CDD_BASELINE" > "$TARGET/.claude/cdd-baseline"

# Resolve the absolute target path for the printed instructions.
TARGET_ABS="$(cd "$TARGET" && pwd)"

# Stage mode stops here: no git init, no scaffold commit, terse output for the
# /retrofit command that drives it.
if [[ -n "$STAGE" ]]; then
  cat <<EOF
Staged CDD template render at: $TARGET_ABS
(stage mode: no git init, no scaffold commit; baseline marker written: $CDD_BASELINE)
EOF
  exit 0
fi

# Initialise git and create the scaffold commit.
(
  cd "$TARGET"
  git init -b main >/dev/null
  git add .
  git -c commit.gpgsign=false commit -m "Initial CDD scaffold" >/dev/null
)

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
