# Claude-Driven Development (CDD)

A human-in-the-loop workflow for building and evolving a software project together with Claude Code. The project's own files (CLAUDE.md, a roadmap, architecture/feature docs, and a small set of slash commands) act as the substrate that drives the agentic process. The substrate evolves as the project evolves, so it stays useful instead of going stale.

This document describes the philosophy, the artifacts, the lifecycle, and the rules. The template files (`CLAUDE.md` skeleton, slash commands, worktree script, doc skeletons) are derived from this document and ship alongside it.

## 1. Philosophy

Four commitments shape every decision in this workflow.

**The human is in the loop at every gate.** The agent never picks the next task, never approves a plan, never merges its own PR, never restructures the roadmap unilaterally. It proposes; the human disposes. The agent's value is throughput inside a clearly-scoped task and consistency in keeping docs current, not autonomous decision-making.

**Automate everything except decisions.** The positive dual of the first commitment: CDD drives toward maximal SDLC automation — implementation, verification, documentation reconciliation, merge mechanics, even the consistency checks that keep the workflow itself honest — while reserving human attention for decisions. The six checkpoints (Section 4) are where automation deliberately stops. Everywhere else, a recurring manual step is a gap: convert it into a mechanism.

**The project documents itself as it grows.** Architecture and feature documentation are first-class deliverables, not afterthoughts. They serve dual duty: human reference and agent context. The same `pre-pr` step that runs CI also reconciles the docs against the code. A change isn't done until the docs match it.

**Context is the scarcest resource.** Each Claude Code session has a finite, expensive context window. The workflow is structured to keep each session's context focused on one job: choosing the next task, implementing one task, reviewing one PR, resolving one merge. Sessions hand off via files (handoffs, the roadmap, the docs) rather than by trying to share context.

A non-goal: full autonomy. CDD is not an attempt to take the human out of the loop. It is a way to amplify a single developer (initially) by structuring how the agent participates.

## 2. Artifacts

CDD relies on a small set of artifacts. Each has a clear owner, a clear update rule, and a clear consumer.

### 2.1 `CLAUDE.md` (project root)

