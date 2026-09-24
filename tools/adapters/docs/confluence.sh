#!/usr/bin/env bash
# CDD docs capability adapter — Confluence Cloud backend (curl + jq). Read-only.
#
# Contract: doc/architecture/capability-adapters.md. Workflow-level rules: process
# doc §2.16. Nothing here re-decides either; this file implements them against Confluence.
#
# Usage:
#   tools/adapters/docs/confluence.sh describe
#   tools/adapters/docs/confluence.sh doc-search <query> [--limit N]
#   tools/adapters/docs/confluence.sh doc-read <ref> [--section <heading>] [--max-chars N]
#   tools/adapters/docs/confluence.sh doc-stat <ref>
#
# A <ref> is a numeric page id or a page URL (`…/wiki/spaces/KEY/pages/<id>/…` or
# `…?pageId=<id>`). A URL's `#fragment` selects a section, as --section does; --section
# wins when both are given. Tiny links (`/wiki/x/…`) are not accepted.
#
# Configuration is environment variables only — no config file, nothing read from disk:
#   CONFLUENCE_BASE_URL    the site, e.g. https://<site>.atlassian.net (https:// may be left
#                          off; a trailing /wiki is dropped). Falls back to JIRA_BASE_URL.
#   CONFLUENCE_EMAIL       the Atlassian account the API token belongs to
#   CONFLUENCE_API_TOKEN   an Atlassian API token; lives in the user's shell, never in a file
#   CONFLUENCE_SPACE_KEYS  optional; comma-separated space keys doc-search is restricted to
#
# Credential fallback: when BOTH CONFLUENCE_EMAIL and CONFLUENCE_API_TOKEN are unset and
# both JIRA_EMAIL and JIRA_API_TOKEN are set, the Jira pair is used (said once on stderr),
# so an Atlassian account shared with the Jira tracker adapter is configured once. The
# pair falls back as a pair or not at all — one variable from each set is never mixed.
# The site falls back to JIRA_BASE_URL independently: API tokens are per account, not
# per site, so a Jira pair also works on a Confluence site of the same account.
#
# A project binds to it by making `.cdd/docs` an executable that execs this file,
# exporting only the non-secret coordinates — the token stays in the user's shell:
#
#   #!/usr/bin/env bash
#   export CONFLUENCE_BASE_URL=https://<site>.atlassian.net CONFLUENCE_SPACE_KEYS=ENG
#   exec /path/to/cdd/tools/adapters/docs/confluence.sh "$@"
#
# It does NOT self-install: a Confluence binding is per-project by nature (a site and the
# spaces worth searching), so a machine-global install has nothing sensible to point at.
#
# Confluence Cloud only. Data Center / Server is out of scope.
#
# Exit codes (contract-wide): 0 ok, 1 operation failed, 2 usage error,
# 3 verb unsupported by this backend, 4 not configured / auth missing.

set -euo pipefail

CONTRACT_VERSION=1
BACKEND="confluence"
# What doc-read and doc-stat accept: a numeric page id, or a page URL carrying one.
REF_PATTERN='^([0-9]+|https?://[^[:space:]]+/wiki/[^[:space:]]*pages/[0-9]+[^[:space:]]*|https?://[^[:space:]]+/wiki/[^[:space:]]*[?&]pageId=[0-9]+[^[:space:]]*)$'
SPACE_KEY_PATTERN='^[A-Za-z0-9_~-]+$'
# `describe` is excluded from this list by the contract: it is mandatory for every
# adapter, so declaring it would be redundant.
DECLARED_VERBS='["doc-search","doc-read","doc-stat"]'

# The context-cost caps (contract: doc-search and doc-read limits).
SEARCH_LIMIT_DEFAULT=10
SEARCH_LIMIT_MAX=25
READ_CAP_DEFAULT=24000
READ_CAP_MAX=100000

err() { printf '%s\n' "$*" >&2; }

# Minimal JSON string escaping for the values `describe` builds with printf (it must
# not need jq, so it stays answerable on a host with nothing installed).
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]//g'
}

