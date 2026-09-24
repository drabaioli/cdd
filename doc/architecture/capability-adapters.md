# Capability adapters: the tracker and docs contracts

The wire contract every capability adapter answers, pinned for two capabilities: the **tracker** — reference implementation `tools/adapters/tracker/github.sh`, alongside a Jira Cloud adapter (`tools/adapters/tracker/jira.sh`) — and **docs**, read-only, whose reference implementation is the Confluence Cloud adapter `tools/adapters/docs/confluence.sh`.

The *why* lives elsewhere and is not restated here: the process doc's §2.16 states the workflow-level rules (the fixed `.cdd/` namespace, the mandatory `describe` verb, the resolution ladder, the replace-vs-mirror rule, and that CDD never stores or proxies a secret), and `adr/0007-extend-cdd-through-capability-adapters.md` records the decision and its alternatives. This document is the layer below both: the verbs, the JSON each returns, the exit codes, and the two invariants a conformance gate can be written against. An adapter author needs this document and nothing else.

Nothing here ships to downstream projects. The CDD repo is the canonical reference for adapter authors, exactly as it is for the process doc, and the template ships no copy of either.

## What an adapter is

An executable — any language — at a fixed path, invoked as `<adapter> <verb> [args...]`. It is not a library, not a config file, and not a service. CDD discovers it by testing that the path exists and is executable, and learns what it can do by running `describe`.

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
 "verbs":["issue-read","issue-list","issue-create","issue-close-token"],
 "create_target":"drabaioli/cdd"}
```

| Field           | Required | Meaning                                                                        |
| --------------- | -------- | ------------------------------------------------------------------------------ |
| `capability`    | yes      | The role this adapter fills — `tracker` or `docs`. Matches the file name under `.cdd/`. |
| `contract`      | yes      | Integer contract version; see below.                                            |
| `backend`       | yes      | Non-empty string naming the service (`github`, `jira`, …). Free-form; nothing branches on it. |
| `ref_pattern`   | yes      | An **ERE** that matches a reference this backend accepts. CDD dispatches on it instead of hardcoding a shape. |
| `verbs`         | yes      | Non-empty array of the verbs this adapter implements, **excluding `describe`**. |
| `create_target` | no       | Tracker. Human-readable coordinates a created item would land in (`owner/repo`, `XYZ / board 42`). Shown to a human before a write; nothing parses it. Omitted when it cannot be derived locally. |
| `link_pattern`  | no       | Docs. An unanchored **ERE** that finds a reference *inside prose* — a handoff, a review comment. See [Two reference patterns](#two-reference-patterns). Omitted when the backend has no unambiguous form. |
| `search_scope`  | no       | Docs. Human-readable coordinates `doc-search` is restricted to (`TT @ <site>`); nothing parses it. Omitted when the search is unrestricted or the coordinates cannot be derived locally. |

**`describe` excludes itself from `verbs`.** It is mandatory for every adapter, so listing it is redundant, and the conformance gate checks it separately. Issue #86's Jira example must not be read the other way.

**Versioning: `describe.contract` is an integer, and CDD supports N and N-1.** An adapter declaring an older-than-N-1 or newer-than-N version is ignored with a line saying so, not an error. **No `describe`, or an unparseable one, means "not an adapter"** — also ignored, also announced. The current contract version is **1**.

`ref_pattern` is what makes the ladder work in the direction issue #86 requires: a prompt must **not** learn to recognize `XYZ-123`. It resolves the adapter, reads `ref_pattern`, and lets the adapter decide what a valid reference looks like. The built-in (no-adapter) tracker behaves as though `ref_pattern` were `^#?[0-9]+$`.

## The tracker verbs

Six verbs, of which one (`describe`) is mandatory and the other five are declared per backend.