The entry point Claude Code reads at session start. Kept thin: it is an index, not a knowledge dump. It points to the canonical docs and inlines only the highest-frequency constraints (the ones the agent will violate within minutes if they aren't right at the top).

Typical sections:

- One-paragraph project description.
- A "Key references" table pointing to architecture, feature docs, coding standards, and the roadmap.
- A short "Critical constraints" section with the rules that bite immediately (language version, banned constructs, naming conventions, units).
- Build, test, lint, format commands.
- A short "Workflow" pointer telling the agent to run `/pre-pr` before opening a PR and to keep docs current.

CLAUDE.md is updated by the agent during `/pre-pr` when module layout, build commands, or top-level constraints change. It is not the place to dump architecture details; those live in `doc/architecture/`.

### 2.2 The roadmap (`doc/knowledge_base/roadmap.md` or similar)

A checklist of tasks, grouped into phases. Each phase ends with a milestone statement. Each task is a checkbox. The roadmap is simultaneously a plan, a progress log, and a context document for future sessions.

Three rules govern the roadmap:

1. **The handoff session never edits the roadmap file.** It may discuss roadmap changes during clarification, but it records desired edits in the handoff and instructs the implementation session to apply them. Two reinforcing reasons: its context is already spent on cross-phase reasoning rather than any single task, and it runs on main, which is protected from direct edits and pushes — so the restriction is structural, not just convention. Roadmap edits happen in worktree sessions: the implementation session, and the pre-PR session per the Section 5 matrix.
2. **Roadmap edits beyond ticking a checkbox require human approval.** Adding, removing, or splitting tasks; restructuring phases; reordering priorities, the agent proposes, the human approves.
3. **Inline annotations stay terse.** When ticking a completed task, do not restate what the task did or describe how it was implemented — that lives in the commit, the PR description, and (for any lasting behaviour change) the process / architecture / feature docs, which the agent updates as part of the same change. Annotate inline *only* when a future session needs information that none of those sources will carry: a deferred sub-item, a surprising caveat, or a scope change. If there is nothing of that nature, just tick the box. One short clause, not a sentence with a parenthetical.

The roadmap is the central artifact. If it drifts from reality, the workflow loses its anchor.

### 2.3 Architecture docs (`doc/architecture/`)

"What the system is now," structurally. Module boundaries, data flow, key interfaces, deployment topology, threading model. Updated continuously by the implementation session as it changes the system, and reconciled by `/pre-pr` against the diff.

The directory is organised as an index plus per-topic documents. `index.md` is a pure pointer list — one link per document with a one-line summary — and the content lives in the per-topic docs (`overview.md`, `message-bus.md`, …). A session reads the index, then loads only the documents relevant to its task; this is the context-economy counterpart of CLAUDE.md staying thin. A top-level `doc/index.md` points at the architecture, features, and knowledge-base directories so a session can navigate the whole doc tree from one file, and CLAUDE.md's key-references table points at the indexes.

**The `index.md` is a pointer list only.** Substantive content — descriptions, rationale, data flows — belongs in the named subdocuments, not in the index. An index that accumulates content defeats the selective-loading model: a session that reads the index to decide which subdoc to load ends up reading all the content anyway. If content is worth writing, it belongs in a named file.

Architecture decision records (ADRs) live at `doc/architecture/adr/NNNN-short-title.md` and are listed from `doc/architecture/index.md`. Write an ADR for any structural decision that is not recoverable from the code or the existing docs: a choice of framework, a significant interface design, a constraint accepted for non-obvious reasons, a pattern adopted across the codebase. Nygard style: Title, Status, Context, Decision, Consequences. The ADR template lives at `doc/architecture/adr/0000-template.md`. ADRs are append-only; when a decision is superseded, add a new ADR and update the old one's Status to "Superseded by NNNN".

Architecture docs are load-bearing for the agent: when a new session opens with no memory of previous work, these docs (linked from CLAUDE.md) are how it rebuilds its mental model. If the architecture docs are wrong, the agent's plans will be wrong.

### 2.4 Feature docs (`doc/features/`)

"What the system does," from a capability/user perspective. One doc per significant feature. Created or updated by the implementation session whenever a feature is added or changed in a user-visible way. Reconciled by `/pre-pr`.

Feature docs serve human readers (what does this system do today?) and the agent (what's the contract this feature must preserve when I refactor near it?). On projects with no external "users" yet (greenfield internal tools, firmware), the audience is future-you and future-collaborators.

The same index convention as architecture docs applies: `doc/features/index.md` is a pointer list; each feature doc carries the content. Do not accumulate feature descriptions in the index itself — put them in per-feature documents and link from the index.

### 2.5 Knowledge base (`doc/knowledge_base/`)

Project metadata and history. The roadmap lives here. So do:

- The project overview (`project-overview.md`): the project's charter — what it is, why it exists, what it does and explicitly does not do, its constraints, and its architecture intentions. See below.
- Decision records: why we chose this RTOS, this framework, this hardware target, this protocol. Append-only.
- Coding standards: language-specific style and convention rules.
- Investigation notes: deep dives done in the course of the project that don't fit into architecture or feature docs.

The knowledge base is mostly append-only. Decisions are not rewritten when they are superseded; new decisions are added that supersede them, with a reference back. This preserves the reasoning trail.

The project overview is the exception to the append-only rule and is distinct from a founding document (below). It is a **living charter**, kept current: a fresh session reads it first to learn what the project is for and where its boundaries sit, before descending into the architecture and feature docs. `/bootstrap` (Section 6) populates it from the discovery conversation at project creation; later sessions keep it true as scope and constraints evolve. A founding document, by contrast, is the historical reasoning trail — *not* kept current. The two can coexist: the overview says what the project is today; the founding document records why it was shaped that way.

A common member of the knowledge base is the project's **founding document**: the investigation that led to creating and structuring the project, usually written before any code exists, and the main input to the first roadmap. Founding documents follow the decision-record rule: they are not kept current. After bootstrap their purpose shifts from driving the project to preserving the reasoning trail — why the project is shaped the way it is. Living context belongs to the architecture and feature docs and the roadmap; when a founding document contains structural description that proves durable, migrate it into `doc/architecture/` as the structure stabilises rather than maintaining it in place. (This repo's own `claude-driven-development.md` is a special case: here the founding document is also the shipped product, so unlike an ordinary founding document it *is* kept current — edits to it are edits to the deliverable.)

### 2.6 Handoff files (`~/.claude-handoffs/<repo-name>/<branch>.md`)

The contract between the handoff session and the implementation session. Lives outside the repo, namespaced by repo so multiple CDD projects don't collide (branch-scoped, ephemeral). Created by `/next-step`. Consumed by the first prompt of the implementation session. Deleted when the branch is deleted.

Schema:

```markdown
# Task: <short title>

## Branch
<branch_name>

## Roadmap reference
<exact checkbox line(s) from the roadmap being addressed>

## Implementation prompt
<self-contained prompt for the implementation session>

## Notes
<open questions deferred to the implementation session, caveats, or "None">
```

The implementation prompt is self-contained: it includes only context the implementation session cannot recover from CLAUDE.md, the roadmap, or the architecture docs. Restating project conventions is forbidden; those are inferable from the repo. Open questions deferred to the implementation session are listed in Notes so the implementation session can address them up front rather than running into them mid-plan.

### 2.7 Slash commands (`.claude/commands/`)

Project-level Claude Code slash commands. CDD ships four commands in the per-task lifecycle:

- `/next-step`, exploratory session, run on main, produces a handoff.
- `/pre-pr`, verification session, run on the feature branch, runs CI and reconciles docs.
- `/merge-main`, side-loop, run on a feature branch when main has advanced, does conflict assessment then merge.
- `/process-pr`, side-loop, run on a feature branch after the PR is opened and reviewed; reads the PR's review comments, addresses them in-session, posts replies, and commits + pushes. Analogous in lifecycle position to `/merge-main`. (See Section 4 for the deliberate checkpoint exception it carries.)

Two further commands exist in the CDD repo only and are deliberately not shipped in the template, because each operates *on* a target project from a CDD-repo session and needs `template/` plus the bootstrap script — downstream projects have no use for a copy. This is justified one-sided drift between `.claude/commands/` and `template/.claude/commands/` (recorded in `scripts/command-drift-whitelist.txt`):

- `/bootstrap`, used once at project start: a guided session that helps the user produce the project definition and a draft roadmap, then scaffolds a new greenfield project from the template in a single bootstrap invocation (see Section 6).
- `/retrofit`, which installs CDD into an existing project or upgrades a project already running it (see Section 6).

Slash commands are declarative: they describe what to do, not how to orchestrate it. Orchestration (worktree creation, branch lifecycle) lives in the shell helpers.

### 2.8 Worktree shell helpers (`tools/<slug>-worktree.sh`)

A bash script providing three commands, sourced from `~/.bashrc`:

- `<slug>-worktree <branch>`, creates a worktree for `<branch>` and launches Claude Code in plan mode in it with the suggested first prompt already submitted. Requires a handoff file to exist.
- `<slug>-worktree-done`, run from a feature worktree once the PR has landed or the branch is being abandoned. Returns to the default branch, pulls, removes the worktree, resolves the branch (safe-delete if merged, force-delete if squash-merged, prompt otherwise), and deletes the handoff iff the branch was deleted.
- `<slug>-worktree-list`, lists active handoffs with worktree/branch/PR status. Highlights stale entries.

The helpers derive the repository's default branch from `origin`'s HEAD (falling back to `main`) and assume the remote is named `origin`; the remote-name assumption is documented in `template/BOOTSTRAP.md`.

These helpers encode an invariant worth stating explicitly:

> Handoff deletion is tied to branch deletion. Branch deletion is tied to "merged, or human explicitly approved discard." A handoff is never deleted while its branch still exists.

This invariant prevents losing in-flight work and prevents stale handoffs from accumulating.

### 2.9 The three-identifier model

Every CDD project carries three distinct identifiers, and the template encodes them as separate placeholders so substitution can't conflate them:

- **`<PROJECT_NAME>`** — the display name. Human-readable, may contain spaces and mixed case. Example: `Sprint Planning Automation POC`. Used in document titles and prose references to the project.
- **`<PROJECT_SLUG>`** — the shell-command slug. A valid shell identifier prefix (lowercase, no spaces, hyphen-safe). Example: `spa-poc`. Used wherever a worktree command is referenced (`<PROJECT_SLUG>-worktree <branch>`, `<PROJECT_SLUG>-worktree-list`, etc.).
- **`<PROJECT_DIR>`** — the directory and repo slug. Used in `$HOME/Code/<PROJECT_DIR>/...` paths and as the working tree's directory name. Example: `sprint-planning-automation-poc`. Often the same as the slug but allowed to differ for projects whose directory name is more verbose than the typed command.

Internally, `template/tools/PROJECT-worktree.sh` also uses a bare `PROJECT` token where shell function names are defined; angle-bracketed placeholders aren't valid shell identifiers, so this token is a substitution artifact local to that file. It receives the same value as `<PROJECT_SLUG>` during bootstrap.

Substitution order is significant: `<PROJECT_NAME>`, `<PROJECT_SLUG>`, `<PROJECT_DIR>` are substituted first (the angle brackets keep them unambiguous), and bare `PROJECT` only inside the renamed worktree script. The bootstrap script (see Section 6) enforces this.

### 2.10 The template baseline marker (`.claude/cdd-baseline`)

Every bootstrapped or retrofitted project carries a one-line marker file, `.claude/cdd-baseline`, holding the commit hash of the CDD repo the template was rendered from (or the literal `unknown` when the bootstrap script runs outside a git checkout of the CDD repo). The marker is written by `bootstrap-cdd-project.sh` and by `/retrofit`; no template file ships it, because its value only exists at render time.

Its sole purpose is to anchor `/retrofit`'s upgrade mode: with the baseline hash, the old template a project started from can be recovered (`git show <hash>:template/<file>` in the CDD repo) and a three-way comparison can distinguish "the CDD template evolved" from "the project customized this file". Projects bootstrapped before the marker existed fall back to heuristic two-way diffing; the first upgrade writes the marker going forward.

## 3. Lifecycle

A task flows through CDD in up to five sessions, two of them optional side-loops (`/merge-main` before the PR, `/process-pr` after review). Each session type has a name, one command, and one job:

| Session            | Command                                       | Runs on                              | May edit (summary; see Section 5)          |
| ------------------ | --------------------------------------------- | ------------------------------------ | ------------------------------------------ |
| **Handoff**        | `/next-step`                                  | main worktree                        | the handoff file only — repo is read-only  |
| **Implementation** | auto-started by `<slug>-worktree <branch>`    | feature worktree, opens in plan mode | code, docs, roadmap                        |
| **Merge** (opt.)   | `/merge-main`                                 | feature worktree                     | merge resolution, docs if needed           |
| **Pre-PR**         | `/pre-pr`                                     | feature worktree                     | doc reconciliation, approved roadmap edits |
| **PR-review** (opt.) | `/process-pr`                               | feature worktree                     | review-driven code and replies             |

The blanket invariant: **every CDD session is a fresh context doing exactly one job.** This is a rule, not a per-command judgment call — the merge and PR-review sessions get fresh contexts for the same reason the pre-PR session does, even when the previous session's window is still open and would be convenient to reuse.

The five rows above are the per-task lifecycle. Two further session types sit outside it, run once at the start of a project's relationship with CDD rather than once per task: the **bootstrap session** (`/bootstrap`, greenfield setup) and the **retrofit session** (`/retrofit`, installing or upgrading CDD on an existing project). Both are CDD-repo-only meta sessions — they operate on a target path and need `template/` plus the bootstrap script (see Section 6) — and both keep the same fresh-context-one-job discipline.

```
                       (on main worktree)
            ┌──────────────────────────────────┐
            │ Handoff session: /next-step      │
            │                                  │
            │ Read roadmap (or take a task     │
            │ prompt), discuss/scope, clarify  │
            │ cheap requirements, write        │
            │ handoff file.                    │
            └──────────────────────────────────┘
                            │
                            │  handoff file
                            ▼
                  <project>-worktree <branch>
                            │
                            ▼
                       (on new worktree)
            ┌──────────────────────────────────┐
            │ Implementation session           │
            │                                  │
            │ Read handoff + roadmap + docs.   │
            │ Clarify expensive requirements   │
            │ in a clean context. Present plan │
            │ (plan mode). Human approves.     │
            │ Implement. Update docs and       │
            │ roadmap. Commit.                 │
            └──────────────────────────────────┘
                            │
                            │  (optional, if main moved)
                            ▼
            ┌──────────────────────────────────┐
            │ Merge session: /merge-main       │
            │                                  │
            │ Dry-run conflict assessment.     │
            │ Human approves. Merge main into  │
            │ the feature branch. Resolve.     │
            └──────────────────────────────────┘
                            │
                            ▼
            ┌──────────────────────────────────┐
            │ Pre-PR session: /pre-pr          │
            │                                  │
            │ Run build, format, lint, tests,  │
            │ integration tests. Code review.  │
            │ Reconcile architecture and       │
            │ feature docs. Propose roadmap    │
            │ edits. Conditionally propose CI  │
            │ improvements.                    │
            └──────────────────────────────────┘
                            │
                            ▼
                     gh pr create + human review
                            │
                            │  (optional, if review left comments)
                            ▼
            ┌──────────────────────────────────┐
            │ PR-review session: /process-pr   │
            │                                  │
            │ Read the PR's review comments.   │
            │ Triage; human approves the plan. │
            │ Address them, pushing back       │
            │ where warranted. Auto-post       │
            │ replies, commit + push.          │
            │ Back to PR review.               │
            └──────────────────────────────────┘
                            │
                            ▼
                       gh pr merge (squash)
                            │
                            ▼
                 <project>-worktree-done
                            │
                            ▼
                    back on main, clean
```

### 3.1 Handoff session: `/next-step` (on main)

Goal: pick what to do next and produce a clean handoff.

The session has two triggers, and converges on the same handoff either way:

- **Roadmap-driven** (`/next-step`, no argument): the session reads the roadmap and the stale-handoff list, proposes one or more candidate tasks, discusses dependencies and ambiguity with the human, and converges on a single task.
- **Intent-driven** (`/next-step <prompt describing a task to start>`): the task is already chosen by the human, so candidate proposal is skipped. This supports the common case where the human wants to start something off-roadmap rather than picking the next checkbox. The session loads context adaptively — the roadmap and the architecture/feature *indexes*, then selectively only the docs the described task actually touches — enough to scope it and detect overlap, not an exhaustive read (the implementation session rebuilds detailed context). It then does two things proposal mode does not: an **overlap check** — if the prompt substantially matches an existing (especially unchecked) roadmap item, surface that and ask whether to proceed as that item rather than silently creating a duplicate — and a **roadmap-belonging decision** — judge whether this new task belongs on the roadmap (substantive, evolving, will be referenced → yes; trivial throwaway → maybe not), asking the human if it's unclear. The verdict is recorded in the handoff's Notes as an instruction to the implementation session, which makes the actual roadmap edit.

Either way, the session then clarifies requirements that are cheap to resolve here, the ones where the right answer can be inferred from the roadmap or briefly discussed, and explicitly defers harder requirements to the implementation session.

Two reinforcing rationales drive this split. The first is context economy: the handoff session's context is necessarily polluted by reading the whole roadmap and reasoning across phases, while the implementation session's context is clean and dedicated to one task — the right environment for the harder, more focused clarification. The second is structural: the handoff session runs on main, which is protected from direct edits and pushes, so it cannot edit the roadmap even by accident; all roadmap edits happen in worktree sessions.

The session ends by writing the handoff file and printing the `<project>-worktree <branch>` command.

The handoff session does not edit the roadmap file. If roadmap edits are needed, it notes them in the handoff and instructs the implementation session to make them.

### 3.2 Worktree creation

The human closes the handoff session and runs `<project>-worktree <branch>` from the main worktree. The shell helper creates the new worktree and launches Claude Code in plan mode in it, passing the one-line first prompt (`Read <handoff path> and follow the Implementation prompt.`) as the initial user message so the implementation session opens already processing it.

### 3.3 Implementation session (on the new worktree)

The session opens in plan mode, reads the handoff, and rebuilds its context from CLAUDE.md, the roadmap, and the architecture/feature docs. It surfaces any deferred or freshly-discovered open questions and confirms scope with the human, then presents a plan.

Plan mode is the load-bearing checkpoint here: the agent cannot modify files while in plan mode, so the human gets a guaranteed approval gate before any code is written.

Once the plan is approved, the session implements the task, updates architecture and feature docs to reflect the change, updates the roadmap (ticking the completed checkbox; applying any add/modify/remove edits previously discussed and approved), and commits.

### 3.4 Merge session (optional): `/merge-main`

Run on the feature branch when main has advanced and the feature branch needs to integrate the new state, either because the PR will conflict or because the feature work depends on something that just landed on main.

Two-phase:

1. **Dry run.** Identify what main contains that's not on this branch. Assess merge complexity: which files conflict, whether the conflicts look mechanical or logical, whether new conventions on main affect this branch. Report. Do not merge yet.
2. **Merge.** On human approval, perform the merge and resolve. If conflicts are non-trivial, the agent may ask the human for clarification mid-resolution.

This is also where the agent can pull in improvements from main that are useful here without scheduling an explicit roadmap task (small refactors, new utilities, updated conventions).

### 3.5 Pre-PR session: `/pre-pr`

A fresh session on the feature branch, started after the implementation session has closed. This isolation is deliberate: a fresh context avoids the implementation session grading its own homework, and any "propose to the human" step in `/pre-pr` is a proposal to the human running this session, not to another session. Runs the CI gates, reads the diff, code-reviews changed files, and reconciles documentation.

Doc reconciliation has three parts:

- **Architecture docs**: read the docs that touch the changed area, compare against the actual code, fix discrepancies directly.
- **Feature docs**: same, for feature docs.
- **Roadmap**: tick newly-completed checkboxes directly; identify roadmap edits (add/modify/remove tasks) implied by what landed and present them to the human in this session for approval before applying.

`/pre-pr` also performs a conditional CI-improvement check: if the change introduces a category of work that the existing CI doesn't cover (new file type, new test category, a tool that should be linted but isn't), propose improvements to the human. On approval, apply them as part of the same PR; alternatively, the human may defer them as a new roadmap task. The default is silence. The agent should not propose CI improvements every run; only when the change genuinely surfaces a gap.

