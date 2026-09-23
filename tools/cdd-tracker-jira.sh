#!/usr/bin/env bash
# CDD tracker capability adapter — Jira Cloud backend (curl + jq, REST API v3).
#
# Contract: doc/architecture/capability-adapters.md. Workflow-level rules: process
# doc §2.16. Nothing here re-decides either; this file implements them against Jira.
#
# Usage:
#   cdd-tracker-jira.sh describe
#   cdd-tracker-jira.sh issue-read <ref>
#   cdd-tracker-jira.sh issue-list
#   cdd-tracker-jira.sh issue-create --title <title> --body <body>
#   cdd-tracker-jira.sh issue-transition <ref> <open|closed>
#   cdd-tracker-jira.sh issue-close-token <ref>
#
# Configuration is environment variables only — no config file, nothing read from disk:
#   JIRA_BASE_URL          the site, e.g. https://<site>.atlassian.net (https:// may be left off)
#   JIRA_EMAIL             the Atlassian account the API token belongs to
#   JIRA_API_TOKEN         an Atlassian API token; lives in the user's shell, never in a file
#   JIRA_PROJECT_KEY       the project issue-list and issue-create work in, e.g. ABC
#   JIRA_ISSUE_TYPE        optional; the issue type issue-create uses (default: Task if the
#                          project has it, else the project's first standard type)
#   JIRA_CREATE_FIELDS     optional; a JSON object of extra fields issue-create sends, for a
#                          project that requires custom fields, e.g.
#                          {"customfield_10042":{"value":"Backend"}}
#   JIRA_CLOSE_TRANSITION  optional; the smart-commit transition issue-close-token names
#                          (default done; lowercased, spaces become hyphens)
#
# A project binds to it by making `.cdd/tracker` an executable that execs this file,
# exporting only the non-secret coordinates — the token stays in the user's shell:
#
#   #!/usr/bin/env bash
#   export JIRA_BASE_URL=https://<site>.atlassian.net JIRA_PROJECT_KEY=ABC
#   exec /path/to/cdd-tracker-jira.sh "$@"
#
# It does NOT self-install: a Jira binding is per-project by nature (a site and a
# project key), so a machine-global install has nothing sensible to point at.
#
# Jira Cloud only. Data Center / Server (personal access tokens, API v2) is out of scope.
#
# Exit codes (contract-wide): 0 ok, 1 operation failed, 2 usage error,
# 3 verb unsupported by this backend, 4 not configured / auth missing.

set -euo pipefail

CONTRACT_VERSION=1
BACKEND="jira"
# A Jira key: the project key (an uppercase letter, then uppercase letters, digits or
# underscores), a hyphen, the issue number. No leading `#`, so it never overlaps the
# built-in GitHub shape.
REF_PATTERN='^[A-Z][A-Z0-9_]+-[0-9]+$'
PROJECT_KEY_PATTERN='^[A-Z][A-Z0-9_]+$'
# `describe` is excluded from this list by the contract: it is mandatory for every
# adapter, so declaring it would be redundant.
DECLARED_VERBS='["issue-read","issue-list","issue-create","issue-transition","issue-close-token"]'

err() { printf '%s\n' "$*" >&2; }

# Minimal JSON string escaping for the values `describe` builds with printf (it must
# not need jq, so it stays answerable on a host with nothing installed).
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]//g'
}

# Validate a reference and publish it in $REF. A global rather than printed output,
# for the same reason as the GitHub adapter: called as `$(normalize_ref ...)` its
# `exit 2` would kill only the subshell. Usage errors exit 2 here, BEFORE any
# configuration check or backend contact.
REF=""
normalize_ref() {
  local ref="${1-}"
  if [[ -z "$ref" ]]; then
    err "usage: $(basename "$0") $VERB <ref>   (a Jira issue key, e.g. ABC-123)"
    exit 2
  fi
  if [[ ! "$ref" =~ $REF_PATTERN ]]; then
    err "not a Jira issue key: '$ref' (expected $REF_PATTERN)"
    exit 2
  fi
  REF="$ref"
}

