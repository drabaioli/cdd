#!/usr/bin/env bash
# CDD tracker capability adapter — GitLab backend (curl + jq, REST API v4).
#
# Contract: doc/architecture/capability-adapters.md. Workflow-level rules: process
# doc §2.16. Nothing here re-decides either; this file implements them against GitLab.
#
# Usage:
#   tools/adapters/tracker/gitlab.sh describe
#   tools/adapters/tracker/gitlab.sh issue-read <ref>
#   tools/adapters/tracker/gitlab.sh issue-list
#   tools/adapters/tracker/gitlab.sh issue-create --title <title> --body <body>
#   tools/adapters/tracker/gitlab.sh issue-transition <ref> <open|closed>
#   tools/adapters/tracker/gitlab.sh issue-comment <ref> --body <body>
#   tools/adapters/tracker/gitlab.sh issue-close-token <ref>
#
# Configuration is environment variables only — no config file, nothing read from disk.
# The same three the GitLab code-host adapter reads:
#   GITLAB_URL      optional; the instance, default https://gitlab.com. A self-managed
#                   host, with a sub-path root if it has one (https:// may be left off)
#   GITLAB_PROJECT  the project's path, e.g. group/project or group/sub/project
#   GITLAB_TOKEN    a personal, project or group access token with the `api` scope;
#                   lives in the user's shell, never in a file
#
# A project binds to it with a committed `.cdd/tracker` shim that exports only the
# non-secret coordinates — the token stays in the user's shell — and execs the copy
# `cdd-worktree.sh install` puts in the adapter library (ADR 0011).
# `bootstrap-cdd-project.sh --tracker gitlab --gitlab-project group/project` writes it;
# its core is:
#
#   #!/usr/bin/env bash
#   export GITLAB_URL='https://gitlab.com' GITLAB_PROJECT='group/project'
#   exec "$HOME/.cdd/tools/adapters/tracker/gitlab.sh" "$@"
#
# It never installs itself as a resolution-ladder rung, for the Jira adapter's reason:
# a GitLab binding is per-project by nature (an instance and a project path), so a
# machine rung has nothing sensible to point at.
#
# Exit codes (contract-wide): 0 ok, 1 operation failed, 2 usage error,
# 3 verb unsupported by this backend, 4 not configured / auth missing.

set -euo pipefail

CONTRACT_VERSION=1
BACKEND="gitlab"
# A GitLab issue's project-scoped number (its iid), GitLab's own `#42` handle. The same
# shape as GitHub's; only one tracker resolves per project, so they never compete.
REF_PATTERN='^#?[0-9]+$'
# A project path: namespace segments, then the project, separated by `/`.
PROJECT_PATTERN='^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)+$'
DEFAULT_URL='https://gitlab.com'
# `describe` is excluded from this list by the contract: it is mandatory for every
# adapter, so declaring it would be redundant.
DECLARED_VERBS='["issue-read","issue-list","issue-create","issue-transition","issue-comment","issue-close-token"]'

err() { printf '%s\n' "$*" >&2; }

# Minimal JSON string escaping for the values `describe` builds with printf (it must
# not need jq, so it stays answerable on a host with nothing installed).
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]//g'
}

# Validate a reference and publish the bare iid in $REF. A global rather than printed
# output, for the GitHub adapter's reason: called as `$(normalize_ref ...)` its `exit 2`
# would kill only the subshell. Usage errors exit 2 here, BEFORE any configuration check
# or backend contact.
REF=""
normalize_ref() {
  local ref="${1-}"
  if [[ -z "$ref" ]]; then
    err "usage: $(basename "$0") $VERB <ref>   (a GitLab issue number, e.g. 42 or #42)"
    exit 2
  fi
  if [[ ! "$ref" =~ $REF_PATTERN ]]; then
    err "not a GitLab issue reference: '$ref' (expected $REF_PATTERN)"
    exit 2
  fi
  REF="${ref#\#}"
}

# The instance URL, normalized: the default when unset, `https://` added to a bare host
# (without a scheme curl would speak plain http), no trailing slash. Hermetic, so
# `describe` uses it too.
base_url() {
  local u="${GITLAB_URL:-$DEFAULT_URL}"
  u="${u%/}"
  [[ "$u" == *://* ]] || u="https://$u"
  printf '%s' "$u"
}

config_hint() {
  case "$1" in
    GITLAB_PROJECT) echo "export it as the GitLab project's path, e.g. group/project (a project's .cdd/tracker may export it)" ;;
    GITLAB_TOKEN)   echo "export it in your shell (a GitLab access token with the api scope: <instance>/-/user_settings/personal_access_tokens); never commit it" ;;
    *)              echo "export it and re-run" ;;
  esac
}