Output is a pass/fail summary across all the gates.

### 3.6 PR review and merge

The human runs `gh pr create`, reviews the PR (with full Claude assistance if desired, but in a fresh session, not the implementation session), and merges. Squash-merge is the default; the worktree script handles squash-merged branches as a first-class case.

### 3.7 PR-review session (optional): `/process-pr`

Run on the feature branch when a review has left comments that need addressing. A fresh session reads the open PR's review comments (inline review threads, review summary bodies, and general conversation comments), processes only the unresolved ones, and triages them: change-request, question, nit, or discussion. It presents the triage plan to the human, then implements the change-requests and nits, answers the questions, and pushes back — disagreeing and explaining in the reply — on any change-request it judges wrong or risky rather than implementing it blindly.

Approving the triage plan is the session's single checkpoint: once the human approves it, the rest of the run — the edits, the in-thread replies, the commit, the push — executes without further confirmation gates. The rationale is described in Section 4. Review threads are never resolved by the command; resolving them is the human's call during re-review.

This loop can repeat across review rounds.

### 3.8 Worktree teardown

The human runs `<project>-worktree-done` from the feature worktree. The script returns to main, pulls, removes the worktree (handling root-owned Docker artifacts via `sudo` with confirmation), resolves the branch, and deletes the handoff iff the branch was deleted.