# The site, from CONFLUENCE_BASE_URL or its JIRA_BASE_URL fallback, normalized to
# `https://<host>` (no trailing slash, no /wiki). Empty when neither is set. Pure
# parameter expansion, so `describe` can use it too.
site_url() {
  local u="${CONFLUENCE_BASE_URL:-${JIRA_BASE_URL-}}"
  [[ -n "$u" ]] || return 0
  u="${u%/}"
  u="${u%/wiki}"
  u="${u%/}"
  [[ "$u" == *://* ]] || u="https://$u"
  printf '%s' "$u"
}

url_host() {  # url_host <url> -> lowercased host (port kept)
  local h="${1#*://}"
  h="${h%%[/?#]*}"
  printf '%s' "${h,,}"
}

# Validate a reference and publish the page id in $REF, the URL's host in $REF_HOST
# (empty for a bare id) and its decoded fragment in $FRAGMENT. Globals rather than
# printed output: called as `$(normalize_ref ...)` its `exit 2` would kill only the
# subshell. Usage errors exit 2 here, BEFORE any configuration check or backend contact.
REF="" REF_HOST="" FRAGMENT=""
normalize_ref() {
  local ref="${1-}" frag
  if [[ -z "$ref" ]]; then
    err "usage: $(basename "$0") $VERB <ref>   (a Confluence page id, or a page URL)"
    exit 2
  fi
  if [[ ! "$ref" =~ $REF_PATTERN ]]; then
    err "not a Confluence page reference: '$ref' (expected a page id or a page URL; tiny links are not supported)"
    exit 2
  fi
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    REF="$ref"
    return 0
  fi
  REF_HOST="$(url_host "$ref")"
  if [[ "$ref" == *"#"* ]]; then
    frag="${ref#*#}"
    frag="${frag//+/ }"
    frag="${frag//\\/}"
    # Percent-decoding: %XX -> \xXX, which printf %b expands (UTF-8 survives).
    printf -v FRAGMENT '%b' "${frag//%/\\x}"
    ref="${ref%%#*}"
  fi
  if [[ "$ref" =~ pages/([0-9]+) ]] || [[ "$ref" =~ [?\&]pageId=([0-9]+) ]]; then
    REF="${BASH_REMATCH[1]}"
  else
    err "no page id in '$ref'"
    exit 2
  fi
}

config_hint() {
  case "$1" in
    CONFLUENCE_BASE_URL)  echo "export it as your Confluence site's URL, e.g. https://<site>.atlassian.net (JIRA_BASE_URL is used when it is unset)" ;;
    CONFLUENCE_EMAIL)     echo "export it as the email of the Atlassian account the API token belongs to (or leave both CONFLUENCE_EMAIL and CONFLUENCE_API_TOKEN unset to use JIRA_EMAIL / JIRA_API_TOKEN)" ;;
    CONFLUENCE_API_TOKEN) echo "export it in your shell (an Atlassian API token: https://id.atlassian.com/manage-profile/security/api-tokens); never commit it (or leave both CONFLUENCE_EMAIL and CONFLUENCE_API_TOKEN unset to use JIRA_EMAIL / JIRA_API_TOKEN)" ;;
    *)                    echo "export it and re-run" ;;
  esac
}

