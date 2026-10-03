#!/usr/bin/env bash
# CDD code-host capability adapter — GitLab backend (curl + jq, REST API v4).
#
# Contract: doc/architecture/capability-adapters.md. Workflow-level rules: process
# doc §2.16. Nothing here re-decides either; this file implements them against GitLab,
# where a PR is a merge request (MR).
#
# Usage:
#   tools/adapters/code-host/gitlab.sh describe
#   tools/adapters/code-host/gitlab.sh pr-create --title <title> --body <body> [--base <branch>]
#   tools/adapters/code-host/gitlab.sh pr-for-branch <branch>
#   tools/adapters/code-host/gitlab.sh pr-comments <pr>
#   tools/adapters/code-host/gitlab.sh pr-reply <pr> [--to <thread-id>] --body <body>
#   tools/adapters/code-host/gitlab.sh pr-merged <branch> [--base <branch>]
#   tools/adapters/code-host/gitlab.sh default-branch
#
# Configuration is environment variables only — no config file, nothing read from disk.
# The same three the GitLab tracker adapter reads:
#   GITLAB_URL      optional; the instance, default https://gitlab.com. A self-managed
#                   host, with a sub-path root if it has one (https:// may be left off)
#   GITLAB_PROJECT  the project's path, e.g. group/project or group/sub/project
#   GITLAB_TOKEN    a personal, project or group access token with the `api` scope;
#                   lives in the user's shell, never in a file
#
# A project binds to it with a committed `.cdd/code-host` shim that exports only the
# non-secret coordinates and execs the copy `cdd-worktree.sh install` puts in the
# adapter library (ADR 0011). `bootstrap-cdd-project.sh --code-host gitlab
# --gitlab-project group/project` writes it; its core is:
#
#   #!/usr/bin/env bash
#   export GITLAB_URL='https://gitlab.com' GITLAB_PROJECT='group/project'
#   exec "$HOME/.cdd/tools/adapters/code-host/gitlab.sh" "$@"
#
# It never installs itself as a resolution-ladder rung: a GitLab binding is per-project
# by nature, so a machine rung has nothing sensible to point at.
#
# Exit codes (contract-wide): 0 ok, 1 operation failed, 2 usage error,
# 3 verb unsupported by this backend, 4 not configured / auth missing.

set -euo pipefail

CONTRACT_VERSION=1
BACKEND="gitlab"
# A project path: namespace segments, then the project, separated by `/`.
PROJECT_PATTERN='^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)+$'
DEFAULT_URL='https://gitlab.com'
# `describe` is excluded from this list by the contract: it is mandatory for every
# adapter, so declaring it would be redundant. GitLab supports the whole contract.
DECLARED_VERBS='["pr-create","pr-for-branch","pr-comments","pr-reply","pr-merged","default-branch"]'

err() { printf '%s\n' "$*" >&2; }

# Argument checks publish into globals rather than printing, for the tracker adapters'
# reason: called as `$(check ...)` their `exit 2` would kill only the command
# substitution's subshell. Usage errors exit 2 here, BEFORE any configuration check or
# backend contact — the contract requires argument validation to precede authentication.
require_branch() {
  local b="${1-}"
  if [[ -z "$b" || "$b" == -* ]]; then
    err "usage: $(basename "$0") $VERB <branch>"
    exit 2
  fi
}