## 4. Human checkpoints

Six explicit checkpoints. The human is also free to interject at any other point.

1. **Task selection** (end of `/next-step`): the human chooses among proposed candidates.
2. **Handoff approval** (end of `/next-step`): the human approves the drafted implementation prompt and notes.
3. **Plan approval** (start of implementation session, plan mode): the human approves the plan before any file is written.
4. **Merge-main approval** (between dry run and merge in `/merge-main`): the human approves after seeing conflict complexity.
5. **Roadmap edit approval** (during `/pre-pr`): the human approves proposed add/modify/remove edits before they are applied.
6. **PR merge** (after `/pre-pr`): standard GitHub PR review and merge.

These six are the gates. The agent should never proceed past a gate without explicit human confirmation.

### 4.1 The `/process-pr` exception

In `/process-pr` (Section 3.7) the gate sits up front rather than on each action: the human approves the triage plan (which comments will be addressed, and how) before any file is edited, and that single approval authorizes everything that follows — the edits, the in-thread replies, the commit, and the push. There is no second confirmation before the GitHub-side actions. This is a conscious trade-off, not an oversight: in a single-user, fast review-iteration loop the PR is already open, the human is actively reviewing it, and every change the command makes is visible in the PR diff and revertable from git history. Re-confirming each reply or push after the plan was already approved would defeat the purpose of a tight address-and-re-review cycle.