# Exit 4 with one actionable line per missing variable. Never reached by `describe`,
# which is hermetic, nor by a usage error, which has already exited 2. Publishes the
# normalized instance in $GL_URL and the API root in $API.
GL_URL="" API="" PROJECT_ID=""
require_config() {
  local v missing=0
  for v in GITLAB_PROJECT GITLAB_TOKEN; do
    if [[ -z "${!v-}" ]]; then
      err "$v is not set; $(config_hint "$v")"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 4
  if [[ ! "$GITLAB_PROJECT" =~ $PROJECT_PATTERN ]]; then
    err "GITLAB_PROJECT is not a GitLab project path: '$GITLAB_PROJECT' (expected group/project)"
    exit 4
  fi
  GL_URL="$(base_url)"
  API="$GL_URL/api/v4"
  # The path form as a URL-encoded id; the validated charset leaves only `/` to encode.
  PROJECT_ID="${GITLAB_PROJECT//\//%2F}"
}

require_tools() {
  local t
  for t in curl jq; do
    if ! command -v "$t" >/dev/null 2>&1; then
      err "\`$t\` is not installed or not on PATH; the GitLab adapter needs curl and jq — install it and re-run"
      exit 4
    fi
  done
}

# --- HTTP ---------------------------------------------------------------------
SCRATCH=""
scratch() {
  if [[ -z "$SCRATCH" ]]; then
    SCRATCH="$(mktemp -d)"
    trap 'rm -rf "$SCRATCH"' EXIT
  fi
}

# gitlab_request <method> <api path> [extra curl args...]
# Leaves the response body in $RESP and returns only on a 2xx; every failure exits 1
# with a line on stderr. The token reaches curl as a PRIVATE-TOKEN header through
# `--config -` on stdin, never through argv (`-H` would show it to anyone running
# `ps`), and is never written to a file.
RESP=""
gitlab_request() {
  local method="$1" path="$2"; shift 2
  local code detail
  scratch
  RESP="$SCRATCH/resp"
  # Escape `\` and `"` for curl's quoted config syntax; pure parameter expansion, so
  # the token never becomes another process's argument either.
  if ! code="$(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(v="${GITLAB_TOKEN//\\/\\\\}"; printf '%s' "${v//\"/\\\"}")" |
                 curl -sS --config - -X "$method" -H 'Accept: application/json' \
                      -o "$RESP" -w '%{http_code}' "$@" "$API$path" \
                      2>"$SCRATCH/curl.err")"; then
    err "could not reach GitLab at $GL_URL: $(head -1 "$SCRATCH/curl.err")"
    exit 1
  fi
  [[ "$code" == 2?? ]] && return 0
  # `.message` may be a string, an array, or an object of field errors.
  detail="$(jq -r '[(.message // empty | if type == "string" then . elif type == "array" then join("; ") else tojson end),
                    (.error_description // .error // empty)] | join("; ")' "$RESP" 2>/dev/null || true)"
  case "$code" in
    401) err "GitLab rejected the token for $GL_URL (check GITLAB_TOKEN)" ;;
    403) err "GitLab refused $method $path (the token needs the api scope, and your role must allow it)${detail:+: $detail}" ;;
    404) err "GitLab returned 404 for $path (no such issue or project, or no access)${detail:+: $detail}" ;;
    *)   err "GitLab returned HTTP $code for $method $path${detail:+: $detail}" ;;
  esac
  exit 1
}

# --- jq helpers ---------------------------------------------------------------
# iso_utc: GitLab's `2016-01-04T15:31:51.081Z` -> `2016-01-04T15:31:51Z`; an explicit
# offset (a self-managed instance may send one) is converted to UTC. Offset arithmetic
# by hand rather than strptime("%z"), whose support is libc-dependent. Anything
# unrecognized passes through unchanged.
# shellcheck disable=SC2016  # $c is a jq variable, not a shell one
JQ_LIB='
def iso_utc:
  if type != "string" then ""
  else
    (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})T(?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})([.][0-9]+)?(?<z>Z|(?<s>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2}))$") as $c
     | if $c.z == "Z" then "\($c.d)T\($c.t)Z"
       else (("\($c.d)T\($c.t)Z" | fromdateiso8601)
             - ((if $c.s == "-" then -1 else 1 end) * (($c.h | tonumber) * 3600 + ($c.m | tonumber) * 60)))
            | todate
       end) // .
  end;
