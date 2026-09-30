#!/usr/bin/env bash
# Bootstrap a new CDD project from the repo-root template/ directory.
#
# Usage:
#   bootstrap-cdd-project.sh \
#     --name "Display Name" \
#     --path /path/to/dir-slug \
#     [--overlay /path/to/seed ...] \
#     [--tracker BACKEND] [--code-host BACKEND] [--jira-site HOST --jira-key KEY] \
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
# Used by /cdd-retrofit to stage a render that is then merged into an existing project.
# Because a staging path's basename is typically a throwaway tmp name, --dir is
# required with --stage to supply the real <PROJECT_DIR> value.
#
# --template-dir DIR substitutes from DIR instead of the repo-root template/.
# Used by /cdd-retrofit upgrade mode to render an old template snapshot
# (extracted via `git show`) through the same substitution path.
#
# --tracker / --code-host BACKEND bind the project to a shipped capability adapter
# (tools/adapters/<cap>/<BACKEND>.sh) by writing .cdd/<cap>: a small committed shim
# that execs the machine-global adapter library at ~/.cdd/tools/adapters/<cap>/, which
# `cdd-worktree.sh install` provides (ADR 0011). The shim carries the backend and, for
# Jira, the non-secret coordinates (--jira-site, --jira-key) -- never a credential, and
# no path to this checkout, so the binding works from a clone on any machine. A backend
# with no shipped adapter is refused (exit 2). Opt-in: no flag, no .cdd/. Honoured under
# --stage too, which is how /cdd-retrofit renders bindings for approval.
#
# In both modes the script writes a one-line baseline marker, .claude/cdd-baseline,
# holding the CDD repo commit hash the template was rendered from (or "unknown"
# when this script does not live in a git checkout). /cdd-retrofit upgrade mode uses
# it as the three-way merge base.
#
# See template/BOOTSTRAP.md for the full procedure and the two-identifier model.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: bootstrap-cdd-project.sh --name "Display Name" --path /path/to/dir-slug [--overlay DIR ...]
         [--tracker BACKEND] [--code-host BACKEND] [--jira-site HOST --jira-key KEY]
         [--stage --dir dir-slug] [--template-dir DIR]

  --name          Display name; may contain spaces. E.g. "Sprint Planning Automation POC".
  --path          Path where the project will be created (absolute or relative). The basename
                  becomes the directory slug. The path must not exist, or must be an empty
                  directory.
  --overlay       Directory copied over the template before substitution (repeatable). Lets a
                  filled-in seed override template files; overlaid files are substituted too.
  --tracker       Bind the tracker capability to a shipped adapter (github, jira): writes
                  .cdd/tracker, a shim onto ~/.cdd/tools/adapters/tracker/BACKEND.sh.
  --code-host     Bind the code-host capability to a shipped adapter (github): writes
                  .cdd/code-host, a shim onto ~/.cdd/tools/adapters/code-host/BACKEND.sh.
  --jira-site     With --tracker jira (required): the Jira Cloud site, e.g. acme.atlassian.net.
  --jira-key      With --tracker jira (required): the Jira project key, e.g. ABC.
                  Credentials (JIRA_EMAIL, the API token) are never written; they stay in
                  the user's shell.
  --stage         Render-only mode: substitute into --path but skip git init and the scaffold
                  commit. Requires --dir. Used by /cdd-retrofit to stage a render for merging
                  into an existing project.
  --dir           Override the directory slug (<PROJECT_DIR>) instead of deriving it from the
                  basename of --path. Required with --stage.
  --template-dir  Substitute from this directory instead of the repo-root template/.
                  Used by /cdd-retrofit upgrade mode to render an old template snapshot.
EOF
  exit 2
}

PROJECT_NAME=""
TARGET=""
OVERLAYS=()
STAGE=""
DIR_OVERRIDE=""
TEMPLATE_DIR_OVERRIDE=""
BIND_TRACKER=""
BIND_CODE_HOST=""
JIRA_SITE=""
JIRA_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)         PROJECT_NAME="${2:-}";          shift 2 ;;
    --path)         TARGET="${2:-}";                shift 2 ;;
    --overlay)      OVERLAYS+=("${2:-}");           shift 2 ;;
    --stage)        STAGE=1;                        shift ;;
    --dir)          DIR_OVERRIDE="${2:-}";          shift 2 ;;
    --template-dir) TEMPLATE_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    --tracker)      BIND_TRACKER="${2:-}";          shift 2 ;;
    --code-host)    BIND_CODE_HOST="${2:-}";        shift 2 ;;
    --jira-site)    JIRA_SITE="${2:-}";             shift 2 ;;
    --jira-key)     JIRA_KEY="${2:-}";              shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$PROJECT_NAME" ]] || { echo "error: --name is required" >&2; usage; }
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

