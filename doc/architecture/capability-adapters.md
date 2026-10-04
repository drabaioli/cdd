# Capability adapters: the tracker and code-host contracts

The wire contract every capability adapter answers, pinned for two capabilities: the **tracker**, with a GitHub reference implementation (`tools/adapters/tracker/github.sh`), a Jira Cloud adapter (`tools/adapters/tracker/jira.sh`) and a GitLab adapter (`tools/adapters/tracker/gitlab.sh`), and the **code host** — where PRs and merge state live — with a GitHub reference implementation (`tools/adapters/code-host/github.sh`) and a GitLab adapter (`tools/adapters/code-host/gitlab.sh`).

The *why* lives elsewhere and is not restated here: the process doc's §2.16 states the workflow-level rules (the fixed `.cdd/` namespace, the mandatory `describe` verb, the resolution ladder, the replace-vs-mirror rule, and that CDD never stores or proxies a secret), and `adr/0007-extend-cdd-through-capability-adapters.md` records the decision and its alternatives (`adr/0009-drop-the-docs-capability.md` narrows it: docs is not a capability; `adr/0010-code-host-rename-and-broken-adapter-rule.md` names the code host and replaces the ladder's fall-through for a broken adapter; `adr/0011-bind-adapters-through-a-machine-global-library.md` settles how a downstream project's committed binding reaches a shipped adapter). This document is the layer below both: the verbs, the JSON each returns, the exit codes, and the two invariants a conformance gate can be written against. An adapter author needs this document and nothing else.

Nothing here ships to downstream projects. The CDD repo is the canonical reference for adapter authors, exactly as it is for the process doc, and the template ships no copy of either — only a one-line pointer here, in its `doc/architecture/index.md`.

## What an adapter is

An executable — any language — at a fixed path, invoked as `<adapter> <verb> [args...]`. It is not a library, not a config file, and not a service. CDD discovers it by testing that the path exists — a file that exists but is not executable is broken, not absent — and learns what it can do by running `describe`.

Three rules hold for every verb of every capability:

- **JSON on stdout**, one object or one array, never partial output. Human-readable messages — errors, hints, progress — go to **stderr**, always. A caller reads stdout as data and shows stderr to the user.
- **Timestamps are ISO-8601 UTC** (`2026-09-11T08:12:00Z`).
- **Omit unsupported fields; never emit `null` to mean "unsupported."** An absent field means the backend has no such concept. `[]` and `""` mean the backend has the concept and it is empty. A `null` is a bug, and the conformance gate rejects one anywhere in `describe`'s output.

## Exit codes

The same table for every verb of every capability:

```
0  success (JSON on stdout)
1  operation failed        (network, auth rejected, bad ref)
2  usage error
3  verb not supported by this backend
4  not configured / auth missing → actionable message on stderr
```

The distinction that earns its keep is **3 vs 1**. A verb absent from `describe.verbs` is unsupported, and calling it exits 3 — which is what lets a prompt tell "GitHub has no transitions, carry on" apart from "Jira is down, stop." Without a distinct code every caller has to guess, and they will guess differently.

Two rules bound the codes, and the offline conformance gate exists because of them:

- **`describe` is hermetic.** It touches no network, requires no authentication, and **always exits 0**. Whatever it reports is derivable locally — from the adapter's own source, from the environment, or from the repo. An adapter that cannot answer `describe` without credentials is non-conformant.
- **Verb dispatch precedes any backend work.** An unknown verb exits 3, and a missing or invalid argument to a known verb — or no verb at all — exits 2, *before* the adapter contacts its backend or authenticates. An adapter that authenticates first and parses later is non-conformant, and turns a usage error into an auth error for everyone downstream.

## `describe`

Mandatory for every adapter of every capability. It takes no arguments.

```console
$ .cdd/tracker describe
{"capability":"tracker","contract":1,"backend":"github",
 "ref_pattern":"^#?[0-9]+$",
 "verbs":["issue-read","issue-list","issue-create","issue-transition","issue-comment","issue-close-token"],
 "create_target":"drabaioli/cdd"}
```

| Field           | Required | Meaning                                                                        |
| --------------- | -------- | ------------------------------------------------------------------------------ |
| `capability`    | yes      | The role this adapter fills — `tracker` or `code-host`. Matches the file name under `.cdd/`. |
| `contract`      | yes      | Integer contract version; see below.                                            |
| `backend`       | yes      | Non-empty string naming the service (`github`, `jira`, …). Free-form; nothing branches on it. |
| `ref_pattern`   | tracker  | An **ERE** that matches a reference this backend accepts. CDD dispatches on it instead of hardcoding a shape. Required of a tracker; not part of the code-host contract, where every PR ref a caller holds is one the adapter itself emitted, so nothing dispatches on its shape. |
| `verbs`         | yes      | Non-empty array of the verbs this adapter implements, **excluding `describe`**. |
| `create_target` | no (tracker) | Human-readable coordinates a created item would land in (`owner/repo`, `XYZ / board 42`). Shown to a human before a write; nothing parses it. Omitted when it cannot be derived locally. |

**`describe` excludes itself from `verbs`.** It is mandatory for every adapter, so listing it is redundant, and the conformance gate checks it separately. Issue #86's Jira example must not be read the other way.