Human-in-the-loop judgment is preserved where it matters: the plan is approved before execution, and the command pushes back on change-requests it judges wrong rather than implementing them blindly. What is dropped is only repeated confirmation of the outbound actions that execute the approved plan. Review threads are also never auto-resolved — the human resolves them during re-review.

## 5. Edit rules: who edits what, when

The matrix below resolves any ambiguity about which session is allowed to touch which artifact. Columns are the session types named in Section 3.

| Artifact                | Handoff      | Implementation     | Merge         | Pre-PR                 | PR-review              |
| ----------------------- | ------------ | ------------------ | ------------- | ---------------------- | ---------------------- |
| Roadmap (tick)          | no           | yes                | no            | yes                    | yes if review-driven   |
| Roadmap (add/mod/rm)    | no           | yes (pre-approved) | no            | yes (human-approved)   | no                     |
| Architecture docs       | no           | yes                | yes if needed | yes (reconcile)        | yes if review-driven   |
| Feature docs            | no           | yes                | yes if needed | yes (reconcile)        | yes if review-driven   |
| CLAUDE.md               | no           | yes if needed      | no            | yes (reconcile)        | yes if review-driven   |
| README.md               | no           | yes if needed      | no            | yes (reconcile)        | yes if review-driven   |
| Knowledge base (other)  | no           | yes if needed      | no            | yes if needed          | yes if review-driven   |
| Code                    | no           | yes                | yes (merge)   | yes (review-driven)    | yes (review-driven)    |
| Handoff file            | yes (write)  | no (read-only)     | no            | no                     | no                     |
| CI config               | no           | yes if in scope    | no            | yes (human-approved)   | yes if review-driven   |

