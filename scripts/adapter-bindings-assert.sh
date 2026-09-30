#!/usr/bin/env bash
# Smoke for the capability bindings the installers write (ADR 0011).
#
# `bootstrap-cdd-project.sh --tracker/--code-host` writes .cdd/<cap> shims that exec
# the machine-global adapter library `cdd-worktree.sh install` puts under
# ~/.cdd/tools/adapters/. This pins, offline:
#   - install copies the shipped adapters into the library
#   - a bootstrap with bindings commits executable .cdd/ shims naming no machine path
#   - from a fresh clone on a "second machine" (another HOME with the library), each
#     shim passes describe both directly (the prompt path) and through the helpers'
#     resolver (the cdd-worktree path)
#   - on a machine without the library the resolver stops with one "is unusable"
#     line that relays the shim's install hint (the broken-adapter rule, no fallback)
#   - a Jira binding carries its site and key (and no credential) in the shim
#   - unsupported backends and malformed Jira coordinates are refused before any write
#   - --stage renders the shims too; a bare bootstrap writes no .cdd/
#
# The conformance checker is deliberately not run on these shims: it probes with an
# empty HOME, where no library exists by construction.
#
# Usage: scripts/adapter-bindings-assert.sh   (provisions and tears down its own temp tree)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/tools/cdd-worktree.sh"
BOOTSTRAP="$REPO_ROOT/tools/bootstrap-cdd-project.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the helpers read an adapter's describe with it"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
cat > "$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	name = CDD Smoke
	email = smoke@example.com
[init]
	defaultBranch = main
[commit]
	gpgsign = false
EOF

HOME_A="$WORK/home-a"   # the machine that bootstraps
HOME_B="$WORK/home-b"   # a second machine, library installed
HOME_C="$WORK/home-c"   # a machine without the library
mkdir -p "$HOME_A" "$HOME_B" "$HOME_C"

# Resolve <cap> through the helpers from <dir> under <home>; stderr to $WORK/err.
resolve() {
  local home="$1" dir="$2" cap="$3"
  RC=0
  # shellcheck source=/dev/null
  ( cd "$dir" && export HOME="$home" \
    && source "$HELPER" && cdd-worktree-adapter "$cap" ) 2>"$WORK/err" || RC=$?
}

# --- 1. install puts the adapter library in place ------------------------------
for home in "$HOME_A" "$HOME_B"; do
  HOME="$home" bash "$HELPER" install >/dev/null 2>&1 || fail "install into $home failed"
done
for a in tracker/github.sh tracker/jira.sh code-host/github.sh; do
  [[ -x "$HOME_A/.cdd/tools/adapters/$a" ]] || fail "install did not provide the library file $a"
done
pass "install copies the shipped adapters into ~/.cdd/tools/adapters/"

# --- 2. bootstrap with bindings commits portable shims -------------------------
PROJ="$WORK/proj"
HOME="$HOME_A" "$BOOTSTRAP" --name "Bound" --path "$PROJ" \
  --tracker github --code-host github >/dev/null || fail "bootstrap with bindings failed"
for cap in tracker code-host; do
  [[ -x "$PROJ/.cdd/$cap" ]] || fail "bootstrap did not write an executable .cdd/$cap"
  [[ -n "$(git -C "$PROJ" ls-files ".cdd/$cap")" ]] || fail ".cdd/$cap is not in the scaffold commit"
  if grep -nF -e "$REPO_ROOT" -e "$WORK" -e "/home/" "$PROJ/.cdd/$cap"; then
    fail ".cdd/$cap names a machine-specific path"
  fi
done
pass "bootstrap commits executable .cdd/ shims that name no machine path"

# --- 3. a fresh clone on a second machine: both call paths pass describe -------
CLONE="$WORK/clone"
git clone -q "$PROJ" "$CLONE"
for cap in tracker code-host; do
  HOME="$HOME_B" "$CLONE/.cdd/$cap" describe \
    | jq -e --arg c "$cap" '.capability == $c and .backend == "github" and .contract == 1' >/dev/null \
    || fail "clone, prompt path: .cdd/$cap describe did not validate"
  resolve "$HOME_B" "$CLONE" "$cap"
  [[ $RC -eq 0 ]] || fail "clone, helper path: resolving $cap returned $RC: $(cat "$WORK/err")"
  grep -qxF "$cap: using adapter .cdd/$cap (github)" "$WORK/err" \
    || fail "clone, helper path: expected the one announcement line for $cap, got: $(cat "$WORK/err")"
