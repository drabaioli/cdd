#!/usr/bin/env bash
# CDD code-host capability adapter — GitHub backend (the reference implementation).
#
# Contract: doc/architecture/capability-adapters.md. Workflow-level rules: process
# doc §2.16. Nothing here re-decides either; this file implements them against `gh`.
#
# Usage:
#   tools/adapters/code-host/github.sh describe
#   tools/adapters/code-host/github.sh pr-create --title <title> --body <body> [--base <branch>]
#   tools/adapters/code-host/github.sh pr-for-branch <branch>
#   tools/adapters/code-host/github.sh pr-comments <pr>
#   tools/adapters/code-host/github.sh pr-reply <pr> [--to <thread-id>] --body <body>
#   tools/adapters/code-host/github.sh pr-merged <branch> [--base <branch>]
#   tools/adapters/code-host/github.sh default-branch
#
# A project binds to it with a committed `.cdd/code-host` shim that execs the copy
# `cdd-worktree.sh install` puts in the adapter library, via $HOME so the binding
# names no machine's checkout (ADR 0011). `bootstrap-cdd-project.sh --code-host github`
# writes it; its core is:
#
#   #!/usr/bin/env bash
#   exec "$HOME/.cdd/tools/adapters/code-host/github.sh" "$@"
#
# It deliberately never installs itself as a resolution-ladder RUNG, for the tracker
# adapter's reason: the machine rung binds every repository on the machine, GitHub or
# not. The library copy is not a rung.
#
# Exit codes (contract-wide): 0 ok, 1 operation failed, 2 usage error,
# 3 verb unsupported by this backend, 4 not configured / auth missing.

set -euo pipefail

CONTRACT_VERSION=1
BACKEND="github"
# `describe` is excluded from this list by the contract: it is mandatory for every
# adapter, so declaring it would be redundant. GitHub supports the whole contract.
DECLARED_VERBS='["pr-create","pr-for-branch","pr-comments","pr-reply","pr-merged","default-branch"]'

err() { printf '%s\n' "$*" >&2; }

# Minimal JSON string escaping for values that come from outside this file (a branch
# name, a URL). Escapes backslash and quote and strips control characters, which
# cannot appear unescaped inside a JSON string.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]//g'
}

# Argument checks publish into globals rather than printing, for the tracker adapter's
# reason: called as `$(check ...)` their `exit 2` would kill only the command
# substitution's subshell. Usage errors exit 2 here, BEFORE any backend contact — the
# contract requires argument validation to precede authentication.
require_branch() {
  local b="${1-}"
  if [[ -z "$b" || "$b" == -* ]]; then
    err "usage: $(basename "$0") $VERB <branch>"
    exit 2
  fi
}

