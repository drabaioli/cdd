#!/usr/bin/env bash
# Offline correctness checks for the Confluence docs adapter (tools/adapters/docs/confluence.sh).
#
# The adapter-conformance gate proves the adapter is contract-SHAPED — describe, dispatch,
# exit codes — and stops there on purpose: a declared verb reaching an implementation says
# nothing about what the implementation returns. For the tracker adapters that floor is
# the whole offline story. The docs adapter does real work between the wire and stdout —
# ADF flattened to Markdown, sections cut by heading, content capped and flagged — and
# every piece of it is pure transformation, testable with no backend at all.
#
# So this script puts a stub `curl` first on PATH that serves canned Confluence payloads
# by request path, and runs the real adapter against it:
#   1. doc-read, whole page: the Markdown conversion (headings, lists with their start
#      number, fenced code with its language, inline code, links, inline cards, empty
#      paragraphs dropped), the heading list, ISO-8601 UTC, the page URL.
#   2. doc-read --section: the cut stops at the next heading of the same or higher level;
#      a URL #fragment selects the same section, in both Confluence anchor styles.
#   3. An unknown section is exit 1 and names the headings that do exist.
#   4. Truncation: the default cap, --max-chars, and its bounds (exit 2 outside them).
#   5. doc-stat carries version and freshness and no body.
#   6. doc-search: highlight markers stripped, entities decoded, the excerpt cap, the CQL
#      it sends (pages only, quotes escaped, space filter), the --limit bound.
#   7. Configuration: the Jira credential fallback (as a pair, never mixed), the site
#      fallback, a malformed space key.
#   8. A page URL on another site is refused before any request; a missing page is exit 1;
#      a rejected token — which Confluence answers with a 404 or 403, not a 401 — is
#      reported as rejected credentials, not as a missing page.
# Throughout, the stub asserts the API token never appears on curl's command line (it
# must arrive through `--config -` on stdin) and the adapter runs under `env -i`, so no
# credential the caller has exported can leak in or be needed.
#
# Usage: scripts/docs-adapter-assert.sh   (no arguments; no side effects outside $TMPDIR)
# Requires jq (the adapter itself needs it); without it the test skips (advisory).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$REPO_ROOT/tools/adapters/docs/confluence.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -x "$ADAPTER" ]] || fail "adapter not found or not executable: $ADAPTER"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not available; the Confluence adapter needs it"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FIX="$WORK/fixtures"
STUB="$WORK/stub"
mkdir -p "$FIX" "$STUB" "$WORK/home"

TOKEN="fake-not-a-secret-7f3a"
SITE="https://example.atlassian.net"

# --- The stub curl ------------------------------------------------------------
# Parses the argv the adapter builds (-D headers file, -o body file, -w code format,
# --data-urlencode pairs, the URL last), logs the request, and serves a fixture by path.
# It never logs the credential line; it logs only the user half, so the fallback test can
# see which account was used.
cat > "$STUB/curl" <<STUB
#!/usr/bin/env bash
FIX="$FIX"
TOKEN="$TOKEN"
STUB
cat >> "$STUB/curl" <<'STUB'
LOG="$FIX/curl.log"
for a in "$@"; do
  [[ "$a" == *"$TOKEN"* ]] && { echo "stub curl: the API token is on the command line" >&2; exit 99; }
done
cfg="$(cat)"
[[ "$cfg" == 'user = "'* ]] || { echo "stub curl: no credential on stdin" >&2; exit 98; }
user="${cfg#user = \"}"
echo "cred-user=${user%%:*}" >> "$LOG"
headers='' out='' url='' has_body=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -D) headers="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    --data-urlencode)
      echo "data=$2" >> "$LOG"
      [[ "$2" == body-format=atlas_doc_format ]] && has_body=1
      shift 2 ;;
    -X|-H|-w|--config) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
echo "url=$url" >> "$LOG"
: > "$headers"
path="/${url#*://*/}"
code=200
# A rejected token, as Confluence Cloud answers one: served anonymously, so a page is a
# 404, a search a 403, and "who am I" a 403 — no 401, no failed-login header.
if [[ "$cfg" == *":bad-token"* ]]; then
  case "$path" in
    /wiki/rest/api/search|/wiki/rest/api/user/current) code=403 ;;
    *) code=404 ;;
  esac
  echo '{"message":"stub: anonymous"}' > "$out"
  printf '%s' "$code"
  exit 0