| Verb                                | Replaces today                              | Notes                          |
| ----------------------------------- | ------------------------------------------- | ------------------------------ |
| `describe`                          | —                                           | mandatory                      |
| `issue-read <ref>`                  | `gh issue view` (`/cdd-next-step` §0b)      | comments inline                |
| `issue-list`                        | `gh issue list` (`/cdd-next-step` §0b)      | open items only                |
| `issue-create --title T --body B`   | `/cdd-pre-pr`'s improvement channel         |                                |
| `issue-transition <ref> <state>`    | —                                           | unsupported on GitHub          |
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
{"ref":"XYZ-123","state":"closed","state_raw":"Done"}
```

`<state>` is a normalized `open`/`closed`; the adapter maps it onto whatever the backend calls that. Backends without a workflow model do not declare this verb.

### `issue-close-token <ref>` → object

```json
{"ref":"42","token":"Closes #42"}
```

The string a commit message or PR description carries so the backend auto-closes the item on merge. GitHub yields `Closes #42`; Jira yields a smart commit. A backend with no such mechanism does not declare the verb, and the caller simply writes no token.

Its consumer is `/cdd-pre-pr` §11, when it opens the PR: it reads the references recorded on the task's state record (`cdd-state get issue_refs`, process doc §2.13), calls this verb once per reference, and appends each `.token` to the PR body. The rung is announced **once**, before the first of those calls, rather than once per call — N identical lines is noise, and the announcement rule exists to be read. An adapter that does not declare the verb yields no close lines at all, said in one line and never guessed at; and when no reference was recorded, the command never reaches the ladder and emits no close lines either. The state record is the only carrier — there is no branch-name fallback behind it ([ADR 0008](adr/0008-drop-the-issue-ref-branch-token.md)).

**What the token can and cannot promise.** Emitting a close line is not the same as closing the
item, and the contract deliberately does not claim otherwise. Three cases:

- **Tracker and forge are the same backend** (a GitHub PR closing a GitHub issue, a GitLab MR
  closing a GitLab issue). The forge parses its own PR body and closes the item on merge. This is
  the *forge's* feature, not the tracker's, and it is the only case CDD can rely on.
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

**A close that is guaranteed across backends needs `issue-transition` called after the merge**, by
an actor CDD does not have today: `/cdd-pre-pr` runs pre-merge, and `cdd-worktree-gc` — the only
thing that runs post-merge — is local maintenance whose merge check is hardcoded to `gh`. The
natural home is gc once the forge capability puts `pr-merged` behind an adapter, opt-in and
reporting each transition, which is where the roadmap sequences it. Until then, cross-backend
closing is the tracker integration's job and CDD's contribution is emitting the token it reads.

## The docs verbs

Four verbs, **all read-only**: `describe`, mandatory, and three declared per backend. There is no write verb. The docs capability sits on the *mirror* side of §2.16's replace-vs-mirror rule: a session reads a page for context the repo does not hold — an integration contract, a platform spec — and the repo stays the source for its own docs. Publishing repo docs to a backend is out of scope, and a sync verb was considered and dropped.

| Verb                                                    | Returns | Notes                          |
| ------------------------------------------------------- | ------- | ------------------------------ |
| `describe`                                              | object  | mandatory                      |
| `doc-search <query> [--limit N]`                        | array   | excerpts, never page bodies    |
| `doc-read <ref> [--section <heading>] [--max-chars N]`  | object  | capped; says when it truncated |
| `doc-stat <ref>`                                        | object  | version and freshness only     |

```console
$ .cdd/docs describe
{"capability":"docs","contract":1,"backend":"confluence",
 "ref_pattern":"^([0-9]+|https?://…/wiki/…pages/[0-9]+…|https?://…/wiki/…[?&]pageId=[0-9]+…)$",
 "link_pattern":"https?://example[.]atlassian[.]net/wiki/[^[:space:])>\"]*(pages/[0-9]+|pageId=[0-9]+)[^[:space:])>\"]*",
 "verbs":["doc-search","doc-read","doc-stat"],
 "search_scope":"TT @ example.atlassian.net"}
```

### Two reference patterns

A docs adapter reports two patterns, because it has two different questions to answer.