# Resolve the site and the credential pair, applying the fallbacks above, into $BASE,
# $CRED_EMAIL and $CRED_TOKEN. Exit 4 with one actionable line per missing variable.
# Never reached by `describe`, which is hermetic, nor by a usage error, which has
# already exited 2.
BASE="" CRED_EMAIL="" CRED_TOKEN="" CRED_SOURCE=""
require_config() {
  local missing=0 key
  BASE="$(site_url)"
  if [[ -z "$BASE" ]]; then
    err "CONFLUENCE_BASE_URL is not set; $(config_hint CONFLUENCE_BASE_URL)"
    missing=1
  fi
  if [[ -n "${CONFLUENCE_EMAIL-}" && -n "${CONFLUENCE_API_TOKEN-}" ]]; then
    CRED_EMAIL="$CONFLUENCE_EMAIL" CRED_TOKEN="$CONFLUENCE_API_TOKEN" CRED_SOURCE="CONFLUENCE_EMAIL / CONFLUENCE_API_TOKEN"
  elif [[ -z "${CONFLUENCE_EMAIL-}" && -z "${CONFLUENCE_API_TOKEN-}" && -n "${JIRA_EMAIL-}" && -n "${JIRA_API_TOKEN-}" ]]; then
    CRED_EMAIL="$JIRA_EMAIL" CRED_TOKEN="$JIRA_API_TOKEN" CRED_SOURCE="JIRA_EMAIL / JIRA_API_TOKEN"
  else
    [[ -n "${CONFLUENCE_EMAIL-}" ]] || { err "CONFLUENCE_EMAIL is not set; $(config_hint CONFLUENCE_EMAIL)"; missing=1; }
    [[ -n "${CONFLUENCE_API_TOKEN-}" ]] || { err "CONFLUENCE_API_TOKEN is not set; $(config_hint CONFLUENCE_API_TOKEN)"; missing=1; }
  fi
  if [[ -n "${CONFLUENCE_SPACE_KEYS-}" ]]; then
    IFS=',' read -ra SPACE_KEYS <<<"$CONFLUENCE_SPACE_KEYS"
    for key in "${SPACE_KEYS[@]}"; do
      if [[ ! "$key" =~ $SPACE_KEY_PATTERN ]]; then
        err "CONFLUENCE_SPACE_KEYS holds a malformed space key: '$key' (expected comma-separated keys, e.g. ENG,TT)"
        missing=1
      fi
    done
  fi
  [[ $missing -eq 0 ]] || exit 4
  if [[ "$CRED_SOURCE" == JIRA_* ]]; then
    err "using JIRA_EMAIL / JIRA_API_TOKEN; CONFLUENCE_EMAIL and CONFLUENCE_API_TOKEN are unset"
  fi
}

require_tools() {
  local t
  for t in curl jq; do
    if ! command -v "$t" >/dev/null 2>&1; then
      err "\`$t\` is not installed or not on PATH; the Confluence adapter needs curl and jq — install it and re-run"
      exit 4
    fi
  done
}

# A URL ref must point at the configured site: the credential is sent only there, and a
# page id from another site means nothing on this one.
require_same_host() {
  local site_host
  [[ -n "$REF_HOST" ]] || return 0
  site_host="$(url_host "$BASE")"
  if [[ "$REF_HOST" != "$site_host" ]]; then
    err "the page URL is on $REF_HOST, but the configured Confluence site is $site_host (CONFLUENCE_BASE_URL, or its JIRA_BASE_URL fallback)"
    exit 1
  fi
}

# --- HTTP ---------------------------------------------------------------------
SCRATCH=""
scratch() {
  if [[ -z "$SCRATCH" ]]; then
    SCRATCH="$(mktemp -d)"
    trap 'rm -rf "$SCRATCH"' EXIT
  fi
}