# An MR's project-scoped number (its iid). GitLab's own handle is `!42`; `#42` and `42`
# are accepted too.
PR=""
normalize_pr() {
  local ref="${1-}"
  if [[ -z "$ref" ]]; then
    err "usage: $(basename "$0") $VERB <pr>   (a GitLab merge request number, e.g. 42 or !42)"
    exit 2
  fi
  if [[ ! "$ref" =~ ^[!#]?[0-9]+$ ]]; then
    err "not a GitLab merge request reference: '$ref' (expected a number, e.g. 42 or !42)"
    exit 2
  fi
  PR="${ref#[#]}"
  PR="${PR#!}"
}

# The instance URL, normalized: the default when unset, `https://` added to a bare host
# (without a scheme curl would speak plain http), no trailing slash.
base_url() {
  local u="${GITLAB_URL:-$DEFAULT_URL}"
  u="${u%/}"
  [[ "$u" == *://* ]] || u="https://$u"
  printf '%s' "$u"
}

config_hint() {
  case "$1" in
    GITLAB_PROJECT) echo "export it as the GitLab project's path, e.g. group/project (a project's .cdd/code-host may export it)" ;;
    GITLAB_TOKEN)   echo "export it in your shell (a GitLab access token with the api scope: <instance>/-/user_settings/personal_access_tokens); never commit it" ;;
    *)              echo "export it and re-run" ;;
  esac
}

# Configuration, then tools: exit 4 with one actionable line per missing variable, or
# for a missing curl / jq. Never reached by `describe`, which is hermetic, nor by a
# usage error, which has already exited 2. Publishes the normalized instance in
# $GL_URL, the API root in $API, and the URL-encoded project path in $PROJECT_ID.
GL_URL="" API="" PROJECT_ID=""
require_backend() {
  local v t missing=0
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
  for t in curl jq; do
    if ! command -v "$t" >/dev/null 2>&1; then
      err "\`$t\` is not installed or not on PATH; the GitLab adapter needs curl and jq — install it and re-run"
      exit 4
    fi
  done
  GL_URL="$(base_url)"
  API="$GL_URL/api/v4"
  # The validated charset leaves only `/` to encode.
  PROJECT_ID="${GITLAB_PROJECT//\//%2F}"
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
    404) err "GitLab returned 404 for $path (no such merge request or project, or no access)${detail:+: $detail}" ;;
    *)   err "GitLab returned HTTP $code for $method $path${detail:+: $detail}" ;;
  esac
  exit 1
}

# --- jq helpers ---------------------------------------------------------------
# iso_utc: GitLab's `2016-01-04T15:31:51.081Z` -> `2016-01-04T15:31:51Z`; an explicit
# offset is converted to UTC. Anything unrecognized passes through unchanged.
# mr_state: `opened` and `locked` (an MR mid-merge) are open; `closed` and `merged` are
# themselves.
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
def mr_state: if . == "merged" then "merged" elif . == "closed" then "closed" else "open" end;
def note: {id: (.id | tostring), author: (.author.username // ""), created_at: (.created_at | iso_utc), body: (.body // "")};
'

# --- describe ----------------------------------------------------------------
# Hermetic by contract: no network, no credentials, always exit 0. Every field is a
# constant in this file.
verb_describe() {
  printf '{"capability":"code-host","contract":%s,"backend":"%s","verbs":%s}\n' \
    "$CONTRACT_VERSION" "$BACKEND" "$DECLARED_VERBS"
}

# The project's default branch, asked of GitLab.
remote_default_branch() {
  gitlab_request GET "/projects/$PROJECT_ID"
  jq -r '.default_branch // empty' "$RESP"
}

# --- pr-create -----------------------------------------------------------------
# The source branch is the current one, which must already be pushed (GitLab refuses an
# MR from a branch it does not have). Without --base the target is the project's
# default branch. GitLab's refusals — an MR for the branch already open, a missing
# source branch — arrive as its own message, exit 1.
verb_pr_create() {
  local title="$1" body="$2" base="$3" head
  head="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$head" ]]; then
    err "not on a branch (detached HEAD, or not a git repository); check out the branch to open a merge request from"
    exit 1
  fi
  if [[ -z "$base" ]]; then
    base="$(remote_default_branch)"
    if [[ -z "$base" ]]; then
      err "GitLab reports no default branch for $GITLAB_PROJECT; pass --base"
      exit 1
    fi
  fi
  scratch
  jq -n --arg s "$head" --arg t "$base" --arg title "$title" --arg body "$body" \
    '{source_branch: $s, target_branch: $t, title: $title, description: $body}' > "$SCRATCH/body.json"
  gitlab_request POST "/projects/$PROJECT_ID/merge_requests" \
    -H 'Content-Type: application/json' --data-binary @"$SCRATCH/body.json"
  jq -c '{ref: (.iid | tostring), url: .web_url}' "$RESP"
}

# mr_list <branch> [<base>]: every MR whose source is the branch (into <base>, if
# given), newest first — GitLab's default order, asked for explicitly. One page of 100.
mr_list() {
  local -a args=(--data-urlencode "source_branch=$1" --data-urlencode 'state=all'
                 --data-urlencode 'order_by=created_at' --data-urlencode 'sort=desc'
                 --data-urlencode 'per_page=100')
  [[ -n "${2-}" ]] && args+=(--data-urlencode "target_branch=$2")
  gitlab_request GET "/projects/$PROJECT_ID/merge_requests" --get "${args[@]}"
}

