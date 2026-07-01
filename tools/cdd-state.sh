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
#                                      `scoped` with an empty `sessions`. Used by
#                                      /cdd-next-step on the default branch.
#   cdd-state set <stage> [--pr N] Advance an existing record to <stage> (and set
#                                      the PR number with --pr). Derives repo/branch
#                                      from the current worktree. Skips silently if
#                                      the record is absent (writers never fabricate
#                                      one). Appends a {id, stage} entry for
#                                      $CLAUDE_CODE_SESSION_ID unless it is empty or
#                                      already the last entry's id.
#
# Stages (a single enum; the record carries no separate status):
#   scoped  plan_approved  implementation_done  merged  checks_passed  pr_open  addressed

# The schema version this helper writes; consumers version their parser on it.
CDD_STATE_SCHEMA_VERSION=1

cdd-state-stages() {
  printf '%s\n' scoped plan_approved implementation_done merged checks_passed pr_open addressed
}

# Path to the state record for the current worktree's branch.
cdd-state-file() {
  local repo_name branch
  repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")")" || return 1
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  printf '%s\n' "$HOME/.cdd/handoffs/${repo_name}/${branch}.state.json"
}

# Atomic write: render to a temp file in the same dir, then mv into place.
cdd-state-write() {
  local dest="$1" content="$2" tmp
  tmp="$(mktemp "${dest}.XXXXXX")" || return 1
  printf '%s\n' "$content" >"$tmp" && mv -f "$tmp" "$dest"
}

cdd-state() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "cdd-state: jq not found; skipping state update (advisory)." >&2
    return 0
  fi

  local cmd="$1"; shift 2>/dev/null
  case "$cmd" in
    seed)
      local branch="$1"
      if [[ -z "$branch" ]]; then
        echo "usage: cdd-state seed <branch>" >&2
        return 2
      fi
      local repo_name dir
      repo_name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")")" || return 1
      dir="$HOME/.cdd/handoffs/${repo_name}"
      mkdir -p "$dir"
      local content
      content="$(jq -n \
        --argjson v "$CDD_STATE_SCHEMA_VERSION" \
        --arg branch "$branch" \
        '{schema_version: $v, branch: $branch, stage: "scoped", pr: null, sessions: []}')" || return 1
      cdd-state-write "${dir}/${branch}.state.json" "$content" \
        && echo "Seeded state: ${dir}/${branch}.state.json"
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
      local file
      file="$(cdd-state-file)" || return 1
      # Writers never fabricate a record; only `seed` (i.e. /cdd-next-step) creates one.
      if [[ ! -f "$file" ]]; then
        echo "cdd-state: no record at $file; skipping (advisory)." >&2
        return 0
      fi
      local filter='.stage = $stage'
      [[ -n "$pr" ]] && filter="$filter | .pr = (\$pr | tonumber)"
      # Append this session unless CLAUDE_CODE_SESSION_ID is empty or already the
      # last entry's id (dedups repeated writes within one session).
      local sid="${CLAUDE_CODE_SESSION_ID:-}"
      if [[ -n "$sid" ]]; then
        filter="$filter | if (.sessions[-1].id // \"\") == \$sid then . else .sessions += [{id: \$sid, stage: \$stage}] end"
      fi
      local content
      content="$(jq \
        --arg stage "$stage" \
        --arg pr "$pr" \
        --arg sid "$sid" \
        "$filter" "$file")" || { echo "cdd-state: failed to update $file" >&2; return 1; }
      cdd-state-write "$file" "$content" \
        && echo "State: $(basename "$file") -> $stage${pr:+ (pr #$pr)}"
      ;;
    install|"")
      cdd-state-install "$@"
      ;;
    *)
      echo "usage: cdd-state {seed <branch> | set <stage> [--pr N] | install}" >&2
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
[[ -f "\$HOME/.cdd/tools/cdd-state.sh" ]] && source "\$HOME/.cdd/tools/cdd-state.sh"
${marker_end}
RCBLOCK
      echo "Wired: $rc"
    fi
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
source "$HOME/.cdd/tools/cdd-state.sh"
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