The handoff session is read-only on the repo. This keeps its job narrow: read, discuss, write the handoff. Everything else happens in worktrees. "Review-driven" in the PR-review column means the edit was requested by a reviewer and covered by the approved triage plan (Section 3.7); the PR-review session initiates no edits of its own.

## 6. Known gaps and deferred design

Several areas were intentionally out of scope for the first version of the template; two of them — adapting an existing project, and greenfield bootstrap — are now addressed by `/retrofit` and `/bootstrap` respectively.

**Greenfield bootstrap.** How a project gets its first roadmap, its first CLAUDE.md, its project overview, and its first architecture skeleton. This is addressed by `/bootstrap`, a command that lives in the CDD repo only (see Section 2.7) and is run from a CDD-repo session. It takes no argument: the project's name, slug, directory, and target location all emerge from the discovery conversation, so there is nothing to pass up front (the target path is proposed — defaulting to `$HOME/Code/<PROJECT_DIR>` — and confirmed once the identifiers are settled). It is a **guided** session, not a brief-to-files converter: the discovery conversation is part of the command. It walks the user through defining the project — what it is, its goals, what it does and explicitly does not do, its constraints, its architecture intentions — and from that produces the project overview (Section 2.5), a filled-in `CLAUDE.md`, and a draft roadmap. Each is confirmed with the user (project definition, then roadmap, then the three identifiers) before anything is rendered.