fi
case "$path" in
  /wiki/rest/api/user/current) echo '{"type":"known","accountType":"atlassian"}' > "$out" ;;
  /wiki/api/v2/pages/*)
    f="$FIX/page-${path##*/}.json"
    if [[ ! -f "$f" ]]; then
      code=404
      echo '{"errors":[{"status":404,"code":"NOT_FOUND","title":"Not Found","detail":null}]}' > "$out"
    elif [[ $has_body -eq 1 ]]; then
      cat "$f" > "$out"
    else
      jq 'del(.body)' "$f" > "$out"
    fi ;;
  /wiki/rest/api/search) cat "$FIX/search.json" > "$out" ;;
  *) code=404; echo '{"message":"stub: unknown path"}' > "$out" ;;
esac
printf '%s' "$code"
STUB
chmod 755 "$STUB/curl"

# --- Fixtures -----------------------------------------------------------------
# A v2 page whose ADF body is — as Confluence sends it — a JSON document serialized into
# a string. Headings are top-level, as in the ADF the editor produces.
jq -n '
  def t($s): {type: "text", text: $s};
  def p($c): {type: "paragraph", content: $c};
  def h($l; $s): {type: "heading", attrs: {level: $l}, content: [t($s)]};
  def li($c): {type: "listItem", content: $c};
  { type: "doc", version: 1, content: [
      p([t("Intro text.")]),
      h(2; "Requirements"),
      {type: "bulletList", content: [
        li([p([t("Linux")])]),
        li([p([t("At least "), {type: "text", text: "8 GB", marks: [{type: "code"}]}, t(" of RAM")]),
            {type: "bulletList", content: [li([p([t("16 GB for the simulator")])])]}])]},
      h(2; "Install steps"),
      h(3; "Base"),
      {type: "orderedList", attrs: {order: 1}, content: [
        li([p([t("Download it")]),
            {type: "codeBlock", attrs: {language: "shell"}, content: [t("curl -O https://example.com/x")]}]),
        li([p([t("Read "), {type: "text", text: "the manual", marks: [{type: "link", attrs: {href: "https://example.com/manual"}}]}])])]},
      {type: "paragraph"},
      h(3; "CCA3"),
      {type: "orderedList", attrs: {order: 8}, content: [li([p([t("Run the tool")])])]},
      h(3; "Simulator"),
      p([{type: "inlineCard", attrs: {url: "https://example.com/sim"}}]),
      {type: "rule"},
      h(2; "Support"),
      p([t("Email us.")])
  ]} as $adf
  | { id: "100", title: "Setup Guide", status: "current",
      version: {number: 17, createdAt: "2026-06-02T09:14:03.123Z"},
      _links: {base: "https://example.atlassian.net/wiki", webui: "/spaces/TT/pages/100/Setup+Guide"},
      body: {atlas_doc_format: {value: ($adf | tojson), representation: "atlas_doc_format"}} }' > "$FIX/page-100.json"

# A page larger than the default cap: 300 paragraphs of 100 characters.
jq -n '
  { type: "doc", version: 1,
    content: [range(300) | {type: "paragraph", content: [{type: "text", text: ("x" * 100)}]}] } as $adf
  | { id: "200", title: "Big", version: {number: 2, createdAt: "2026-01-01T00:00:00.000+0100"},
      _links: {base: "https://example.atlassian.net/wiki", webui: "/spaces/TT/pages/200/Big"},
      body: {atlas_doc_format: {value: ($adf | tojson), representation: "atlas_doc_format"}} }' > "$FIX/page-200.json"

# A v1 search response: highlight markers, an HTML entity, a long excerpt, and a result
# with no space container.
jq -n '
  { results: [
      { content: {id: "100", type: "page", title: "Setup Guide"},
        title: "@@@hl@@@Setup@@@endhl@@@ Guide",
        excerpt: ("Install the @@@hl@@@tool@@@endhl@@@ &amp; its   deps. " + ("y" * 400)),
        url: "/spaces/TT/pages/100/Setup+Guide",
        lastModified: "2026-06-02T09:14:03.000Z",
        resultGlobalContainer: {title: "Team Tech", displayUrl: "/spaces/TT"} },
      { content: {id: "300", type: "page", title: "Other"},
        title: "Other", excerpt: "short &lt;one&gt;", url: "/spaces/TT/pages/300/Other",
        lastModified: "2026-05-01T10:00:00.000Z" } ],
    start: 0, limit: 10, size: 2, totalSize: 2,
    _links: {base: "https://example.atlassian.net/wiki", context: "/wiki"} }' > "$FIX/search.json"