**Versioning: `describe.contract` is an integer, and CDD supports N and N-1.** The current contract version is **1**, for both capabilities. An adapter declaring an older-than-N-1 or newer-than-N version, a `describe` that exits non-zero or does not parse, or one reporting another `capability`, is **installed but broken**: the caller says so in one line and does not try a lower rung (see [Resolution](#resolution-the-broken-adapter-rule-and-the-announcement-rule)).

`ref_pattern` is what makes the ladder work in the direction issue #86 requires: a prompt must **not** learn to recognize `XYZ-123`. It resolves the adapter, reads `ref_pattern`, and lets the adapter decide what a valid reference looks like. With no tracker adapter resolved there is no `ref_pattern`, so no argument is issue-shaped ([ADR 0012](adr/0012-drop-the-builtin-gh-rung.md)).

## The tracker verbs

Seven verbs, of which one (`describe`) is mandatory and the other six are declared per backend.

| Verb                                | Replaces today                              | Notes                          |
| ----------------------------------- | ------------------------------------------- | ------------------------------ |
| `describe`                          | —                                           | mandatory                      |
| `issue-read <ref>`                  | `gh issue view` (`/cdd-next-step` §0b)      | comments inline                |
| `issue-list`                        | `gh issue list` (`/cdd-next-step` §0b)      | open items only                |
| `issue-create --title T --body B`   | `/cdd-pre-pr`'s improvement channel         |                                |
| `issue-transition <ref> <state>`    | `cdd-worktree-done` / `-gc`, post-merge     | once per recorded ref          |
| `issue-comment <ref> --body B`      | — (new)                                     | `cdd-worktree-done` / `-gc`, after a post-merge close |
| `issue-close-token <ref>`           | `/cdd-pre-pr` §11, once per recorded ref    | `Closes #42` / a Jira smart commit |

### `issue-read <ref>` → object

```json
{ "ref": "XYZ-123", "id": "10432", "backend": "jira",
  "title": "…", "body": "…",
  "state": "open", "state_raw": "In Review",
  "url": "https://…", "labels": ["…"], "assignee": "…",
  "comments": [{"author":"…","created_at":"2026-09-11T08:12:00Z","body":"…"}],
  "raw": { } }
```

Four shape rules, all of which generalize past this verb:

- **`ref` vs `id`.** `ref` is the human handle — what a user types and what the branch name embeds. `id` is the backend's internal key, emitted only when it differs from `ref`. For GitHub `ref` is the bare number as a string (`"42"`, accepted as `42` or `#42`) and `id` is the GraphQL node id, so both are present and distinct.
- **`state` is normalized to `open` or `closed`**; `state_raw` keeps the backend's own value (`In Review`, `CLOSED`). A caller that only needs "is this still live" reads `state`; one showing the user a status reads `state_raw`.
- **`raw`** is an optional passthrough of the backend's native payload. Nothing in CDD reads it; it exists so an adapter never has to choose between the contract and the truth.
- **Omit, don't null** (above).

### `issue-list` → array

```json
[ {"ref":"42","title":"…","state":"open","url":"https://…","labels":["…"]} ]
```

Open items only. Empty is `[]`, not an error.

### `issue-create --title T --body B` → object

```json
{"ref":"42","url":"https://…","backend":"github"}
```

`id` follows `issue-read`'s omit rule and one more: it is emitted only when it differs from `ref` **and the backend reports it on a create**. GitHub's `gh issue create` prints the new issue's URL and nothing else, so the shipped adapter omits `id` here while `issue-read` carries it — which is the omit-don't-null rule doing its job, not an inconsistency.

### `issue-transition <ref> <state>` → object

```json
{"ref":"XYZ-123","state":"closed","state_raw":"Done","changed":true}
```

`<state>` is a normalized `open`/`closed`; the adapter maps it onto whatever the backend calls that. An item already in the target state is a no-op: exit 0 with `changed: false`, so the caller can tell "closed now" from "was already closed" without parsing stderr. `changed` is an additive field, so the contract stays at 1; a caller treats its absence as `true`. A backend with no way to change an item's state does not declare the verb.

Its consumer is the post-merge close in `cdd-worktree-done` and `cdd-worktree-gc`: once the code host confirms the task's PR merged, each calls `issue-transition <ref> closed` once for every ref on the task's state record (see [Shell helpers](shell-helpers.md#tracker-resolution-the-post-merge-issue-close)).

### `issue-comment <ref> --body B` → object

```json
{"ref":"XYZ-123","id":"10000","url":"https://…/browse/XYZ-123?focusedCommentId=10000"}
```

Posts a comment on the item. `B` is plain text; an adapter may render a bare `http(s)` URL in it as a link (the Jira adapter does). `url` is the new comment's, omitted when the backend does not report one; `id` follows `issue-create`'s omit rule. Additive, so the contract stays at 1.

Its consumer is the post-merge close: on each ref that `issue-transition` reports it closed **now** (`changed: true`), `cdd-worktree-done` and `cdd-worktree-gc` post one comment naming the merged PR and its link — `Closed after PR #42 merged: https://…`. A ref already closed (`changed: false`) gets none, so a gc retry never comments twice, and an item closed by the PR's own close line already shows the PR (GitHub's timeline, Jira's development panel). The comment is best-effort: a failure is one warning and never keeps the task's record, and an adapter that does not declare the verb is said once per run and the rest skipped.

### `issue-close-token <ref>` → object

```json
{"ref":"42","token":"Closes #42"}
```

The string a commit message or PR description carries so the backend auto-closes the item on merge. GitHub yields `Closes #42`; Jira yields a smart commit. A backend with no such mechanism does not declare the verb, and the caller simply writes no token.

Its consumer is `/cdd-pre-pr` §11, when it opens the PR: it reads the references recorded on the task's state record (`cdd-state get issue_refs`, process doc §2.13), calls this verb once per reference, and appends each `.token` to the PR body. The rung is announced **once**, before the first of those calls, rather than once per call — N identical lines is noise, and the announcement rule exists to be read. An adapter that does not declare the verb yields no close lines at all, said in one line and never guessed at; and when no reference was recorded, the command never reaches the ladder and emits no close lines either. The state record is the only carrier — there is no branch-name fallback behind it ([ADR 0008](adr/0008-drop-the-issue-ref-branch-token.md)).

**What the token can and cannot promise.** Emitting a close line is not the same as closing the
item, and the contract deliberately does not claim otherwise. Three cases:

- **Tracker and code host are the same backend** (a GitHub PR closing a GitHub issue, a GitLab MR
  closing a GitLab issue). The code host parses its own PR body and closes the item on merge. This
  is the *code host's* feature, not the tracker's, and it is the only case where the token alone can be relied on.
- **Different backends, with an integration** (a GitHub PR closing a Jira issue). Still a string in
  text, but the party acting on it is a tracker-side integration — Jira's DVCS connector or the
  GitHub-for-Jira app — which must be installed and watching the repo. Where it is, a smart commit
  like `PROJ-114 #close` transitions the issue; where it is not, nothing happens.
- **No integration at all.** The line is inert prose.

The verb is the adapter's because only the adapter knows its backend's syntax and whether such a
mechanism exists at all — which is why it is optional, and why an adapter that declares it not
yields no line rather than a guessed one. But a declared token proves the *syntax* exists, never
that anything is listening, and an adapter cannot check the latter offline. So `/cdd-pre-pr` states
which of the three cases applies when it offers to open the PR, rather than letting a line that
does nothing look like one that does.

**The close CDD guarantees is made after the merge, by `issue-transition`.** `cdd-worktree-done`
(the primary path) and `cdd-worktree-gc` (the backstop) close every ref recorded on the task's state
record once the code host confirms the PR merged — automatically, on every backend, GitHub-on-GitHub
included. There it is usually a no-op (`changed: false`), but it also covers a dropped close line
and a PR merged into a non-default branch, where GitHub does not auto-close. So the token is now
the fast path where a backend or integration acts on it, not the only mechanism. When CDD itself
makes the close, it follows it with an `issue-comment` linking the merged PR, so the item still
names the PR that closed it.

## The GitHub reference adapter

Shipped adapters live at `tools/adapters/<capability>/<backend>.sh` — one directory per capability, mirroring the machine rung `~/.cdd/adapters/<capability>` — so a new backend is one new file, which the lint and conformance gates pick up by glob.

`tools/adapters/tracker/github.sh` is the reference implementation, and the conformance gate's subject. A project binds to it with a committed `.cdd/tracker` shim onto the adapter library (see [Installing a binding](#installing-a-binding)). **It never installs itself as a ladder rung**: the machine rung binds every repository on the machine, GitHub or not, so only a project's own committed shim binds it. `cdd-worktree.sh install` does copy it machine-globally — but into the adapter library, which is not a rung and binds nothing on its own. That is the difference from `tools/cdd-worktree.sh` and `tools/cdd-state.sh`, which self-install as sourced shell libraries wired through an rc block, a different shape entirely (see [Shell helpers](shell-helpers.md)).

It **declares all six verbs**. `issue-transition` reverses issue #86's "unsupported on GitHub" verdict: GitHub has no workflow states beyond open/closed, but open/closed is all the verb needs, and the post-merge close calls it on every backend — consistency rather than detecting GitHub-on-GitHub and skipping it. `closed` is `gh issue close`, `open` is `gh issue reopen`; it reads the issue's state first, so an issue already there is `changed: false` and no write. `issue-comment` is `gh issue comment`, whose printed URL becomes `url`. With no shipped adapter now omitting a contract verb, the live exit-3 case is the nonsense verb, and the undeclared-contract-verb path is kept tested by a mutation in `scripts/adapter-conformance-assert.sh`.

Its `ref_pattern` is `^#?[0-9]+$`, which is exactly the shape `/cdd-next-step` hardcoded before the ladder existed. `create_target` is derived from `git remote get-url origin` parsed to `owner/repo` — local, no network — and omitted when it cannot be derived.

Authentication is `gh`'s own, untouched: `gh` absent from `PATH`, or `gh auth status` failing, is exit 4 with an actionable line on stderr. CDD stores, reads and proxies no secret (§2.16).

## The code-host verbs

Seven verbs, of which one (`describe`) is mandatory and the other six are declared per backend. The code host is where PRs and merge state live; its `describe` carries no `ref_pattern` and no `create_target`:

```console
$ .cdd/code-host describe
{"capability":"code-host","contract":1,"backend":"github",
 "verbs":["pr-create","pr-for-branch","pr-comments","pr-reply","pr-merged","default-branch"]}
```

| Verb                                         | Replaces today                                               | Caller today                                   |
| -------------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------- |
| `describe`                                   | —                                                            | mandatory                                      |
| `pr-create --title T --body B [--base B]`    | `/cdd-pre-pr`'s `gh pr create`                               | `/cdd-pre-pr` §11                              |
| `pr-for-branch <branch>`                     | `gh pr list --head B --state all`, `/cdd-process-pr` §1's `gh pr view` | `cdd-worktree-list`, the `cdd-worktree-resume` picker, `/cdd-process-pr` §1 |
| `pr-comments <pr>`                           | `/cdd-process-pr` §2's GraphQL and REST reads                | `/cdd-process-pr` §2–3                         |
| `pr-reply <pr> [--to <thread-id>] --body B`  | `/cdd-process-pr` §6's replies and `gh pr comment`           | `/cdd-process-pr` §6                           |
| `pr-merged <branch> [--base B]`              | `gh pr list --state merged` (done), `state == MERGED` (gc)   | `cdd-worktree-done`, `cdd-worktree-gc`         |
| `default-branch`                             | `git symbolic-ref refs/remotes/origin/HEAD`                  | `cdd-worktree-default-branch`, `/cdd-pre-pr` §0, `/cdd-merge-base` §0 |

Every pinned verb has a caller, so a project on a non-GitHub code host can open and process a PR through CDD via its adapter; with no adapter installed the prompts stop or skip with one line naming `/cdd-retrofit`. `/cdd-process-pr` takes the newest **open** entry of `pr-for-branch`, and when `pr-comments` omits `viewer` it filters nothing on authorship and leaves already-answered threads for its triage checkpoint to drop, rather than asking `gh` who the user is on a system that may not be GitHub.

One `gh` call stays direct on purpose: the "file an issue on the CDD repo" offer in `/cdd-pre-pr` §7 and `/cdd-process-pr` §5 is `gh issue create --repo drabaioli/cdd`, because it always targets CDD upstream on GitHub — routing it through the project's tracker adapter would file a CDD bug in the project's own tracker (its Jira, say).

`state` on a PR is normalized to **`open`, `closed` or `merged`** — three values, not the tracker's two, because merged is the fact CDD branches on — and `state_raw` keeps the backend's own value. A PR's `ref` is the human handle as a string (`"42"` on GitHub).

### `pr-create --title T --body B [--base B]` → object

```json
{"ref":"42","url":"https://…"}
```

Without `--base`, the backend's default branch is the target.

### `pr-for-branch <branch>` → array

```json
[ {"ref":"42","state":"merged","state_raw":"MERGED","url":"https://…","head":"my_branch","base":"main"} ]
```

Every PR whose head is the branch, **newest first**; `[]` when there is none, as with `issue-list`.

### `pr-merged <branch> [--base B]` → object

```json
{"branch":"my_branch","merged":true,"ref":"42","head_sha":"5276df1e…","url":"https://…"}
```

**Whether the branch's most recent PR** (into `--base`, if given) **has merged.** It takes a branch because both of its callers start from one. `ref` and `url` (the PR's page, an additive field) are present only when `merged` is true; `url` is what the post-merge close links on the items it closes, and a caller without it names the PR by `ref` alone. `head_sha` (also additive, so the contract stays `1`) is the PR's head commit as a full SHA: the source branch's tip that the PR merged, not a squash or merge commit. It is what tells this branch's PR from an old merged PR of a **reused branch name**: `cdd-worktree-done` force-deletes an unmerged-looking branch only when `head_sha` contains the local tip (is it, or descends from it — a branch behind its PR), and asks otherwise. An adapter that omits it still conforms and still resolves, but its answer can never confirm a force-delete — `done` then asks instead, and `gc` (which compares only when the branch still exists locally) behaves as without the check. The shipped code-host adapters always report it on a merged answer. This is deliberately conservative — it does not accept *any* merged PR into the base: a branch with an older merged PR and a newer open one reads as not merged, so `done` prompts instead of force-deleting; the head check backs the same rule for the case the branch name alone cannot tell apart.

### `pr-comments <pr>` → object

```json
{"ref":"42","viewer":"octocat",
 "threads":[{"id":"123456","resolved":false,"outdated":false,"path":"a.sh","line":12,
             "comments":[{"id":"123456","author":"rev","created_at":"…Z","body":"…"}]}],
 "reviews":[{"id":"…","author":"rev","state_raw":"CHANGES_REQUESTED","created_at":"…Z","body":"…"}],
 "comments":[{"id":"…","author":"rev","created_at":"…Z","body":"…"}]}
```

Everything `/cdd-process-pr` reads today, in one call. `threads` are inline review threads with their resolution state; a thread's `id` is the reply target for `pr-reply --to`, and `line` is omitted when the backend reports none (an outdated thread). `reviews` holds only reviews with a non-empty body. `comments` are top-level PR comments. `viewer` is the authenticated account, so "skip a thread whose latest comment is mine" works on any backend; it is omitted when it cannot be derived.

### `pr-reply <pr> [--to <thread-id>] --body B` → object

```json
{"ref":"42","url":"https://…"}
```

With `--to`, a reply in that review thread; without, a top-level PR comment. `url` is the new comment's.

### `default-branch` → object

```json
{"branch":"main"}
```

A bare branch name, never `origin/main`.

## The GitHub code-host adapter

`tools/adapters/code-host/github.sh` is the reference implementation and the code-host conformance subject. It follows the tracker adapter line for line — dispatch before any backend work, `gh`'s own authentication (absent or unauthenticated is exit 4), no JSON dependency beyond `gh --jq`, and **never a ladder rung**, for the same reason: the built-in rung already is GitHub. A project binds to it with a committed `.cdd/code-host` shim onto the adapter library.

This repo binds both GitHub adapters to itself by committing `.cdd/code-host` and `.cdd/tracker` as relative symlinks into `tools/adapters/` — dogfooding, and a symlink cannot drift from its target. A downstream project has no `tools/adapters/` of its own, so it binds by a shim onto the machine-global adapter library ([Installing a binding](#installing-a-binding)).

It declares all six verbs. `describe` is a constant — it does not even need git. `pr-for-branch` and `pr-merged` (asked for the PR's `url` too, and `headRefOid` as `head_sha` — the branch head at merge time, not the squash commit) are `gh pr list --head <branch> --state all`, whose order is newest first. `pr-comments` is one GraphQL call (`reviewThreads`, `reviews`, `comments`, and `viewer`), with each thread's `id` taken from its first comment's REST id — the id GitHub's reply endpoint takes. `pr-reply --to` posts to that endpoint; without `--to` it is `gh pr comment`. `default-branch` reads the local `origin/HEAD` first, so on a normal clone it answers offline, and asks `gh repo view` only when `origin/HEAD` is unset — where the helpers' git fallback would guess `main`.

## The Jira adapter

`tools/adapters/tracker/jira.sh` answers the same contract against **Jira Cloud** through its REST API v3, with `curl` and `jq` — no Jira CLI. Data Center / Server (personal access tokens, API v2) is out of scope. Like the GitHub adapter it **is never a ladder rung**, for a different reason: a Jira binding is per-project by nature (a site and a project key), so a machine rung has nothing sensible to point at. A project binds it through a `.cdd/tracker` shim onto the adapter library, which exports the non-secret coordinates (the generated form, abridged — see [Installing a binding](#installing-a-binding)):

```bash
#!/usr/bin/env bash
export JIRA_BASE_URL='https://<site>.atlassian.net' JIRA_PROJECT_KEY='ABC'
exec "$HOME/.cdd/tools/adapters/tracker/jira.sh" "$@"
```

**Configuration is environment variables only** — no config file, nothing read from disk:

| Variable                | Needed by                                              | Meaning |
| ----------------------- | ------------------------------------------------------ | ------- |
| `JIRA_BASE_URL`         | every verb but `describe` / `issue-close-token`        | The site, `https://<site>.atlassian.net`; a bare host gets `https://` added |
| `JIRA_EMAIL`            | same                                                   | The Atlassian account the token belongs to |
| `JIRA_API_TOKEN`        | same                                                   | An Atlassian API token. Lives in the user's shell; never in `.cdd/tracker` or any file |
| `JIRA_PROJECT_KEY`      | `issue-list`, `issue-create`                           | The project, e.g. `ABC` |
| `JIRA_ISSUE_TYPE`       | `issue-create`, optional                               | Default: `Task` if the project has it, else its first standard type (one extra read) |
| `JIRA_CREATE_FIELDS`    | `issue-create`, optional                               | A JSON object of extra fields, for a project that requires custom fields (`{"customfield_10042":{"value":"Backend"}}`). It cannot override project, type, title or body; malformed is exit 4 |
| `JIRA_CLOSE_TRANSITION` | `issue-close-token`, optional                          | Default `done` |

A missing variable is exit 4 with one stderr line per variable, naming it — after argument validation, so a usage error is still 2 on an unconfigured machine. The token reaches `curl` through `--config -` on stdin, never on the command line (where `ps` would show it), and is never written to a file. Rejected credentials are exit 1 ("auth rejected", per the exit-code table) and said as such — including the case Jira Cloud does not answer with a 401: a bad token is served anonymously and gets a 404, with the failed login flagged only in the `X-Seraph-LoginReason` response header, which the adapter checks first. A 404 and every other non-2xx are exit 1 with Jira's own error messages on stderr — a project's required custom fields, for instance, surface here by name.

It **declares all six verbs**. Its `ref_pattern` is `^[A-Z][A-Z0-9_]+-[0-9]+$` — a Jira key, which never overlaps GitHub's `^#?[0-9]+$`. `describe` needs neither network nor `jq`; `create_target` is `<JIRA_PROJECT_KEY> @ <site host>` when both variables are set, and omitted otherwise.

- **State.** `closed` is the status *category* `done`; `open` is anything else. `state_raw` is the status name (`In Review`). `issue-list` is the project's items whose category is not Done, one page of up to 100 (the GitHub adapter's cap), through `/rest/api/3/search/jql` — the older `/search` endpoint has been removed from Jira Cloud. Search reads Jira's index, which trails a write by a second or two, so an item transitioned a moment ago can still appear; `issue-read` is always current.
- **`issue-transition`.** Workflows are per project, so it asks Jira which transitions are available from the current status and takes the first that lands in the target category — for `open`, preferring a To Do-category status. Already there is a no-op, exit 0 with `changed: false`; a transition made is `changed: true`. No fitting transition is exit 1, listing the transitions that do exist. A transition that needs a screen field fails with Jira's 400 message, also exit 1.
- **`issue-comment`** posts to `/rest/api/3/issue/<key>/comment`; `id` is the comment's numeric id and `url` the issue page focused on it (`…/browse/<key>?focusedCommentId=<id>`).
- **`issue-close-token`** yields a smart commit, `ABC-123 #done`; `JIRA_CLOSE_TRANSITION` overrides the transition name, lowercased with spaces hyphenated as smart commits expect (`Close Issue` → `#close-issue`). It acts only where Jira is connected to the code host with smart commits enabled — the second of the three cases above.
- **Bodies.** Jira v3 speaks Atlassian Document Format. `issue-read` flattens it to plain text (paragraphs, line breaks, lists, mentions, code; marks and layout dropped) for the body and every comment; `issue-create` and `issue-comment` wrap plain text as ADF paragraphs, so Markdown shows literally, but a bare `http(s)` URL becomes a link. Comment timestamps are converted to ISO-8601 UTC. `id` is Jira's numeric id and is emitted on both `issue-read` and `issue-create`, since Jira reports it on a create; `assignee` is the display name, omitted when unassigned.

## The GitLab adapters

`tools/adapters/tracker/gitlab.sh` (issues) and `tools/adapters/code-host/gitlab.sh` (merge requests) answer the two contracts against **GitLab's REST API v4**, with `curl` and `jq` — no `glab`. Both work against gitlab.com and a self-managed instance. They follow the Jira adapter's posture — env-configured, never a ladder rung, a binding being per-project by nature — and share one configuration vocabulary, so a project may bind either, both, or GitLab for one capability and another backend for the other. Each is a single standalone file, so the small config and HTTP helpers are duplicated between them on purpose: the library installs, and the shim's hint `curl`-fetches, one file per adapter. A project binds them through shims onto the adapter library, each exporting the same non-secret coordinates (abridged — see [Installing a binding](#installing-a-binding)):

```bash
#!/usr/bin/env bash
export GITLAB_URL='https://gitlab.com' GITLAB_PROJECT='group/project'
exec "$HOME/.cdd/tools/adapters/code-host/gitlab.sh" "$@"
```

| Variable         | Needed by                                                  | Meaning |
| ---------------- | ---------------------------------------------------------- | ------- |
| `GITLAB_URL`     | optional                                                   | The instance, default `https://gitlab.com`. A self-managed host, with its sub-path root if it has one (`https://example.com/gitlab`); a bare host gets `https://` added |
| `GITLAB_PROJECT` | every verb but `describe` / `issue-close-token` (and `default-branch` while `origin/HEAD` is set) | The project's path, `group/project` or `group/sub/project`. The path form, not a numeric id: it is also what builds `create_target` and comment URLs |
| `GITLAB_TOKEN`   | same                                                       | A personal, project or group access token with the `api` scope. Lives in the user's shell; never in a shim or any file |

The project is named explicitly rather than derived from `origin` inside the adapter: an SSH remote's host and port are not the API's, and `describe` must depend on the binding alone. `/cdd-retrofit` derives the coordinates from `origin` once, as a proposal for the user to confirm.

A missing variable is exit 4 with one stderr line per variable, after argument validation; a malformed `GITLAB_PROJECT` is exit 4 too. The token reaches `curl` as a `PRIVATE-TOKEN` header through `--config -` on stdin — never on the command line, never in a file. A 401 is exit 1, "GitLab rejected the token"; a 403 is exit 1 naming the `api` scope and the role; a 404 is exit 1, "no such item or project, or no access"; every other non-2xx is exit 1 with GitLab's own message. Every list is one page of 100, the other adapters' cap. Timestamps arrive with milliseconds and are trimmed to ISO-8601 UTC.

**The tracker.** Its `ref_pattern` is `^#?[0-9]+$` — GitLab's own `#42`, the same shape as GitHub's, which is harmless since only one tracker resolves per project. `create_target` is `<GITLAB_PROJECT> @ <instance host>` when `GITLAB_PROJECT` is set, omitted otherwise.

- **Ids.** `ref` is the issue's project-scoped number (its `iid`); `id` is GitLab's global id, which differs, so it is emitted on `issue-read` and on `issue-create` (GitLab reports it there).
- **State.** `opened` is `open`, `closed` is `closed`; `state_raw` is GitLab's value. There is no workflow: `issue-transition` is a `close` or `reopen` state event, read first so an issue already there is `changed: false` and no write.
- **`issue-read`** carries the issue's notes as `comments`, oldest first, system notes ("changed the label") dropped; `assignee` is the first assignee's username, omitted when none.
- **`issue-comment`** posts a note; `url` is the issue's own `web_url` anchored on it (`#note_<id>`) — read from GitLab rather than built, since gitlab.com now serves issues under `/-/work_items/<n>`.
- **`issue-close-token`** yields `Closes #42`. It acts only when the MR carrying it merges into the project's **default** branch, and only while the project's "Auto-close referenced issues on default branch" setting is on (the default) — the first of the three cases above, with that caveat.

**The code host.** A PR is a merge request; its `ref` is the MR's `iid` as a string, accepted as `42`, `#42` or GitLab's own `!42`.

- **State.** `opened` and `locked` (an MR mid-merge) are `open`; `closed` and `merged` are themselves.
- **`pr-create`** opens an MR from the current branch, which must already be pushed; without `--base` the target is the project's default branch, asked of GitLab. An existing open MR for the branch is GitLab's own refusal, exit 1.
- **`pr-for-branch` / `pr-merged`** list the branch's MRs (into `--base`, if given) newest first. `pr-merged`'s `head_sha` is the MR's `sha`, its source branch's head commit — not `merge_commit_sha` or `squash_commit_sha`.
- **`pr-comments`** reads the MR's discussions. A threaded discussion is a thread: its `id` is the **discussion id** — the reply target `pr-reply --to` takes — `resolved` is GitLab's flag, and an inline one carries the `path` and `line` of its position (both omitted for a general thread on the overview). A standalone note is a top-level comment; system notes ("added 1 commit") are dropped. `viewer` is the token's user (`/user`), omitted if GitLab does not say. **`outdated` and `reviews` are omitted**: GitLab has no "this hunk no longer applies" flag (a note on an older revision is a different fact), and no review object carrying a body — an approval has none, and a submitted review's summary is an ordinary note, already in `comments`.
- **`pr-reply`** posts a note in the discussion (with `--to`) or on the MR; `url` is the MR page anchored on it.
- **`default-branch`** reads the local `origin/HEAD` first, as the GitHub adapter does, and asks GitLab only when it is unset.

## Installing a binding

The installers bind a project to the shipped adapters ([ADR 0011](adr/0011-bind-adapters-through-a-machine-global-library.md)). Two layers:

- **The adapter code is machine-global.** `cdd-worktree.sh install`, run from a CDD checkout, copies every `tools/adapters/<capability>/<backend>.sh` to the **adapter library**, `~/.cdd/tools/adapters/<capability>/<backend>.sh` — newest wins, like the helpers themselves. The library is **not a ladder rung**: the machine rung is `~/.cdd/adapters/<capability>`, and nothing in the library is consulted unless a project's binding points at it, so installing it leaves every unbound project with no adapter.
- **The binding is per-project and committed.** `.cdd/<capability>` is a small shim that names the backend and, for Jira, the site and project key; for GitLab, the instance and project path. It reaches the library through `$HOME`, never through a path to one machine's CDD checkout, so a fresh clone on another machine works once the helpers are installed there. It holds no secret (§2.16).

`tools/bootstrap-cdd-project.sh` writes the shims, from opt-in flags: `--tracker <backend>`, `--code-host <backend>`, `--jira-site <host>` / `--jira-key <KEY>` with `--tracker jira`, and `--gitlab-project <path>` / `--gitlab-url <url>` (optional, default gitlab.com) with either capability bound to `gitlab`. A backend with no shipped adapter is refused (exit 2) rather than written as a binding that cannot work. The flags work under `--stage` too. The prompts decide *which* backends; the script is the only writer:

- **`/cdd-bootstrap`** asks where issues and code review live, offering GitHub as the default, and asks only for the site and key for Jira, and the instance and project path for GitLab.
- **`/cdd-retrofit`** detects them from the target (the origin host — `github` or `gitlab` in it, with GitLab's coordinates derived from the remote — and Jira-key-shaped branch names or commit subjects), proposes each with its evidence under per-file approval, and never overwrites an existing `.cdd/<capability>`. In upgrade mode it also classifies a local prompt edit that swaps in another backend as **migrate into `.cdd/`**.

A backend CDD ships no adapter for (Bitbucket, say) gets no binding, said in one line, with the issue and PR features skipping until one is bound; a project adapter written against this contract can be bound by hand.

The shim checks that its library file is executable and `exec`s it; the script's `write_binding` is the one source of its text.

**A missing library is a broken adapter, not an absent one.** The shim exists, so the ladder has resolved to it; its `describe` exits 4 with the install command, and the resolver relays that first stderr line in its one "is unusable" line. Every call site then stops (or shows no data, for a listing) — never a silent fall-through to `gh`. A machine whose helper install predates the library needs one re-run of `cdd-worktree.sh install`.

**The announcement line appears.** A bound project is served by an adapter, so the helpers print their one "using adapter" line (below).

The conformance checker is not run against a downstream shim: it probes with an empty `HOME`, where no library exists. The `adapter-bindings` gate covers the shims instead, from a fresh clone on a second scratch `HOME`, through both a direct `describe` and the helpers' resolver.

## Docs: not a capability

There is no `.cdd/docs`. An adapter is justified only when a CDD script or structured workflow step consumes its output, and a docs lookup is read only by Claude, as prose (`adr/0009-drop-the-docs-capability.md`). A project whose reference docs live in an external store — Confluence, Notion, a wiki — serves them this way instead:

1. **The store's MCP server** goes in the project's `.mcp.json`. Authentication is that server's own; CDD holds no credential for it.
2. **One `CLAUDE.md` paragraph** says what lives in the store and when to look: the task links a page, or the work codes against one of the integrations the store documents.
3. **A subagent reads the page** and returns only the relevant section, so a long page never lands whole in the session's context.
4. **What was used is recorded** under the plan's `## External findings`, with the page link and its version.
5. **Page content is never copied** into the repo's docs. The repo stays the source of its own docs (replace-vs-mirror).

## Resolution, the broken-adapter rule, and the announcement rule

Resolution is the ladder from §2.16 — project `.cdd/<capability>`, then machine `~/.cdd/adapters/<capability>`, then nothing ([ADR 0012](adr/0012-drop-the-builtin-gh-rung.md)) — and the **first file present** wins. What happens next is one of four cases, for every capability ([ADR 0010](adr/0010-code-host-rename-and-broken-adapter-rule.md)):

- **Missing** — no file at the rung: the next rung.
- **Nothing installed** — no file at any rung: the feature is skipped with one line naming `/cdd-retrofit`, except where the feature is the whole point of the invocation (issue-driven `/cdd-next-step`, `/cdd-process-pr`), which stops with the same line. No caller falls back to `gh`. Prompts print `No <capability> adapter is installed; run /cdd-retrofit in this project to install one.`; the helpers print `<capability>: no adapter installed; run /cdd-retrofit in this project to install one`, then what was skipped.
- **Installed but broken** — the file is not executable; `describe` exits non-zero, does not parse as JSON, reports another `capability`, or a `contract` outside N / N-1; or `jq` is absent, so the caller cannot read `describe`: **one line naming the adapter and why, and no lower rung.** When `describe` exits non-zero, the "why" carries the first line it printed on stderr, so an adapter's own diagnosis (a binding's "adapter library missing … install with …") reaches the user. A broken project adapter does not fall to a working machine one, and neither falls to `gh`. An installed adapter declares the backend, so any lower rung would answer from the wrong system.
- **Verb unsupported** — absent from `describe.verbs`, or exit 3: not an error. The caller skips the feature, exactly as when the backend has no answer.

Once an adapter serves, a call that **fails** (exit 1, 4, anything but 0 or 3) is reported in one line and treated as "no answer" — never retried against a lower rung.

How far "no lower rung" reaches is set per call site, by what the caller would do with a wrong answer:

| Call site                                          | Broken adapter                                               |
| -------------------------------------------------- | ------------------------------------------------------------ |
| `/cdd-next-step` (tracker)                         | stops the command                                            |
| `/cdd-pre-pr` §0, `/cdd-merge-base` §0 (code host) | stops the command — only reached when no base was recorded   |
| `cdd-worktree` (code host)                         | stops before cutting the branch — only when no base was recorded |
| `cdd-worktree-done`, `-gc`, `-resume` (code host)  | stops before doing anything                                  |
| `cdd-worktree-done` (tracker)                      | stops before doing anything — only when the task recorded issue refs |
| `cdd-worktree-gc` (tracker)                        | keeps the tasks with issue refs; reaps the rest              |
| `cdd-worktree-list` (code host)                    | prints the line and shows `-` for every PR                   |
| `/cdd-pre-pr` §11 (code host)                      | does not open the PR; the checklist still stands             |
| `/cdd-process-pr` (code host)                      | stops the command                                            |

The helpers' side is detailed in [Shell helpers](shell-helpers.md#code-host-resolution).

Announcing which rung served is scoped **to the point of use, not to the session**:

- Resolution performed merely to **classify** something — deciding whether `$ARGUMENTS` looks like an issue reference, say — is **silent**. Taken literally, "say when no adapter is installed" would print a line in every session in every repo, since no project has an adapter; that is noise, and noise is how a load-bearing line stops being read.
- When a prompt **actually makes a call**, it announces in one line which rung served it — or, with nothing installed, the one missing-adapter line above.
- **The shell helpers say what they skip.** `cdd-worktree-done`, `-gc`, `-list` and `-resume` print the missing-adapter line once when a code-host (or, for the issue close, tracker) adapter is needed and absent, because with the built-in rung gone a silent skip would be indistinguishable from "nothing to do". `done` then falls to its keep/delete/abort prompt and keeps the task record for `gc`; `gc` reaps nothing; `list` and `resume` show no PR column.
- **The broken-adapter line is unconditional**, even during silent classification. The user installed something that is not working, and silence there is indistinguishable from it working.

## The conformance gate

`scripts/adapter-conformance-check.sh` (the `adapter-conformance` gate, `needs: jq`) checks an adapter against this document, for either capability. It defaults to `tools/adapters/tracker/github.sh` and takes an optional path, so a project can point it at its own `.cdd/tracker` or `.cdd/code-host`, and an optional capability; without one, the capability comes from the path (`tools/adapters/<capability>/…`, `.cdd/<capability>`, `~/.cdd/adapters/<capability>`), and failing that from `describe` itself. `scripts/ci.sh` runs it over every `tools/adapters/*/*.sh`, so all five shipped adapters are checked and a new one is covered without editing the runner.

It is **offline by construction**, and backend-neutral: every probe runs with the environment scrubbed (`env -i`, so a credential or coordinate the caller happens to have exported never reaches the subject), under either a scratch `PATH` holding stub backend tools — a `gh` that is authenticated and useless, a `curl` that always fails as if the host were unreachable — or a minimal `PATH` with no backend tooling at all. Nothing it runs can reach the network or authenticate. No probe mode, no dry-run flag — an adapter is checked exactly as a caller would invoke it. What it asserts:

1. `describe` exits 0 with backend tooling absent from `PATH` and the environment scrubbed, and its stdout parses as JSON (hermeticity).
2. `describe` is contract-shaped: `capability` is the one being checked; `contract` is an integer ≥ 1; `backend` is a non-empty string; for a tracker, `ref_pattern` is a non-empty string that `grep -E` accepts as a valid ERE; `verbs` is a non-empty array of strings; `describe` is **not** among them; every declared verb is one of that capability's non-`describe` verbs; and no `null` appears anywhere in the output.
3. Every verb in `describe.verbs`, invoked with **no arguments**, exits something other than 3 — i.e. dispatch reaches a real implementation rather than the unsupported-verb branch.
4. Every contract verb the adapter does not declare exits 3, and so does a nonsense verb. The shipped adapters each declare every verb of their contract, so on them the nonsense verb is the live case; a mutation in `scripts/adapter-conformance-assert.sh` keeps the undeclared-verb path tested.
5. A verb called without its required argument exits 2 — `issue-read` for a tracker, `pr-merged` for a code host.
6. A verb that needs the backend, called with backend tooling absent and the environment scrubbed, exits 4 with a line on stderr — `issue-list` for a tracker, `pr-for-branch <branch>` for a code host; missing tooling for a `gh`-based adapter, missing configuration for an env-configured one.
7. Neither the adapter nor `.cdd/*` (when present) contains anything secret-shaped — a GitHub token prefix, an Atlassian API token prefix, a GitLab token prefix, a hardcoded basic-auth header, a PEM private-key header, or an assignment of a password / secret / token / api-key to a literal. This is §2.16's "never stores a secret" made mechanical, and it is the same class of check as `scripts/prompt-seam-check.sh`.

**Its stated limit:** check 3 proves that dispatch *reaches* an implementation, not that the implementation is *correct*. Correctness needs a live call against a real backend, which the offline-only decision rules out on purpose — a gate that SKIPs on most hosts is a gate whose verdict nobody can rely on. Checks 1, 2 and 4–7 are exact; check 3 is a floor.

Check 3 is only meaningful because of the dispatch-order rule above: an adapter that authenticated before parsing its arguments would exit 4 here for reasons that say nothing about dispatch. Such an adapter is non-conformant by construction, which is why the rule is stated as a rule and not as a hint.

**The shipped code-host adapters' answers.** The same gate also runs `scripts/adapter-answers-assert.sh`, which narrows check 3's limit for the one answer a helper force-deletes on: each shipped code-host adapter's `pr-merged` runs over a stub `gh` or `curl` returning a canned backend response, offline and with the environment scrubbed, and must report `merged`, `ref`, `url` and `head_sha` when merged and none of them otherwise. It is a separate script rather than a check in the checker because it needs each backend's wire format, and the checker stays backend-neutral so a project can point it at its own adapter.