config_hint() {
  case "$1" in
    JIRA_BASE_URL)    echo "export it as your Jira site's URL, e.g. https://<site>.atlassian.net" ;;
    JIRA_EMAIL)       echo "export it as the email of the Atlassian account the API token belongs to" ;;
    JIRA_API_TOKEN)   echo "export it in your shell (an Atlassian API token: https://id.atlassian.com/manage-profile/security/api-tokens); never commit it" ;;
    JIRA_PROJECT_KEY) echo "export it as the Jira project key, e.g. ABC (a project's .cdd/tracker may export it)" ;;
    *)                echo "export it and re-run" ;;
  esac
}

# Exit 4 with one actionable line per missing variable. Never reached by `describe`,
# which is hermetic, nor by a usage error, which has already exited 2.
require_config() {
  local v missing=0
  for v in "$@"; do
    if [[ -z "${!v-}" ]]; then
      err "$v is not set; $(config_hint "$v")"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 4
  # The site may be given as a bare host (`<site>.atlassian.net`), the form Atlassian
  # itself shows; without a scheme curl would speak plain http and stop at the redirect.
  if [[ -n "${JIRA_BASE_URL-}" ]]; then
    JIRA_BASE_URL="${JIRA_BASE_URL%/}"
    [[ "$JIRA_BASE_URL" == *://* ]] || JIRA_BASE_URL="https://$JIRA_BASE_URL"
  fi
  if [[ " $* " == *" JIRA_PROJECT_KEY "* && ! "$JIRA_PROJECT_KEY" =~ $PROJECT_KEY_PATTERN ]]; then
    err "JIRA_PROJECT_KEY is not a Jira project key: '$JIRA_PROJECT_KEY' (expected $PROJECT_KEY_PATTERN)"
    exit 4
  fi
}

require_tools() {
  local t
  for t in curl jq; do
    if ! command -v "$t" >/dev/null 2>&1; then
      err "\`$t\` is not installed or not on PATH; the Jira adapter needs curl and jq — install it and re-run"
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

# jira_request <method> <api path> [extra curl args...]
# Leaves the response body in $RESP and returns only on a 2xx; every failure exits 1
# with a line on stderr. The credential reaches curl through `--config -` on stdin,
# never through argv (`-u` / `-H` would show it to anyone running `ps`), and is never
# written to a file.
RESP=""
jira_request() {
  local method="$1" path="$2"; shift 2
  local base="$JIRA_BASE_URL" code detail
  scratch
  RESP="$SCRATCH/resp"
  # Escape `\` and `"` for curl's quoted config syntax; pure parameter expansion, so
  # the credential never becomes another process's argument either.
  local cred_user="${JIRA_EMAIL//\\/\\\\}"
  cred_user="${cred_user//\"/\\\"}"
  if ! code="$(printf 'user = "%s:%s"\n' "$cred_user" "$(v="${JIRA_API_TOKEN//\\/\\\\}"; printf '%s' "${v//\"/\\\"}")" |
                 curl -sS --config - -X "$method" -H 'Accept: application/json' \
                      -D "$SCRATCH/headers" -o "$RESP" -w '%{http_code}' "$@" "$base$path" \
                      2>"$SCRATCH/curl.err")"; then
    err "could not reach Jira at $base: $(head -1 "$SCRATCH/curl.err")"
    exit 1
  fi
  # A bad token is not always a 401: Jira Cloud serves the request anonymously and
  # answers 404 for an issue anonymous users cannot see, flagging the failed login only
  # in a header. Checked first, so a wrong token is never reported as a missing issue.
  if [[ "$code" == 401 ]] || grep -qi '^x-seraph-loginreason:.*AUTHENTICATED_FAILED' "$SCRATCH/headers" 2>/dev/null; then
    err "Jira rejected the credentials for $base (check JIRA_EMAIL / JIRA_API_TOKEN)"
    exit 1
  fi
  [[ "$code" == 2?? ]] && return 0
  detail="$(jq -r '[.errorMessages[]?, ((.errors // {}) | to_entries[] | "\(.key): \(.value)")] | join("; ")' \
              "$RESP" 2>/dev/null || true)"
  case "$code" in
    404) err "Jira returned 404 for $path (no such issue, or no access)${detail:+: $detail}" ;;
    *)   err "Jira returned HTTP $code for $method $path${detail:+: $detail}" ;;
  esac
  exit 1
}

