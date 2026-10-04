#!/usr/bin/env bash
# Answer-shape check for the SHIPPED code-host adapters' `pr-merged`, offline.
#
# The conformance checker (adapter-conformance-check.sh) is backend-neutral: it probes
# any adapter's describe, verb set and exit codes, and never feeds one a backend answer,
# so it can run against a project's own adapter. Whether a shipped adapter turns its
# backend's answer into the contract's fields is backend-specific, so it lives here, run
# by the same adapter-conformance gate. Each adapter runs over a stub backend tool
# (`gh`, `curl`) that returns a canned response, and must answer:
#   - merged     -> merged:true, ref, url, and head_sha (the PR's head commit), which
#                   cdd-worktree-done compares to the local branch tip before -D
#   - not merged -> merged:false and none of those fields (omit-don't-null)
# The stub `gh` keeps only the fields named in `--json`, as gh does, so a field the
# adapter reads without asking for comes back missing.
#
# Usage: scripts/adapter-answers-assert.sh   (provisions and tears down its own temp tree)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB="$REPO_ROOT/tools/adapters/code-host/github.sh"
GITLAB="$REPO_ROOT/tools/adapters/code-host/gitlab.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# jq is required: the answers are read with it (and the GitLab adapter needs it). A
# missing tool is a failure, never a skip (scripts/ci.sh).
command -v jq >/dev/null 2>&1 || fail "jq is required and not installed"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stub" "$WORK/home"
SHA="5276df1e590550e01599307f95a10331f0418d15"

# Stub gh: authenticated; `pr list` projects the canned list down to the --json fields,
# then applies the --jq filter, as gh does.
cat > "$WORK/stub/gh" <<'STUB'
#!/usr/bin/env bash
[[ "${1-}" == auth ]] && exit 0
[[ "${1-}" == pr && "${2-}" == list ]] || exit 1
fields="" filter="."
while (( $# )); do
  case "$1" in
    --json) fields="$2"; shift ;;
    --jq)   filter="$2"; shift ;;
  esac
  shift
done
jq --arg f "$fields" '[.[] | with_entries(select(.key as $k | $f | split(",") | index($k)))]' "$CANNED" \
  | jq -r "$filter"
STUB

# Stub curl: swallows the --config on stdin (the token), writes the canned body to the
# -o file, prints the status code for -w.
cat > "$WORK/stub/curl" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
out=""
while (( $# )); do
  [[ "$1" == -o ]] && { out="$2"; shift; }
  shift
done
cp "$CANNED" "$out"
printf 200
STUB
chmod 755 "$WORK/stub/gh" "$WORK/stub/curl"

# answer <adapter> <canned json> — runs `pr-merged feat --base main` in an empty
# environment (as the conformance checker does) over the stubs; the answer lands in
# $WORK/out.
answer() {
  local adapter="$1"
  printf '%s\n' "$2" > "$WORK/canned.json"
  env -i PATH="$WORK/stub:$PATH" HOME="$WORK/home" CANNED="$WORK/canned.json" \
         GITLAB_PROJECT=g/p GITLAB_TOKEN=x \
         "$adapter" pr-merged feat --base main >"$WORK/out" 2>"$WORK/err" \
    || fail "$(basename "$adapter") pr-merged exited non-zero: $(head -1 "$WORK/err")"
  jq -e . "$WORK/out" >/dev/null 2>&1 || fail "$(basename "$adapter") pr-merged printed no JSON: $(cat "$WORK/out")"
}

expect_merged() {  # expect_merged <label> <ref> <url>
  jq -e --arg ref "$2" --arg url "$3" --arg sha "$SHA" \
     '.merged == true and .ref == $ref and .url == $url and .head_sha == $sha' "$WORK/out" >/dev/null \
    || fail "$1: expected merged:true, ref $2, url and head_sha, got $(cat "$WORK/out")"
}

expect_not_merged() {  # expect_not_merged <label>
  jq -e '.merged == false and (has("ref") or has("url") or has("head_sha") | not)' "$WORK/out" >/dev/null \
    || fail "$1: expected merged:false with no ref/url/head_sha, got $(cat "$WORK/out")"
}

# --- GitHub ----------------------------------------------------------------------
GH_URL="https://github.com/o/r/pull/42"
answer "$GITHUB" '[{"number":42,"state":"MERGED","url":"'"$GH_URL"'","headRefOid":"'"$SHA"'"}]'
expect_merged "github, merged" 42 "$GH_URL"
answer "$GITHUB" '[{"number":42,"state":"OPEN","url":"'"$GH_URL"'","headRefOid":"'"$SHA"'"}]'
expect_not_merged "github, open"
answer "$GITHUB" '[]'
expect_not_merged "github, no PR"
# A head gh does not report is omitted, and the url after it still parses.
answer "$GITHUB" '[{"number":42,"state":"MERGED","url":"'"$GH_URL"'","headRefOid":null}]'
jq -e --arg url "$GH_URL" '.merged == true and .url == $url and (has("head_sha") | not)' "$WORK/out" >/dev/null \
  || fail "github, merged with no head: expected the url and no head_sha, got $(cat "$WORK/out")"
pass "the GitHub code-host adapter's pr-merged reports ref, url and head_sha (headRefOid) when merged, none otherwise"

# --- GitLab ----------------------------------------------------------------------
GL_URL="https://gitlab.example/g/p/-/merge_requests/42"
answer "$GITLAB" '[{"iid":42,"state":"merged","web_url":"'"$GL_URL"'","sha":"'"$SHA"'","merge_commit_sha":"ffffffffffffffffffffffffffffffffffffffff"}]'
expect_merged "gitlab, merged" 42 "$GL_URL"
answer "$GITLAB" '[{"iid":42,"state":"opened","web_url":"'"$GL_URL"'","sha":"'"$SHA"'"}]'
expect_not_merged "gitlab, opened"
answer "$GITLAB" '[]'
expect_not_merged "gitlab, no MR"
pass "the GitLab code-host adapter's pr-merged reports ref, url and head_sha (the MR's sha) when merged, none otherwise"

echo "all adapter answer checks passed"