# confluence_request <method> <path under the site> [extra curl args...]
# Leaves the response body in $RESP and returns only on a 2xx; every failure exits 1
# with a line on stderr. The credential reaches curl through `--config -` on stdin,
# never through argv (`-u` / `-H` would show it to anyone running `ps`), and is never
# written to a file.
RESP=""
# curl_cred <body file> <headers file> <curl args...> -> the HTTP code on stdout
curl_cred() {
  local body="$1" headers="$2"; shift 2
  # Escape `\` and `"` for curl's quoted config syntax; pure parameter expansion, so
  # the credential never becomes another process's argument either.
  local cred_user="${CRED_EMAIL//\\/\\\\}"
  cred_user="${cred_user//\"/\\\"}"
  printf 'user = "%s:%s"\n' "$cred_user" "$(v="${CRED_TOKEN//\\/\\\\}"; printf '%s' "${v//\"/\\\"}")" |
    curl -sS --config - -H 'Accept: application/json' \
         -D "$headers" -o "$body" -w '%{http_code}' "$@" 2>"$SCRATCH/curl.err"
}

confluence_request() {
  local method="$1" path="$2"; shift 2
  local code detail
  scratch
  RESP="$SCRATCH/resp"
  if ! code="$(curl_cred "$RESP" "$SCRATCH/headers" -X "$method" "$@" "$BASE$path")"; then
    err "could not reach Confluence at $BASE: $(head -1 "$SCRATCH/curl.err")"
    exit 1
  fi
  # A bad token is rarely a 401 on Confluence Cloud: the request is served anonymously,
  # so a page answers 404 and a search 403, with no failed-login header (checked live).
  # So a 403 or 404 costs one more request — who the credential authenticates as — and
  # an anonymous answer is reported as rejected credentials, never as a missing page.
  if [[ "$code" == 401 ]] || grep -qi '^x-seraph-loginreason:.*AUTHENTICATED_FAILED' "$SCRATCH/headers" 2>/dev/null ||
     { [[ "$code" == 40[34] ]] && ! credentials_accepted; }; then
    err "Confluence rejected the credentials for $BASE (check $CRED_SOURCE)"
    exit 1
  fi
  [[ "$code" == 2?? ]] && return 0
  # v1 errors carry `.message`; v2 errors an `.errors[]` of {title, detail}.
  detail="$(jq -r '[.message? // empty, (.errors? // [] | if type == "array" then .[] else empty end
                    | objects | (.detail // .title // empty))] | map(select(. != "")) | join("; ")' \
              "$RESP" 2>/dev/null || true)"
  case "$code" in
    404) err "Confluence returned 404 for $path (no such page, or no access)${detail:+: $detail}" ;;
    *)   err "Confluence returned HTTP $code for $method $path${detail:+: $detail}" ;;
  esac
  exit 1
}

# True when the credential authenticates as a known user. Any failure to tell — including
# an unreachable host — counts as accepted, leaving the original status to be reported.
credentials_accepted() {
  local code
  code="$(curl_cred "$SCRATCH/whoami" "$SCRATCH/whoami.headers" "$BASE/wiki/rest/api/user/current")" || return 0
  [[ "$code" == 200 ]] && jq -e '.type == "known"' "$SCRATCH/whoami" >/dev/null 2>&1 && return 0
  [[ "$code" == 200 || "$code" == 401 || "$code" == 403 ]] && return 1
  return 0
}

# --- jq helpers ---------------------------------------------------------------
# iso_utc: `2026-06-02T09:14:03.123Z` or `…+0200` -> `2026-06-02T09:14:03Z` (UTC, no
# fraction). Offset arithmetic by hand rather than strptime("%z"), whose support is
# libc-dependent. Anything unrecognized passes through unchanged.
#
# md_*: Atlassian Document Format -> a Markdown subset: headings, paragraphs, lists
# (nested, ordered with their start number), task lists, fenced code with its language,
# inline code, links, block quotes, rules, and tables as ` | `-joined rows. Colours,
# emphasis, layout and media are dropped; the goal is text a session can reason over.
#
# norm: the section-matching key — lowercase, every non-alphanumeric character dropped,
# so `Installation procedure steps`, `installation-procedure-steps` and a URL fragment
# `#Installation-procedure-steps` are the same heading.
# shellcheck disable=SC2016  # $c, $m and the like are jq variables, not shell ones
JQ_LIB='
def iso_utc:
  if type != "string" then ""
  else
    (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})T(?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})([.][0-9]+)?(?:(?<z>Z)|(?<s>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2}))$") as $c
     | (("\($c.d)T\($c.t)Z" | fromdateiso8601)
        - (if $c.z then 0
           else (if $c.s == "-" then -1 else 1 end) * (($c.h | tonumber) * 3600 + ($c.m | tonumber) * 60)
           end))
     | todate) // .
  end;