# --- Running the adapter ------------------------------------------------------
# ENV is the adapter's entire environment (it runs under env -i); tests adjust copies.
BASE_ENV=(PATH="$STUB:$PATH" HOME="$WORK/home"
          CONFLUENCE_BASE_URL="$SITE" CONFLUENCE_EMAIL="docs@example.invalid" CONFLUENCE_API_TOKEN="$TOKEN")
ENV=("${BASE_ENV[@]}")
RC=0
run() {  # run <adapter arg>...  -> $RC, $WORK/out, $WORK/err
  RC=0
  : > "$FIX/curl.log"
  env -i "${ENV[@]}" "$ADAPTER" "$@" >"$WORK/out" 2>"$WORK/err" || RC=$?
}
expect_rc() {  # expect_rc <want> <label>
  [[ "$RC" == "$1" ]] || fail "$2: expected exit $1, got $RC; stderr: $(head -3 "$WORK/err")"
}
check() {  # check <label> <jq filter that must be true on stdout>
  jq -e "$2" "$WORK/out" >/dev/null || fail "$1; got: $(head -c 600 "$WORK/out")"
}

# --- 1. doc-read, whole page ----------------------------------------------------
run doc-read 100
expect_rc 0 "doc-read of a page"
check "format is markdown" '.format == "markdown"'
check "headings carry their level" '.content | contains("## Requirements") and contains("### CCA3")'
# SC2016: the backticks are Markdown inside a jq string, not command substitution.
# shellcheck disable=SC2016
check "the fenced code block keeps its language" '.content | contains("```shell\n   curl -O https://example.com/x\n   ```")'
check "a link mark becomes [text](href)" '.content | contains("[the manual](https://example.com/manual)")'
# shellcheck disable=SC2016  # as above
check "inline code becomes backticks" '.content | contains("`8 GB`")'
check "a nested list is indented" '.content | contains("\n  - 16 GB for the simulator")'
check "an ordered list keeps its start number" '.content | contains("8. Run the tool")'
check "a code block inside a list item is indented under it" '.content | contains("1. Download it\n   ```shell")'
check "an inline card becomes its URL" '.content | contains("https://example.com/sim")'
check "an empty paragraph leaves no gap" '.content | contains("\n\n\n") | not'
check "not truncated" '.truncated == false'
check "content_chars is the content length" '.content_chars == (.content | length)'
check "sections lists every heading, in order" '.sections == ["Requirements","Install steps","Base","CCA3","Simulator","Support"]'
check "updated_at is ISO-8601 UTC without the fraction" '.updated_at == "2026-06-02T09:14:03Z"'
check "url is the site base plus the page path" '.url == "https://example.atlassian.net/wiki/spaces/TT/pages/100/Setup+Guide"'
check "ref and version" '.ref == "100" and .version == 17 and .title == "Setup Guide"'
check "no section field without a section request" 'has("section") | not'
check "no nulls" '[.. | select(. == null)] | length == 0'
grep -qx 'data=body-format=atlas_doc_format' "$FIX/curl.log" || fail "doc-read did not ask for the ADF body"
pass "doc-read converts a page to Markdown, with its headings, version and URL"

# --- 2. doc-read --section ----------------------------------------------------
run doc-read 100 --section CCA3
expect_rc 0 "doc-read --section CCA3"
check "the section starts at its heading" '.content | startswith("### CCA3")'
check "the section stops before the next same-level heading" '(.content | contains("Run the tool")) and (.content | contains("Simulator") | not)'
check "the section is echoed" '.section == "CCA3"'
check "sections still lists the whole page" '.sections | length == 6'
cp "$WORK/out" "$WORK/cca3.json"

run doc-read 100 --section install-steps
expect_rc 0 "doc-read --section of an h2"
check "an h2 section runs past its h3s and the rule, up to the next h2" \
  '(.content | startswith("## Install steps")) and (.content | contains("### Simulator")) and (.content | contains("---")) and (.content | contains("Support") | not)'

run doc-read "$SITE/wiki/spaces/TT/pages/100/Setup+Guide#CCA3"
expect_rc 0 "doc-read of a URL with a #fragment"
[[ "$(jq -c 'del(.url)' "$WORK/out")" == "$(jq -c 'del(.url)' "$WORK/cca3.json")" ]] ||
  fail "a URL #fragment did not select the same section as --section: $(head -c 300 "$WORK/out")"