- **`ref_pattern`** (required, anchored) — what `doc-read` and `doc-stat` accept, exactly as for the tracker. For Confluence: a numeric page id, or a page URL.
- **`link_pattern`** (optional, unanchored) — how a session spots a page reference *in prose*, which is what fires the first trigger below. It must match only unambiguous forms. A bare page id is a valid `ref_pattern` match but must never be a `link_pattern` match: a bare number is exactly the built-in tracker's `^#?[0-9]+$`, so a pattern that fired on it would treat every issue number in a handoff as a page. For Confluence it matches page URLs only, narrowed to the configured site when one is set. With no `link_pattern`, the first trigger simply never fires.

### Context-cost caps

A tracker item is small; a page can be arbitrarily large, and a session's context is the budget it comes out of. So the docs verbs are capped, and the caps are part of the contract, not a backend's choice:

| What                          | Default     | Maximum                        | Outside the bounds |
| ----------------------------- | ----------- | ------------------------------ | ------------------ |
| `doc-search` results          | 10          | 25, via `--limit`              | exit 2             |
| `doc-search` excerpt          | 300 chars   | —                              | cut, ending in `…` |
| `doc-read` content            | 24,000 chars | 100,000, via `--max-chars`    | exit 2             |
| `doc-read` `sections` entries | 100         | —                              | the rest omitted   |

"Characters" are Unicode code points. Excerpts are whitespace-collapsed, with the backend's highlight markup removed and HTML entities decoded.

**The truncation signal.** `doc-read` content beyond the cap is **cut, not summarized**, and nothing is appended inside `content` — the flag is the signal. `truncated` is **always present**, `true` or `false` (it is not an optional field: the concept always exists). `content_chars` is the length of the full content, or of the full section, before the cut. `sections` lists every heading of the page, so a caller that hit the cap can re-ask for just the part it needs. A truncated read also prints one line on stderr saying how to narrow it.

### `doc-search <query> [--limit N]` → array

```json
[ {"ref":"2808119297","title":"…","url":"https://…","excerpt":"…",
   "updated_at":"2026-06-02T09:14:03Z","space":"Team Tech"} ]
```

Pages only. `ref` is what `doc-read` accepts; `space` is the container's display name, omitted when the backend does not report one. Empty is `[]`, not an error. A missing query is exit 2.

### `doc-read <ref> [--section <heading>] [--max-chars N]` → object

```json
{ "ref":"2808119297", "title":"…", "url":"https://…",
  "version":17, "updated_at":"2026-06-02T09:14:03Z",
  "format":"markdown", "content":"## CCA3\n\n8. …",
  "truncated":false, "content_chars":412,
  "sections":["System Minimum Requirements","Pre-requisites","…"],
  "section":"CCA3" }
```