def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
def plain: [.. | objects | select(.type == "text") | .text // ""] | join("");
def md_marks($m):
  reduce (($m // []) | sort_by(if .type == "code" then 0 elif .type == "link" then 2 else 1 end))[] as $k (.;
    if $k.type == "code" then "`" + . + "`"
    elif $k.type == "link" and ($k.attrs.href // "") != "" then "[" + . + "](" + $k.attrs.href + ")"
    else . end);
def md_inline:
  if .type == "text" then . as $n | ($n.text // "") | md_marks($n.marks)
  elif .type == "hardBreak" then "\n"
  elif .type == "mention" or .type == "emoji" or .type == "status" then (.attrs.text // "")
  elif .type == "inlineCard" then (.attrs.url // "")
  else ([.content[]? | md_inline] | join(""))
  end;
def indent_rest($pad):
  split("\n") | to_entries
  | map(if .key == 0 or .value == "" then .value else $pad + .value end) | join("\n");
def md_block:
  def item($pad): [.content[]? | md_block | select(length > 0)] | join("\n") | indent_rest($pad);
  def inl: [.content[]? | md_inline] | join("") | sub("\\s+$"; "");
  if .type == "paragraph" then inl
  elif .type == "heading" then ("#" * (.attrs.level // 1)) + " " + inl
  elif .type == "codeBlock" then "```" + (.attrs.language // "") + "\n" + ([.content[]? | .text // ""] | join("")) + "\n```"
  elif .type == "bulletList" then [.content[]? | "- " + item("  ")] | join("\n")
  elif .type == "orderedList" then
    (.attrs.order // 1) as $start
    | [.content // [] | to_entries[] | "\(.key + $start). " as $p | $p + (.value | item($p | gsub("."; " ")))] | join("\n")
  elif .type == "taskList" then [.content[]? | md_block] | join("\n")
  elif .type == "taskItem" then (if .attrs.state == "DONE" then "- [x] " else "- [ ] " end) + inl
  elif .type == "blockquote" then [.content[]? | md_block | select(length > 0)] | join("\n\n") | split("\n") | map("> " + .) | join("\n")
  elif .type == "rule" then "---"
  elif .type == "table" then [.content[]? | md_block] | join("\n")
  elif .type == "tableRow" then [.content[]? | [.content[]? | md_block | select(length > 0)] | join(" ")] | join(" | ")
  elif .type == "expand" or .type == "nestedExpand" then
    ([.content[]? | md_block | select(length > 0)] | join("\n\n")) as $body
    | if (.attrs.title // "") != "" then .attrs.title + "\n\n" + $body else $body end
  elif .type == "media" or .type == "mediaSingle" or .type == "mediaGroup" or .type == "extension" then ""
  elif .type == "text" or .type == "hardBreak" or .type == "mention" or .type == "emoji" or .type == "inlineCard" or .type == "status" then md_inline
  else [.content[]? | md_block | select(length > 0)] | join("\n\n")
  end;
def md_doc: [.[] | md_block | select(length > 0)] | join("\n\n") | sub("\\s+$"; "");
def adf_of_page:
  (.body.atlas_doc_format.value // null)
  | if . == null then {type: "doc", content: []} elif type == "string" then fromjson else . end;
def page_url($site): ((._links.base // "\($site)/wiki") + (._links.webui // ""));
def clean_text:
  gsub("@@@(end)?hl@@@"; "")
  | gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&quot;"; "\"") | gsub("&#39;"; "'"'"'") | gsub("&amp;"; "&")
  | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
'

# --- describe ----------------------------------------------------------------
# Hermetic by contract: no network, no credentials, always exit 0, no jq. Everything it
# reports is a constant here or read from the local environment. link_pattern spots a
# page URL inside prose — never a bare id, which would collide with the built-in
# tracker's `^#?[0-9]+$` — and is narrowed to the configured site when one is set.
# search_scope is OMITTED, not nulled, unless both coordinates it is built from are set.
verb_describe() {
  local site host host_re='[A-Za-z0-9.-]+[.]atlassian[.]net' link scope=''
  site="$(site_url)"
  if [[ -n "$site" ]]; then
    host="$(url_host "$site")"
    if [[ "$host" =~ ^[a-z0-9.-]+(:[0-9]+)?$ ]]; then
      host_re="${host//./[.]}"
    else
      host=''
    fi
  fi
  link="https?://${host_re}/wiki/[^[:space:])>\"]*(pages/[0-9]+|pageId=[0-9]+)[^[:space:])>\"]*"
  if [[ -n "${CONFLUENCE_SPACE_KEYS-}" && -n "${host-}" ]]; then
    scope="$CONFLUENCE_SPACE_KEYS @ $host"
  fi

  printf '{"capability":"docs","contract":%s,"backend":"%s","ref_pattern":"%s","link_pattern":"%s","verbs":%s' \
    "$CONTRACT_VERSION" "$BACKEND" "$(json_escape "$REF_PATTERN")" "$(json_escape "$link")" "$DECLARED_VERBS"
  if [[ -n "$scope" ]]; then
    printf ',"search_scope":"%s"' "$(json_escape "$scope")"
  fi
  printf '}\n'
}

# --- doc-search ---------------------------------------------------------------
# CQL through v1 `/wiki/rest/api/search` (v2 has no CQL search). Pages only, excerpts
# only — never a page body. Highlight markers are stripped, entities decoded, whitespace
# collapsed, and each excerpt cut to 300 characters (ending in `…` when cut). Empty is
# `[]`, not an error.
verb_doc_search() {
  local query="$1" limit="$2" q cql key keys=''
  q="${query//\\/\\\\}"
  q="${q//\"/\\\"}"
  cql="type = page AND text ~ \"$q\""
  if [[ -n "${CONFLUENCE_SPACE_KEYS-}" ]]; then
    for key in "${SPACE_KEYS[@]}"; do
      keys+="${keys:+,}\"$key\""
    done
    cql+=" AND space in ($keys)"
  fi
  confluence_request GET "/wiki/rest/api/search" --get \
    --data-urlencode "cql=$cql" \
    --data-urlencode "limit=$limit" \
    --data-urlencode 'excerpt=highlight'
  jq -c --arg site "$BASE" "$JQ_LIB"'
    (._links.base // "\($site)/wiki") as $base
    | [.results[]? | select(.content.id != null)
       | { ref: (.content.id | tostring),
           title: ((.content.title // .title // "") | clean_text),
           url: ($base + (.url // .content._links.webui // "")),
           excerpt: ((.excerpt // "") | clean_text | if length > 300 then .[0:299] + "…" else . end),
           updated_at: (.lastModified | iso_utc),
           space: .resultGlobalContainer.title }
       | with_entries(select(.value != null))]' "$RESP"
}

# --- doc-read -----------------------------------------------------------------
# v2 page with its body as ADF (a JSON document serialized into a string), flattened to
# Markdown. A section runs from the heading whose norm() matches the request up to the
# next heading of the same or a higher level. `sections` lists every heading of the page
# (up to 100), so a caller that hit the cap can re-ask for just the part it needs.
# Content beyond the cap is cut, not summarized: `truncated` says so, and one stderr line
# says how to narrow the read.
verb_doc_read() {
  local id="$1" section="$2" cap="$3"
  confluence_request GET "/wiki/api/v2/pages/$id" --get --data-urlencode 'body-format=atlas_doc_format'
  jq -c --arg site "$BASE" --arg ref "$id" --arg section "$section" --argjson cap "$cap" "$JQ_LIB"'
    . as $p
    | (adf_of_page.content // []) as $blocks
    | [$blocks | to_entries[] | select(.value.type == "heading")
       | {i: .key, level: (.value.attrs.level // 1), text: (.value | plain)}] as $heads
    | ($heads | map(.text) | .[0:100]) as $names
    | if $section == "" then {blocks: $blocks}
      else
        ($section | norm) as $want
        | (($p.title // "") | norm) as $title
        | ([$heads[] | select(($want | length) > 0
                              and ((.text | norm) == $want or ($title + (.text | norm)) == $want))] | first) as $h
        | if $h == null then {missing: true, sections: $names}
          else ([$heads[] | select(.i > $h.i and .level <= $h.level) | .i] | first // ($blocks | length)) as $end
          | {blocks: $blocks[$h.i:$end], section: $h.text}
          end
      end
    | if .missing then .
      else (.blocks | md_doc) as $full
      | { ref: (($p.id // $ref) | tostring),
          title: ($p.title // ""),
          url: ($p | page_url($site)),
          version: $p.version.number,
          updated_at: ($p.version.createdAt | iso_utc),
          format: "markdown",
          content: $full[0:$cap],
          truncated: (($full | length) > $cap),
          content_chars: ($full | length),
          sections: $names,
          section: .section }
        | with_entries(select(.value != null))
      end' "$RESP" > "$SCRATCH/out.json"
  if jq -e '.missing == true' "$SCRATCH/out.json" >/dev/null; then
    err "no section '$section' on page $id; its headings: $(jq -r '.sections | if length == 0 then "none" else map("\"" + . + "\"") | join(", ") end' "$SCRATCH/out.json")"
    exit 1
  fi
  if jq -e '.truncated' "$SCRATCH/out.json" >/dev/null; then
    err "truncated at $cap of $(jq -r '.content_chars' "$SCRATCH/out.json") characters; narrow the read with --section <heading> (see .sections) or raise --max-chars (up to $READ_CAP_MAX)"
  fi
  cat "$SCRATCH/out.json"
}

# --- doc-stat -----------------------------------------------------------------
# Version and freshness only; the body is not fetched.
verb_doc_stat() {
  local id="$1"
  confluence_request GET "/wiki/api/v2/pages/$id"
  jq -c --arg site "$BASE" --arg ref "$id" "$JQ_LIB"'
    { ref: ((.id // $ref) | tostring),
      title: (.title // ""),
      url: page_url($site),
      version: .version.number,
      updated_at: (.version.createdAt | iso_utc) }
    | with_entries(select(.value != null))' "$RESP"
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
  doc-search)
    query='' have_query=0 limit="$SEARCH_LIMIT_DEFAULT"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --limit) limit="${2-}"; shift 2 || { err "--limit needs a value"; exit 2; } ;;
        --*) err "unknown option for doc-search: $1"; exit 2 ;;
        *)
          [[ $have_query -eq 0 ]] || { err "doc-search takes one query; quote it if it has spaces"; exit 2; }
          query="$1" have_query=1; shift ;;
      esac
    done
    if [[ -z "$query" ]]; then
      err "usage: $(basename "$0") doc-search <query> [--limit N]"
      exit 2
    fi
    if [[ ! "$limit" =~ ^[1-9][0-9]?$ ]] || (( limit > SEARCH_LIMIT_MAX )); then
      err "--limit must be a whole number from 1 to $SEARCH_LIMIT_MAX, not '$limit'"
      exit 2
    fi
    require_config
    require_tools
    verb_doc_search "$query" "$limit"
    ;;
  doc-read)
    ref='' have_ref=0 section='' have_section=0 cap="$READ_CAP_DEFAULT"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --section)   section="${2-}"; have_section=1; shift 2 || { err "--section needs a value"; exit 2; } ;;
        --max-chars) cap="${2-}"; shift 2 || { err "--max-chars needs a value"; exit 2; } ;;
        --*) err "unknown option for doc-read: $1"; exit 2 ;;
        *)
          [[ $have_ref -eq 0 ]] || { err "doc-read takes exactly one reference"; exit 2; }
          ref="$1" have_ref=1; shift ;;
      esac
    done
    normalize_ref "$ref"
    if [[ $have_section -eq 1 && -z "$section" ]]; then
      err "--section needs a heading"
      exit 2
    fi
    if [[ ! "$cap" =~ ^[1-9][0-9]{0,5}$ ]] || (( cap > READ_CAP_MAX )); then
      err "--max-chars must be a whole number from 1 to $READ_CAP_MAX, not '$cap'"
      exit 2
    fi
    [[ $have_section -eq 1 ]] || section="$FRAGMENT"
    require_config
    require_tools
    require_same_host
    verb_doc_read "$REF" "$section" "$cap"
    ;;
  doc-stat)
    normalize_ref "${1-}"
    [[ $# -le 1 ]] || { err "doc-stat takes exactly one reference"; exit 2; }
    require_config
    require_tools
    require_same_host
    verb_doc_stat "$REF"
    ;;
  ''|-h|--help|help)
    err "usage: $(basename "$0") <describe|doc-search|doc-read|doc-stat> [args...]"
    exit 2
    ;;
  *)
    err "unknown verb: $VERB"
    exit 3
    ;;
esac