run doc-read "$SITE/wiki/spaces/TT/pages/100/Setup+Guide#SetupGuide-CCA3"
expect_rc 0 "doc-read of a URL with an old-style #Title-Heading fragment"
check "an old-style anchor selects the same section" '.section == "CCA3"'

run doc-read "$SITE/wiki/pages/viewpage.action?pageId=100"
expect_rc 0 "doc-read of a ?pageId= URL"
check "a ?pageId= URL resolves the page" '.ref == "100" and (has("section") | not)'
pass "doc-read --section and URL fragments cut the page at the right headings"

# --- 3. an unknown section ----------------------------------------------------
run doc-read 100 --section nope
expect_rc 1 "doc-read of a missing section"
grep -q '"Requirements"' "$WORK/err" || fail "a missing section did not list the page's headings: $(cat "$WORK/err")"
[[ ! -s "$WORK/out" ]] || fail "a missing section still wrote to stdout"
pass "an unknown section is exit 1 and names the headings that exist"

# --- 4. truncation ------------------------------------------------------------
run doc-read 200
expect_rc 0 "doc-read of a big page"
check "a page over the default cap is flagged" '.truncated == true and (.content | length) == 24000 and .content_chars > 24000'
grep -q 'truncated at 24000' "$WORK/err" || fail "truncation did not say so on stderr"
check "a +01:00 timestamp is converted to UTC" '.updated_at == "2025-12-31T23:00:00Z"'
run doc-read 200 --max-chars 500
expect_rc 0 "doc-read --max-chars 500"
check "--max-chars sets the cap" '.truncated == true and (.content | length) == 500'
run doc-read 100 --max-chars 100000
expect_rc 0 "doc-read --max-chars at the maximum"
for bad in 0 100001 abc 0500; do
  run doc-read 100 --max-chars "$bad"
  expect_rc 2 "doc-read --max-chars $bad"
  [[ ! -s "$FIX/curl.log" ]] || fail "doc-read --max-chars $bad reached curl before rejecting it"
done
pass "doc-read caps content, flags truncation, and bounds --max-chars"

# --- 5. doc-stat --------------------------------------------------------------
run doc-stat 100
expect_rc 0 "doc-stat"
check "doc-stat carries exactly ref, title, url, version, updated_at" \
  '(keys == (["ref","title","url","version","updated_at"] | sort)) and .version == 17 and .updated_at == "2026-06-02T09:14:03Z"'
grep -q '^data=' "$FIX/curl.log" && fail "doc-stat asked for the page body"
pass "doc-stat reports version and freshness without the body"

# --- 6. doc-search ------------------------------------------------------------
run doc-search 'say "hi"'
expect_rc 0 "doc-search"
check "doc-search returns an array" 'type == "array" and length == 2'
check "highlight markers are stripped" '[.[] | .title, .excerpt] | all(contains("@@@") | not)'
check "entities are decoded and whitespace collapsed" '.[0].excerpt | startswith("Install the tool & its deps. ")'
check "a long excerpt is cut to 300 characters, ending in an ellipsis" '.[0].excerpt | length == 300 and endswith("…")'
check "a short excerpt is left whole" '.[1].excerpt == "short <one>"'
check "space is present when known and omitted otherwise" '.[0].space == "Team Tech" and (.[1] | has("space") | not)'
check "result fields" '.[0].ref == "100" and .[0].url == "https://example.atlassian.net/wiki/spaces/TT/pages/100/Setup+Guide" and .[0].updated_at == "2026-06-02T09:14:03Z"'
grep -qxF 'data=cql=type = page AND text ~ "say \"hi\""' "$FIX/curl.log" ||
  fail "doc-search sent the wrong CQL: $(grep '^data=cql' "$FIX/curl.log")"
grep -qx 'data=limit=10' "$FIX/curl.log" || fail "doc-search did not send the default limit of 10"

ENV=("${BASE_ENV[@]}" CONFLUENCE_SPACE_KEYS="TT,ENG")
run doc-search tool --limit 25
expect_rc 0 "doc-search with space keys"
grep -qxF 'data=cql=type = page AND text ~ "tool" AND space in ("TT","ENG")' "$FIX/curl.log" ||
  fail "CONFLUENCE_SPACE_KEYS did not restrict the search: $(grep '^data=cql' "$FIX/curl.log")"
ENV=("${BASE_ENV[@]}" CONFLUENCE_SPACE_KEYS='TT,E"NG')
run doc-search tool
expect_rc 4 "a malformed space key"
ENV=("${BASE_ENV[@]}")

