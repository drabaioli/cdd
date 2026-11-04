#!/usr/bin/env bash
# Install this project's dependencies: CDD's required tools, the tools of the capability
# adapters the project binds, and the project's own build and test toolchain.
#
# Usage: scripts/install-deps.sh [--check]
#   (no argument)  install whatever is missing, then check again
#   --check        only report what is missing: exit 1 if anything is, 0 otherwise
#
# It checks first and installs only what is missing, so a second run installs nothing.
# Ubuntu (apt-get, through sudo unless already root) and macOS (Homebrew) are supported;
# anywhere else it lists what is missing and how to install it. It never installs
# Homebrew and never adds a third-party apt repository: a tool its package manager
# cannot install prints its install steps and counts as a failure. `claude` comes from
# Anthropic's native installer, run as you, never under sudo.
#
# CDD requires git, bash >= 4, jq and claude: its helpers and its bootstrap script refuse
# to run without them (CDD process doc, section 2.18). Everything outside the project
# block below belongs to CDD and changes with it (/cdd-retrofit carries those changes
# over); the project block belongs to this project.
#
# Plain bash 3.2 on purpose: on stock macOS it runs before any newer bash is installed.

usage() {
  echo "usage: scripts/install-deps.sh [--check]" >&2
  exit 2
}

CHECK_ONLY=0
[ $# -le 1 ] || usage
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=1 ;;
  *) usage ;;
esac

# One entry per tool: "command|apt package|brew package|how to install it by hand".
# A `-` in a package column: that package manager does not install it; the hint is
# printed instead and the tool counts as a failure until it is installed.
CDD_TOOLS=(
  "git|git|git|https://git-scm.com/downloads"
  "bash|-|bash|brew install bash (macOS; Ubuntu's bash is already >= 4)"
  "jq|jq|jq|https://jqlang.org/download/"
  "claude|-|-|curl -fsSL https://claude.ai/install.sh | bash"
)

# --- project tools BEGIN (filled by /cdd-bootstrap or /cdd-retrofit; owned by this project) ---
# <project tools: one "command|apt package|brew package|manual hint" entry per line — the bound adapters' tools (gh for GitHub; curl for Jira or GitLab) and this project's build/test toolchain>
PROJECT_TOOLS=(
)
# --- project tools END ---

CLAUDE_INSTALLER="https://claude.ai/install.sh"

# present <command>: is the tool usable from PATH? `bash` means the bash on PATH reports
# major version >= 4, since CDD's helpers run as `#!/usr/bin/env bash`.
present() {
  local v
  if [ "$1" = bash ]; then
    v="$(bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)"
    [ -n "$v" ] && [ "$v" -ge 4 ] 2>/dev/null
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

# Every entry, CDD's first. The `+` form keeps an empty project block from tripping
# bash 3.2's unbound-array quirk.
ALL_TOOLS=("${CDD_TOOLS[@]}" ${PROJECT_TOOLS[@]+"${PROJECT_TOOLS[@]}"})

# missing_tools: the entries whose command is not usable, one per line.
missing_tools() {
  local entry
  hash -r 2>/dev/null
  for entry in "${ALL_TOOLS[@]}"; do
    present "${entry%%|*}" || printf '%s\n' "$entry"
  done
}

MISSING=()
while IFS= read -r entry; do
  [ -n "$entry" ] && MISSING+=("$entry")
done <<EOF
$(missing_tools)
EOF

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "All dependencies present."
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  for entry in "${MISSING[@]}"; do
    IFS='|' read -r cmd apt brew hint <<EOF
$entry
EOF
    echo "missing: $cmd (by hand: $hint)"
  done
  exit 1
fi

PM=""
case "$(uname -s)" in
  Darwin) PM=brew ;;
  Linux) command -v apt-get >/dev/null 2>&1 && PM=apt ;;
esac

if [ -z "$PM" ]; then
  echo "This system is neither Ubuntu (apt-get) nor macOS; install these by hand:" >&2
  for entry in "${MISSING[@]}"; do
    IFS='|' read -r cmd apt brew hint <<EOF
$entry
EOF
    echo "  $cmd: $hint" >&2
  done
  exit 1
fi
if [ "$PM" = brew ] && ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is needed on macOS and is not installed; install it first: https://brew.sh" >&2
  exit 1
fi

# Sort the missing tools by how each gets installed.
PKGS=()
MANUAL=()
WANT_CLAUDE=0
for entry in "${MISSING[@]}"; do
  IFS='|' read -r cmd apt brew hint <<EOF
$entry
EOF
  if [ "$cmd" = claude ]; then
    # Already installed but off PATH: reinstalling would not help; the re-check says why.
    [ -x "$HOME/.local/bin/claude" ] || WANT_CLAUDE=1
    continue
  fi
  if [ "$PM" = apt ]; then pkg="$apt"; else pkg="$brew"; fi
  if [ "$pkg" = - ] || [ -z "$pkg" ]; then
    MANUAL+=("$cmd: $hint")
  else
    PKGS+=("$pkg")
  fi
done
# claude's installer is fetched with curl: install curl alongside, when it is missing.
if [ "$WANT_CLAUDE" -eq 1 ] && ! command -v curl >/dev/null 2>&1; then
  PKGS+=(curl)
fi

run_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

status=0
if [ ${#PKGS[@]} -gt 0 ]; then
  echo "Installing with $PM: ${PKGS[*]}"
  if [ "$PM" = apt ]; then
    run_root apt-get update -q \
      && run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${PKGS[@]}" \
      || status=1
  else
    brew install "${PKGS[@]}" || status=1
  fi
fi

if [ "$WANT_CLAUDE" -eq 1 ]; then
  if command -v curl >/dev/null 2>&1; then
    echo "Installing claude with Anthropic's native installer ($CLAUDE_INSTALLER)"
    # pipefail in a subshell: a failed download must fail this step, not feed bash nothing.
    ( set -o pipefail; curl -fsSL "$CLAUDE_INSTALLER" | bash ) || status=1
  else
    echo "claude: its installer needs curl, which is not installed; install curl, then re-run." >&2
    status=1
  fi
fi

if [ ${#MANUAL[@]} -gt 0 ]; then
  echo "Not installable with $PM here; install by hand, then re-run:" >&2
  for line in "${MANUAL[@]}"; do
    echo "  $line" >&2
  done
fi

# Check again, and say why anything is still missing.
STILL=()
while IFS= read -r entry; do
  [ -n "$entry" ] && STILL+=("$entry")
done <<EOF
$(missing_tools)
EOF

if [ ${#STILL[@]} -eq 0 ] && [ "$status" -eq 0 ]; then
  echo "All dependencies present."
  exit 0
fi
for entry in ${STILL[@]+"${STILL[@]}"}; do
  cmd="${entry%%|*}"
  case "$cmd" in
    bash)
      echo "still missing: bash >= 4 on PATH; the new bash is not ahead of /bin/bash on PATH: add Homebrew to it (eval \"\$(brew shellenv)\")" >&2 ;;
    claude)
      if [ -x "$HOME/.local/bin/claude" ]; then
        echo "still missing: claude on PATH; it is installed at ~/.local/bin/claude, which is not on PATH: add it, or open a new shell" >&2
      else
        echo "still missing: claude (by hand: curl -fsSL $CLAUDE_INSTALLER | bash)" >&2
      fi ;;
    *)
      echo "still missing: $cmd (by hand: ${entry##*|})" >&2 ;;
  esac
done
exit 1
