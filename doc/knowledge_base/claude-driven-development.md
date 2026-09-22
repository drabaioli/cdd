# Claude-Driven Development (CDD)

A human-in-the-loop workflow for building and evolving a software project together with Claude Code. The project's own files (CLAUDE.md, a roadmap, architecture/feature docs, and a small set of slash commands) act as the substrate that drives the agentic process. The substrate evolves as the project evolves, so it stays useful instead of going stale.

This document describes the philosophy, the artifacts, the lifecycle, and the rules — the workflow itself, and nothing else. The template files (`CLAUDE.md` skeleton, slash commands, doc skeletons) are derived from this document and ship alongside it. What this repo provides is described in `doc/features/`; how this repo and its tooling are built is described in `doc/architecture/`.

**Document altitude.** This document stays at the workflow level: what the artifacts, contracts, invariants, and checkpoints *are*, and why — never how a script implements them. Implementation mechanics (install wiring, shims, fallback ladders, git plumbing) belong in code comments and `doc/architecture/`; user-facing capability descriptions belong in `doc/features/`. The editing test: if a passage would have to change when a script is refactored without the workflow itself changing, it belongs next to the code — leave a one-line pointer here instead.

## 1. Philosophy

Five commitments shape every decision in this workflow.

**The human is in the loop at every gate.** The agent never picks the next task, never approves a plan, never merges its own PR, never restructures the roadmap unilaterally. It proposes; the human disposes. The agent's value is throughput inside a clearly-scoped task and consistency in keeping docs current, not autonomous decision-making.

**Automate everything except decisions.** The positive dual of the first commitment: CDD drives toward maximal SDLC automation — implementation, verification, documentation reconciliation, merge mechanics, even the consistency checks that keep the workflow itself honest — while reserving human attention for decisions. The six checkpoints (Section 4) are where automation deliberately stops. Everywhere else, a recurring manual step is a gap: convert it into a mechanism.

**The project holds itself to engineering standards as it grows.** Sound architecture, structured documentation, tested behaviour, and a working CI gate are first-class deliverables, not afterthoughts; they serve dual duty as human reference and agent context. Documentation is the part CDD enforces directly today: the same `pre-pr` step that runs CI reconciles the docs against the code, and a change isn't done until the docs match it. The rest — that new behaviour ships with a test, that CI builds and checks the project, that dependencies and style stay honest — CDD instils by *mechanism and floor, not prescription*: it ships a written definition of what "engineering-ready" means (the engineering-practices contract, Section 2.12), asks at the pre-PR gate whether new behaviour is tested, and tracks the practices it does not yet enforce on the roadmap — while leaving the concrete tools, frameworks, and commands to the project. It raises the floor without dictating the house. This is how CDD instils engineering excellence into an adopting project without invading how it works.

**Context is the scarcest resource.** Each Claude Code session has a finite, expensive context window. The workflow is structured to keep each session's context focused on one job: choosing the next task, implementing one task, reviewing one PR, resolving one merge. Sessions hand off via files (handoffs, the roadmap, the docs) rather than by trying to share context.

**The workflow improves itself.** CDD treats its own substrate — `CLAUDE.md`, the commands, the CI and test scaffolding, the docs, the conventions — as a product under continuous revision. When a session discovers a better way to work (a constraint that should have been in `CLAUDE.md`, a check the pre-PR gate should run, a convention worth adopting), the improvement does not evaporate at session end: it is routed into the project's own roadmap or conventions as a tracked change, and an improvement general enough to help any project is surfaced as a candidate to upstream into CDD itself. Three recurring channels carry this: the improvement check in the pre-PR session (§3.6), which catches it at discovery time; the workflow-gap route in the PR-review session (§3.8), which catches what a reviewer sees from outside the session that caused it; and `/cdd-retrofit` upgrade mode, which catches it at upgrade time. A recurring friction that no artifact captures is a gap, the same way a recurring manual step is.

A non-goal: full autonomy. CDD is not an attempt to take the human out of the loop. It is a way to amplify a single developer (initially) by structuring how the agent participates.

## 2. Artifacts

CDD relies on a small set of artifacts. Each has a clear owner, a clear update rule, and a clear consumer. Concrete skeletons for the per-project artifacts ship in `template/` (see `doc/features/template.md`).

### 2.1 `CLAUDE.md` (project root)

The entry point Claude Code reads at session start. Kept thin: an index, not a knowledge dump — a one-paragraph project description, a key-references table pointing at the canonical docs, the critical constraints that bite within minutes, the build/test commands, and a workflow pointer (run `/cdd-pre-pr` before opening a PR; keep docs current). Updated by the agent during `/cdd-pre-pr` when module layout, build commands, or top-level constraints change. Architecture details do not live here; they live in `doc/architecture/`.

### 2.2 The roadmap (`doc/knowledge_base/roadmap.md` or similar)

A checklist of tasks, grouped into phases, each phase ending with a milestone statement. The roadmap is simultaneously a plan, a progress log, and a context document for future sessions — the central artifact: if it drifts from reality, the workflow loses its anchor.

Three rules govern it:

1. **The handoff session never edits the roadmap file.** It records desired edits in the handoff for the implementation session to apply. Two reinforcing reasons: its context is already spent on cross-phase reasoning, and it runs on main, which is protected from direct edits — so the restriction is structural, not just convention.
2. **Roadmap edits beyond ticking a checkbox require human approval.** Adding, removing, or splitting tasks; restructuring phases; reordering priorities: the agent proposes, the human approves.
3. **Every item stays terse — pending and completed alike.** An item reads like a PR title or barely more, and fits in **200 characters** including the checkbox prefix: enough for a reader to place the task in the roadmap's arc, with the fine-grained detail left to the PR description, the ADRs, and the docs — which the same change updates anyway. Tick the box; annotate only what no other artifact (commit, PR, docs) will carry — a deferred sub-item, a surprising caveat, a scope change — in one short clause after a semicolon, never a restatement of the work. Pending items are not exempt, and this is the half a length convention usually forgets: detail that does not fit does not go on the roadmap. A pending task's scope belongs in a **GitHub issue** referenced by number on the line (§3.1 already treats issues as the inbox feeding the roadmap, and `/cdd-next-step #NN` sources a task straight from one); implementation-time detail belongs in the handoff. Where a task hinges on a design decision, the ADR is written when the decision is *taken* — an ADR records a decision, not pending scope, and the issue carries the thinking until then. A separate backlog or notes document is deliberately *not* part of the workflow — it is a second list of pending work to keep in sync, and the roadmap is the source of truth. Because a cap nobody measures drifts back, the cap is a gate (§2.14) where the project has a check runner; this repo's is `scripts/roadmap-length-check.sh`. The bar is stated in full, with an example, under "Annotation conventions" in the roadmap itself, so the session applying an edit reads it in the file it is editing.

### 2.3 Architecture docs (`doc/architecture/`)

"What the system is now," structurally. Updated continuously by the implementation session as it changes the system, and reconciled by `/cdd-pre-pr` against the diff. These docs are load-bearing for the agent: a fresh session rebuilds its mental model from them, so if they are wrong, its plans will be wrong.

The directory is an index plus per-topic documents. **`index.md` is a pointer list only** — one link per document with a one-line summary; the content lives in the per-topic docs. A session reads the index, then loads only the documents relevant to its task — the context-economy counterpart of CLAUDE.md staying thin. An index that accumulates content defeats this selective-loading model. A top-level `doc/index.md` points at the architecture, features, and knowledge-base directories so a session can navigate the whole doc tree from one file.

Architecture decision records (ADRs, Nygard style: Title, Status, Context, Decision, Consequences) live at `doc/architecture/adr/NNNN-short-title.md` and are listed from the index. Write one for any structural decision not recoverable from the code or the existing docs. ADRs are append-only: a superseded decision gets a new ADR and a Status update, not a rewrite.

### 2.4 Feature docs (`doc/features/`)

"What the system does," from a capability/user perspective — one doc per significant feature, created or updated by the implementation session whenever a feature changes in a user-visible way, and reconciled by `/cdd-pre-pr`. They serve human readers (what does this system do today?) and the agent (what contract must a refactor preserve?). The same index convention as architecture docs applies.

### 2.5 Knowledge base (`doc/knowledge_base/`)

Project metadata and history: the roadmap, the project overview, decision records, coding standards, the engineering-practices contract (§2.12), and investigation notes. Mostly append-only — decisions are superseded by new records referencing the old, preserving the reasoning trail.