for bad in 26 0 x; do
  run doc-search tool --limit "$bad"
  expect_rc 2 "doc-search --limit $bad"
done
run doc-search
expect_rc 2 "doc-search with no query"
pass "doc-search cleans excerpts, caps them, and sends pages-only CQL"

# --- 7. configuration fallbacks ----------------------------------------------
ENV=(PATH="$STUB:$PATH" HOME="$WORK/home" CONFLUENCE_BASE_URL="$SITE"
     JIRA_EMAIL="jira@example.invalid" JIRA_API_TOKEN="$TOKEN")
run doc-stat 100
expect_rc 0 "doc-stat on the Jira credential pair"
grep -q 'using JIRA_EMAIL / JIRA_API_TOKEN' "$WORK/err" || fail "the Jira fallback was not said on stderr"
grep -qx 'cred-user=jira@example.invalid' "$FIX/curl.log" || fail "the Jira fallback did not send the Jira account"

ENV=(PATH="$STUB:$PATH" HOME="$WORK/home" CONFLUENCE_BASE_URL="$SITE" CONFLUENCE_EMAIL="docs@example.invalid"
     JIRA_EMAIL="jira@example.invalid" JIRA_API_TOKEN="$TOKEN")
run doc-stat 100
expect_rc 4 "one Confluence credential set, the Jira pair set"
grep -q 'CONFLUENCE_API_TOKEN is not set' "$WORK/err" || fail "a half-set Confluence pair did not name the missing variable"
[[ ! -s "$FIX/curl.log" ]] || fail "a half-set Confluence pair mixed in the Jira token and reached curl"

ENV=(PATH="$STUB:$PATH" HOME="$WORK/home" JIRA_BASE_URL="jira-site.atlassian.net/"
     CONFLUENCE_EMAIL="docs@example.invalid" CONFLUENCE_API_TOKEN="$TOKEN")
run doc-stat 100
expect_rc 0 "doc-stat on the JIRA_BASE_URL fallback"
grep -qx 'url=https://jira-site.atlassian.net/wiki/api/v2/pages/100' "$FIX/curl.log" ||
  fail "the site did not fall back to JIRA_BASE_URL: $(grep '^url=' "$FIX/curl.log")"

ENV=(PATH="$STUB:$PATH" HOME="$WORK/home")
run doc-stat 100
expect_rc 4 "no configuration at all"
grep -q 'CONFLUENCE_BASE_URL is not set' "$WORK/err" || fail "no site did not name CONFLUENCE_BASE_URL"
ENV=("${BASE_ENV[@]}")
pass "credentials fall back to the Jira pair only as a pair; the site falls back on its own"

# --- 8. refusals --------------------------------------------------------------
run doc-read "https://elsewhere.atlassian.net/wiki/spaces/TT/pages/100/X"
expect_rc 1 "a page URL on another site"
if ! grep -q 'elsewhere.atlassian.net' "$WORK/err" || ! grep -q 'example.atlassian.net' "$WORK/err"; then
  fail "a foreign-site URL did not name both hosts: $(cat "$WORK/err")"
fi
[[ ! -s "$FIX/curl.log" ]] || fail "a foreign-site URL reached curl"
run doc-read 999
expect_rc 1 "a missing page"
grep -q 'returned 404' "$WORK/err" || fail "a missing page did not report the 404: $(cat "$WORK/err")"
grep -qx 'url=https://example.atlassian.net/wiki/rest/api/user/current' "$FIX/curl.log" ||
  fail "a 404 did not check whether the credentials were accepted"
ENV=("${BASE_ENV[@]}" CONFLUENCE_API_TOKEN="bad-token")
for verb in "doc-stat 100" "doc-search tool"; do
  # shellcheck disable=SC2086  # the verb and its argument split on purpose
  run $verb
  expect_rc 1 "$verb with a rejected token"
  grep -q 'rejected the credentials' "$WORK/err" ||
    fail "$verb with a rejected token was not reported as rejected credentials: $(cat "$WORK/err")"
done
ENV=("${BASE_ENV[@]}")
run doc-read "$SITE/wiki/x/AbCd"
expect_rc 2 "a tiny link"
pass "a foreign-site URL, a missing page and a rejected token are each reported as such"

# The token went through stdin every time (the stub exits 99 otherwise, and every
# request above succeeded or failed on its own terms); it was never logged either.
grep -rqF "$TOKEN" "$FIX/curl.log" && fail "the API token reached the request log"
pass "the API token never reached curl's command line"

echo "docs adapter: clean (offline, against canned Confluence payloads)"