The mechanism is the `demo/setup.sh` pattern: `/bootstrap` writes the generated artifacts into a staging overlay directory and invokes `bootstrap-cdd-project.sh` once with `--overlay`, so the overlay overrides the template stubs and the filled-in docs land in the initial scaffold commit — no post-hoc copying. Because `/bootstrap` writes the architecture intentions, the overview, and a real roadmap through the conversation, the generated roadmap starts at the project's real first phase and does **not** carry the template's pre-filled "CDD bootstrap" phase (survey the codebase / write the docs / fill the roadmap). That pre-filled phase exists for files-only starts — `/retrofit` install mode and the manual bootstrap-script path below — where the docs have not yet been written.

The manual fallback is to run `bootstrap-cdd-project.sh` from the CDD repo root (see `template/BOOTSTRAP.md` for the procedure): it copies the template into a fresh directory, performs the placeholder substitution non-interactively, and runs the initial `git init` + scaffold commit, leaving the stubs and the pre-filled bootstrap phase to be filled in by hand and by the first few `/next-step` sessions. Use this when guided discovery isn't wanted; otherwise prefer `/bootstrap`.

**Parallel-merge structure.** When two worktrees land in sequence, the second needs to integrate the first. Today this is partly automated (`/merge-main` covers it) and partly manual (the human decides when to trigger). A more structured approach, perhaps with a "second worktree must re-run pre-pr after merge-main", may be warranted once parallel work is common. The invariant is clear: a feature branch must integrate main and re-pass pre-pr before it's ready to merge.

**Template opinionation per project type.** The current template encodes the workflow, but the project-specific bits (build commands, language constraints, module layout) are placeholders. Different project archetypes (firmware, web app, library, data pipeline) probably want different opinionated defaults for those placeholders. Worth deriving from real usage rather than guessing up front.

**Adapting an existing project.** Addressed by `/retrofit`, a command that lives in the CDD repo only (see Section 2.7) and is run from a CDD-repo session with the target project's path as argument. It auto-detects which of two modes applies:

- *Install mode* — the target has no CDD scaffolding. A files-only install of the template: slash commands, doc skeletons, the worktree helper, `.claude/settings.json`, with placeholder substitution done by `bootstrap-cdd-project.sh` in a render-only staging mode (the command never reimplements substitution). Files missing from the target are copied; collisions with existing files (a project's own `CLAUDE.md`, for instance) are merged interactively, one file at a time, with human approval — never overwritten silently. No codebase survey happens at install time: the template roadmap ships with a pre-filled bootstrap phase (survey the codebase, draft the initial architecture docs, write the feature docs, fill in the roadmap), so the project's first `/next-step` picks those up as the next unchecked tasks. This pre-filled phase is for files-only starts — install mode here and the manual bootstrap-script path — where no docs have been written yet; `/bootstrap` writes the docs through guided discovery and so ships a real roadmap without it.
- *Upgrade mode* — the target already runs CDD. Using the baseline marker (Section 2.10) as the merge base, each CDD-managed file is compared three ways: improvements the CDD template has accrued are proposed for application; local customizations are preserved; files changed on both sides get an interactive merge. Local changes that look general rather than project-specific are not silently kept local — they are surfaced as candidates to upstream into the CDD repo. Every change that touches a project file is approved per file; the checkpoints of Section 4 apply in spirit here too.

In both modes the retrofit isolates its writes from the target's current branch. Before rendering anything, it creates a dedicated branch (`cdd-retrofit`) and a sibling worktree off the target's HEAD, directs every write into that worktree, and — once all per-file approvals are done — makes a single commit on the branch so the user reviews and merges the scaffolding through a normal PR rather than finding it strewn across the current branch (usually the default branch). This is the one place CDD runs history-mutating git in a target, and it is deliberately scoped: the command only ever creates the dedicated branch and commits onto *it*, never onto the target's existing branches. On the happy path — a sibling worktree off HEAD — it never touches the current checkout. If the target is not a git repo, the command warns and falls back to writing in place without committing; if it is a git repo with no commits yet (an unborn HEAD, where a worktree can't be created), it falls back to a plain branch in the existing checkout and commits there. Because the worktree branches from HEAD, uncommitted local edits to CDD-managed files are not seen by the upgrade comparison; the command warns when it detects them rather than hard-stopping on any dirty tree.

The doc-reconciliation discipline remains the bigger ask; existing projects without it will have a painful first few PRs as the docs are made to reflect reality.

## 7. Template directory layout

The template ships as a directory copied into a new project root by `bootstrap-cdd-project.sh` (which lives at the CDD repo root, not inside `template/`). The bootstrapped tree looks like:

```
<PROJECT_DIR>/
├── CLAUDE.md                                 # skeleton with placeholders, filled by hand after bootstrap
├── .claude/
│   ├── cdd-baseline                          # written at render time, not shipped in the template
│   ├── settings.json                         # auto-allows worktree sessions to read their handoff file
│   └── commands/
│       ├── next-step.md
│       ├── pre-pr.md
│       ├── merge-main.md
│       └── process-pr.md
├── doc/
│   ├── index.md                              # top-level pointer to the doc directories
│   ├── architecture/
│   │   └── index.md                          # pointer-list skeleton
│   ├── features/
│   │   └── index.md                          # pointer-list skeleton
│   └── knowledge_base/
│       ├── project-overview.md               # project charter skeleton, filled by /bootstrap or by hand
│       ├── roadmap.md                        # pre-filled bootstrap phase + placeholder phases
│       └── README.md                         # explains the knowledge base
└── tools/
    └── <PROJECT_SLUG>-worktree.sh            # renamed and substituted by bootstrap
```

`template/BOOTSTRAP.md` is meta-documentation that lives in the template directory but is **not** copied into the bootstrapped project; the bootstrap script excludes it. Likewise, the bootstrap script itself stays at the CDD repo root and is not part of the bootstrapped tree.

Bootstrap procedure for a new project:

1. From the CDD repo root, run:
   `./bootstrap-cdd-project.sh --name "Display Name" --slug shell-slug --path /path/to/dir-slug`
   The basename of `--path` becomes the `<PROJECT_DIR>` slug.
2. Add the worktree-helper source line to `~/.bashrc` (the script prints the exact line on success).
3. Fill in CLAUDE.md placeholders: project description, key references, critical constraints, build/test commands.
4. Start the first `/next-step` session (it creates the per-repo handoff directory `~/.claude-handoffs/<repo-name>/` on demand). The roadmap's pre-filled bootstrap phase carries the first tasks: survey the codebase, draft the initial architecture docs, and replace the placeholder phases with the project's real plan — a suggested-infrastructure list (CI, linting, tests, …) helps populate the early phases.

### 7.1 The CDD repo as its own project

A natural extension: the CDD repo itself is a project, and it uses CDD on itself. The template directory becomes content that the project ships, distinct from the project's own scaffolding.

Concretely, the CDD repo has two layers:

- **Its own CDD scaffolding** at the repo root: `./CLAUDE.md`, `./.claude/commands/`, `./doc/{architecture,features,knowledge_base}/`, `./tools/cdd-worktree.sh`. This is how Claude Code works on the CDD repo itself.
- **The template** under `./template/`: the copy-paste material that gets dropped into new projects. This is content, not scaffolding.

The two layers share a shape but serve different purposes. `./CLAUDE.md` is the CDD project's actual context (it references the process doc, lists open work, points at the template). `./template/CLAUDE.md` is a skeleton with placeholders, intended to be copied and filled in for a different project. `./template/BOOTSTRAP.md` documents the bootstrap recipe (it is template-adjacent meta-doc, not content that ships into the bootstrapped project), and `./bootstrap-cdd-project.sh` at the CDD repo root automates the copy + substitution.

The duplication between `./.claude/commands/` and `./template/.claude/commands/` is real but small, and it is the right duplication: the template ships a snapshot, the CDD repo's own copy can drift slightly if a command needs CDD-specific behaviour, and divergence is visible at review time. The CDD repo's own `/pre-pr` includes a command-set drift step that diffs the two trees and presents each hunk to the human, who judges whether it is expected substitution drift or unintended divergence.

The process doc itself (`claude-driven-development.md`) lives under `doc/knowledge_base/` in the CDD repo, since it is the foundational design document for the project. Other projects using the template do not get a copy of the process doc by default; the template is self-sufficient for users who don't need the philosophy.

This pattern, the meta-project hosting its own template, is the cleanest available demonstration of CDD's value. Anything awkward about applying CDD to its own evolution is a real bug in the workflow.

## 8. Adapting to a team

The workflow as described assumes a single human in the loop. A few adjustments anticipated for team use, not yet designed:

- Handoff files would need to live somewhere shared (repo-tracked under `.handoffs/`, or a shared filesystem location, or an issue tracker). Branch-keyed naming still works.
- Task selection in `/next-step` needs visibility into others' in-flight worktrees to avoid stomping. The worktree-list command would need to query a shared source.
- PR review remains a human gate, but the team needs a convention on who reviews what; the agent's PR-review pass becomes one input among several.
- Roadmap edits, especially structural ones, need a team approval mechanism beyond "the human running the session approves." A lightweight rule: structural edits go through a PR against the roadmap itself.

These extensions are tractable but deserve their own design pass once single-user usage is solid.