- **`format`** names the representation of `content`: `markdown` (a subset — headings, lists, fenced code, links; see the backend's section) or `text`. A caller reads it rather than assuming.
- **A section** runs from the heading that matches the request up to, not including, the next heading of the **same or a higher** level — so an `h3` stops at the next `h3` or `h2`, and an `h2` runs past its `h3`s. Matching is on a normalized form — lowercase, every non-alphanumeric character dropped — so `Installation procedure steps`, `installation-procedure-steps` and a URL fragment `#Installation-procedure-steps` are the same heading; the first match wins. The request comes from `--section`, else from the ref's URL fragment, else the whole page is read. A heading that is not there is **exit 1**, with the page's headings listed on stderr. `section` echoes the matched heading and is present only when a section was read.
- `version` is the backend's page version; `updated_at` is when that version was made.

### `doc-stat <ref>` → object

```json
{"ref":"2808119297","title":"…","url":"https://…","version":17,"updated_at":"2026-06-02T09:14:03Z"}
```

No body is fetched. It is the cheap way to ask "has this page changed since the version I recorded?".

### When a session calls the docs adapter

Six commands can read through a docs adapter — `/cdd-next-step`, `/cdd-plan`, `/cdd-implement`, `/cdd-small-change`, `/cdd-pre-pr` and `/cdd-process-pr` — and the cost of that to a project with no docs store has to be zero. So each command's existing opening shell block carries one extra line, which prints only when an adapter resolves (project `.cdd/docs`, then machine `~/.cdd/adapters/docs`; there is no built-in rung) and never fails the block:

```bash
for c in .cdd/docs ~/.cdd/adapters/docs; do [ -x "$c" ] && { echo "docs adapter: $c"; break; }; done; true
```

It printed nothing → the session makes no call and prints no line. An installed adapter is **still not called by default**; it is called only on a trigger, strongest first:

1. A page reference — text matching `describe.link_pattern` — in the handoff, the issue, a review comment or the user's message.
2. A line in the project's `CLAUDE.md` saying what lives in the docs store ("platform integration specs live in Confluence space TT"), matching the task.
3. The task depends on an external system the repo does not document.

No trigger, no lookup. When one fires, `describe` is run first and accepted on the tracker's terms (exit 0, parses, a supported `contract`; otherwise one line and carry on without it), the adapter that served is announced **once**, `doc-search` then `doc-read --section` is preferred to whole pages, and `truncated` is checked. What a session reads stays in its own artifacts — a handoff's notes, a plan's external findings — and is never copied into the repo's docs.

`/cdd-merge-base` is deliberately not wired: it reconciles two versions of the repo's own code and has no use for outside context.

The second trigger depends on a line a project writes, so the commands that set a project up ask for it: `/cdd-bootstrap` during discovery, `/cdd-retrofit` on install — and on upgrade when the baseline predates the docs capability — each ask whether the project refers to an external docs store and what lives there, and record the answer as one line in `CLAUDE.md` (the template ships it as an optional fill-in). Binding the adapter itself (`.cdd/docs`) is offered with confirmation, never done silently; detecting and installing adapters generally is a later roadmap item.

## The GitHub reference adapter

Shipped adapters live at `tools/adapters/<capability>/<backend>.sh` — one directory per capability, mirroring the machine rung `~/.cdd/adapters/<capability>` — so a new backend is one new file, which the lint and conformance gates pick up by glob.

`tools/adapters/tracker/github.sh` is the reference implementation, and the conformance gate's subject. A project binds to it by making `.cdd/tracker` an executable that `exec`s it. **It does not self-install**: the built-in rung of the ladder already *is* GitHub, so installing it machine-globally would change no behaviour while destroying the "no adapter installed" baseline that behaviour-neutrality is checked against. This is the one way it differs from `tools/cdd-worktree.sh` and `tools/cdd-state.sh`, which do self-install — and they are sourced shell libraries wired through an rc block, a different shape entirely (see [Shell helpers](shell-helpers.md)).

It **declares four verbs**: `issue-read`, `issue-list`, `issue-create`, `issue-close-token`. It **does not declare `issue-transition`** — issue #86 settles that verb as "unsupported on GitHub" — so calling it exits 3. That is the contract's only live exit-3 case on a shipped adapter, and the conformance gate asserts it.

Its `ref_pattern` is `^#?[0-9]+$`, which is exactly the shape `/cdd-next-step` hardcoded before the ladder existed. `create_target` is derived from `git remote get-url origin` parsed to `owner/repo` — local, no network — and omitted when it cannot be derived.

Authentication is `gh`'s own, untouched: `gh` absent from `PATH`, or `gh auth status` failing, is exit 4 with an actionable line on stderr. CDD stores, reads and proxies no secret (§2.16).

## The Jira adapter

`tools/adapters/tracker/jira.sh` answers the same contract against **Jira Cloud** through its REST API v3, with `curl` and `jq` — no Jira CLI. Data Center / Server (personal access tokens, API v2) is out of scope. Like the GitHub adapter it **does not self-install**, for a different reason: a Jira binding is per-project by nature (a site and a project key), so a machine-global install has nothing sensible to point at. A project binds it through `.cdd/tracker`, which may export the non-secret coordinates:

```bash
#!/usr/bin/env bash
export JIRA_BASE_URL=https://<site>.atlassian.net JIRA_PROJECT_KEY=ABC
exec /path/to/cdd/tools/adapters/tracker/jira.sh "$@"
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

It **declares all five verbs**, so `issue-transition` is the contract's live exit-0 case that GitHub lacks. Its `ref_pattern` is `^[A-Z][A-Z0-9_]+-[0-9]+$` — a Jira key, which never overlaps the built-in `^#?[0-9]+$`. `describe` needs neither network nor `jq`; `create_target` is `<JIRA_PROJECT_KEY> @ <site host>` when both variables are set, and omitted otherwise.

- **State.** `closed` is the status *category* `done`; `open` is anything else. `state_raw` is the status name (`In Review`). `issue-list` is the project's items whose category is not Done, one page of up to 100 (the GitHub adapter's cap), through `/rest/api/3/search/jql` — the older `/search` endpoint has been removed from Jira Cloud. Search reads Jira's index, which trails a write by a second or two, so an item transitioned a moment ago can still appear; `issue-read` is always current.
- **`issue-transition`.** Workflows are per project, so it asks Jira which transitions are available from the current status and takes the first that lands in the target category — for `open`, preferring a To Do-category status. Already there is a no-op, exit 0. No fitting transition is exit 1, listing the transitions that do exist. A transition that needs a screen field fails with Jira's 400 message, also exit 1.
- **`issue-close-token`** yields a smart commit, `ABC-123 #done`; `JIRA_CLOSE_TRANSITION` overrides the transition name, lowercased with spaces hyphenated as smart commits expect (`Close Issue` → `#close-issue`). It acts only where Jira is connected to the forge with smart commits enabled — the second of the three cases above.
- **Bodies.** Jira v3 speaks Atlassian Document Format. `issue-read` flattens it to plain text (paragraphs, line breaks, lists, mentions, code; marks and layout dropped) for the body and every comment; `issue-create` wraps plain text as ADF paragraphs, so Markdown shows literally. Comment timestamps are converted to ISO-8601 UTC. `id` is Jira's numeric id and is emitted on both `issue-read` and `issue-create`, since Jira reports it on a create; `assignee` is the display name, omitted when unassigned.

