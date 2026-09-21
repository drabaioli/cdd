#!/usr/bin/env bash
# CDD tracker capability adapter — GitHub backend (the reference implementation).
#
# Contract: doc/architecture/capability-adapters.md. Workflow-level rules: process
# doc §2.16. Nothing here re-decides either; this file implements them against `gh`.
#
# Usage:
#   cdd-tracker-github.sh describe
#   cdd-tracker-github.sh issue-read <ref>
#   cdd-tracker-github.sh issue-list
#   cdd-tracker-github.sh issue-create --title <title> --body <body>
#   cdd-tracker-github.sh issue-close-token <ref>
#
# A project binds to it by making `.cdd/tracker` an executable that execs this file:
#
#   #!/usr/bin/env bash
#   exec /path/to/cdd-tracker-github.sh "$@"
#
# It deliberately does NOT self-install (unlike cdd-worktree.sh / cdd-state.sh, which
# are sourced shell libraries): the built-in rung of the resolution ladder already IS
# GitHub, so a machine-global install would change no behaviour while destroying the
# "no adapter installed" baseline that behaviour-neutrality is checked against.
#
# Exit codes (contract-wide): 0 ok, 1 operation failed, 2 usage error,
# 3 verb unsupported by this backend, 4 not configured / auth missing.

set -euo pipefail

CONTRACT_VERSION=1
BACKEND="github"
REF_PATTERN='^#?[0-9]+$'
# `describe` is excluded from this list by the contract: it is mandatory for every
# adapter, so declaring it would be redundant. `issue-transition` is absent because
# GitHub has no workflow states beyond open/closed — calling it exits 3.
DECLARED_VERBS='["issue-read","issue-list","issue-create","issue-close-token"]'

err() { printf '%s\n' "$*" >&2; }

# Minimal JSON string escaping for the one field whose value comes from outside this
# file (create_target, derived from the origin URL). Escapes backslash and quote and
# strips control characters, which cannot appear unescaped inside a JSON string.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]//g'
}

# Normalize a reference to the bare number GitHub uses. Accepts `42` and `#42`, and
# publishes the result in $REF. It sets a global rather than printing, deliberately:
# called as `$(normalize_ref ...)` its `exit 2` would kill only the command
# substitution's subshell, and the caller would sail on into the backend with an empty
# ref and report the wrong exit code. Usage errors exit 2 here, BEFORE any backend
# contact — the contract requires argument validation to precede authentication.
REF=""
normalize_ref() {
  local ref="${1-}"
  if [[ -z "$ref" ]]; then
    err "usage: $(basename "$0") $VERB <ref>   (a GitHub issue number, e.g. 42 or #42)"
    exit 2
  fi
  if [[ ! "$ref" =~ $REF_PATTERN ]]; then
    err "not a GitHub issue reference: '$ref' (expected $REF_PATTERN)"
    exit 2
  fi
  REF="${ref#\#}"
}

# Exit 4 with an actionable line rather than failing, per the contract. Never reached
# by `describe`, which is hermetic, nor by a usage error, which has already exited 2.
require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    err "the GitHub CLI (\`gh\`) is not installed or not on PATH; install it from https://cli.github.com and re-run"
    exit 4
  fi
  if ! gh auth status >/dev/null 2>&1; then
    err "the GitHub CLI is not authenticated; run \`gh auth login\` and re-run"
    exit 4
  fi
}