The **project overview** (`project-overview.md`) is the exception to append-only: a living charter — what the project is, why it exists, what it does and explicitly does not do, its constraints, its architecture intentions — read first by a fresh session and kept current. A **founding document**, by contrast, is the investigation that led to creating the project; after bootstrap it is *not* kept current — its purpose shifts to preserving the reasoning trail, and durable structural description migrates into `doc/architecture/` as the structure stabilises. The two coexist: the overview says what the project is today; the founding document records why it was shaped that way. (This repo's own `claude-driven-development.md` is the special case where the founding document is also the shipped product, so it *is* kept current.)

### 2.6 Handoff files (`~/.cdd/handoffs/<repo-name>/<branch>.md`)

The contract between the handoff session and the plan session. Lives outside the repo, namespaced by repo so multiple CDD projects don't collide; branch-scoped and ephemeral — created by `/cdd-next-step`, consumed by the first prompt of the plan session, deleted when the branch is deleted. Two siblings share its lifecycle: the **state record** (`<branch>.state.json`, §2.13) seeded beside it, and the **plan file** (`<branch>.plan.md`, §2.15) written later by `/cdd-plan`.

Schema:

```markdown
# Task: <short title>

## Branch
<branch_name>

## Roadmap reference
<exact checkbox line(s) from the roadmap being addressed>

## Requirements
<observable acceptance criteria, as few as possible — minimum 1, typically 3-6, hard cap 10; no design>

## Implementation prompt
<self-contained prompt for the plan session>

## Notes
<open questions deferred to the plan session, caveats, or "None">
```

The implementation prompt is self-contained: it includes only context the plan session cannot recover from CLAUDE.md, the roadmap, or the architecture docs. Restating project conventions is forbidden; those are inferable from the repo. Open questions deferred to the plan session are listed in Notes so it can address them up front rather than mid-plan. The prompt carries no standing instructions about planning, committing, or advancing the state record: once the implementation cycle has command files of its own (§3.3, §3.4), those live there and are improved once rather than regenerated into every handoff.

**Requirements** are the one artifact that survives *both* halves of the split implementation cycle and is checkable against each: `/cdd-plan` checks its plan against them, `/cdd-implement` treats them as the done-test, and `/cdd-pre-pr` reconciles the diff against them instead of inferring intent. They are observable acceptance criteria — what a reader could check on the finished change — never design. The **cap is load-bearing**: as few as possible, typically 3–6, and never more than 10. It is what stops the handoff session inflating into a requirements interview, which the cheap/expensive split (§3.1) exists to prevent; a criterion that cannot be stated cheaply here is a deferred question for the plan session, recorded in Notes. So is the **floor of 1**: `/cdd-pre-pr` reconciles the diff *against* this section, so an empty one leaves it inferring intent — exactly what the section exists to prevent. Even "tick one box" gets a criterion, and it is a real check rather than a restatement, because it says what must *not* also change. A small-change handoff (§3.2a) normally carries one or two.

A **small-change handoff omits `## Implementation prompt` entirely**: on that lane the requirements already say everything a change whose diff fits in one sentence has to say, and a section restating them is a place for the two to drift apart. Frozen (below) means never renamed, not always present.

The heading `## Implementation prompt` is **frozen**, even though its content is now a plain task spec. An older worktree helper's first prompt names that heading verbatim, so renaming it would dangle that prompt against a project that has been retrofitted; keeping it means an old helper meeting a new project degrades gracefully into the un-split flow (§2.8).

### 2.7 Slash commands (`.claude/commands/`)

Project-level Claude Code slash commands. They are declarative — they describe what to do, not how to orchestrate it; orchestration (worktree creation, branch lifecycle) lives in the shell helpers (§2.8). CDD ships seven commands in the per-task lifecycle:

- `/cdd-next-step`, exploratory session, run on main, produces a handoff.
- `/cdd-plan`, plan session, auto-started in the feature worktree: explores, takes plan approval, writes the plan file (§2.15), and stops without touching the repo.
- `/cdd-implement`, implementation session, started by hand in the same worktree: builds from the plan file, updates docs, commits locally.
- `/cdd-small-change`, small-change session, auto-started in the feature worktree in place of the two above when the task was declared small at scoping (§3.2a): takes its own approval of the concrete change, builds it, updates docs, commits locally.
- `/cdd-pre-pr`, verification session, run on the feature branch, runs the check runner (§2.14) and reconciles docs.
- `/cdd-merge-base`, side-loop, run on a feature branch when main has advanced: conflict assessment, then merge.
- `/cdd-process-pr`, side-loop, run on a feature branch after the PR is opened and reviewed: reads the review comments, addresses them, posts replies, commits + pushes. (See §4.1 for the deliberate checkpoint exception it carries.)

Three further commands — `/cdd-bootstrap` (greenfield setup), `/cdd-retrofit` (install or upgrade CDD on an existing project), and `/cdd-quick-create` (lightweight one-off deliverable) — exist in the CDD repo only and are deliberately not shipped in the template: each operates *on* a target from a CDD-repo session, so downstream projects have no use for a copy. This justified one-sided drift is recorded in `scripts/command-drift-whitelist.txt`. The commands are described in `doc/features/template.md`; their place in the workflow is in Section 6.

### 2.8 The worktree shell helper (`cdd-worktree`)

A single, project-independent bash helper provides five commands — the same script for every CDD project, with everything project-specific (repository name, default branch, handoff directory) derived at runtime:

- `cdd-worktree <branch>`, creates a worktree for `<branch>` and launches Claude Code in it, with the suggested first prompt already submitted (§3.2). Requires a handoff file to exist. It cuts the new branch from the task's recorded base branch (§2.13), falling back to the default branch when none was recorded. It runs from the main worktree — the guard is "not a linked worktree", so a project whose main worktree sits on a non-default integration branch (a gitflow `develop`) is fine.
- `cdd-worktree-done`, run from a feature worktree once the PR has landed or the branch is being abandoned: returns to the default branch, removes the worktree, resolves the branch, and deletes the handoff — and its siblings, the plan file (§2.15) and the state record (§2.13) — iff the branch was deleted.
- `cdd-worktree-list`, lists active handoffs with worktree/branch/PR status, highlighting stale entries.
- `cdd-worktree-gc [--force]`, reaps the artifacts of **finished** tasks — the local handoff, the plan file (§2.15), the state record (§2.13), and the synced per-task ref (§2.13) — for any task whose PR has merged. It is the backstop for `cdd-worktree-done` never running, its ref cleanup failing offline, or a task resumed on several machines leaving materialized copies behind on all but the one where `done` ran. Deliberately conservative: it reaps only merged tasks (a merged PR is the sole trustworthy "done" signal — a scoped-but-unstarted task's handoff and ref exist *before* its branch does, so ref/branch presence alone cannot tell the two apart), and it is dry-run unless `--force`.
- `cdd-worktree-resume [<branch>]`, picks up a task started on another machine that has only a clone of the repo: recreates a worktree tracking an **existing remote branch**, ready for whichever command the task's stage calls for — `/cdd-implement` for a task parked at `plan_written`, otherwise `/cdd-process-pr`, `/cdd-merge-base` or `/cdd-pre-pr`; with no argument it lists the resumable remote branches. If the originating machine synced them, it also fetches and materializes the handoff (§2.6), the plan file (§2.15) and the state record (§2.13) from a per-task ref before it finishes — advisory and best-effort, so a task with no synced ref resumes exactly as before (the resume-side commands read PR/branch state from `git`/`gh`, not the handoff). The sync mechanics live in `doc/architecture/shell-helpers.md`.

Being machine-global has a consequence worth stating as a rule, because it applies to every change of this shape and not just to one:

> **A machine-global artifact must work against every project baseline present on the machine; the per-project artifact carries the switch.**

One version of the helper serves every project on the machine, while `.claude/commands/` and `CLAUDE.md` are retrofitted one project at a time, so a global artifact cannot be staged per project. Two rules follow. Where behaviour must differ, the helper **probes the ground truth rather than assuming or versioning** — it asks the worktree it is standing in whether that project has a given command file, which cannot go stale the way a recorded baseline or version field can. Everything else stays **additive**, so it is inert where no project uses it yet. A workflow change that needs both sides therefore ships global-first and additive, then per-project, in any order and with no flag day. Where a skew is nonetheless possible in the direction a probe cannot cover, the helper prints one warning line rather than degrading silently. Generalizing this into a real versioning and fleet-migration mechanism is deferred design (§6).

The helper installs itself once per machine (`tools/cdd-worktree.sh install`) to a stable home that does not depend on a live CDD checkout; after that the commands work in every CDD project — including ones bootstrapped later — with no per-project setup. It is a machine-global toolchain dependency, like `git` or `gh`: newest wins, install idempotent, always from latest `main` — never pinned per project, since pinning would reintroduce the very conflict a single shared helper avoids. Its contract with projects is deliberately tiny and grows only additively: the command names above plus the `~/.cdd/handoffs/<repo>/<branch>.md` layout; when that shared state must evolve, the change ships as a one-shot migration inside `install`, re-homing every project at once. The install and dispatch mechanics live in `doc/architecture/shell-helpers.md` and the script's own comments.

These helpers encode an invariant worth stating explicitly:

> Handoff deletion is tied to branch deletion. Branch deletion is tied to "merged, or human explicitly approved discard." A handoff is never deleted while its branch still exists.

This invariant prevents losing in-flight work and prevents stale handoffs from accumulating.

A second, equally project-independent helper — `cdd-state` (`tools/cdd-state.sh`) — manages the per-task state record (§2.13). It installs the same way and has its own tiny contract: `seed` / `set` plus the `<branch>.state.json` layout. It is independent of the worktree helper, which only *deletes* the record, so the frozen worktree contract above is unchanged.

### 2.9 The two-identifier model

Every CDD project carries two distinct identifiers, and the template encodes them as separate placeholders so substitution can't conflate them:

- **`<PROJECT_NAME>`** — the display name. Human-readable, may contain spaces and mixed case. Example: `Sprint Planning Automation POC`. Used in document titles and prose references to the project.
- **`<PROJECT_DIR>`** — the directory and repo slug. Used as the working tree's directory name and, at runtime, as the handoff-directory namespace (`~/.cdd/handoffs/<PROJECT_DIR>/`). May be CamelCase (e.g. `PyGroundControl`) to match the actual repository folder.

The angle brackets keep both unambiguous, and the bootstrap script replaces them wherever they appear. (A third, per-project shell-command slug existed before the worktree helper was unified into the single project-independent `cdd-worktree`, §2.8, and was removed with it.)

### 2.10 The template baseline marker (`.claude/cdd-baseline`)

Every bootstrapped or retrofitted project carries a one-line marker file holding the commit hash of the CDD repo the template was rendered from. Its sole purpose is to anchor `/cdd-retrofit`'s upgrade mode: the baseline hash lets a three-way comparison distinguish "the CDD template evolved" from "the project customized this file". Projects bootstrapped before the marker existed fall back to heuristic two-way diffing; the first upgrade writes the marker going forward. Details in `doc/architecture/bootstrap-and-retrofit.md`.

### 2.11 Commit conventions

Several sessions auto-commit at their gate so that a session never leaves a dirty tree for the next one to inherit. Five rules keep this non-disruptive:

1. **A gate commits only the changes it produced** — never `git add -A`. If the tree is already dirty on entry with changes the gate did not create, it stops and surfaces them instead of committing.
2. **Auto-commits are local — no push.** The sole exception is `/cdd-process-pr` (§3.8), the one auto-push gate.
3. **Messages follow the project's own commit conventions** from `CLAUDE.md`, including the `Co-Authored-By` trailer.
4. **Each gate surfaces a short summary** of what it committed (subject and files).
5. **An auto-commit is not a checkpoint.** Local and unpushed is reversible; the six checkpoints (§4) are unchanged by it.

Which sessions auto-commit: `/cdd-implement` (§3.4), `/cdd-small-change` (§3.2a) and `/cdd-pre-pr` (§3.6) commit locally; `/cdd-process-pr` (§3.8) commits and pushes; `/cdd-merge-base` (§3.5) produces a merge commit and enforces a clean tree before merging.

### 2.12 The engineering-practices contract (`doc/knowledge_base/engineering-practices.md`)

The project's engineering floor, written down — the artifact that makes Section 1's engineering-standards commitment legible instead of implicit. Each practice is marked one of two ways:

- **Enforced** — a CDD gate guarantees it on every change. If an enforced practice is failing, `/cdd-pre-pr` reports it and the change is not ready.
- **Expected** — the project is committed to the practice but has not yet mechanized it. Each expected practice is tracked as a roadmap task until it becomes enforced. "Expected" is a promise with a due date, not an opt-out.

A practice moves from expected to enforced in the same change that lands its mechanism: the mechanism and the status flip ship together. The gates behind the enforced practices are collected in one place, the check runner (§2.14), which is what makes them verifiable *before* the PR rather than only in CI. The contract is deliberately generic and language-agnostic — it names *what* the floor is and carries placeholders for the project's own commands, never a shipped CI or lint config. The canonical practice set (documentation, tested behaviour, CI, lint & format, dependency hygiene) lives in the template skeleton, `template/doc/knowledge_base/engineering-practices.md`; new practices are added as the project matures, and a row that genuinely does not apply is dropped with a recorded reason, never silently. The contract is resolved when the project starts rather than shipped as a skeleton — on a greenfield project that resolves most rows to *expected*, which is the honest answer: the question is what the project commits to, not what it already has.

### 2.13 Per-task state record (`~/.cdd/handoffs/<repo>/<branch>.state.json`)

A small JSON sibling of the handoff (§2.6) — same directory, same `<branch>` basename, same branch-scoped ephemeral lifecycle as the handoff and the plan file (§2.15) — recording where a task sits in its lifecycle (`stage`), its PR number once one exists, the task's **base branch** (the one branch it was cut from and merges back into), and, append-only, the chain of Claude Code sessions that have worked it, so a session can be found and resumed (`claude --resume <id>`) without grepping shell history.

The base branch encodes the invariant that **every branch has exactly one base**: `/cdd-next-step` records it when it seeds the record, defaulting to the branch then checked out (so gitflow and recursively stacked branches capture their real parent), and it never changes thereafter. `cdd-worktree` (§2.8) cuts the new branch from it; the resume-side commands `/cdd-merge-base` and `/cdd-pre-pr` (§3.5, §3.6) target it. It is an additive, optional field: a record without one — including every record predating the field — falls back to the platform default branch (`origin`'s HEAD, else `main`), so single-integration-branch projects are unaffected and need no configuration.

The record also carries the task's **lane** — which of the two build paths it takes (§3). `/cdd-next-step` writes it once at scoping, on the human's decision, and it never changes thereafter; `cdd-worktree` and `cdd-worktree-resume` (§2.8) route on it. Like the base branch it is an additive, optional field: absent — including on every record predating it, and on every machine whose helper is too old to write it — means the standard lane, which is also what an unrecognised value means. The degrade is deliberately one-directional: a missing marker costs a window, while a marker fabricated by inference could skip a gate.

On an issue-driven task (§3.1) the record also carries the **issue references** the task was sourced from — a list, because one task may close several items, and strings, because what a reference looks like is the tracker's decision (§2.16), not a number CDD can assume. It is read by CDD itself — by `/cdd-pre-pr` (§3.6) for the close lines, and across every record by `/cdd-next-step` when browsing, to hide items already in flight on a task whose branch carries no token — which is why it is a first-class field and not an `x-` extension key. Additive and optional like the base branch and the lane: absent means no references were recorded, and the close line then falls back to the `gh_issue_NN_` branch token. It breaks the pattern the other two set in one way, deliberately — it is **amendable**. A task that turns out to close a second issue is a real case, and each write replaces the whole list, so a late correction needs no second verb. That is safe here precisely because nothing routes on the field: unlike the lane, a change after the fact contradicts no session already launched.

Beside the per-task files, the same directory carries one **machine-local per-repo marker** (`repo.json`) naming the repo's main worktree. It is the only artifact there that is not task-scoped, so it outlives the reap of every task and keeps a repo locatable once its tasks are all merged; it is written by the same helper (and by the bootstrap script for a fresh project), advisory in exactly the same way, and never synced across machines. Its schema lives in `doc/architecture/shell-helpers.md`.

The record is **advisory**: a consumer that finds it missing or stale falls back to inferring state from handoffs, branches, and `gh`, and a writer that finds it missing does not fabricate one (only `/cdd-next-step` seeds it). It syncs across machines: every write also pushes the handoff, the plan file (§2.15) and the record to a per-task ref, which `cdd-worktree-resume` (§2.8) materializes on the picking-up machine — best-effort, so it degrades to purely local when there is no remote to reach. Writes go through the `cdd-state` helper (§2.8), which keeps them atomic and well-formed and no-ops rather than failing the workflow. Each slash command calls it at its own stage transitions. The schema and the stage-to-writer mapping live in `doc/architecture/shell-helpers.md`.

The record also carries an **extension namespace**: any top-level key prefixed `x-` belongs to whatever extends CDD on this project (§2.16), and CDD's own logic never reads one — they are advisory in exactly the way the rest of the record is. The prefix is what keeps the two apart: CDD may add a field of its own at any time, and a reserved namespace means it can never collide with an extension's. Adding an `x-` field takes **no `schema_version` bump** — the same additive path `sessions`, `dir`, `base_branch` and `lane` already took, and for the same reason: the version is a pinned mirror, so bumping it over one new optional field invalidates every record on the machine. The invariant that makes the namespace usable is that **a write of one field never rewrites the rest**: every verb that touches the record assigns the fields it owns and passes every other key through untouched, so an extension's field survives a lifecycle transition written by a CDD that has never heard of it — and so does a field written by a *newer* CDD than the one doing the write. That is a property a refactor could silently lose, so it is pinned by a gate rather than left to review. The writer is `cdd-state set-field` (§2.8); the verb and the exact exit codes live in `doc/architecture/shell-helpers.md`.

The `stage` field is an **open enum in one direction only**. Adding a stage is additive for a *writer* — nothing that never writes the new value changes behaviour — but it is breaking for a *reader* that validates against a closed set, which may reject the whole record rather than the one field it does not recognise. So a consumer should tolerate an unknown stage and degrade to inferring, and a new stage should be added as a plain enum value rather than by bumping `schema_version`: the version is a pinned mirror, and a mismatch invalidates every record on the machine instead of one field of one record.

### 2.14 The check runner

One command that runs every gate the project has, and is the **sole source of the gate sequence**. CI delegates to it, keeping only platform-specific setup in the CI config, and `/cdd-pre-pr` (§3.6) invokes the same command — so "it passed locally" means "it will pass CI", and there is no second list of checks to keep in sync. Adding a gate to the runner is the only way to add one.

This exists for two reasons, and the second is the larger. A project's gates are otherwise written out once in the CI config, once in `CLAUDE.md`, and once in the pre-PR command — three lists that silently drift. And a pre-PR session that runs only *some* of the gates gives a green verdict that guarantees very little, so the rest of the failures surface after the PR is open, which is exactly when they are most expensive.

The runner is **host-direct and degrades gracefully**: it assumes no container and pins no toolchain. **Tool detection is per gate** — each gate records the executable it needs, and a tool that is absent skips *that* gate and nothing else, so a partial toolchain yields a partial verdict rather than none. A gate whose tool is not installed on this host is reported **skipped — loudly, and non-fatally**. It never fails the run over a missing tool, and it never lets a gate pass silently, because a silent skip is worse than either outcome. The cost of that choice is explicit: a host missing a tool gets a *weaker* verdict than CI, not a wrong one, and the skip says so.

One detection flag for the whole run is a defect, not a shortcut, and it is a defect that hides. While the runner needs a single tool the flag and the gate are the same thing, so nothing looks wrong; when a second tool arrives the flag starts suppressing gates that could have run, and the symptom is a *green* verdict rather than a failure. Per-gate detection costs one field per gate and does not have that failure mode. A project may of course make a gate's tool a hard requirement instead; that is a per-project call, not a workflow rule. Skip-and-continue is the right default where gates carry independent optional tools — this repo's `shellcheck` and `jq` are exactly that. The hard requirement is the right call where every gate shares one toolchain, because there a missing tool means *no* gate ran, and skipping onward would report a pass over nothing verified.

The runner is a project artifact, not a shared CDD helper — every project's gates are its own — so CDD ships the practice rather than a script. Its own conventions (registry shape, skip semantics, output grouping) belong in the project's architecture docs; this repo's live in `doc/architecture/overview.md`, with `scripts/ci.sh` as the worked reference for the per-gate registry shape.

### 2.15 Plan files (`~/.cdd/handoffs/<repo>/<branch>.plan.md`)

The contract between the plan session (§3.3) and the implementation session (§3.4). A third branch-scoped sibling of the handoff (§2.6) and the state record (§2.13), sharing their directory, their `<branch>` basename and their ephemeral lifecycle — written by `/cdd-plan` on plan approval, synced on the task ref, reaped when the branch is deleted.

Every task artifact in that directory is a **flat, branch-named sibling** — `<branch>.md`, `<branch>.plan.md`, `<branch>.state.json` — and the plan follows that shape rather than introducing a subdirectory, so one convention describes the whole layout and a reader can tell a task's artifacts apart by suffix alone. The cost is that the plan shares the handoff's `.md` extension, so directory enumeration needs a filter; the rule is that **the shell helpers enumerate that directory in exactly one place**, with `/cdd-next-step`'s prompt-side scan as the one named exception. Mechanics in `doc/architecture/shell-helpers.md`.

Schema:

```markdown
# Plan: <short title>

## Summary
<the bounded digest the session printed at the checkpoint>

## Approach
<one paragraph, then the ordered steps; each step names the files it touches>

## File map
<path -> what changes, plus the distilled fact: file:line + the one-line conclusion>

## External findings
<facts from outside the repo, quoted verbatim, each with its source — or "None">

## Dead ends
<what was tried and why it failed, so it is not re-explored — or "None">

## Open questions resolved
<the handoff's deferred questions, the answers agreed, and any amended `## Requirements` criterion — or "None">

## Doc and roadmap edits
<the doc and roadmap changes the implementation must apply>

## Verification
<which check-runner gates to run, which assertions or tests to add or extend>
```

The plan is written **for the implementing session, not for the human** — the human approved it against the bounded digest printed in chat, which `## Summary` carries verbatim so a fresh session gets orientation before detail. Writing for a machine gives the plan one governing rule:

> **Cite what's in the repo, quote what isn't.** A fact from repo source is cheap for the next session to re-derive, so the plan records a `file:line` pointer plus the one-line conclusion drawn from it. A fact from outside the repo — a web search, vendor documentation, an API's semantics, a version quirk — cannot be recovered without repeating the search, so it is recorded verbatim with its source. Dead ends are the same class: unwritten, they are re-explored at full cost.

The rule is what makes the split safe rather than lossy, and it usefully bounds the plan's length: everything the plan session learned and did not write down dies with it.

Two properties follow from the plan being a file rather than a transcript. It is **human-editable** before implementing — the reason the implementation session is started by hand rather than chained automatically. And it is **durable**: a session that dies after plan approval loses nothing, where before it lost all of the exploration. Unlike the handoff, it is mutable, so a machine picking the task up takes the plan whenever it takes the state record it travels with.

### 2.16 Capability adapters (`.cdd/`)

An executable the project commits that stands in for an external service CDD talks to — a tracker, a forge, a doc system, a notification channel — so that a project whose tracker is Jira or whose forge is GitLab adapts CDD by adding a file rather than by editing a shipped prompt. Every such binding is otherwise hardcoded in a command or a shell helper, and the only way to change one is a local edit to a file CDD ships, which is a fork in slow motion. An adapter is the place to put that adaptation instead.

The namespace is **fixed**: `.cdd/`, one executable per capability, each named for the role it fills, and discovery is simply whether that file exists and is executable. There is no config format, no parser and no registry. The path is fixed rather than project-chosen because an adapter must resolve identically from a prompt and from a shell helper, and a helper has no LLM to read `CLAUDE.md` with — the check runner (§2.14) can live wherever a project likes because every one of its invokers is project-owned: the project's own CI config, and a prompt that reads `CLAUDE.md`. `.cdd/` also mirrors the machine-level `~/.cdd/`, and is not `.claude/`, which belongs to Claude Code.

Every adapter answers one mandatory **`describe`** verb. That is what makes the binding introspectable without inventing a configuration format: the same trick the check runner uses when it makes itself the sole source of its own gate sequence. `describe` is what a conformance gate checks an adapter against, and what an external consumer reads to see which backend a repo is bound to.

Resolution is a ladder — **project (`.cdd/`) → machine (`~/.cdd/adapters/`) → built-in behaviour** — and it **degrades loudly and never fails**. An absent adapter yields today's behaviour with a line saying so — at the point a call is actually made rather than once per session, and unconditionally when an adapter is present but unusable — which is §2.14's per-gate skip rule applied to a different artifact: a weaker binding, announced, rather than a broken session. The machine tier exists because one Jira shop has many repos; its half of an adapter installs machine-globally under §2.8's rules, additive and never pinned per project.

CDD **never stores, reads or proxies a secret**. Authentication is whatever the underlying tool already does, and the committed file carries coordinates only — it may name an environment variable, never contain one.

What an extension is allowed to substitute is bounded by one rule:

> An extension may **replace** anything CDD already treats as external — issues, PRs, CI, notifications, review. It may only **mirror** what CDD treats as in-repo substrate — roadmap, architecture/feature docs, ADRs, handoff.

The rule falls out of invariants already stated rather than out of taste. Issues are an external inbox feeding the roadmap (§3.1), so swapping one tracker for another changes nothing structural. The roadmap is in-repo because the implementation session ticks it in the same commit as the change (§5), `/cdd-pre-pr` reconciles it against the diff (§3.6), and a structural edit to it takes its human gate as a PR — relocating it breaks all three, and offline reads and `git blame` attribution with them. So a roadmap mirrored into a doc backend is fine; a roadmap sourced from one is not.

The one piece that does ship ahead of the adapters is the **`x-` extension namespace** on the per-task state record, so an extension has somewhere to keep what only it knows — a notification's message id, a requirements-tracker link — that is neither derivable from the repo nor re-fetchable from the backend. It is specified in §2.13, which owns the record's schema.

The first capability is live: the **tracker**, with a GitHub reference adapter and a conformance gate; every other binding is still the built-in one. The decision and its reasoning are recorded in `doc/architecture/adr/0007-extend-cdd-through-capability-adapters.md`; the verb contracts, JSON shapes and exit codes are pinned in `doc/architecture/capability-adapters.md`, which is what an adapter author reads.

## 3. Lifecycle

A task flows through CDD in up to six sessions, two of them optional side-loops (`/cdd-merge-base` before the PR, `/cdd-process-pr` after review). The middle of that flow has **two lanes**: the standard lane plans and then implements, and the small-change lane (§3.2a) does both in one session for a task whose finished diff can be stated before any exploration. The lane is chosen once, at scoping; everything before it and everything after it is the same. Each session type has a name, one command, and one job:

| Session              | Command                                       | Runs on                              | May edit (summary; see Section 5)          |
| -------------------- | --------------------------------------------- | ------------------------------------ | ------------------------------------------ |
| **Handoff**          | `/cdd-next-step`                              | main worktree                        | the handoff file only — repo is read-only  |
| **Plan**             | `/cdd-plan`, auto-started by `cdd-worktree <branch>` | feature worktree | the plan file only — repo is read-only |
| **Implementation**   | `/cdd-implement`, started by hand in the same worktree | feature worktree              | code, docs, roadmap                        |
| **Small-change** (lane) | `/cdd-small-change`, auto-started by `cdd-worktree <branch>` in place of Plan + Implementation | feature worktree | code, docs, roadmap                        |
| **Merge** (opt.)     | `/cdd-merge-base`                             | feature worktree                     | merge resolution, docs if needed           |
| **Pre-PR**           | `/cdd-pre-pr`                                 | feature worktree                     | doc reconciliation, approved roadmap edits |
| **PR-review** (opt.) | `/cdd-process-pr`                             | feature worktree                     | review-driven code and replies             |

The plan/implement boundary is an **altitude boundary**, and that is the point of separating them: the handoff answers *what* and *why*, the plan answers *how*, and the code is the thing. Splitting them also means the implementing session's context holds the distilled plan rather than the exploration that produced it — dead ends included. The trade is honest rather than free: the second session re-reads files the first one read, so a net token saving is not guaranteed; the durable wins are the altitude boundary and the plan becoming a real artifact (§2.15). The step between the two sessions is manual by design — it is where the human can read or edit the plan — and it is ceremony, not a checkpoint (§4).

The blanket invariant: **every CDD session is a fresh context doing exactly one job.** This is a rule, not a per-command judgment call — the merge and PR-review sessions get fresh contexts for the same reason the pre-PR session does, even when the previous session's window is still open and would be convenient to reuse.

Three further session types sit outside the per-task lifecycle, each run as a one-shot from a CDD-repo session: **bootstrap** (`/cdd-bootstrap`), **retrofit** (`/cdd-retrofit`), and **quick-create** (`/cdd-quick-create`) — see Section 6 and `doc/features/template.md`. All three operate on a target path and keep the same fresh-context-one-job discipline.

```
                       (on main worktree)
            ┌──────────────────────────────────┐
            │ Handoff session: /cdd-next-step  │
            │                                  │
            │ Read roadmap (or take a task     │
            │ prompt), discuss/scope, clarify  │
            │ cheap requirements, write        │
            │ handoff file.                    │
            └──────────────────────────────────┘
                            │
                            │  handoff file
                            ▼
                       cdd-worktree <branch>
                            │
                            ├────────────────────────────────────────┐
                      standard lane                          small-change lane
                            ▼                                        ▼
                       (on new worktree)                      (on new worktree)
            ┌──────────────────────────────────┐    ┌──────────────────────────────────┐
            │ Plan session: /cdd-plan          │    │ Small-change session:            │
            │                                  │    │ /cdd-small-change                │
            │ Read handoff + roadmap + docs.   │    │                                  │
            │ Explore. Clarify expensive       │    │ Read the thin handoff. Confirm   │
            │ requirements in a clean context. │    │ the task is still small, or take │
            │ Print bounded digest. Human      │    │ the off-ramp to /cdd-plan. State │
            │ approves. Write the plan file.   │    │ the concrete change. Human       │
            │ Stop.                            │    │ approves. Make it. Update docs   │
            └──────────────────────────────────┘    │ and roadmap. Commit.             │
                            │                       └──────────────────────────────────┘
                            │  plan file                             │
                            ▼                                        │
                  human: fresh claude, same worktree                 │
                            │                                        │
                            ▼                                        │
            ┌──────────────────────────────────┐                     │
            │ Implementation session:          │                     │
            │ /cdd-implement                   │                     │
            │                                  │                     │
            │ Read the plan. Targeted re-reads.│                     │
            │ Implement. Update docs and       │                     │
            │ roadmap. Commit.                 │                     │
            └──────────────────────────────────┘                     │
                            │                                        │
                            ├────────────────────────────────────────┘
                            │
                            │  (optional, if main moved)
                            ▼
            ┌──────────────────────────────────┐
            │ Merge session: /cdd-merge-base   │
            │                                  │
            │ Dry-run conflict assessment.     │
            │ Human approves. Merge main into  │
            │ the feature branch. Resolve.     │
            └──────────────────────────────────┘
                            │
                            ▼
            ┌──────────────────────────────────┐
            │ Pre-PR session: /cdd-pre-pr      │
            │                                  │
            │ Run build, format, lint, tests,  │
            │ integration tests. Code review.  │
            │ Reconcile docs and test          │
            │ coverage. Propose roadmap edits. │
            │ Conditionally propose CI         │
            │ improvements.                    │
            └──────────────────────────────────┘
                            │
                            ▼
                     gh pr create + human review
                            │
                            │  (optional, if review left comments)
                            ▼
            ┌────────────────────────────────────┐
            │ PR-review session: /cdd-process-pr │
            │                                    │
            │ Read the PR's review comments.     │
            │ Triage; human approves the plan.   │
            │ Address them, pushing back         │
            │ where warranted. Auto-post         │
            │ replies, commit + push.            │
            │ Back to PR review.                 │
            └────────────────────────────────────┘
                            │
                            ▼
                       gh pr merge (squash)
                            │
                            ▼
                      cdd-worktree-done
                            │
                            ▼
                    back on main, clean
```

### 3.1 Handoff session: `/cdd-next-step` (on main)

Goal: pick what to do next and produce a clean handoff. Three front-ends converge on the same handoff:

- **Roadmap-driven** (no argument): reads the roadmap and the stale-handoff list, proposes candidate tasks, discusses dependencies and ambiguity, and converges on one with the human.
- **Intent-driven** (`/cdd-next-step <task prompt>`): the human has already chosen the task, typically off-roadmap. The session loads context adaptively (the roadmap and doc indexes, then only the docs the task touches), runs an **overlap check** against existing roadmap items, and makes a **roadmap-belonging decision** — whether the new task should become a roadmap item — recording the verdict in the handoff for the implementation session to apply.
- **Issue-driven** (`/cdd-next-step <ref>` — `#123` or a bare integer on the built-in rung — or `issue`/`issues` to browse open items): intent-driven mode with the intent taken from a tracker item, so the tracker is an inbox feeding the roadmap — which remains the source of truth — not a parallel backlog. Several references may be given at once (or multi-selected when browsing), because one task may close several items. The session has no side-effects on the item; the references are threaded forward on the task's **state record** (§2.13), which is what `/cdd-pre-pr` reads to emit one close line per reference, and on GitHub the issues auto-close when the PR merges (§3.6). The `gh_issue_NN_<slug>` branch name survives for a single GitHub-backed numeric reference — durable, readable, and the fallback when the record is unusable — but it is no longer the mechanism, and no reference-encoding scheme is pushed into branch names for the backends it does not fit. The tracker it reads is resolved through §2.16's ladder, and what a reference looks like comes from the resolved adapter rather than from the command; the built-in rung is `gh`, which needs a GitHub `origin` and degrades to a clear message without one.

Before reading any context, the session verifies its checkout is current: if the branch it is standing on is behind its upstream it stops and says so, rather than scoping work from a stale tree where an already-merged task still looks unstarted. Being ahead or diverged is reported and never blocks, and when the remote is unreachable the check is skipped so the session stays usable offline. It never pulls: §5's rule that the handoff session is read-only on the repo holds.

The session clarifies requirements that are cheap to resolve here and explicitly defers harder ones to the **plan session** (§3.3). Two rationales drive this split: context economy — this session's context is spent on cross-phase reasoning, while the plan session's is clean, dedicated to one task, and running in the real worktree — and structure — this session runs on main, which is protected from direct edits, so it cannot edit the roadmap even by accident; desired roadmap edits are recorded in the handoff instead. The split is also what keeps the handoff's `## Requirements` (§2.6) honest: criteria that are cheap to state belong here, and a criterion that is not is a deferred question, not a reason to hold a requirements interview.

Before asking for approval the session prints a **bounded digest** of the handoff in chat — a hard-capped bullet list, one line each — so the human approves against something readable rather than skimming the artifact. The cap is the feature. It ends by writing the handoff file and printing the `cdd-worktree <branch>` command.

### 3.2 Worktree creation

The human closes the handoff session and runs `cdd-worktree <branch>` from the main worktree. The helper creates the worktree and launches Claude Code in it, passing `/cdd-plan` as the initial user message.

Which prompt it passes is decided by a **capability probe**, not a version: the helper checks whether the worktree it just created contains `.claude/commands/cdd-plan.md`. A project not yet retrofitted has no such file, so the helper falls back to the pre-split one-line prompt naming the handoff's `## Implementation prompt` heading (§2.6) — launched in the harness's plan mode, which was that flow's checkpoint — and that project keeps working exactly as before. This is the general rule from §2.8 in its concrete form — the machine-global helper stays compatible with every baseline on the machine, and the per-project artifact carries the switch. The fallback branch is a deprecation seam: it is removed once every project on every machine is retrofitted.

The helper also reads the task's **lane** (§2.13) here, and opens the session on `/cdd-small-change` instead of `/cdd-plan` when the record marks the task small *and* the worktree carries that command. Every other case — no marker, no record, no `jq`, a project that ships no such command, a helper too old to look — leaves `/cdd-plan`, so a lost marker costs a window and can never skip a gate. Routing before the session starts is what keeps each command at one behaviour rather than giving one command a mode.

### 3.2a Small-change lane: `/cdd-small-change` (on the new worktree)

For a task whose finished diff can be stated before any exploration, the plan/implement pair is ceremony: there is nothing to explore, and no reasoning worth carrying between two windows. The small-change lane replaces both sessions with one that takes its own approval of the concrete change and then makes it. Everything around it is unchanged — the handoff, the worktree, the PR, the review round, the teardown — so this shortens the middle of the cycle, never the review.

Which lane a task takes is decided once, by the human, at the end of the handoff session (§3.1, checkpoint 2). `/cdd-next-step` applies one heuristic and recommends:

> If you can state the finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard lane.

Two bounds, and both must hold. **Discovery**: there is nothing to find out — that is the one-sentence test. **Durability**: there is no reasoning worth carrying into the next window, since this lane writes no plan file and only the requirements plus the diff reach `/cdd-pre-pr` and the reviewer. The bar is **not line count**. Qualifying work: ticking a roadmap box; a typo; adding a roadmap phase; adding a small utility script whose behaviour you can state in full; a mechanical rename across a few files. Not qualifying: a three-line change whose consequence you would want reasoned about; a multi-file change you can specify in a sentence but could not justify without explanation.

The session **recommends and the human decides**, in either direction and unconditionally — including declaring small a task the heuristic did not. That is the same posture every other structural choice in CDD takes, and it is safe both ways: a task wrongly declared small takes the off-ramp below, at the cost of one session start, and one wrongly kept standard costs a window. Neither is destructive, which is why the heuristic is allowed to be this short.

The **off-ramp** is what carries that weight. `/cdd-small-change` re-applies the heuristic once it has the handoff in front of it, and if the task is not small it stops, writes nothing, and hands to `/cdd-plan` in the same worktree. A small-change handoff is thin (§2.6) but not deficient: `/cdd-plan` reads `## Requirements` and `## Notes` and never needed an `## Implementation prompt`, so nothing has to be regenerated to escalate.

Otherwise the session states the concrete change file by file, takes approval — this is checkpoint 3 in its lane form (§4) — makes it, updates the docs and the roadmap, runs the check runner whole (§2.14; no per-diff gate selection), commits locally per §2.11, and advances the state record to `implementation_done`. It never passes through `plan_written`, which is a non-event: consumers compare stages by index, so a stage that was never written is simply one they never observe. The routing mechanics live in `doc/architecture/shell-helpers.md`.

### 3.3 Plan session: `/cdd-plan` (on the new worktree)

Reads the handoff and rebuilds its context from the roadmap and the architecture/feature docs. It then **explores** — reading the source it will change, searching the web, consulting vendor and library documentation as the task needs. Exploration is a named step rather than an implied one, because after the split its only output is the plan file: anything this session learns and does not write down is destroyed when it ends.

It surfaces deferred or freshly-discovered open questions, confirms scope, checks its plan against the handoff's `## Requirements`, and prints a **bounded digest** in chat — one short bullet per fixed topic — immediately before asking for approval. That digest exists so the checkpoint stays a real gate: the plan file itself is written for the next session rather than for the human, and asking a human to approve a document written for a machine would weaken the very checkpoint the workflow leans on hardest.

The handoff is immutable (§2.6), so a `## Requirements` criterion the human agrees to amend or drop here is recorded in the plan instead. That record is the channel to `/cdd-pre-pr` (§3.6), which otherwise re-checks the diff against wording nobody stands behind any more and reports the amendment as a miss.

Approval is the load-bearing checkpoint, and it is an **explicit ask** — the session asks the human to approve the plan, the way the handoff session asks. The gate is a workflow rule and has to hold wherever the workflow runs, so it does not lean on an agent harness's plan mode. On approval the session writes the plan file (§2.15) and advances the state record to `plan_written` — the write that pushes the plan onto the task ref — prints the next command, and **stops**. It edits nothing in the repo.

### 3.4 Implementation session: `/cdd-implement` (on the same worktree)

The human opens a fresh Claude Code session in the same worktree and runs `/cdd-implement`. There is no helper for this step and that is deliberate: the manual gap is where the plan file can be read or edited before anything is built.

The session reads the plan, re-reads the files the plan's file map names, implements the task, updates the architecture and feature docs and the roadmap (ticking the completed checkbox; applying pre-approved edits), commits its own changes locally per §2.11, and advances the state record to `implementation_done`. The handoff's `## Requirements` remain its done-test — the one thing that survives both windows and catches a plan that misread the intent.

This session is **unsupervised**: plan approval was the implementation cycle's only checkpoint, and it has already passed. So it carries one hard rule — **if reality contradicts the plan, stop and report; never improvise.** Two cases are expected rather than hypothetical, and are called out explicitly in the command: a `/cdd-merge-base` ran in the (human-paced, possibly overnight) gap and moved everything the plan's `file:line` anchors point at; and the plan file was never materialized on this machine, which an older worktree helper's narrower ref sync can cause. Neither is a licence to rebuild the task from the handoff alone.

### 3.5 Merge session (optional): `/cdd-merge-base`

Run on the feature branch when main has advanced and the feature branch needs to integrate the new state. Two-phase: a **dry run** — identify what main contains that this branch lacks, assess which files conflict and whether the conflicts look mechanical or logical, report, do not merge — then the **merge** itself, asking for clarification mid-resolution if conflicts are non-trivial. This is also where the agent can pull in improvements from main that are useful here without scheduling a roadmap task.

The approval between the two phases is **conditional** (checkpoint 4, §4). On the mechanically-trivial path — clean worktree, zero conflicting files, and nothing flagged by the dry run's scan of the non-conflicting changes — there is no decision for the human to make, so the merge proceeds automatically and the assessment is reported afterwards rather than as a prompt. Anything else stops for approval as before. The trivial path never adopts improvements from main: it is reachable only when the scan flagged none.

### 3.6 Pre-PR session: `/cdd-pre-pr`

A fresh session on the feature branch, started after the implementation session has closed — deliberately, so the implementation session never grades its own homework. It runs the project's check runner (§2.14) — the same command CI runs, so the verdict carries over — code-reviews the diff and checks it against the handoff's `## Requirements` (§2.6), and reconciles four things:

- **Docs**: architecture and feature docs are compared against the actual code and fixed directly; roadmap checkboxes are ticked directly, while structural roadmap edits (add/modify/remove) are proposed to the human for approval before applying.
- **Test coverage**: each behavioural change in the diff either has a test exercising it, or the reason it doesn't is recorded — the recurring guardrail behind §2.12's tested-behaviour row. If the project has no test harness yet, the step notes the untested change and confirms that standing up tests is tracked on the roadmap; it does not invent a framework.
- **CI**: a conditional improvement proposal, only when the change genuinely surfaces a gap the existing CI doesn't cover. The default is silence.
- **Workflow improvements**: a conditional check for something the task revealed about how the project works that no artifact captures — a constraint that belongs in `CLAUDE.md`, a convention applied from inference rather than from the coding standard, a manual step no doc describes. Where it lands is the human's call, asked once with a recommendation: an edit applied now, a roadmap item, or — when it looks general enough for any CDD project — an issue filed against the CDD repo. This is the discovery-time channel behind §1's self-improvement commitment, complementing the review-time route in §3.8 and `/cdd-retrofit` upgrade mode at upgrade time. It judges from the task in front of it — this diff, this session — and never scans earlier PRs; a gap visible only from review feedback belongs to §3.8. Deliberately not a standing log: the discovery lands in machinery that already exists. The default is silence; the step records and never blocks.

Output is a pass/fail/skipped summary across the gates. The session then auto-commits its reconciliation edits locally per §2.11, and ends with an optional, human-gated step to open the PR: a single yes/no question; on approval it derives the title and body and runs `gh pr create`, adding one close line per issue reference recorded on the task's state record (§2.13) so each issue auto-closes on merge. The line itself comes from the resolved tracker (§2.16), which is what makes the close work on a backend whose syntax is not GitHub's; a backend that declares no way to phrase one yields no close lines, said once rather than guessed. With no usable record the session falls back to the `gh_issue_NN` branch token and the single `Closes #NN` it has always produced. `/cdd-pre-pr` never opens a PR without explicit confirmation.

### 3.7 PR review and merge

The PR is opened from §3.6's opt-in step or by the human running `gh pr create` manually. The human reviews (with full Claude assistance if desired, but in a fresh session) and merges. Squash-merge is the default; the worktree helper handles squash-merged branches as a first-class case.

### 3.8 PR-review session (optional): `/cdd-process-pr`

Run on the feature branch when a review has left comments. A fresh session reads the open PR's unresolved review comments and triages them: change-request, question, nit, discussion, or workflow-gap — the last being a comment that points at the project's own substrate rather than this diff, routed, with the human choosing the destination from a recommendation, into an edit folded into this PR, a roadmap item, or a CDD-repo issue. That route is the review-time arm of §1's self-improvement commitment: the review is where a gap becomes visible from outside the session that caused it. It presents the triage plan — the session's single checkpoint — then implements the change-requests and nits, answers the questions, pushes back in the reply on any change-request it judges wrong or risky rather than implementing it blindly, and commits + pushes to the open PR branch (the auto-push exception of §2.11; rationale in §4.1). Review threads are never resolved by the command — that is the human's call during re-review. The loop can repeat across review rounds.

### 3.9 Worktree teardown

The human runs `cdd-worktree-done` from the feature worktree (§2.8), ending back on main with the branch resolved and the handoff cleaned up.

## 4. Human checkpoints

Six explicit checkpoints. The human is also free to interject at any other point.

1. **Task selection** (end of `/cdd-next-step`): the human chooses among proposed candidates.
2. **Handoff approval** (end of `/cdd-next-step`): the human approves the drafted implementation prompt and notes.
3. **Approval of the work** (end of the plan session, or mid-session on the small-change lane): the human approves the plan before any file is written — or, on the small-change lane where there is no plan, the concrete change itself, stated file by file, before the first edit.
4. **Merge-base approval** (between dry run and merge in `/cdd-merge-base`) — *conditional*: the human approves after seeing conflict complexity, whenever there is complexity to see. Skipped only on the mechanically-trivial path (below).
5. **Roadmap edit approval** (during `/cdd-pre-pr`): the human approves proposed add/modify/remove edits before they are applied.
6. **PR merge** (after `/cdd-pre-pr`): standard GitHub PR review and merge.

These six are the gates. The agent should never proceed past a gate without explicit human confirmation.

Splitting the implementation cycle into a plan session and an implementation session (§3.3, §3.4) does not change this count either. Checkpoint 3 does not move: it is still plan approval, and the plan file is written *because* it was approved. The manual step between the two sessions — the human opening a fresh session and running `/cdd-implement` — is ceremony, and a place to read or edit the plan, but it is not a gate: nothing waits on a decision there.

The **small-change lane (§3.2a) does not change this count either, and changes only checkpoint 3's form**. Checkpoints 1, 2, 4, 5 and 6 fire exactly as they do on the standard lane: `/cdd-next-step` and `/cdd-pre-pr` both still run, the PR is still opened and still reviewed. Checkpoint 2 in fact does one more thing — it is where the lane itself is chosen. Checkpoint 3 still fires, still before anything is written, and is still an explicit ask; what changes is what the human is approving, a stated diff rather than a plan file, because on that lane there is no plan file to approve. Say this plainly, because the next reader will otherwise read the lane as erosion: a lane that skipped a checkpoint would be a different proposal, and was not this one. Reasoning in `doc/architecture/adr/0006-small-change-lane.md` (CDD repo).

The auto-commits some sessions make at their gates (§2.11) do not change this count. A local commit with no push is reversible from git history, so it adds no checkpoint and removes none — it is not a seventh gate. The only gate that pushes is `/cdd-process-pr`, and its single up-front checkpoint is described in §4.1.

Checkpoint 4's conditionality does not change the count either. It fires whenever human input is actually needed and is skipped on one path only, defined by three mechanical facts and never by the agent's own judgement: the worktree was clean, `git merge-tree` reported **zero** conflicting files, and the dry run's scan of the non-conflicting changes flagged nothing to adopt. On that path the human is confirming a merge git has already proven textually clean — an approval that carries no decision, which §1's "automate everything except decisions" calls a gap rather than a gate. The same argument §2.11 makes for auto-commits applies: the merge is local and unpushed, and fully revertable (`git merge --abort` mid-merge, `git reset --hard ORIG_HEAD` after), so this defers a gate rather than removing one — the human still sees everything at the PR (checkpoint 6). The post-merge build and tests run on the trivial path exactly as on the approved one, and a failure there is reported with the revert offered, never swallowed. The residual risk is real and worth stating: **a zero-conflict merge can still be a semantic break** — two sides that never touch the same lines can still contradict each other — and the two criteria that would catch it, the scan and the tests, only catch what the scan notices and what the tests cover. The rule is deliberately strict for that reason: a conflict the agent judges "mechanical" is exactly the judgement this checkpoint exists to check, so no auto-resolve tier exists, and there is no flag to widen the path. Reasoning in `doc/architecture/adr/0004-conditional-merge-base-approval.md` (CDD repo).

### 4.1 The `/cdd-process-pr` exception

In `/cdd-process-pr` (Section 3.8) the gate sits up front rather than on each action: the human approves the triage plan (which comments will be addressed, and how) before any file is edited, and that single approval authorizes everything that follows — the edits, the in-thread replies, the commit, and the push. There is no second confirmation before the GitHub-side actions. This is a conscious trade-off, not an oversight: in a single-user, fast review-iteration loop the PR is already open, the human is actively reviewing it, and every change the command makes is visible in the PR diff and revertable from git history. Re-confirming each reply or push after the plan was already approved would defeat the purpose of a tight address-and-re-review cycle. One thing does fall outside that authorization: where a triaged workflow gap is routed — folded into this PR, a roadmap item, or an issue on the CDD repo — is asked once, with a recommendation, because the approved plan settles which comments get addressed, not where a gap that outlives this diff should land.

Human-in-the-loop judgment is preserved where it matters: the plan is approved before execution, and the command pushes back on change-requests it judges wrong rather than implementing them blindly. What is dropped is only repeated confirmation of the outbound actions that execute the approved plan. Review threads are also never auto-resolved — the human resolves them during re-review.

## 5. Edit rules: who edits what, when

The matrix below resolves any ambiguity about which session is allowed to touch which artifact. Columns are the session types named in Section 3.

| Artifact                | Handoff      | Plan            | Small-change       | Implement          | Merge         | Pre-PR                 | PR-review              |
| ----------------------- | ------------ | --------------- | ------------------ | ------------------ | ------------- | ---------------------- | ---------------------- |
| Roadmap (tick)          | no           | no              | yes                | yes                | no            | yes                    | yes if review-driven   |
| Roadmap (add/mod/rm)    | no           | no              | yes (pre-approved) | yes (pre-approved) | no            | yes (human-approved)   | no                     |
| Architecture docs       | no           | no              | yes                | yes                | yes if needed | yes (reconcile)        | yes if review-driven   |
| Feature docs            | no           | no              | yes                | yes                | yes if needed | yes (reconcile)        | yes if review-driven   |
| CLAUDE.md               | no           | no              | yes if needed      | yes if needed      | no            | yes (reconcile)        | yes if review-driven   |
| README.md               | no           | no              | yes if needed      | yes if needed      | no            | yes (reconcile)        | yes if review-driven   |
| Knowledge base (other)  | no           | no              | yes if needed      | yes if needed      | no            | yes if needed          | yes if review-driven   |
| Code                    | no           | no              | yes                | yes                | yes (merge)   | yes (review-driven)    | yes (review-driven)    |
| Handoff file            | yes (write)  | no (read-only)  | no (read-only)     | no (read-only)     | no            | no                     | no                     |
| Plan file               | no           | yes (write)     | no (never written) | no (read-only)     | no            | no                     | no                     |
| CI config               | no           | no              | yes if in scope    | yes if in scope    | no            | yes (human-approved)   | yes if review-driven   |

The small-change column is the implementation column: the two sessions differ in what authorizes them, not in what they may touch. The handoff and plan sessions are both read-only on the repo, and each produces exactly one artifact — the handoff file and the plan file respectively. This keeps their jobs narrow: read, discuss, write the one file. Everything else happens in the implementing and review-side sessions. "Review-driven" in the PR-review column means the edit was requested by a reviewer and covered by the approved triage plan (Section 3.8); the PR-review session initiates no edits of its own.

## 6. Known gaps and deferred design

Three areas that were out of scope for the first version of the template are now addressed by dedicated CDD-repo-only commands (§2.7), described in full in `doc/features/template.md`:

- **Greenfield bootstrap** → `/cdd-bootstrap`: a guided discovery session that produces the project overview (§2.5), a filled-in `CLAUDE.md`, a resolved engineering-practices contract (§2.12), and a real roadmap — each confirmed with the user — then scaffolds the project in a single render, with no pre-filled survey phase because the docs were written through discovery. The manual fallback is `tools/bootstrap-cdd-project.sh` (recipe in `template/BOOTSTRAP.md`), which leaves the template's stubs and pre-filled bootstrap phase to be worked through instead.
- **Lightweight one-off deliverables** → `/cdd-quick-create`: a script-plus-README deliverable with none of the project substrate — no roadmap, no `doc/` tree, no per-task lifecycle. Whether a task is a *deliverable* or a *project* is decided by a shared scope-triage heuristic that `/cdd-quick-create` and `/cdd-bootstrap` both apply, each offering an off-ramp to the other when the signals point the other way (heuristic and off-ramps in `doc/features/template.md`); as with every structural choice in CDD, the command surfaces the signals and recommends — the human decides.
- **Adapting an existing project** → `/cdd-retrofit`: auto-detects *install* mode (files-only template install, collisions merged interactively per file, the codebase survey deferred to the template roadmap's pre-filled bootstrap phase) vs *upgrade* mode (a three-way comparison against the baseline marker, §2.10, that applies template improvements, carries template file renames across as renames rather than as a deletion plus an addition, preserves local customizations, and surfaces general-looking local changes as candidates to upstream into CDD — the upgrade-time one of the three recurring channels behind Section 1's self-improvement commitment; §3.6's improvement check is the discovery-time one and §3.8's workflow-gap route the review-time one). Every change to a project file is approved per file; the checkpoints of Section 4 apply in spirit. Its writes are isolated on a dedicated branch reviewed via a normal PR, and the real cost of a first-time retrofit — the first few doc-reconciliation PRs that force the docs to reflect reality — is deliberately deferred to the project's own first sessions rather than the retrofit session. The cost analysis and reconciliation guidance live in `doc/features/template.md`.

Still deferred:

**Parallel-merge structure.** When two worktrees land in sequence, the second needs to integrate the first. Today this is partly automated (`/cdd-merge-base` covers it) and partly manual (the human decides when to trigger). A more structured approach, perhaps with a "second worktree must re-run pre-pr after merge-base", may be warranted once parallel work is common. The invariant is clear: a feature branch must integrate main and re-pass pre-pr before it's ready to merge.

**Template opinionation per project type.** The current template encodes the workflow, but the project-specific bits (build commands, language constraints, module layout) are placeholders. Different project archetypes (firmware, web app, library, data pipeline) probably want different opinionated defaults for those placeholders. Worth deriving from real usage rather than guessing up front.

**Versioning, deprecation and fleet migration.** §2.8's rule — machine-global artifacts stay backward-compatible and capability-probe, the per-project artifact carries the switch — makes a mixed fleet *safe*, but there is no mechanism behind it. There is no way to announce a path as deprecated and remove it on a defined signal; no handshake by which a project states which helper version it needs or a helper reports what it supports, so skew in the direction a probe cannot cover is caught only by hand-written one-off warnings; and no place recording an upgrade's ordering constraints (consumer first, then global helpers, then projects), which today is derived per change and then lost. Per-project migration is not the gap — `/cdd-retrofit` does that job. The missing layer is the fleet above it.

## 7. The template

The template ships as a directory (`template/`) copied into a new project root by `tools/bootstrap-cdd-project.sh`: the `CLAUDE.md` skeleton, the seven lifecycle commands, the doc skeletons, `.claude/settings.json`, and the baseline marker written at render time. The full contents are enumerated in `doc/features/template.md`; the bootstrapped tree layout and the bootstrap procedure — including the one-time helper install — are in `template/BOOTSTRAP.md`. The bootstrapped tree ships no `tools/` directory: the shell helpers are machine-global installs (§2.8), not per-project files. `template/BOOTSTRAP.md` itself is meta-documentation and is not copied into the bootstrapped project.

### 7.1 The CDD repo as its own project

The CDD repo is itself a CDD project and uses CDD on itself: the template under `template/` is content the project ships, distinct from the repo's own scaffolding at the root. This meta-pattern is deliberate dogfooding — the cleanest available demonstration of CDD's value; anything awkward about applying CDD to its own evolution is a real bug in the workflow. The two-layer structure, the drift guard between `./.claude/commands/` and `template/.claude/commands/`, and this document's own location are described in `doc/architecture/overview.md`. Downstream projects do not get a copy of this process doc; the template is self-sufficient for users who don't need the philosophy.

## 8. Adapting to a team

The workflow as described assumes a single human in the loop. A few adjustments anticipated for team use, not yet designed:

- Handoff files would need to live somewhere shared (repo-tracked under `.handoffs/`, or a shared filesystem location, or an issue tracker). Branch-keyed naming still works.
- Task selection in `/cdd-next-step` needs visibility into others' in-flight worktrees to avoid stomping. The worktree-list command would need to query a shared source.
- PR review remains a human gate, but the team needs a convention on who reviews what; the agent's PR-review pass becomes one input among several.
- Roadmap edits, especially structural ones, need a team approval mechanism beyond "the human running the session approves." A lightweight rule: structural edits go through a PR against the roadmap itself.

These extensions are tractable but deserve their own design pass once single-user usage is solid.