# --- pr-for-branch -------------------------------------------------------------
verb_pr_for_branch() {
  mr_list "$1"
  jq -c "$JQ_LIB"'
    [.[]? | { ref: (.iid | tostring),
              state: (.state | mr_state),
              state_raw: .state,
              url: .web_url,
              head: .source_branch,
              base: .target_branch }]' "$RESP"
}

# --- pr-comments ---------------------------------------------------------------
# GitLab keeps an MR's comments as discussions. A threaded discussion (`individual_note`
# false) is a thread: its id is the discussion id — the reply target `pr-reply --to`
# takes — and an inline one carries its file and line from the first note's position
# (omitted for a general thread on the overview). A standalone note is a top-level
# comment. System notes ("added 1 commit") are dropped everywhere.
#
# `outdated` and `reviews` are omitted: GitLab has no "this hunk no longer applies" flag,
# and no review object carrying a body (approvals have none; a review's summary is an
# ordinary note, already in `comments`). `viewer` is the token's user, omitted if
# GitLab does not say.
verb_pr_comments() {
  local pr="$1" viewer=''
  scratch
  gitlab_request GET "/projects/$PROJECT_ID/merge_requests/$pr"
  gitlab_request GET "/projects/$PROJECT_ID/merge_requests/$pr/discussions" --get --data-urlencode 'per_page=100'
  cp "$RESP" "$SCRATCH/discussions.json"
  # Best-effort: a subshell, so a failure costs only the field. The subshell's own
  # exit does not run the scratch trap, which subshells do not inherit.
  if ( gitlab_request GET "/user" ) 2>/dev/null; then
    viewer="$(jq -r '.username // empty' "$RESP" 2>/dev/null || true)"
  fi
  jq -c --arg ref "$pr" --arg viewer "$viewer" "$JQ_LIB"'
    {ref: $ref}
    + (if $viewer != "" then {viewer: $viewer} else {} end)
    + { threads: [.[]? | select(.individual_note != true)
                  | [.notes[]? | select(.system != true)] as $n | select(($n | length) > 0)
                  | ($n[0].position // {}) as $p
                  | {id: .id, resolved: ($n[0].resolved // false)}
                    + (if ($p.new_path // $p.old_path) != null then {path: ($p.new_path // $p.old_path)} else {} end)
                    + (if ($p.new_line // $p.old_line) != null then {line: ($p.new_line // $p.old_line)} else {} end)
                    + {comments: [$n[] | note]}],
        comments: [.[]? | select(.individual_note == true) | .notes[]? | select(.system != true) | note] }' \
    "$SCRATCH/discussions.json"
}

# --- pr-reply ------------------------------------------------------------------
# With --to, a note in that discussion; without, a new top-level note on the MR. `url`
# is the MR page anchored on the new note, GitLab's own `#note_<id>` form, built
# locally rather than with a second request.
verb_pr_reply() {
  local pr="$1" to="$2" body="$3" path
  scratch
  jq -n --arg body "$body" '{body: $body}' > "$SCRATCH/body.json"
  if [[ -n "$to" ]]; then
    path="/projects/$PROJECT_ID/merge_requests/$pr/discussions/$to/notes"
  else
    path="/projects/$PROJECT_ID/merge_requests/$pr/notes"
  fi
  gitlab_request POST "$path" -H 'Content-Type: application/json' --data-binary @"$SCRATCH/body.json"
  jq -c --arg ref "$pr" --arg page "$GL_URL/$GITLAB_PROJECT/-/merge_requests/$pr" \
    '{ref: $ref, url: "\($page)#note_\(.id)"}' "$RESP"
}

# --- pr-merged -----------------------------------------------------------------
# Whether the branch's MOST RECENT MR (into --base, if given) has merged. `ref` and
# `url` are present only when it has, per omit-don't-null.
verb_pr_merged() {
  local branch="$1" base="$2"
  mr_list "$branch" "$base"
  jq -c --arg branch "$branch" '
    .[0] as $m
    | if $m != null and $m.state == "merged"
      then {branch: $branch, merged: true, ref: ($m.iid | tostring)} + (if $m.web_url then {url: $m.web_url} else {} end)
      else {branch: $branch, merged: false}
      end' "$RESP"
}

# --- default-branch ------------------------------------------------------------
# Local first: origin/HEAD answers on a normal clone and offline, the way git does.
# GitLab is asked only when it is unset, where the helpers' git fallback would guess —
# which is also the only path that needs configuration.
verb_default_branch() {
  local ref branch=''
  if ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" && [[ -n "$ref" ]]; then
    branch="${ref#origin/}"
  else
    require_backend
    branch="$(remote_default_branch)"
  fi
  if [[ -z "$branch" ]]; then
    err "could not determine the default branch (no origin/HEAD, and GitLab did not say)"
    exit 1
  fi
  jq -cn --arg b "$branch" '{branch: $b}'
}

# --- dispatch -----------------------------------------------------------------
# Order per verb: arguments (exit 2), then configuration and tools (exit 4), then the
# backend. So an unknown verb is 3 and a bad argument is 2 even on a machine with no
# configuration, no curl and no network — the conformance gate depends on it.
VERB="${1-}"
[[ $# -gt 0 ]] && shift

# Option parsing shared by the verbs that take flags. Values land in these globals.
OPT_TITLE='' OPT_BODY='' OPT_BASE='' OPT_TO='' HAVE_BODY=0
parse_opts() {  # parse_opts <allowed flags, space-separated> <args>...
  local allowed=" $1 "; shift
  while [[ $# -gt 0 ]]; do
    [[ "$allowed" == *" $1 "* ]] || { err "unknown option for $VERB: $1"; exit 2; }
    [[ $# -ge 2 ]] || { err "$1 needs a value"; exit 2; }
    case "$1" in
      --title) OPT_TITLE="$2" ;;
      --body)  OPT_BODY="$2"; HAVE_BODY=1 ;;
      --base)  OPT_BASE="$2" ;;
      --to)    OPT_TO="$2" ;;
    esac
    shift 2
  done
}

case "$VERB" in
  describe)
    [[ $# -eq 0 ]] || { err "describe takes no arguments"; exit 2; }
    verb_describe
    ;;
  pr-create)
    parse_opts "--title --body --base" "$@"
    if [[ -z "$OPT_TITLE" || -z "$OPT_BODY" ]]; then
      err "usage: $(basename "$0") pr-create --title <title> --body <body> [--base <branch>]"
      exit 2
    fi
    require_backend
    verb_pr_create "$OPT_TITLE" "$OPT_BODY" "$OPT_BASE"
    ;;
  pr-for-branch)
    require_branch "${1-}"
    [[ $# -eq 1 ]] || { err "pr-for-branch takes exactly one branch"; exit 2; }
    require_backend
    verb_pr_for_branch "$1"
    ;;
  pr-comments)
    normalize_pr "${1-}"
    [[ $# -eq 1 ]] || { err "pr-comments takes exactly one merge request"; exit 2; }
    require_backend
    verb_pr_comments "$PR"
    ;;
  pr-reply)
    normalize_pr "${1-}"
    shift
    parse_opts "--to --body" "$@"
    if (( ! HAVE_BODY )) || [[ -z "$OPT_BODY" ]]; then
      err "usage: $(basename "$0") pr-reply <pr> [--to <thread-id>] --body <body>"
      exit 2
    fi
    [[ -z "$OPT_TO" || "$OPT_TO" =~ ^[0-9a-f]+$ ]] \
      || { err "not a GitLab discussion id: '$OPT_TO' (expected a hex id, as pr-comments emits it)"; exit 2; }
    require_backend
    verb_pr_reply "$PR" "$OPT_TO" "$OPT_BODY"
    ;;
  pr-merged)
    require_branch "${1-}"
    branch="$1"; shift
    parse_opts "--base" "$@"
    require_backend
    verb_pr_merged "$branch" "$OPT_BASE"
    ;;
  default-branch)
    [[ $# -eq 0 ]] || { err "default-branch takes no arguments"; exit 2; }
    verb_default_branch
    ;;
  ''|-h|--help|help)
    err "usage: $(basename "$0") <describe|pr-create|pr-for-branch|pr-comments|pr-reply|pr-merged|default-branch> [args...]"
    exit 2
    ;;
  *)
    err "unknown verb: $VERB"
    exit 3
    ;;
esac