# --- jq helpers ---------------------------------------------------------------
# iso_utc: Jira's `2026-09-11T10:12:00.000+0200` -> `2026-09-11T08:12:00Z`. Offset
# arithmetic by hand rather than strptime("%z"), whose support is libc-dependent.
# Anything unrecognized passes through unchanged.
#
# adf_text: Atlassian Document Format -> plain text. Lossy by design (marks, colours
# and layout are dropped); the goal is a body a reader — or a session — can follow.
# shellcheck disable=SC2016  # $c and $i are jq variables, not shell ones
JQ_LIB='
def iso_utc:
  if type != "string" then ""
  else
    (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})T(?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})([.][0-9]+)?(?<s>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2})$") as $c
     | (("\($c.d)T\($c.t)Z" | fromdateiso8601)
        - ((if $c.s == "-" then -1 else 1 end) * (($c.h | tonumber) * 3600 + ($c.m | tonumber) * 60)))
     | todate) // .
  end;
def adf_inline:
  if .type == "text" then (.text // "")
  elif .type == "hardBreak" then "\n"
  elif .type == "mention" or .type == "emoji" then (.attrs.text // "")
  elif .type == "inlineCard" then (.attrs.url // "")
  else ([.content[]? | adf_inline] | join(""))
  end;
def adf_block:
  def item: [.content[]? | if .type == "bulletList" or .type == "orderedList"
                             then (adf_block | split("\n") | map("  " + .) | join("\n"))
                             else adf_block end] | join("\n");
  if .type == "paragraph" or .type == "heading" or .type == "codeBlock" then [.content[]? | adf_inline] | join("")
  elif .type == "bulletList" then [.content[]? | "- " + item] | join("\n")
  elif .type == "orderedList" then
    (.attrs.order // 1) as $start | [.content // [] | to_entries[] | "\(.key + $start). " + (.value | item)] | join("\n")
  elif .type == "rule" then "---"
  elif .type == "table" then [.content[]? | adf_block] | join("\n")
  elif .type == "tableRow" then [.content[]? | item] | join(" | ")
  elif .type == "text" or .type == "hardBreak" or .type == "mention" or .type == "emoji" or .type == "inlineCard" then adf_inline
  else [.content[]? | adf_block] | join("\n\n")
  end;
def adf_text:
  if . == null then ""
  elif type == "string" then .
  else [.content[]? | adf_block] | join("\n\n")
  end
  | sub("\\s+$"; "");
def adf_doc:
  { type: "doc", version: 1,
    content: [ splits("\n\\s*\n") | sub("^\\s+"; "") | sub("\\s+$"; "") | select(length > 0)
               | split("\n") as $lines
               | { type: "paragraph",
                   content: [ range(0; $lines | length) as $i
                              | (if $i > 0 then {type: "hardBreak"} else empty end),
                                (if $lines[$i] != "" then {type: "text", text: $lines[$i]} else empty end) ] } ] };
def norm_state: if .statusCategory.key == "done" then "closed" else "open" end;
'

# --- describe ----------------------------------------------------------------
# Hermetic by contract: no network, no credentials, always exit 0, no jq. Everything it
# reports is a constant here or read from the local environment; create_target is
# OMITTED, not nulled, unless both coordinates it is built from are set.
verb_describe() {
  local target='' host
  if [[ -n "${JIRA_PROJECT_KEY-}" && -n "${JIRA_BASE_URL-}" ]]; then
    host="${JIRA_BASE_URL#*://}"
    host="${host%%/*}"
    target="$JIRA_PROJECT_KEY @ $host"
  fi

  printf '{"capability":"tracker","contract":%s,"backend":"%s","ref_pattern":"%s","verbs":%s' \
    "$CONTRACT_VERSION" "$BACKEND" "$(json_escape "$REF_PATTERN")" "$DECLARED_VERBS"
  if [[ -n "$target" ]]; then
    printf ',"create_target":"%s"' "$(json_escape "$target")"
  fi
  printf '}\n'
}

# --- issue-read ---------------------------------------------------------------
# `id` (Jira's numeric id) differs from the key, so both are emitted. The assignee is
# the display name — the email is often hidden by the account's privacy settings — and
# omitted when unassigned. `raw` is skipped, as in the GitHub adapter: nobody reads it.
verb_issue_read() {
  local ref="$1"
  jira_request GET "/rest/api/3/issue/$ref?fields=summary,description,status,labels,assignee,comment"
  jq -c --arg base "$JIRA_BASE_URL" "$JQ_LIB"'
    { ref: .key,
      id: .id,
      backend: "jira",
      title: (.fields.summary // ""),
      body: (.fields.description | adf_text),
      state: (.fields.status | norm_state),
      state_raw: .fields.status.name,
      url: "\($base)/browse/\(.key)",
      labels: (.fields.labels // []),
      comments: [.fields.comment.comments[]? | {author: (.author.displayName // ""), created_at: (.created | iso_utc), body: (.body | adf_text)}]
    }
    + (if .fields.assignee != null then {assignee: .fields.assignee.displayName} else {} end)' "$RESP"
}

# --- issue-list ---------------------------------------------------------------
# Open items only (status category not Done), one page of up to 100 — the same cap as
# the GitHub adapter. `/rest/api/3/search/jql`, not `/search`: the latter has been
# removed from Jira Cloud. Empty is `[]`, not an error.
verb_issue_list() {
  jira_request GET "/rest/api/3/search/jql" --get \
    --data-urlencode "jql=project = \"$JIRA_PROJECT_KEY\" AND statusCategory != Done ORDER BY created DESC" \
    --data-urlencode 'fields=summary,status,labels' \
    --data-urlencode 'maxResults=100'
  jq -c --arg base "$JIRA_BASE_URL" "$JQ_LIB"'
    [.issues[]? | { ref: .key,
                    title: (.fields.summary // ""),
                    state: (.fields.status | norm_state),
                    url: "\($base)/browse/\(.key)",
                    labels: (.fields.labels // []) }]' "$RESP"
}

# --- issue-create -------------------------------------------------------------
# The body is plain text wrapped as ADF paragraphs (blank lines split paragraphs,
# single newlines become hard breaks). Markdown is not interpreted; it shows literally.
# Jira reports the numeric id on a create, so — unlike the GitHub adapter — it is emitted.
#
# The issue type is JIRA_ISSUE_TYPE when set. Otherwise the project is asked for its
# types and the adapter takes `Task` if it has one, else its first standard type (not a
# sub-task, not an epic): projects rename and replace types freely, and a hard `Task`
# default would fail on every project that did.
#
# JIRA_CREATE_FIELDS, when set, is merged under the fields the adapter owns (project,
# type, summary, description), so it can add a project's required custom fields but not
# silently replace the title. Malformed is exit 4, before any request: it is configuration.
verb_issue_create() {
  local title="$1" body="$2" type_field extra='{}'
  if [[ -n "${JIRA_CREATE_FIELDS-}" ]]; then
    if ! extra="$(jq -ce 'if type == "object" then . else error("not an object") end' <<<"$JIRA_CREATE_FIELDS" 2>/dev/null)"; then
      err "JIRA_CREATE_FIELDS is not a JSON object; set it to the extra fields to send, e.g. {\"customfield_10042\":{\"value\":\"Backend\"}}"
      exit 4
    fi
  fi
  scratch
  if [[ -n "${JIRA_ISSUE_TYPE-}" ]]; then
    type_field="$(jq -cn --arg name "$JIRA_ISSUE_TYPE" '{name: $name}')"
  else
    jira_request GET "/rest/api/3/project/$JIRA_PROJECT_KEY"
    type_field="$(jq -c '
      [.issueTypes[]? | select(.subtask != true)] as $t
      | ([$t[] | select(.name == "Task")] + [$t[] | select((.hierarchyLevel // 0) == 0)] + $t)
      | first // empty | {id: .id}' "$RESP")"
    if [[ -z "$type_field" ]]; then
      err "Jira project $JIRA_PROJECT_KEY reports no issue type to create; set JIRA_ISSUE_TYPE and re-run"
      exit 1
    fi
  fi
  jq -n --arg key "$JIRA_PROJECT_KEY" --argjson type "$type_field" --argjson extra "$extra" \
        --arg title "$title" --arg body "$body" "$JQ_LIB"'
    {fields: ($extra + {project: {key: $key}, issuetype: $type, summary: $title, description: ($body | adf_doc)})}' \
    > "$SCRATCH/body.json"
  jira_request POST "/rest/api/3/issue" -H 'Content-Type: application/json' --data-binary @"$SCRATCH/body.json"
  jq -c --arg base "$JIRA_BASE_URL" \
    '{ref: .key, id: .id, url: "\($base)/browse/\(.key)", backend: "jira"}' "$RESP"
}

# --- issue-transition ---------------------------------------------------------
# Normalized state <-> status category: `closed` is category `done`, `open` is anything
# else. Jira transitions are per-workflow, so the adapter asks which ones are available
# from the issue's current status and takes the first that lands in the target category
# (for `open`, preferring a To Do-category status). Already there is a no-op, exit 0.
# No fitting transition is exit 1, naming the ones that do exist.
verb_issue_transition() {
  local ref="$1" want="$2" current cur_name chosen
  jira_request GET "/rest/api/3/issue/$ref?fields=status"
  current="$(jq -r '.fields.status.statusCategory.key' "$RESP")"
  cur_name="$(jq -r '.fields.status.name' "$RESP")"
  if { [[ "$want" == closed && "$current" == "done" ]] || [[ "$want" == open && "$current" != "done" ]]; }; then
    err "$ref is already $want ('$cur_name'); nothing to do"
    jq -cn --arg ref "$ref" --arg state "$want" --arg raw "$cur_name" '{ref: $ref, state: $state, state_raw: $raw}'
    return 0
  fi

  jira_request GET "/rest/api/3/issue/$ref/transitions"
  chosen="$(jq -c --arg want "$want" '
    [.transitions[]?] as $t
    | if $want == "closed" then [$t[] | select(.to.statusCategory.key == "done")]
      else [$t[] | select(.to.statusCategory.key == "new")] + [$t[] | select(.to.statusCategory.key != "done")]
      end
    | first // empty' "$RESP")"
  if [[ -z "$chosen" ]]; then
    err "no transition from '$cur_name' leads to a $want status; available: $(jq -r \
      '[.transitions[]? | "\(.name) -> \(.to.name)"] | if length == 0 then "none" else join(", ") end' "$RESP")"
    exit 1
  fi

  scratch
  jq -c '{transition: {id: .id}}' <<<"$chosen" > "$SCRATCH/body.json"
  jira_request POST "/rest/api/3/issue/$ref/transitions" \
    -H 'Content-Type: application/json' --data-binary @"$SCRATCH/body.json"
  jq -cn --arg ref "$ref" --arg state "$want" --argjson t "$chosen" '{ref: $ref, state: $state, state_raw: $t.to.name}'
}

# --- issue-close-token --------------------------------------------------------
# Purely local: a smart commit, `<KEY> #<transition>`. It only acts where Jira is
# connected to the forge with smart commits enabled (the contract doc's three cases).
# Smart commits name a transition hyphenated and lowercase (`Start Progress` ->
# `#start-progress`), so the override is normalized to that form.
verb_issue_close_token() {
  local tr="${JIRA_CLOSE_TRANSITION:-done}"
  tr="${tr,,}"
  tr="${tr// /-}"
  printf '{"ref":"%s","token":"%s #%s"}\n' "$1" "$1" "$(json_escape "$tr")"
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
    require_config JIRA_BASE_URL JIRA_EMAIL JIRA_API_TOKEN
    require_tools
    verb_issue_read "$REF"
    ;;
  issue-list)
    [[ $# -eq 0 ]] || { err "issue-list takes no arguments"; exit 2; }
    require_config JIRA_BASE_URL JIRA_EMAIL JIRA_API_TOKEN JIRA_PROJECT_KEY
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
    require_config JIRA_BASE_URL JIRA_EMAIL JIRA_API_TOKEN JIRA_PROJECT_KEY
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
    require_config JIRA_BASE_URL JIRA_EMAIL JIRA_API_TOKEN
    require_tools
    verb_issue_transition "$REF" "$2"
    ;;
  issue-close-token)
    normalize_ref "${1-}"
    [[ $# -le 1 ]] || { err "issue-close-token takes exactly one reference"; exit 2; }
    verb_issue_close_token "$REF"
    ;;
  ''|-h|--help|help)
    err "usage: $(basename "$0") <describe|issue-read|issue-list|issue-create|issue-transition|issue-close-token> [args...]"
    exit 2
    ;;
  *)
    err "unknown verb: $VERB"
    exit 3
    ;;
esac