PR=""
normalize_pr() {
  local ref="${1-}"
  if [[ -z "$ref" ]]; then
    err "usage: $(basename "$0") $VERB <pr>   (a GitHub pull request number, e.g. 42 or #42)"
    exit 2
  fi
  if [[ ! "$ref" =~ ^#?[0-9]+$ ]]; then
    err "not a GitHub pull request reference: '$ref' (expected a number, e.g. 42 or #42)"
    exit 2
  fi
  PR="${ref#\#}"
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
# Hermetic by contract: no network, no auth, always exit 0. Every field is a constant
# in this file — a code-host describe needs not even git.
verb_describe() {
  printf '{"capability":"code-host","contract":%s,"backend":"%s","verbs":%s}\n' \
    "$CONTRACT_VERSION" "$BACKEND" "$DECLARED_VERBS"
}

# --- pr-create -----------------------------------------------------------------
# `gh pr create` prints the PR URL on stdout, not JSON, so `ref` comes from the
# trailing path segment — the same parse as the tracker adapter's `issue-create`.
verb_pr_create() {
  local title="$1" body="$2" base="$3" out url
  local -a args=(--title "$title" --body "$body")
  [[ -n "$base" ]] && args+=(--base "$base")
  require_gh
  if ! out="$(gh pr create "${args[@]}" 2>/dev/null)"; then
    err "could not create the GitHub pull request (no access, no pushed branch, or the request failed)"
    exit 1
  fi
  # `|| true`: under `set -e` + `pipefail` a grep that matches nothing would abort the
  # script at the assignment, taking the actionable message below with it.
  url="$(printf '%s' "$out" | grep -oE 'https://[^[:space:]]+/pull/[0-9]+' | tail -1 || true)"
  if [[ -z "$url" ]]; then
    err "the GitHub CLI created something but printed no pull request URL; check the repository manually"
    exit 1
  fi
  printf '{"ref":"%s","url":"%s"}\n' "${url##*/}" "$(json_escape "$url")"
}

# --- pr-for-branch -------------------------------------------------------------
# Every PR whose head is the branch, newest first (gh's own order), `[]` when none.
# gh's `state` is OPEN/CLOSED/MERGED, so lowercasing it is the normalized value.
verb_pr_for_branch() {
  local branch="$1" out
  require_gh
  if ! out="$(gh pr list --head "$branch" --state all \
                --json number,state,url,headRefName,baseRefName \
                --jq '[.[] | {
                        ref: (.number|tostring),
                        state: (.state|ascii_downcase),
                        state_raw: .state,
                        url: .url,
                        head: .headRefName,
                        base: .baseRefName
                      }]' \
                2>/dev/null)"; then
    err "could not list GitHub pull requests for branch '$branch' (no access, or the request failed)"
    exit 1
  fi
  printf '%s\n' "$out"
}

# --- pr-comments ---------------------------------------------------------------
# One GraphQL call, shaped to the contract: review threads with their resolution
# state and reply target, reviews that carry a body, and top-level comments. gh fills
# the {owner}/{repo} placeholders from the current repository.
verb_pr_comments() {
  local pr="$1" out
  require_gh
  # SC2016: the GraphQL variables ($owner, $repo, $pr) and the jq bindings are not
  # shell expansions; single quotes keep them literal.
  # shellcheck disable=SC2016
  if ! out="$(gh api graphql -F owner='{owner}' -F repo='{repo}' -F pr="$pr" -f query='
      query($owner: String!, $repo: String!, $pr: Int!) {
        viewer { login }
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $pr) {
            number
            reviewThreads(first: 100) { nodes { isResolved isOutdated
              comments(first: 100) { nodes { databaseId body path line createdAt author { login } } } } }
            reviews(first: 100) { nodes { databaseId state body createdAt author { login } } }
            comments(first: 100) { nodes { databaseId body createdAt author { login } } }
          }
        }
      }' \
      --jq '.data as $d | $d.repository.pullRequest as $p | select($p != null) |
            {ref: ($p.number|tostring)}
            + (if ($d.viewer.login // "") != "" then {viewer: $d.viewer.login} else {} end)
            + {
                threads: [$p.reviewThreads.nodes[] | .comments.nodes as $c | select(($c|length) > 0) |
                  {id: ($c[0].databaseId|tostring), resolved: .isResolved, outdated: .isOutdated,
                   path: $c[0].path}
                  + (if $c[0].line != null then {line: $c[0].line} else {} end)
                  + {comments: [$c[] | {id: (.databaseId|tostring), author: (.author.login // ""),
                                        created_at: .createdAt, body: .body}]}],
                reviews: [$p.reviews.nodes[] | select((.body // "") != "") |
                  {id: (.databaseId|tostring), author: (.author.login // ""), state_raw: .state,
                   created_at: .createdAt, body: .body}],
                comments: [$p.comments.nodes[] |
                  {id: (.databaseId|tostring), author: (.author.login // ""),
                   created_at: .createdAt, body: .body}]
              }' \
      2>/dev/null)" || [[ -z "$out" ]]; then
    err "could not read comments on GitHub pull request #$pr (no such PR, no access, or the request failed)"
    exit 1
  fi
  printf '%s\n' "$out"
}

# --- pr-reply ------------------------------------------------------------------
# With --to, a reply in that review thread (the thread id is its first comment's REST
# id, as pr-comments emits it); without, a top-level PR comment.
verb_pr_reply() {
  local pr="$1" to="$2" body="$3" out url
  require_gh
  if [[ -n "$to" ]]; then
    if ! url="$(gh api -X POST "repos/{owner}/{repo}/pulls/$pr/comments/$to/replies" \
                  -f body="$body" --jq '.html_url' 2>/dev/null)" || [[ -z "$url" ]]; then
      err "could not reply to thread $to on GitHub pull request #$pr (no such thread, no access, or the request failed)"
      exit 1
    fi
  else
    if ! out="$(gh pr comment "$pr" --body "$body" 2>/dev/null)"; then
      err "could not comment on GitHub pull request #$pr (no access, or the request failed)"
      exit 1
    fi
    url="$(printf '%s' "$out" | grep -oE 'https://[^[:space:]]+' | tail -1 || true)"
    if [[ -z "$url" ]]; then
      err "the GitHub CLI posted something but printed no comment URL; check the pull request manually"
      exit 1
    fi
  fi
  printf '{"ref":"%s","url":"%s"}\n' "$pr" "$(json_escape "$url")"
}

# --- pr-merged -----------------------------------------------------------------
# Whether the branch's MOST RECENT PR (into --base, if given) has merged. `ref` and
# `url` are present only when it has, per omit-don't-null.
verb_pr_merged() {
  local branch="$1" base="$2" line num state url
  local -a args=(--head "$branch" --state all)
  [[ -n "$base" ]] && args+=(--base "$base")
  require_gh
  if ! line="$(gh pr list "${args[@]}" --json number,state,url \
                 --jq '.[0] | select(.) | "\(.number) \(.state) \(.url)"' 2>/dev/null)"; then
    err "could not list GitHub pull requests for branch '$branch' (no access, or the request failed)"
    exit 1
  fi
  read -r num state url <<<"$line" || true
  if [[ "$state" == MERGED ]]; then
    printf '{"branch":"%s","merged":true,"ref":"%s"' "$(json_escape "$branch")" "$num"
    [[ -n "$url" ]] && printf ',"url":"%s"' "$(json_escape "$url")"
    printf '}\n'
  else
    printf '{"branch":"%s","merged":false}\n' "$(json_escape "$branch")"
  fi
}

# --- default-branch ------------------------------------------------------------
# Local first: origin/HEAD answers on a normal clone and offline, the way git does.
# `gh repo view` only when it is unset, where the helpers' git fallback would guess.
verb_default_branch() {
  local ref branch=''
  if ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" && [[ -n "$ref" ]]; then
    branch="${ref#origin/}"
  else
    require_gh
    branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)"
  fi
  if [[ -z "$branch" ]]; then
    err "could not determine the default branch (no origin/HEAD, and GitHub did not say)"
    exit 1
  fi
  printf '{"branch":"%s"}\n' "$(json_escape "$branch")"
}

# --- dispatch -----------------------------------------------------------------
# Dispatch happens first, before any backend work, so an unknown verb is 3 and a bad
# argument is 2 even on a machine with no `gh` and no credentials. The conformance
# gate's verb probe depends on exactly this ordering.
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
    verb_pr_create "$OPT_TITLE" "$OPT_BODY" "$OPT_BASE"
    ;;
  pr-for-branch)
    require_branch "${1-}"
    [[ $# -eq 1 ]] || { err "pr-for-branch takes exactly one branch"; exit 2; }
    verb_pr_for_branch "$1"
    ;;
  pr-comments)
    normalize_pr "${1-}"
    [[ $# -eq 1 ]] || { err "pr-comments takes exactly one pull request"; exit 2; }
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
    [[ -z "$OPT_TO" || "$OPT_TO" =~ ^[0-9]+$ ]] \
      || { err "not a GitHub review-thread id: '$OPT_TO' (expected a number, as pr-comments emits it)"; exit 2; }
    verb_pr_reply "$PR" "$OPT_TO" "$OPT_BODY"
    ;;
  pr-merged)
    require_branch "${1-}"
    branch="$1"; shift
    parse_opts "--base" "$@"
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