# Dir must be safe for shell identifiers and filesystem paths.
if ! [[ "$PROJECT_DIR" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
  if [[ -n "$DIR_OVERRIDE" ]]; then
    echo "error: --dir must match ^[A-Za-z][A-Za-z0-9_-]*\$ (got: $PROJECT_DIR)" >&2
  else
    echo "error: basename of --path must match ^[A-Za-z][A-Za-z0-9_-]*\$ (got: $PROJECT_DIR)" >&2
  fi
  exit 2
fi

# Resolve template/ relative to this script's location so the script works from
# any CWD; --template-dir overrides it (e.g. an old template snapshot). The script
# lives in tools/, so template/ is one level up at the repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR_OVERRIDE:-$REPO_ROOT/template}"
[[ -d "$TEMPLATE_DIR" ]] || { echo "error: template dir not found: $TEMPLATE_DIR" >&2; exit 1; }

# Validate overlay directories up front so we fail before touching the target.
for overlay in "${OVERLAYS[@]}"; do
  [[ -d "$overlay" ]] || { echo "error: --overlay dir not found: $overlay" >&2; exit 1; }
done

# Validate the adapter bindings up front too. A backend binds only if CDD ships an
# adapter for it; anything else is refused rather than written as a dangling shim.
for pair in "tracker:$BIND_TRACKER" "code-host:$BIND_CODE_HOST"; do
  cap="${pair%%:*}" backend="${pair#*:}"
  [[ -z "$backend" ]] && continue
  if ! [[ "$backend" =~ ^[a-z0-9][a-z0-9_-]*$ && -f "$SCRIPT_DIR/adapters/$cap/$backend.sh" ]]; then
    echo "error: CDD ships no $cap adapter for '$backend'" >&2
    exit 2
  fi
done
if [[ "$BIND_TRACKER" == "jira" ]]; then
  [[ -n "$JIRA_SITE" && -n "$JIRA_KEY" ]] || { echo "error: --tracker jira requires --jira-site and --jira-key" >&2; exit 2; }
elif [[ -n "$JIRA_SITE$JIRA_KEY" ]]; then
  echo "error: --jira-site / --jira-key apply only with --tracker jira" >&2
  exit 2
fi
if [[ -n "$JIRA_KEY" ]] && ! [[ "$JIRA_KEY" =~ ^[A-Z][A-Z0-9_]+$ ]]; then
  echo "error: --jira-key must match ^[A-Z][A-Z0-9_]+\$ (got: $JIRA_KEY)" >&2
  exit 2
fi
if [[ -n "$JIRA_SITE" ]]; then
  # Normalize to https://<host>: the scheme and a trailing slash may be given or not.
  JIRA_SITE="${JIRA_SITE#https://}"
  JIRA_SITE="${JIRA_SITE%/}"
  if ! [[ "$JIRA_SITE" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "error: --jira-site must be a bare host such as acme.atlassian.net (got: $JIRA_SITE)" >&2
    exit 2
  fi
  JIRA_SITE="https://$JIRA_SITE"
fi

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

# Substitute placeholders. The angle brackets keep <PROJECT_NAME> and <PROJECT_DIR>
# unambiguous. Use a sed delimiter unlikely to appear in any value (#); display
# names should be plain text.
escape_sed_repl() {
  # Escape characters special to sed's replacement side: \, &, and the delimiter (#).
  printf '%s' "$1" | sed -e 's/[\\&#]/\\&/g'
}

NAME_ESC=$(escape_sed_repl "$PROJECT_NAME")
DIR_ESC=$(escape_sed_repl "$PROJECT_DIR")

# Walk every regular file in the target and substitute the angle-bracketed placeholders.
# Skip binary files (grep -I treats them as non-matching) so an overlay can carry
# images or other binary assets without sed corrupting them.
while IFS= read -r -d '' f; do
  grep -Iq . "$f" || continue
  sed -i \
    -e "s#<PROJECT_NAME>#${NAME_ESC}#g" \
    -e "s#<PROJECT_DIR>#${DIR_ESC}#g" \
    "$f"
done < <(find "$TARGET" -type f -print0)

# Write the adapter bindings: one .cdd/<cap> shim per bound capability. The shim
# reaches the adapter through $HOME, never through this checkout's path, so it works
# from a clone on any machine that ran `cdd-worktree.sh install`; where the library is
# missing it exits 4 with the install command, which the resolution ladder treats as
# a broken adapter (a stop, never a silent fallback). Written after substitution so no
# placeholder pass touches it; never over an existing file.
BOUND=""
write_binding() {
  local cap="$1" backend="$2" f="$TARGET/.cdd/$1"
  [[ -z "$backend" ]] && return 0
  if [[ -e "$f" ]]; then
    echo "note: $f already exists; left as is." >&2
    return 0
  fi
  mkdir -p "$TARGET/.cdd"
  {
    cat <<SHIM
#!/usr/bin/env bash
# CDD capability adapter binding: $cap -> $backend. Written by bootstrap-cdd-project.sh.
# Coordinates only, never a secret. The adapter body is machine-global (installed by
# \`cdd-worktree.sh install\`); see the CDD repo's doc/architecture/capability-adapters.md.
SHIM
    if [[ "$cap" == "tracker" && "$backend" == "jira" ]]; then
      cat <<SHIM
# Credentials stay in your own shell: export JIRA_EMAIL and the Jira API token there.
export JIRA_BASE_URL='$JIRA_SITE' JIRA_PROJECT_KEY='$JIRA_KEY'
SHIM
    fi
    cat <<SHIM
lib="\$HOME/.cdd/tools/adapters/$cap/$backend.sh"
if [ ! -x "\$lib" ]; then
  echo "adapter library missing: \$lib; install once per machine: <cdd>/tools/cdd-worktree.sh install, or: curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/adapters/$cap/$backend.sh --create-dirs -o \"\$lib\" && chmod +x \"\$lib\"" >&2
  exit 4
fi
exec "\$lib" "\$@"
SHIM
  } > "$f"
  chmod 755 "$f"
  BOUND="${BOUND:+$BOUND, }$cap -> $backend"
}
write_binding tracker "$BIND_TRACKER"
write_binding code-host "$BIND_CODE_HOST"

# Write the baseline marker: the CDD repo commit this render came from. /cdd-retrofit
# upgrade mode uses it as the three-way merge base. "unknown" when the script is
# run outside a git checkout (e.g. shipped standalone).
mkdir -p "$TARGET/.claude"
CDD_BASELINE="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
printf '%s\n' "$CDD_BASELINE" > "$TARGET/.claude/cdd-baseline"

# Resolve the absolute target path for the printed instructions.
TARGET_ABS="$(cd "$TARGET" && pwd)"

# Stage mode stops here: no git init, no scaffold commit, terse output for the
# /cdd-retrofit command that drives it.
if [[ -n "$STAGE" ]]; then
  cat <<EOF
Staged CDD template render at: $TARGET_ABS
(stage mode: no git init, no scaffold commit; baseline marker written: $CDD_BASELINE)
EOF
  if [[ -n "$BOUND" ]]; then
    echo "Adapter bindings staged in .cdd/: $BOUND"
  fi
  exit 0
fi

# Initialise git and create the scaffold commit.
(
  cd "$TARGET"
  git init -b main >/dev/null
  git add .
  git -c commit.gpgsign=false commit -m "Initial CDD scaffold" >/dev/null
)

# Record the new repo in ~/.cdd/handoffs/<repo>/repo.json, so it is locatable before
# it has any task artifacts. Reuse the state helper's writer rather than a second
# copy of the JSON shape: sourcing it defines functions only (it installs only when
# executed directly), and the writer is advisory — it warns and returns 0 on a
# missing jq or an unwritable dir, so it can't fail the bootstrap under `set -e`.
# Runs from inside $TARGET, since the writer derives the path from git. Skipped if the
# sibling helper is absent (script copied out on its own) — also advisory.
if [[ -f "$SCRIPT_DIR/cdd-state.sh" ]]; then
  (
    cd "$TARGET"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/cdd-state.sh"
    cdd-state-write-repo-marker
  )
else
  echo "note: $SCRIPT_DIR/cdd-state.sh not found; skipped the ~/.cdd/handoffs/<repo>/repo.json marker." >&2
fi

cat <<EOF

Bootstrapped CDD project: $PROJECT_NAME
Location: $TARGET_ABS

Next steps:

  1. One-time, if you haven't already: install the shared CDD worktree helper, then
     open a new shell. After that, \`cdd-worktree <branch>\` works in every CDD project.

       ${SCRIPT_DIR}/cdd-worktree.sh install

  2. cd into $TARGET_ABS, fill in CLAUDE.md placeholders, and write the initial roadmap
     in doc/knowledge_base/roadmap.md.

  3. Run \`claude\` and invoke /cdd-next-step to start the first task.

EOF
if [[ -n "$BOUND" ]]; then
  cat <<EOF
Adapter bindings committed in .cdd/: $BOUND
  Their adapter code comes from the adapter library that step 1's install provides;
  re-run that install if the helper was installed before this CDD version.
EOF
  if [[ "$BIND_TRACKER" == "jira" ]]; then
    echo "  Jira: export JIRA_EMAIL and JIRA_API_TOKEN in your own shell; neither is written to the project."
  fi
  echo
fi