done
pass "from a fresh clone, both shims pass describe via a prompt and via cdd-worktree"

# --- 4. no library on this machine: a stop that relays the install hint --------
resolve "$HOME_C" "$CLONE" code-host
[[ $RC -eq 2 ]] || fail "no library: the resolver should report a broken adapter (2), got $RC"
[[ "$(grep -c . "$WORK/err")" == 1 ]] || fail "no library: expected exactly one stderr line: $(cat "$WORK/err")"
grep -qF "code-host adapter .cdd/code-host is unusable: describe exited 4: adapter library missing" "$WORK/err" \
  || fail "no library: the line should name the adapter and relay describe's reason: $(cat "$WORK/err")"
grep -qF "cdd-worktree.sh install" "$WORK/err" || fail "no library: the line should carry the install command"
pass "without the library the resolver stops in one line carrying the install hint"

# --- 5. a Jira binding carries its coordinates, never a credential -------------
JPROJ="$WORK/jproj"
HOME="$HOME_A" "$BOOTSTRAP" --name "Jira Bound" --path "$JPROJ" \
  --tracker jira --jira-site https://acme.atlassian.net/ --jira-key ABC --code-host github >/dev/null \
  || fail "bootstrap with a Jira binding failed"
env -i HOME="$HOME_B" PATH="$PATH" "$JPROJ/.cdd/tracker" describe \
  | jq -e '.backend == "jira" and .create_target == "ABC @ acme.atlassian.net"' >/dev/null \
  || fail "Jira: describe should report the shim's own site and key"
if grep -nE 'JIRA_(EMAIL|API_TOKEN)[[:space:]]*=' "$JPROJ/.cdd/tracker"; then
  fail "Jira: the shim assigns a credential variable"
fi
# The conformance checker's secret patterns, copied from scripts/adapter-conformance-check.sh.
secret_patterns=(
  'gh[pousr]_[A-Za-z0-9]{16,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AT[AC]TT[A-Za-z0-9_=-]{40,}'
  'Authorization:[[:space:]]*Basic[[:space:]]+[A-Za-z0-9+/=]{16,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY'
  '(password|passwd|secret|token|api[_-]?key)[[:space:]]*=[[:space:]]*.[^"'"'"']{8,}'
)
for pattern in "${secret_patterns[@]}"; do
  if grep -nEI -e "$pattern" "$JPROJ/.cdd/tracker" "$PROJ/.cdd/tracker" "$PROJ/.cdd/code-host"; then
    fail "a shim matches the secret pattern $pattern"
  fi
done
pass "a Jira binding exports its site and key, and no credential"

# --- 6. refusals exit 2 before touching the target -----------------------------
refuse() {
  local label="$1"; shift
  local t="$WORK/refused-$label" rc=0
  HOME="$HOME_A" "$BOOTSTRAP" --name "Refused" --path "$t" "$@" >/dev/null 2>&1 || rc=$?
  [[ $rc -eq 2 ]] || fail "refusal ($label): expected exit 2, got $rc"
  [[ ! -e "$t" ]] || fail "refusal ($label): the target was created"
}
refuse gitlab-tracker   --tracker gitlab
refuse gitlab-code-host --code-host gitlab
refuse jira-no-coords   --tracker jira
refuse jira-bad-key     --tracker jira --jira-site acme.atlassian.net --jira-key abc
refuse jira-bad-site    --tracker jira --jira-site 'acme.atlassian.net/x y' --jira-key ABC
refuse site-no-jira     --tracker github --jira-site acme.atlassian.net
pass "unsupported backends and malformed Jira coordinates are refused before any write"

# --- 7. --stage renders the shims; 8. a bare bootstrap writes none -------------
STAGED="$WORK/stage/render"
"$BOOTSTRAP" --stage --dir staged --name "Staged" --path "$STAGED" \
  --tracker github --code-host github >/dev/null || fail "--stage with bindings failed"
[[ -x "$STAGED/.cdd/tracker" && -x "$STAGED/.cdd/code-host" ]] || fail "--stage did not render the shims"
[[ ! -e "$STAGED/.git" ]] || fail "--stage created a git tree"

BARE="$WORK/bare"
HOME="$HOME_A" "$BOOTSTRAP" --name "Bare" --path "$BARE" >/dev/null || fail "bare bootstrap failed"
[[ ! -e "$BARE/.cdd" ]] || fail "a bootstrap without binding flags wrote .cdd/"
pass "--stage renders the shims; a bare bootstrap writes no .cdd/"

echo "adapter bindings: all assertions passed"