def norm_state: if . == "closed" then "closed" else "open" end;
'

# --- describe ----------------------------------------------------------------
# Hermetic by contract: no network, no credentials, always exit 0, no jq. Everything it
# reports is a constant here or read from the local environment; create_target is
# OMITTED, not nulled, unless the project is set (the instance has a default).
verb_describe() {
  local target='' host
  if [[ -n "${GITLAB_PROJECT-}" ]]; then
    host="$(base_url)"
    host="${host#*://}"
    host="${host%%/*}"
    target="$GITLAB_PROJECT @ $host"
  fi

  printf '{"capability":"tracker","contract":%s,"backend":"%s","ref_pattern":"%s","verbs":%s' \
    "$CONTRACT_VERSION" "$BACKEND" "$(json_escape "$REF_PATTERN")" "$DECLARED_VERBS"
  if [[ -n "$target" ]]; then
    printf ',"create_target":"%s"' "$(json_escape "$target")"
  fi
  printf '}\n'
}

# --- issue-read ---------------------------------------------------------------
# `ref` is the iid; `id` is GitLab's global id, which differs, so both are emitted.
# Comments are the issue's notes minus system notes ("changed the label", "closed"),
# oldest first, one page of 100. The assignee is the first assignee's username (the
# singular `assignee` field is deprecated), omitted when unassigned. `raw` is skipped,
# as in the other adapters: nobody reads it.
verb_issue_read() {
  local ref="$1"
  scratch
  gitlab_request GET "/projects/$PROJECT_ID/issues/$ref"
  cp "$RESP" "$SCRATCH/issue.json"
  gitlab_request GET "/projects/$PROJECT_ID/issues/$ref/notes" --get \
    --data-urlencode 'sort=asc' --data-urlencode 'order_by=created_at' --data-urlencode 'per_page=100'
  jq -c --slurpfile notes "$RESP" "$JQ_LIB"'
    { ref: (.iid | tostring),
      id: (.id | tostring),
      backend: "gitlab",
      title: (.title // ""),
      body: (.description // ""),
      state: (.state | norm_state),
      state_raw: .state,
      url: .web_url,
      labels: (.labels // []),
      comments: [$notes[0][]? | select(.system != true)
                 | {author: (.author.username // ""), created_at: (.created_at | iso_utc), body: (.body // "")}]
    }
    + (if (.assignees // []) != [] then {assignee: .assignees[0].username} else {} end)' "$SCRATCH/issue.json"
}

# --- issue-list ---------------------------------------------------------------
# Open items only, newest first, one page of up to 100 — the same cap as the other
# adapters. Empty is `[]`, not an error.
verb_issue_list() {
  gitlab_request GET "/projects/$PROJECT_ID/issues" --get \
    --data-urlencode 'state=opened' --data-urlencode 'order_by=created_at' \
    --data-urlencode 'sort=desc' --data-urlencode 'per_page=100'
  jq -c '[.[]? | { ref: (.iid | tostring),
                   title: (.title // ""),
                   state: "open",
                   url: .web_url,
                   labels: (.labels // []) }]' "$RESP"
}

# --- issue-create -------------------------------------------------------------
# GitLab renders the body as Markdown, as GitHub does. It reports the global id on a
# create, so — unlike the GitHub adapter — `id` is emitted.
verb_issue_create() {
  local title="$1" body="$2"
  scratch
  jq -n --arg title "$title" --arg body "$body" '{title: $title, description: $body}' > "$SCRATCH/body.json"
  gitlab_request POST "/projects/$PROJECT_ID/issues" \
    -H 'Content-Type: application/json' --data-binary @"$SCRATCH/body.json"
  jq -c '{ref: (.iid | tostring), id: (.id | tostring), url: .web_url, backend: "gitlab"}' "$RESP"
}

# --- issue-transition ---------------------------------------------------------
# GitLab issues are `opened` or `closed`, with no workflow: `closed` is a `close` state
# event, `open` a `reopen`. The current state is read first, so an issue already there
# is a no-op, exit 0, reported as `changed: false` and no write.
verb_issue_transition() {
  local ref="$1" want="$2" current event
  gitlab_request GET "/projects/$PROJECT_ID/issues/$ref"
  current="$(jq -r '.state' "$RESP")"
  if { [[ "$want" == closed && "$current" == closed ]] || [[ "$want" == open && "$current" != closed ]]; }; then
    err "#$ref is already $want ('$current'); nothing to do"
    jq -cn --arg ref "$ref" --arg state "$want" --arg raw "$current" '{ref: $ref, state: $state, state_raw: $raw, changed: false}'
    return 0
  fi

  [[ "$want" == closed ]] && event=close || event=reopen
  scratch
  jq -n --arg e "$event" '{state_event: $e}' > "$SCRATCH/body.json"
  gitlab_request PUT "/projects/$PROJECT_ID/issues/$ref" \
    -H 'Content-Type: application/json' --data-binary @"$SCRATCH/body.json"
  jq -c --arg ref "$ref" --arg state "$want" '{ref: $ref, state: $state, state_raw: .state, changed: true}' "$RESP"
}

# --- issue-comment ------------------------------------------------------------
# A note on the issue. `id` is the note's id; `url` is the issue page anchored on it,
# GitLab's own `#note_<id>` form. The page is the issue's own `web_url`, read first
# rather than built: GitLab has been moving issues from `/-/issues/N` to
# `/-/work_items/N`, and only it knows which one a project serves.
verb_issue_comment() {
  local ref="$1" body="$2" page
  scratch
  gitlab_request GET "/projects/$PROJECT_ID/issues/$ref"
  page="$(jq -r '.web_url // empty' "$RESP")"
  jq -n --arg body "$body" '{body: $body}' > "$SCRATCH/body.json"
  gitlab_request POST "/projects/$PROJECT_ID/issues/$ref/notes" \
    -H 'Content-Type: application/json' --data-binary @"$SCRATCH/body.json"
  jq -c --arg ref "$ref" --arg page "$page" '
    {ref: $ref}
    + (if ((.id // "") | tostring) != "" then
         {id: (.id | tostring)} + (if $page != "" then {url: "\($page)#note_\(.id)"} else {} end)
       else {} end)' "$RESP"
}

# --- issue-close-token --------------------------------------------------------
# Purely local: GitLab's default closing pattern. It acts when the MR carrying it is
# merged into the project's DEFAULT branch, and only while the project's "Auto-close
# referenced issues on default branch" setting is on (the default).
verb_issue_close_token() {
  printf '{"ref":"%s","token":"Closes #%s"}\n' "$1" "$1"
}

# --- dispatch -----------------------------------------------------------------
# Order per verb: arguments (exit 2), then configuration (exit 4), then tools (exit 4),
# then the backend. So an unknown verb is 3 and a bad argument is 2 even on a machine
# with no configuration, no curl and no network — the conformance gate depends on it.
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
    require_config
    require_tools
    verb_issue_read "$REF"
    ;;
  issue-list)
    [[ $# -eq 0 ]] || { err "issue-list takes no arguments"; exit 2; }
    require_config
    require_tools
    verb_issue_list
    ;;
  issue-create)
    title='' body=''
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
    require_config
    require_tools
    verb_issue_create "$title" "$body"
    ;;
  issue-transition)
    normalize_ref "${1-}"
    case "${2-}" in
      open|closed) ;;
      '') err "usage: $(basename "$0") issue-transition <ref> <open|closed>"; exit 2 ;;
      *)  err "not a normalized state: '${2}' (expected open or closed)"; exit 2 ;;
    esac
    [[ $# -le 2 ]] || { err "issue-transition takes a reference and a state"; exit 2; }
    require_config
    require_tools
    verb_issue_transition "$REF" "$2"
    ;;
  issue-comment)
    normalize_ref "${1-}"
    shift
    body=''
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body) body="${2-}"; shift 2 || { err "--body needs a value"; exit 2; } ;;
        *) err "unknown argument for issue-comment: $1"; exit 2 ;;
      esac
    done
    if [[ -z "$body" ]]; then
      err "usage: $(basename "$0") issue-comment <ref> --body <body>"
      exit 2
    fi
    require_config
    require_tools
    verb_issue_comment "$REF" "$body"
    ;;
  issue-close-token)
    normalize_ref "${1-}"
    [[ $# -le 1 ]] || { err "issue-close-token takes exactly one reference"; exit 2; }
    verb_issue_close_token "$REF"
    ;;
  ''|-h|--help|help)
    err "usage: $(basename "$0") <describe|issue-read|issue-list|issue-create|issue-transition|issue-comment|issue-close-token> [args...]"
    exit 2
    ;;
  *)
    err "unknown verb: $VERB"
    exit 3
    ;;
esac