# --- describe ----------------------------------------------------------------
# Hermetic by contract: no network, no auth, always exit 0. Everything it reports is
# either a constant in this file or derived from the local git config, so it stays
# answerable on a machine with no credentials at all — which is what makes an offline
# conformance gate possible.
verb_describe() {
  local url target='' escaped
  # `git remote get-url` is local (it reads .git/config); a failure just means no
  # origin, in which case create_target is OMITTED rather than emitted as null.
  if url="$(git remote get-url origin 2>/dev/null)" && [[ -n "$url" ]]; then
    # git@host:owner/repo.git | https://host/owner/repo.git | ssh://git@host/owner/repo
    target="${url%.git}"
    target="${target%/}"
    target="$(printf '%s' "$target" | sed -E 's#^.*[:/]([^:/]+/[^:/]+)$#\1#')"
    [[ "$target" == */* ]] || target=''
  fi

  printf '{"capability":"tracker","contract":%s,"backend":"%s","ref_pattern":"%s","verbs":%s' \
    "$CONTRACT_VERSION" "$BACKEND" "$(json_escape "$REF_PATTERN")" "$DECLARED_VERBS"
  if [[ -n "$target" ]]; then
    escaped="$(json_escape "$target")"
    printf ',"create_target":"%s"' "$escaped"
  fi
  printf '}\n'
}

# --- issue-read ---------------------------------------------------------------
# `gh`'s payload needs three fixes to meet the contract: `state` arrives uppercase
# (OPEN/CLOSED) and must be normalized while `state_raw` keeps the native value;
# `labels` is an array of OBJECTS, so a naive passthrough would emit the wrong shape;
# and `assignees` is a list where the contract wants one optional `assignee`, omitted
# rather than nulled when there is none. `id` (the GraphQL node id) genuinely differs
# from `ref` on GitHub, so both are emitted. `raw` is contract-optional and skipped:
# every caller here is an LLM session, and a duplicate of the whole payload is context
# nobody reads.
verb_issue_read() {
  local ref="$1" out
  require_gh
  if ! out="$(gh issue view "$ref" \
                --json number,title,body,url,comments,state,labels,assignees,id \
                --jq '{
                        ref: (.number|tostring),
                        id: .id,
                        backend: "github",
                        title: .title,
                        body: .body,
                        state: (.state|ascii_downcase),
                        state_raw: .state,
                        url: .url,
                        labels: [.labels[].name],
                        comments: [.comments[] | {author: (.author.login // ""), created_at: .createdAt, body: .body}]
                      }
                      + (if (.assignees|length) > 0 then {assignee: .assignees[0].login} else {} end)' \
                2>/dev/null)"; then
    err "could not read GitHub issue #$ref (no such issue, no access, or the request failed)"
    exit 1
  fi
  printf '%s\n' "$out"
}

# --- issue-list ---------------------------------------------------------------
# Open items only, per the contract. An empty list is `[]` and exit 0, not an error.
verb_issue_list() {
  local out
  require_gh
  if ! out="$(gh issue list --state open --limit 100 \
                --json number,title,state,url,labels \
                --jq '[.[] | {
                        ref: (.number|tostring),
                        title: .title,
                        state: (.state|ascii_downcase),
                        url: .url,
                        labels: [.labels[].name]
                      }]' \
                2>/dev/null)"; then
    err "could not list GitHub issues (no access, or the request failed)"
    exit 1
  fi
  printf '%s\n' "$out"
}

# --- issue-create -------------------------------------------------------------
# `gh issue create` prints the issue URL on stdout, not JSON, so `ref` comes from the
# trailing path segment. It reports no node id, and the contract says omit rather than
# null, so `id` is absent here while `issue-read` carries it.
verb_issue_create() {
  local title='' body='' url out
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="${2-}"; shift 2 || { err "--title needs a value"; exit 2; } ;;
      --body)  body="${2-}";  shift 2 || { err "--body needs a value";  exit 2; } ;;
      *) err "unknown option for issue-create: $1"; exit 2 ;;
    esac
  done
  if [[ -z "$title" || -z "$body" ]]; then
    err "usage: $(basename "$0") issue-create --title <title> --body <body>"
    exit 2
  fi

  require_gh
  if ! out="$(gh issue create --title "$title" --body "$body" 2>/dev/null)"; then
    err "could not create the GitHub issue (no access, or the request failed)"
    exit 1
  fi
  # `|| true`: under `set -e` + `pipefail` a grep that matches nothing would abort the
  # script at the assignment, taking the actionable message below with it.
  url="$(printf '%s' "$out" | grep -oE 'https://[^[:space:]]+/issues/[0-9]+' | tail -1 || true)"
  if [[ -z "$url" ]]; then
    err "the GitHub CLI created something but printed no issue URL; check the repository manually"
    exit 1
  fi
  printf '{"ref":"%s","url":"%s","backend":"%s"}\n' "${url##*/}" "$(json_escape "$url")" "$BACKEND"
}

# --- issue-close-token --------------------------------------------------------
# Purely local: the token is a property of the backend's commit-message syntax, not of
# any particular issue, so this verb contacts nothing and needs no credentials.
verb_issue_close_token() {
  printf '{"ref":"%s","token":"Closes #%s"}\n' "$1" "$1"
}

# --- dispatch -----------------------------------------------------------------
# Dispatch happens first, before any backend work, so an unknown verb is 3 and a bad
# argument is 2 even on a machine with no `gh` and no credentials. The conformance
# gate's verb probe depends on exactly this ordering.
VERB="${1-}"
[[ $# -gt 0 ]] && shift

case "$VERB" in
  describe)
    [[ $# -eq 0 ]] || { err "describe takes no arguments"; exit 2; }
    verb_describe
    ;;
  issue-read)
    normalize_ref "${1-}"
    [[ $# -le 1 ]] || { err "issue-read takes exactly one reference"; exit 2; }
    verb_issue_read "$REF"
    ;;
  issue-list)
    [[ $# -eq 0 ]] || { err "issue-list takes no arguments"; exit 2; }
    verb_issue_list
    ;;
  issue-create)
    verb_issue_create "$@"
    ;;
  issue-close-token)
    normalize_ref "${1-}"
    [[ $# -le 1 ]] || { err "issue-close-token takes exactly one reference"; exit 2; }
    verb_issue_close_token "$REF"
    ;;
  issue-transition)
    err "issue-transition is not supported by the GitHub backend: GitHub issues have no workflow states beyond open/closed"
    exit 3
    ;;
  ''|-h|--help|help)
    err "usage: $(basename "$0") <describe|issue-read|issue-list|issue-create|issue-close-token> [args...]"
    exit 2
    ;;
  *)
    err "unknown verb: $VERB"
    exit 3
    ;;
esac