## The Confluence adapter

`tools/adapters/docs/confluence.sh` is the docs capability's reference implementation: **Confluence Cloud**, through its REST API with `curl` and `jq`, read-only. Data Center / Server is out of scope. Like the Jira adapter it **does not self-install** — a binding is per-project by nature (a site, and the spaces worth searching) — and a project binds it through `.cdd/docs`, which may export the non-secret coordinates:

```bash
#!/usr/bin/env bash
export CONFLUENCE_BASE_URL=https://<site>.atlassian.net CONFLUENCE_SPACE_KEYS=TT
exec /path/to/cdd/tools/adapters/docs/confluence.sh "$@"
```

**Configuration is environment variables only:**

| Variable                 | Meaning |
| ------------------------ | ------- |
| `CONFLUENCE_BASE_URL`    | The site, `https://<site>.atlassian.net`; a bare host gets `https://`, a trailing `/wiki` is dropped. Falls back to `JIRA_BASE_URL` |
| `CONFLUENCE_EMAIL`       | The Atlassian account the token belongs to |
| `CONFLUENCE_API_TOKEN`   | An Atlassian API token. Lives in the user's shell; never in `.cdd/docs` or any file |
| `CONFLUENCE_SPACE_KEYS`  | Optional. Comma-separated space keys `doc-search` is restricted to; unset, the search is site-wide. A malformed key is exit 4 |

**The Jira fallback.** Jira and Confluence often share one Atlassian account, and sometimes do not (they can live on different sites). So the adapter has its own settings, and falls back to the Jira adapter's where they are unset:

- **Credentials fall back as a pair or not at all.** When *both* `CONFLUENCE_EMAIL` and `CONFLUENCE_API_TOKEN` are unset and both `JIRA_EMAIL` and `JIRA_API_TOKEN` are set, the Jira pair is used, and stderr says so once. Exactly one Confluence variable set is exit 4 naming the missing one — one variable from each set is never mixed.
- **The site falls back on its own**, to `JIRA_BASE_URL`. Atlassian API tokens belong to the account, not the site, so a Jira pair works on a different site of the same account.

