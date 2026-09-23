# Capability adapters: the tracker contract

The wire contract every capability adapter answers, pinned for the **tracker** capability — the first one with a shipped reference implementation (`tools/adapters/tracker/github.sh`) and, alongside it, a Jira Cloud adapter (`tools/adapters/tracker/jira.sh`).

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
| `capability`    | yes      | The role this adapter fills — `tracker` here. Matches the file name under `.cdd/`. |
| `contract`      | yes      | Integer contract version; see below.                                            |
| `backend`       | yes      | Non-empty string naming the service (`github`, `jira`, …). Free-form; nothing branches on it. |
| `ref_pattern`   | yes      | An **ERE** that matches a reference this backend accepts. CDD dispatches on it instead of hardcoding a shape. |
| `verbs`         | yes      | Non-empty array of the verbs this adapter implements, **excluding `describe`**. |
| `create_target` | no       | Human-readable coordinates a created item would land in (`owner/repo`, `XYZ / board 42`). Shown to a human before a write; nothing parses it. Omitted when it cannot be derived locally. |

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

## The GitHub reference adapter

Shipped adapters live at `tools/adapters/<capability>/<backend>.sh` — one directory per capability, mirroring the machine rung `~/.cdd/adapters/<capability>` — so a new tracker backend is one new file, which the lint and conformance gates pick up by glob.

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

## Resolution and the announcement rule

Resolution is the ladder from §2.16 — project `.cdd/<capability>`, then machine `~/.cdd/adapters/<capability>`, then built-in behaviour — first executable wins, and it degrades loudly rather than failing.

"Loudly" is scoped **to the point of use, not to the session**:

- Resolution performed merely to **classify** something — deciding whether `$ARGUMENTS` looks like an issue reference, say — is **silent**. Taken literally, "an absent adapter yields today's behaviour with a line saying so" would print a fallback line in every session in every repo, since no project has an adapter; that is noise, and noise is how a load-bearing line stops being read.
- When a tracker call is **actually made**, the caller announces in one line which rung served it — including the "no adapter installed, using built-in `gh`" case.
- **One exception, unconditional:** an adapter that is **present but rejected** — unparseable `describe`, an unsupported `contract` version, or a non-zero exit from `describe` — is announced **always**, even during silent classification. The user installed something that is not working, and silence there is indistinguishable from it working.

## The conformance gate

`scripts/adapter-conformance-check.sh` (the `adapter-conformance` gate, `needs: jq`) checks an adapter against this document. It defaults to `tools/adapters/tracker/github.sh` and takes an optional path, so a project can point it at its own `.cdd/tracker`; `scripts/ci.sh` runs it over every `tools/adapters/tracker/*.sh`, so both shipped adapters are checked and a new one is covered without editing the runner.

It is **offline by construction**, and backend-neutral: every probe runs with the environment scrubbed (`env -i`, so a credential or coordinate the caller happens to have exported never reaches the subject), under either a scratch `PATH` holding stub backend tools — a `gh` that is authenticated and useless, a `curl` that always fails as if the host were unreachable — or a minimal `PATH` with no backend tooling at all. Nothing it runs can reach the network or authenticate. No probe mode, no dry-run flag — an adapter is checked exactly as a caller would invoke it. What it asserts:

1. `describe` exits 0 with backend tooling absent from `PATH` and the environment scrubbed, and its stdout parses as JSON (hermeticity).
2. `describe` is contract-shaped: `capability` is `tracker`; `contract` is an integer ≥ 1; `backend` is a non-empty string; `ref_pattern` is a non-empty string that `grep -E` accepts as a valid ERE; `verbs` is a non-empty array of strings; `describe` is **not** among them; every declared verb is one of the five non-`describe` verbs above; and no `null` appears anywhere in the output.
3. Every verb in `describe.verbs`, invoked with **no arguments**, exits something other than 3 — i.e. dispatch reaches a real implementation rather than the unsupported-verb branch.
4. Every contract verb the adapter does not declare exits 3 (`issue-transition`, on GitHub), and so does a nonsense verb.
5. `issue-read` with no arguments exits 2.
6. `issue-list` with backend tooling absent and the environment scrubbed exits 4 with a line on stderr — missing tooling for a `gh`-based adapter, missing configuration for an env-configured one.
7. Neither the adapter nor `.cdd/*` (when present) contains anything secret-shaped — a GitHub token prefix, an Atlassian API token prefix, a hardcoded basic-auth header, a PEM private-key header, or an assignment of a password / secret / token / api-key to a literal. This is §2.16's "never stores a secret" made mechanical, and it is the same class of check as `scripts/prompt-seam-check.sh`.

**Its stated limit:** check 3 proves that dispatch *reaches* an implementation, not that the implementation is *correct*. Correctness needs a live call against a real backend, which the offline-only decision rules out on purpose — a gate that SKIPs on most hosts is a gate whose verdict nobody can rely on. Checks 1, 2 and 4–7 are exact; check 3 is a floor.

Check 3 is only meaningful because of the dispatch-order rule above: an adapter that authenticated before parsing its arguments would exit 4 here for reasons that say nothing about dispatch. Such an adapter is non-conformant by construction, which is why the rule is stated as a rule and not as a hint.
