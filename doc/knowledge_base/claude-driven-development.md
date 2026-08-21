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

**The workflow improves itself.** CDD treats its own substrate — `CLAUDE.md`, the commands, the CI and test scaffolding, the docs, the conventions — as a product under continuous revision. When a session discovers a better way to work (a constraint that should have been in `CLAUDE.md`, a check the pre-PR gate should run, a convention worth adopting), the improvement does not evaporate at session end: it is routed into the project's own roadmap or conventions as a tracked change, and an improvement general enough to help any project is surfaced as a candidate to upstream into CDD itself. Three recurring channels carry this: the improvement check in the pre-PR session (§3.5), which catches it at discovery time; the workflow-gap route in the PR-review session (§3.7), which catches what a reviewer sees from outside the session that caused it; and `/cdd-retrofit` upgrade mode, which catches it at upgrade time. A recurring friction that no artifact captures is a gap, the same way a recurring manual step is.

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
3. **Inline annotations stay terse.** Tick the box; annotate only what no other artifact (commit, PR, docs) will carry — a deferred sub-item, a surprising caveat, a scope change. One short clause, not a restatement of the work. A completed item reads like a PR title or barely more: enough for a reader to place the task in the roadmap's arc, with the fine-grained detail left to the PR description, the ADRs, and the docs — which the same change updates anyway. The bar is stated in full, with an example, under "Annotation conventions" in the roadmap itself, so the session applying an edit reads it in the file it is editing.

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

The contract between the handoff session and the implementation session. Lives outside the repo, namespaced by repo so multiple CDD projects don't collide; branch-scoped and ephemeral — created by `/cdd-next-step`, consumed by the first prompt of the implementation session, deleted when the branch is deleted. A sibling **state record** (`<branch>.state.json`) is seeded beside it and shares its lifecycle — see §2.13.

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

The implementation prompt is self-contained: it includes only context the implementation session cannot recover from CLAUDE.md, the roadmap, or the architecture docs. Restating project conventions is forbidden; those are inferable from the repo. Open questions deferred to the implementation session are listed in Notes so it can address them up front rather than mid-plan.

### 2.7 Slash commands (`.claude/commands/`)

Project-level Claude Code slash commands. They are declarative — they describe what to do, not how to orchestrate it; orchestration (worktree creation, branch lifecycle) lives in the shell helpers (§2.8). CDD ships four commands in the per-task lifecycle:

- `/cdd-next-step`, exploratory session, run on main, produces a handoff.
- `/cdd-pre-pr`, verification session, run on the feature branch, runs the check runner (§2.14) and reconciles docs.
- `/cdd-merge-base`, side-loop, run on a feature branch when main has advanced: conflict assessment, then merge.
- `/cdd-process-pr`, side-loop, run on a feature branch after the PR is opened and reviewed: reads the review comments, addresses them, posts replies, commits + pushes. (See §4.1 for the deliberate checkpoint exception it carries.)

Three further commands — `/cdd-bootstrap` (greenfield setup), `/cdd-retrofit` (install or upgrade CDD on an existing project), and `/cdd-quick-create` (lightweight one-off deliverable) — exist in the CDD repo only and are deliberately not shipped in the template: each operates *on* a target from a CDD-repo session, so downstream projects have no use for a copy. This justified one-sided drift is recorded in `scripts/command-drift-whitelist.txt`. The commands are described in `doc/features/template.md`; their place in the workflow is in Section 6.

### 2.8 The worktree shell helper (`cdd-worktree`)

A single, project-independent bash helper provides four commands — the same script for every CDD project, with everything project-specific (repository name, default branch, handoff directory) derived at runtime:

- `cdd-worktree <branch>`, creates a worktree for `<branch>` and launches Claude Code in plan mode in it, with the suggested first prompt already submitted. Requires a handoff file to exist. It cuts the new branch from the task's recorded base branch (§2.13), falling back to the default branch when none was recorded. It runs from the main worktree — the guard is "not a linked worktree", so a project whose main worktree sits on a non-default integration branch (a gitflow `develop`) is fine.
- `cdd-worktree-done`, run from a feature worktree once the PR has landed or the branch is being abandoned: returns to the default branch, removes the worktree, resolves the branch, and deletes the handoff — and its sibling state record (§2.13) — iff the branch was deleted.
- `cdd-worktree-list`, lists active handoffs with worktree/branch/PR status, highlighting stale entries.
- `cdd-worktree-gc [--force]`, reaps the artifacts of **finished** tasks — the local handoff, the state record (§2.13), and the synced per-task ref (§2.13) — for any task whose PR has merged. It is the backstop for `cdd-worktree-done` never running, its ref cleanup failing offline, or a task resumed on several machines leaving materialized copies behind on all but the one where `done` ran. Deliberately conservative: it reaps only merged tasks (a merged PR is the sole trustworthy "done" signal — a scoped-but-unstarted task's handoff and ref exist *before* its branch does, so ref/branch presence alone cannot tell the two apart), and it is dry-run unless `--force`.
- `cdd-worktree-resume [<branch>]`, picks up a task started on another machine that has only a clone of the repo: recreates a worktree tracking an **existing remote branch**, ready for a resume-side command (`/cdd-process-pr`, `/cdd-merge-base`, `/cdd-pre-pr`); with no argument it lists the resumable remote branches. If the originating machine synced them, it also fetches and materializes the handoff (§2.6) and state record (§2.13) from a per-task ref before it finishes — advisory and best-effort, so a task with no synced ref resumes exactly as before (the resume-side commands read PR/branch state from `git`/`gh`, not the handoff). The sync mechanics live in `doc/architecture/shell-helpers.md`.

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
2. **Auto-commits are local — no push.** The sole exception is `/cdd-process-pr` (§3.7), the one auto-push gate.
3. **Messages follow the project's own commit conventions** from `CLAUDE.md`, including the `Co-Authored-By` trailer.
4. **Each gate surfaces a short summary** of what it committed (subject and files).
5. **An auto-commit is not a checkpoint.** Local and unpushed is reversible; the six checkpoints (§4) are unchanged by it.

Which sessions auto-commit: the implementation session (§3.3) and `/cdd-pre-pr` (§3.5) commit locally; `/cdd-process-pr` (§3.7) commits and pushes; `/cdd-merge-base` (§3.4) produces a merge commit and enforces a clean tree before merging.

### 2.12 The engineering-practices contract (`doc/knowledge_base/engineering-practices.md`)

The project's engineering floor, written down — the artifact that makes Section 1's engineering-standards commitment legible instead of implicit. Each practice is marked one of two ways:

- **Enforced** — a CDD gate guarantees it on every change. If an enforced practice is failing, `/cdd-pre-pr` reports it and the change is not ready.
- **Expected** — the project is committed to the practice but has not yet mechanized it. Each expected practice is tracked as a roadmap task until it becomes enforced. "Expected" is a promise with a due date, not an opt-out.

A practice moves from expected to enforced in the same change that lands its mechanism: the mechanism and the status flip ship together. The gates behind the enforced practices are collected in one place, the check runner (§2.14), which is what makes them verifiable *before* the PR rather than only in CI. The contract is deliberately generic and language-agnostic — it names *what* the floor is and carries placeholders for the project's own commands, never a shipped CI or lint config. The canonical practice set (documentation, tested behaviour, CI, lint & format, dependency hygiene) lives in the template skeleton, `template/doc/knowledge_base/engineering-practices.md`; new practices are added as the project matures, and a row that genuinely does not apply is dropped with a recorded reason, never silently. The contract is resolved when the project starts rather than shipped as a skeleton — on a greenfield project that resolves most rows to *expected*, which is the honest answer: the question is what the project commits to, not what it already has.

### 2.13 Per-task state record (`~/.cdd/handoffs/<repo>/<branch>.state.json`)

A small JSON sibling of the handoff (§2.6) — same directory, same `<branch>` basename, same branch-scoped ephemeral lifecycle — recording where a task sits in its lifecycle (`stage`), its PR number once one exists, the task's **base branch** (the one branch it was cut from and merges back into), and, append-only, the chain of Claude Code sessions that have worked it, so a session can be found and resumed (`claude --resume <id>`) without grepping shell history.

The base branch encodes the invariant that **every branch has exactly one base**: `/cdd-next-step` records it when it seeds the record, defaulting to the branch then checked out (so gitflow and recursively stacked branches capture their real parent), and it never changes thereafter. `cdd-worktree` (§2.8) cuts the new branch from it; the resume-side commands `/cdd-merge-base` and `/cdd-pre-pr` (§3.4, §3.5) target it. It is an additive, optional field: a record without one — including every record predating the field — falls back to the platform default branch (`origin`'s HEAD, else `main`), so single-integration-branch projects are unaffected and need no configuration.

Beside the per-task files, the same directory carries one **machine-local per-repo marker** (`repo.json`) naming the repo's main worktree. It is the only artifact there that is not task-scoped, so it outlives the reap of every task and keeps a repo locatable once its tasks are all merged; it is written by the same helper (and by the bootstrap script for a fresh project), advisory in exactly the same way, and never synced across machines. Its schema lives in `doc/architecture/shell-helpers.md`.

The record is **advisory**: a consumer that finds it missing or stale falls back to inferring state from handoffs, branches, and `gh`, and a writer that finds it missing does not fabricate one (only `/cdd-next-step` seeds it). It syncs across machines: every write also pushes the handoff and record to a per-task ref, which `cdd-worktree-resume` (§2.8) materializes on the picking-up machine — best-effort, so it degrades to purely local when there is no remote to reach. Writes go through the `cdd-state` helper (§2.8), which keeps them atomic and well-formed and no-ops rather than failing the workflow. The slash commands call it at their stage transitions; the implementation session's calls are driven by a standing instruction in the handoff (§3.3). The schema and the stage-to-writer mapping live in `doc/architecture/shell-helpers.md`.

### 2.14 The check runner

One command that runs every gate the project has, and is the **sole source of the gate sequence**. CI delegates to it, keeping only platform-specific setup in the CI config, and `/cdd-pre-pr` (§3.5) invokes the same command — so "it passed locally" means "it will pass CI", and there is no second list of checks to keep in sync. Adding a gate to the runner is the only way to add one.

This exists for two reasons, and the second is the larger. A project's gates are otherwise written out once in the CI config, once in `CLAUDE.md`, and once in the pre-PR command — three lists that silently drift. And a pre-PR session that runs only *some* of the gates gives a green verdict that guarantees very little, so the rest of the failures surface after the PR is open, which is exactly when they are most expensive.

The runner is **host-direct and degrades gracefully**: it assumes no container and pins no toolchain. **Tool detection is per gate** — each gate records the executable it needs, and a tool that is absent skips *that* gate and nothing else, so a partial toolchain yields a partial verdict rather than none. A gate whose tool is not installed on this host is reported **skipped — loudly, and non-fatally**. It never fails the run over a missing tool, and it never lets a gate pass silently, because a silent skip is worse than either outcome. The cost of that choice is explicit: a host missing a tool gets a *weaker* verdict than CI, not a wrong one, and the skip says so.

One detection flag for the whole run is a defect, not a shortcut, and it is a defect that hides. While the runner needs a single tool the flag and the gate are the same thing, so nothing looks wrong; when a second tool arrives the flag starts suppressing gates that could have run, and the symptom is a *green* verdict rather than a failure. Per-gate detection costs one field per gate and does not have that failure mode. A project may of course make a gate's tool a hard requirement instead; that is a per-project call, not a workflow rule. Skip-and-continue is the right default where gates carry independent optional tools — this repo's `shellcheck` and `jq` are exactly that. The hard requirement is the right call where every gate shares one toolchain, because there a missing tool means *no* gate ran, and skipping onward would report a pass over nothing verified.

The runner is a project artifact, not a shared CDD helper — every project's gates are its own — so CDD ships the practice rather than a script. Its own conventions (registry shape, skip semantics, output grouping) belong in the project's architecture docs; this repo's live in `doc/architecture/overview.md`, with `scripts/ci.sh` as the worked reference for the per-gate registry shape.

## 3. Lifecycle

A task flows through CDD in up to five sessions, two of them optional side-loops (`/cdd-merge-base` before the PR, `/cdd-process-pr` after review). Each session type has a name, one command, and one job:

| Session              | Command                                       | Runs on                              | May edit (summary; see Section 5)          |
| -------------------- | --------------------------------------------- | ------------------------------------ | ------------------------------------------ |
| **Handoff**          | `/cdd-next-step`                              | main worktree                        | the handoff file only — repo is read-only  |
| **Implementation**   | auto-started by `cdd-worktree <branch>`    | feature worktree, opens in plan mode | code, docs, roadmap                        |
| **Merge** (opt.)     | `/cdd-merge-base`                             | feature worktree                     | merge resolution, docs if needed           |
| **Pre-PR**           | `/cdd-pre-pr`                                 | feature worktree                     | doc reconciliation, approved roadmap edits |
| **PR-review** (opt.) | `/cdd-process-pr`                             | feature worktree                     | review-driven code and replies             |

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
- **Issue-driven** (`/cdd-next-step #123`, a bare integer, or `issue`/`issues` to browse open issues): intent-driven mode with the intent taken from a GitHub issue, so issues are an inbox feeding the roadmap — which remains the source of truth — not a parallel backlog. The session has no side-effects on the issue; the issue number is threaded forward solely through the branch name (`gh_issue_NN_<slug>`), and the issue auto-closes when the PR merges (§3.5). Needs `gh` and a GitHub `origin`; degrades to a clear message without them.

The session clarifies requirements that are cheap to resolve here and explicitly defers harder ones to the implementation session. Two rationales drive this split: context economy — this session's context is spent on cross-phase reasoning, while the implementation session's is clean and dedicated to one task — and structure — this session runs on main, which is protected from direct edits, so it cannot edit the roadmap even by accident; desired roadmap edits are recorded in the handoff instead. It ends by writing the handoff file and printing the `cdd-worktree <branch>` command.

### 3.2 Worktree creation

The human closes the handoff session and runs `cdd-worktree <branch>` from the main worktree. The helper creates the worktree and launches Claude Code in plan mode in it, passing the one-line first prompt (`Read <handoff path> and follow the Implementation prompt.`) as the initial user message.

### 3.3 Implementation session (on the new worktree)

Opens in plan mode, reads the handoff, and rebuilds its context from CLAUDE.md, the roadmap, and the architecture/feature docs. It surfaces deferred or freshly-discovered open questions, confirms scope, and presents a plan. Plan mode is the load-bearing checkpoint: the agent cannot modify files until the human approves. Once the plan is approved, the session implements the task, updates the architecture and feature docs and the roadmap (ticking the completed checkbox; applying pre-approved edits), and commits its own changes locally per §2.11. Because this session has no command file, the commit and its two state-record updates (`plan_approved` on approval, `implementation_done` after the commit) are reinforced by a standing instruction in the handoff that `/cdd-next-step` generates.

### 3.4 Merge session (optional): `/cdd-merge-base`

Run on the feature branch when main has advanced and the feature branch needs to integrate the new state. Two-phase: a **dry run** — identify what main contains that this branch lacks, assess which files conflict and whether the conflicts look mechanical or logical, report, do not merge — then the **merge** itself, asking for clarification mid-resolution if conflicts are non-trivial. This is also where the agent can pull in improvements from main that are useful here without scheduling a roadmap task.

The approval between the two phases is **conditional** (checkpoint 4, §4). On the mechanically-trivial path — clean worktree, zero conflicting files, and nothing flagged by the dry run's scan of the non-conflicting changes — there is no decision for the human to make, so the merge proceeds automatically and the assessment is reported afterwards rather than as a prompt. Anything else stops for approval as before. The trivial path never adopts improvements from main: it is reachable only when the scan flagged none.

### 3.5 Pre-PR session: `/cdd-pre-pr`

A fresh session on the feature branch, started after the implementation session has closed — deliberately, so the implementation session never grades its own homework. It runs the project's check runner (§2.14) — the same command CI runs, so the verdict carries over — code-reviews the diff, and reconciles four things:

- **Docs**: architecture and feature docs are compared against the actual code and fixed directly; roadmap checkboxes are ticked directly, while structural roadmap edits (add/modify/remove) are proposed to the human for approval before applying.
- **Test coverage**: each behavioural change in the diff either has a test exercising it, or the reason it doesn't is recorded — the recurring guardrail behind §2.12's tested-behaviour row. If the project has no test harness yet, the step notes the untested change and confirms that standing up tests is tracked on the roadmap; it does not invent a framework.
- **CI**: a conditional improvement proposal, only when the change genuinely surfaces a gap the existing CI doesn't cover. The default is silence.
- **Workflow improvements**: a conditional check for something the task revealed about how the project works that no artifact captures — a constraint that belongs in `CLAUDE.md`, a convention applied from inference rather than from the coding standard, a manual step no doc describes. Where it lands is the human's call, asked once with a recommendation: an edit applied now, a roadmap item, or — when it looks general enough for any CDD project — an issue filed against the CDD repo. This is the discovery-time channel behind §1's self-improvement commitment, complementing the review-time route in §3.7 and `/cdd-retrofit` upgrade mode at upgrade time. It judges from the task in front of it — this diff, this session — and never scans earlier PRs; a gap visible only from review feedback belongs to §3.7. Deliberately not a standing log: the discovery lands in machinery that already exists. The default is silence; the step records and never blocks.

Output is a pass/fail/skipped summary across the gates. The session then auto-commits its reconciliation edits locally per §2.11, and ends with an optional, human-gated step to open the PR: a single yes/no question; on approval it derives the title and body and runs `gh pr create`, adding a `Closes #NN` line when the branch carries the `gh_issue_NN` token so the issue auto-closes on merge. `/cdd-pre-pr` never opens a PR without explicit confirmation.

### 3.6 PR review and merge

The PR is opened from §3.5's opt-in step or by the human running `gh pr create` manually. The human reviews (with full Claude assistance if desired, but in a fresh session) and merges. Squash-merge is the default; the worktree helper handles squash-merged branches as a first-class case.

### 3.7 PR-review session (optional): `/cdd-process-pr`

Run on the feature branch when a review has left comments. A fresh session reads the open PR's unresolved review comments and triages them: change-request, question, nit, discussion, or workflow-gap — the last being a comment that points at the project's own substrate rather than this diff, routed, with the human choosing the destination from a recommendation, into an edit folded into this PR, a roadmap item, or a CDD-repo issue. That route is the review-time arm of §1's self-improvement commitment: the review is where a gap becomes visible from outside the session that caused it. It presents the triage plan — the session's single checkpoint — then implements the change-requests and nits, answers the questions, pushes back in the reply on any change-request it judges wrong or risky rather than implementing it blindly, and commits + pushes to the open PR branch (the auto-push exception of §2.11; rationale in §4.1). Review threads are never resolved by the command — that is the human's call during re-review. The loop can repeat across review rounds.

### 3.8 Worktree teardown

The human runs `cdd-worktree-done` from the feature worktree (§2.8), ending back on main with the branch resolved and the handoff cleaned up.

## 4. Human checkpoints

Six explicit checkpoints. The human is also free to interject at any other point.

1. **Task selection** (end of `/cdd-next-step`): the human chooses among proposed candidates.
2. **Handoff approval** (end of `/cdd-next-step`): the human approves the drafted implementation prompt and notes.
3. **Plan approval** (start of implementation session, plan mode): the human approves the plan before any file is written.
4. **Merge-base approval** (between dry run and merge in `/cdd-merge-base`) — *conditional*: the human approves after seeing conflict complexity, whenever there is complexity to see. Skipped only on the mechanically-trivial path (below).
5. **Roadmap edit approval** (during `/cdd-pre-pr`): the human approves proposed add/modify/remove edits before they are applied.
6. **PR merge** (after `/cdd-pre-pr`): standard GitHub PR review and merge.

These six are the gates. The agent should never proceed past a gate without explicit human confirmation.

The auto-commits some sessions make at their gates (§2.11) do not change this count. A local commit with no push is reversible from git history, so it adds no checkpoint and removes none — it is not a seventh gate. The only gate that pushes is `/cdd-process-pr`, and its single up-front checkpoint is described in §4.1.

Checkpoint 4's conditionality does not change the count either. It fires whenever human input is actually needed and is skipped on one path only, defined by three mechanical facts and never by the agent's own judgement: the worktree was clean, `git merge-tree` reported **zero** conflicting files, and the dry run's scan of the non-conflicting changes flagged nothing to adopt. On that path the human is confirming a merge git has already proven textually clean — an approval that carries no decision, which §1's "automate everything except decisions" calls a gap rather than a gate. The same argument §2.11 makes for auto-commits applies: the merge is local and unpushed, and fully revertable (`git merge --abort` mid-merge, `git reset --hard ORIG_HEAD` after), so this defers a gate rather than removing one — the human still sees everything at the PR (checkpoint 6). The post-merge build and tests run on the trivial path exactly as on the approved one, and a failure there is reported with the revert offered, never swallowed. The residual risk is real and worth stating: **a zero-conflict merge can still be a semantic break** — two sides that never touch the same lines can still contradict each other — and the two criteria that would catch it, the scan and the tests, only catch what the scan notices and what the tests cover. The rule is deliberately strict for that reason: a conflict the agent judges "mechanical" is exactly the judgement this checkpoint exists to check, so no auto-resolve tier exists, and there is no flag to widen the path. Reasoning in `doc/architecture/adr/0004-conditional-merge-base-approval.md` (CDD repo).

### 4.1 The `/cdd-process-pr` exception

In `/cdd-process-pr` (Section 3.7) the gate sits up front rather than on each action: the human approves the triage plan (which comments will be addressed, and how) before any file is edited, and that single approval authorizes everything that follows — the edits, the in-thread replies, the commit, and the push. There is no second confirmation before the GitHub-side actions. This is a conscious trade-off, not an oversight: in a single-user, fast review-iteration loop the PR is already open, the human is actively reviewing it, and every change the command makes is visible in the PR diff and revertable from git history. Re-confirming each reply or push after the plan was already approved would defeat the purpose of a tight address-and-re-review cycle. One thing does fall outside that authorization: where a triaged workflow gap is routed — folded into this PR, a roadmap item, or an issue on the CDD repo — is asked once, with a recommendation, because the approved plan settles which comments get addressed, not where a gap that outlives this diff should land.

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

Three areas that were out of scope for the first version of the template are now addressed by dedicated CDD-repo-only commands (§2.7), described in full in `doc/features/template.md`:

- **Greenfield bootstrap** → `/cdd-bootstrap`: a guided discovery session that produces the project overview (§2.5), a filled-in `CLAUDE.md`, a resolved engineering-practices contract (§2.12), and a real roadmap — each confirmed with the user — then scaffolds the project in a single render, with no pre-filled survey phase because the docs were written through discovery. The manual fallback is `tools/bootstrap-cdd-project.sh` (recipe in `template/BOOTSTRAP.md`), which leaves the template's stubs and pre-filled bootstrap phase to be worked through instead.
- **Lightweight one-off deliverables** → `/cdd-quick-create`: a script-plus-README deliverable with none of the project substrate — no roadmap, no `doc/` tree, no per-task lifecycle. Whether a task is a *deliverable* or a *project* is decided by a shared scope-triage heuristic that `/cdd-quick-create` and `/cdd-bootstrap` both apply, each offering an off-ramp to the other when the signals point the other way (heuristic and off-ramps in `doc/features/template.md`); as with every structural choice in CDD, the command surfaces the signals and recommends — the human decides.
- **Adapting an existing project** → `/cdd-retrofit`: auto-detects *install* mode (files-only template install, collisions merged interactively per file, the codebase survey deferred to the template roadmap's pre-filled bootstrap phase) vs *upgrade* mode (a three-way comparison against the baseline marker, §2.10, that applies template improvements, preserves local customizations, and surfaces general-looking local changes as candidates to upstream into CDD — the upgrade-time one of the three recurring channels behind Section 1's self-improvement commitment; §3.5's improvement check is the discovery-time one and §3.7's workflow-gap route the review-time one). Every change to a project file is approved per file; the checkpoints of Section 4 apply in spirit. Its writes are isolated on a dedicated branch reviewed via a normal PR, and the real cost of a first-time retrofit — the first few doc-reconciliation PRs that force the docs to reflect reality — is deliberately deferred to the project's own first sessions rather than the retrofit session. The cost analysis and reconciliation guidance live in `doc/features/template.md`.

Still deferred:

**Parallel-merge structure.** When two worktrees land in sequence, the second needs to integrate the first. Today this is partly automated (`/cdd-merge-base` covers it) and partly manual (the human decides when to trigger). A more structured approach, perhaps with a "second worktree must re-run pre-pr after merge-base", may be warranted once parallel work is common. The invariant is clear: a feature branch must integrate main and re-pass pre-pr before it's ready to merge.

**Template opinionation per project type.** The current template encodes the workflow, but the project-specific bits (build commands, language constraints, module layout) are placeholders. Different project archetypes (firmware, web app, library, data pipeline) probably want different opinionated defaults for those placeholders. Worth deriving from real usage rather than guessing up front.

## 7. The template

The template ships as a directory (`template/`) copied into a new project root by `tools/bootstrap-cdd-project.sh`: the `CLAUDE.md` skeleton, the four lifecycle commands, the doc skeletons, `.claude/settings.json`, and the baseline marker written at render time. The full contents are enumerated in `doc/features/template.md`; the bootstrapped tree layout and the bootstrap procedure — including the one-time helper install — are in `template/BOOTSTRAP.md`. The bootstrapped tree ships no `tools/` directory: the shell helpers are machine-global installs (§2.8), not per-project files. `template/BOOTSTRAP.md` itself is meta-documentation and is not copied into the bootstrapped project.

### 7.1 The CDD repo as its own project

The CDD repo is itself a CDD project and uses CDD on itself: the template under `template/` is content the project ships, distinct from the repo's own scaffolding at the root. This meta-pattern is deliberate dogfooding — the cleanest available demonstration of CDD's value; anything awkward about applying CDD to its own evolution is a real bug in the workflow. The two-layer structure, the drift guard between `./.claude/commands/` and `template/.claude/commands/`, and this document's own location are described in `doc/architecture/overview.md`. Downstream projects do not get a copy of this process doc; the template is self-sufficient for users who don't need the philosophy.

## 8. Adapting to a team

The workflow as described assumes a single human in the loop. A few adjustments anticipated for team use, not yet designed:

- Handoff files would need to live somewhere shared (repo-tracked under `.handoffs/`, or a shared filesystem location, or an issue tracker). Branch-keyed naming still works.
- Task selection in `/cdd-next-step` needs visibility into others' in-flight worktrees to avoid stomping. The worktree-list command would need to query a shared source.
- PR review remains a human gate, but the team needs a convention on who reviews what; the agent's PR-review pass becomes one input among several.
- Roadmap edits, especially structural ones, need a team approval mechanism beyond "the human running the session approves." A lightweight rule: structural edits go through a PR against the roadmap itself.

These extensions are tractable but deserve their own design pass once single-user usage is solid.