A missing variable is exit 4 with one line per variable — after argument validation, so a usage error is still 2 on an unconfigured machine. The token reaches `curl` through `--config -` on stdin, never on the command line, and is never written to a file. Rejected credentials are exit 1 and said as such — which takes one extra step on Confluence Cloud: a bad token is not refused but served anonymously, so a page answers 404 and a search 403, with no failed-login header at all (checked live). On a 403 or 404 the adapter therefore asks who the credential authenticates as (`/wiki/rest/api/user/current`); an anonymous answer is reported as rejected credentials, a known user as "no such page, or no access". Both are exit 1; the extra request is paid only on failure.

It **declares all three verbs**. `describe` needs neither network nor `jq`; `link_pattern` matches page URLs on the configured site (or on any `*.atlassian.net` site when none is set), and `search_scope` is `<CONFLUENCE_SPACE_KEYS> @ <site host>` when both are set.

- **References.** A numeric page id; a page URL, `…/wiki/spaces/<KEY>/pages/<id>/…`; or a `…/wiki/…?pageId=<id>` URL. A URL's `#fragment` selects a section — in the current editor's form (`#CCA3`) and the older `#PageTitle-Heading` form alike. A URL on a different host than the configured site is exit 1, naming both, before any request: the credential goes only to the configured site. Tiny links (`/wiki/x/…`) are not accepted — resolving one needs an extra redirect-following request.
- **`doc-read` and `doc-stat`** use the v2 page endpoint, `GET /wiki/api/v2/pages/<id>` — `doc-read` with `body-format=atlas_doc_format`, `doc-stat` without a body. `version` is the page's version number and `updated_at` that version's creation time; `url` is the page's web link.
- **The body** arrives as Atlassian Document Format, serialized into a JSON string, and is flattened to Markdown with `jq` — the same approach as the Jira adapter's plain-text flattener, but keeping structure a reader and a section cut need: headings with their level, paragraphs, nested bullet and ordered lists (with their start number), task lists, fenced code with its language, inline code, links as `[text](href)`, inline cards as their URL, block quotes, rules, and tables as ` | `-joined rows. Emphasis, colours, layout and media are dropped. Storage format (XHTML) was rejected: stripping HTML with regexes in `jq` is lossy and leaves no reliable heading structure to cut sections on. Sections are cut on the page's top-level headings, which is where the editor puts them.
- **`doc-search`** uses v1 CQL search, `GET /wiki/rest/api/search` (v2 has no CQL search), with `type = page AND text ~ "<query>"`, plus `AND space in (…)` when `CONFLUENCE_SPACE_KEYS` is set.

## Resolution and the announcement rule

Resolution is the ladder from §2.16 — project `.cdd/<capability>`, then machine `~/.cdd/adapters/<capability>`, then built-in behaviour — first executable wins, and it degrades loudly rather than failing.

"Loudly" is scoped **to the point of use, not to the session**:

- Resolution performed merely to **classify** something — deciding whether `$ARGUMENTS` looks like an issue reference, say — is **silent**. Taken literally, "an absent adapter yields today's behaviour with a line saying so" would print a fallback line in every session in every repo, since no project has an adapter; that is noise, and noise is how a load-bearing line stops being read.
- When a tracker call is **actually made**, the caller announces in one line which rung served it — including the "no adapter installed, using built-in `gh`" case. The docs capability has no built-in rung: with no adapter there is no call to announce, and nothing is printed.
- **One exception, unconditional:** an adapter that is **present but rejected** — unparseable `describe`, an unsupported `contract` version, or a non-zero exit from `describe` — is announced **always**, even during silent classification. The user installed something that is not working, and silence there is indistinguishable from it working.

## The conformance gate

`scripts/adapter-conformance-check.sh` (the `adapter-conformance` gate, `needs: jq`) checks an adapter against this document, whatever its capability. It defaults to `tools/adapters/tracker/github.sh` and takes an optional path, so a project can point it at its own `.cdd/tracker` or `.cdd/docs`; `scripts/ci.sh` runs it over every `tools/adapters/*/*.sh`, so every shipped adapter is checked and a new one is covered without editing the runner. The subject's own `describe` names its capability, which picks a row of the checker's table: that capability's contract verbs, the check-5 probe and the check-6 probe.

It is **offline by construction**, and backend-neutral: every probe runs with the environment scrubbed (`env -i`, so a credential or coordinate the caller happens to have exported never reaches the subject), under either a scratch `PATH` holding stub backend tools — a `gh` that is authenticated and useless, a `curl` that always fails as if the host were unreachable — or a minimal `PATH` with no backend tooling at all. Nothing it runs can reach the network or authenticate. No probe mode, no dry-run flag — an adapter is checked exactly as a caller would invoke it. What it asserts:

1. `describe` exits 0 with backend tooling absent from `PATH` and the environment scrubbed, and its stdout parses as JSON (hermeticity).
2. `describe` is contract-shaped: `capability` is one with a published contract (`tracker`, `docs`); `contract` is an integer ≥ 1; `backend` is a non-empty string; `ref_pattern` is a non-empty string that `grep -E` accepts as a valid ERE, and so is `link_pattern` when present; `verbs` is a non-empty array of strings; `describe` is **not** among them; every declared verb is one of that capability's non-`describe` verbs above; and no `null` appears anywhere in the output.
3. Every verb in `describe.verbs`, invoked with **no arguments**, exits something other than 3 — i.e. dispatch reaches a real implementation rather than the unsupported-verb branch.
4. Every contract verb the adapter does not declare exits 3 (`issue-transition`, on GitHub), and so does a nonsense verb.
5. A verb that needs an argument, called without one, exits 2: `issue-read` for a tracker, `doc-read` for docs.
6. A well-formed call with backend tooling absent and the environment scrubbed exits 4 with a line on stderr — missing tooling for a `gh`-based adapter, missing configuration for an env-configured one: `issue-list` for a tracker, `doc-stat 12345` for docs.
7. Neither the adapter nor `.cdd/*` (when present) contains anything secret-shaped — a GitHub token prefix, an Atlassian API token prefix, a hardcoded basic-auth header, a PEM private-key header, or an assignment of a password / secret / token / api-key to a literal. This is §2.16's "never stores a secret" made mechanical, and it is the same class of check as `scripts/prompt-seam-check.sh`.

**Its stated limit:** check 3 proves that dispatch *reaches* an implementation, not that the implementation is *correct*. Correctness needs a live call against a real backend, which the offline-only decision rules out on purpose — a gate that SKIPs on most hosts is a gate whose verdict nobody can rely on. Checks 1, 2 and 4–7 are exact; check 3 is a floor.

Check 3 is only meaningful because of the dispatch-order rule above: an adapter that authenticated before parsing its arguments would exit 4 here for reasons that say nothing about dispatch. Such an adapter is non-conformant by construction, which is why the rule is stated as a rule and not as a hint.

**The docs adapter goes one step further offline.** Most of what it does is transformation, not transport — a page body flattened to Markdown, a section cut, a cap applied — and that is testable with no backend at all. `scripts/docs-adapter-assert.sh` (the `docs-adapter` gate, `needs: jq`) runs the real Confluence adapter against a stub `curl` that serves canned payloads by request path, and checks what comes out: the Markdown conversion, where section cuts start and stop (by `--section` and by URL fragment), the truncation cap and its flag, `doc-stat`'s shape, excerpt cleaning and the CQL `doc-search` sends, the credential and site fallbacks, the foreign-site refusal — and, inside the stub, that the API token never appears on `curl`'s command line. What it cannot prove is that the canned payloads still match what Confluence sends; that is the live test's job, done once against a real page when the adapter shipped.
