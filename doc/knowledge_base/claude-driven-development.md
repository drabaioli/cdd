# Claude-Driven Development (CDD)

A human-in-the-loop workflow for building and evolving a software project together with Claude Code. The project's own files (CLAUDE.md, a roadmap, architecture/feature docs, and a small set of slash commands) act as the substrate that drives the agentic process. The substrate evolves as the project evolves, so it stays useful instead of going stale.

This document describes the philosophy, the artifacts, the lifecycle, and the rules. The template files (`CLAUDE.md` skeleton, slash commands, worktree script, doc skeletons) are derived from this document and ship alongside it.

## 1. Philosophy

Three commitments shape every decision in this workflow.

**The human is in the loop at every gate.** The agent never picks the next task, never approves a plan, never merges its own PR, never restructures the roadmap unilaterally. It proposes; the human disposes. The agent's value is throughput inside a clearly-scoped task and consistency in keeping docs current, not autonomous decision-making.

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

1. **Only the implementation session edits the roadmap file.** The `next-step` session may discuss roadmap changes during clarification but does not edit the file. It records desired edits in the handoff and instructs the implementation session to apply them.
2. **Roadmap edits beyond ticking a checkbox require human approval.** Adding, removing, or splitting tasks; restructuring phases; reordering priorities, the agent proposes, the human approves.
3. **Inline annotations stay terse.** When ticking a completed task, do not restate what the task did or describe how it was implemented — that lives in the commit, the PR description, and (for any lasting behaviour change) the process / architecture / feature docs, which the agent updates as part of the same change. Annotate inline *only* when a future session needs information that none of those sources will carry: a deferred sub-item, a surprising caveat, or a scope change. If there is nothing of that nature, just tick the box. One short clause, not a sentence with a parenthetical.

The roadmap is the central artifact. If it drifts from reality, the workflow loses its anchor.

### 2.3 Architecture docs (`doc/architecture/`)

"What the system is now," structurally. Module boundaries, data flow, key interfaces, deployment topology, threading model. Updated continuously by the implementation session as it changes the system, and reconciled by `/pre-pr` against the diff.

Architecture docs are load-bearing for the agent: when a new session opens with no memory of previous work, these docs (linked from CLAUDE.md) are how it rebuilds its mental model. If the architecture docs are wrong, the agent's plans will be wrong.

### 2.4 Feature docs (`doc/features/`)

"What the system does," from a capability/user perspective. One doc per significant feature. Created or updated by the implementation session whenever a feature is added or changed in a user-visible way. Reconciled by `/pre-pr`.

Feature docs serve human readers (what does this system do today?) and the agent (what's the contract this feature must preserve when I refactor near it?). On projects with no external "users" yet (greenfield internal tools, firmware), the audience is future-you and future-collaborators.

### 2.5 Knowledge base (`doc/knowledge_base/`)

Project metadata and history. The roadmap lives here. So do:

- Decision records: why we chose this RTOS, this framework, this hardware target, this protocol. Append-only.
- Coding standards: language-specific style and convention rules.
- Investigation notes: deep dives done in the course of the project that don't fit into architecture or feature docs.

The knowledge base is mostly append-only. Decisions are not rewritten when they are superseded; new decisions are added that supersede them, with a reference back. This preserves the reasoning trail.

### 2.6 Handoff files (`~/.claude-handoffs/<repo-name>/<branch>.md`)

The contract between the `next-step` session and the implementation session. Lives outside the repo, namespaced by repo so multiple CDD projects don't collide (branch-scoped, ephemeral). Created by `/next-step`. Consumed by the first prompt of the implementation session. Deleted when the branch is deleted.

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

Project-level Claude Code slash commands. CDD ships four active commands plus one deferred:

- `/next-step`, exploratory session, run on main, produces a handoff.
- `/pre-pr`, verification session, run on the feature branch, runs CI and reconciles docs.
- `/merge-main`, side-loop, run on a feature branch when main has advanced, does conflict assessment then merge.
- `/process-pr`, side-loop, run on a feature branch after the PR is opened and reviewed; reads the PR's review comments, addresses them in-session, posts replies, and commits + pushes. Analogous in lifecycle position to `/merge-main`. (See Section 4 for the deliberate checkpoint exception it carries.)
- `/bootstrap`, optional, used once at project start to scaffold the workflow files. Defer for now (see Section 6).

Slash commands are declarative: they describe what to do, not how to orchestrate it. Orchestration (worktree creation, branch lifecycle) lives in the shell helpers.

### 2.8 Worktree shell helpers (`tools/<slug>-worktree.sh`)

A bash script providing three commands, sourced from `~/.bashrc`:

- `<slug>-worktree <branch>`, creates a worktree for `<branch>` and launches Claude Code in plan mode in it with the suggested first prompt already submitted. Requires a handoff file to exist.
- `<slug>-worktree-done`, run from a feature worktree once the PR has landed or the branch is being abandoned. Returns to main, pulls, removes the worktree, resolves the branch (safe-delete if merged, force-delete if squash-merged, prompt otherwise), and deletes the handoff iff the branch was deleted.
- `<slug>-worktree-list`, lists active handoffs with worktree/branch/PR status. Highlights stale entries.

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

## 3. Lifecycle

A task flows through CDD in up to five sessions, two of them optional side-loops (`/merge-main` before the PR, `/process-pr` after review). Each session is a fresh Claude Code conversation with its own clean context.

```
                       (on main worktree)
            ┌──────────────────────────────────┐
            │ Session 1: /next-step            │
            │                                  │
            │ Read roadmap, discuss what next, │
            │ clarify cheap requirements,      │
            │ write handoff file.              │
            └──────────────────────────────────┘
                            │
                            │  handoff file
                            ▼
                  <project>-worktree <branch>
                            │
                            ▼
                       (on new worktree)
            ┌──────────────────────────────────┐
            │ Session 2: implementation        │
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
            │ Session 3 (optional): /merge-main│
            │                                  │
            │ Dry-run conflict assessment.     │
            │ Human approves. Merge main into  │
            │ the feature branch. Resolve.     │
            └──────────────────────────────────┘
                            │
                            ▼
            ┌──────────────────────────────────┐
            │ Session 4: /pre-pr               │
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
            │ Session 5 (optional): /process-pr│
            │                                  │
            │ Read the PR's review comments.   │
            │ Triage; human sees the plan.     │
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

### 3.1 Session 1: `/next-step` (on main)

Goal: pick what to do next and produce a clean handoff.

The session reads the roadmap and the stale-handoff list, proposes one or more candidate tasks, discusses dependencies and ambiguity with the human, and converges on a single task. It clarifies requirements that are cheap to resolve here, the ones where the right answer can be inferred from the roadmap or briefly discussed, and explicitly defers harder requirements to the implementation session.

The reason for this split is context, not git topology: the `next-step` session's context is necessarily polluted by reading the whole roadmap and reasoning across phases. The implementation session's context is clean and dedicated to one task, which is the right environment for the harder, more focused clarification.

The session ends by writing the handoff file and printing the `<project>-worktree <branch>` command.

The `next-step` session does not edit the roadmap file. If roadmap edits are needed, it notes them in the handoff and instructs the implementation session to make them.

### 3.2 Worktree creation

The human closes the `next-step` session and runs `<project>-worktree <branch>` from the main worktree. The shell helper creates the new worktree and launches Claude Code in plan mode in it, passing the one-line first prompt (`Read <handoff path> and follow the Implementation prompt.`) as the initial user message so the implementation session opens already processing it.

### 3.3 Session 2: implementation (on the new worktree)

The session opens in plan mode, reads the handoff, and rebuilds its context from CLAUDE.md, the roadmap, and the architecture/feature docs. It surfaces any deferred or freshly-discovered open questions and confirms scope with the human, then presents a plan.

Plan mode is the load-bearing checkpoint here: the agent cannot modify files while in plan mode, so the human gets a guaranteed approval gate before any code is written.

Once the plan is approved, the session implements the task, updates architecture and feature docs to reflect the change, updates the roadmap (ticking the completed checkbox; applying any add/modify/remove edits previously discussed and approved), and commits.

### 3.4 Session 3 (optional): `/merge-main`

Run on the feature branch when main has advanced and the feature branch needs to integrate the new state, either because the PR will conflict or because the feature work depends on something that just landed on main.

Two-phase:

1. **Dry run.** Identify what main contains that's not on this branch. Assess merge complexity: which files conflict, whether the conflicts look mechanical or logical, whether new conventions on main affect this branch. Report. Do not merge yet.
2. **Merge.** On human approval, perform the merge and resolve. If conflicts are non-trivial, the agent may ask the human for clarification mid-resolution.

This is also where the agent can pull in improvements from main that are useful here without scheduling an explicit roadmap task (small refactors, new utilities, updated conventions).

### 3.5 Session 4: `/pre-pr`

A fresh session on the feature branch, started after the implementation session has closed. This isolation is deliberate: a fresh context avoids the implementation session grading its own homework, and any "propose to the human" step in `/pre-pr` is a proposal to the human running this session, not to another session. Runs the CI gates, reads the diff, code-reviews changed files, and reconciles documentation.

Doc reconciliation has three parts:

- **Architecture docs**: read the docs that touch the changed area, compare against the actual code, fix discrepancies directly.
- **Feature docs**: same, for feature docs.
- **Roadmap**: tick newly-completed checkboxes directly; identify roadmap edits (add/modify/remove tasks) implied by what landed and present them to the human in this session for approval before applying.

`/pre-pr` also performs a conditional CI-improvement check: if the change introduces a category of work that the existing CI doesn't cover (new file type, new test category, a tool that should be linted but isn't), propose improvements to the human. On approval, apply them as part of the same PR; alternatively, the human may defer them as a new roadmap task. The default is silence. The agent should not propose CI improvements every run; only when the change genuinely surfaces a gap.

Output is a pass/fail summary across all the gates.

### 3.6 PR review and merge

The human runs `gh pr create`, reviews the PR (with full Claude assistance if desired, but in a fresh session, not the implementation session), and merges. Squash-merge is the default; the worktree script handles squash-merged branches as a first-class case.

### 3.7 Session 5 (optional): `/process-pr`

Run on the feature branch when a review has left comments that need addressing. A fresh session reads the open PR's review comments (inline review threads, review summary bodies, and general conversation comments), processes only the unresolved ones, and triages them: change-request, question, nit, or discussion. It presents the triage plan to the human, then implements the change-requests and nits, answers the questions, and pushes back — disagreeing and explaining in the reply — on any change-request it judges wrong or risky rather than implementing it blindly.

Unlike the other sessions, the GitHub-side actions are not gated: `/process-pr` auto-posts an in-thread reply to each processed comment and auto-commits and pushes the resulting changes. The rationale and the one checkpoint it retains are described in Section 4.

After processing, the human re-runs `/pre-pr` before the PR goes back for re-review. This loop can repeat across review rounds.

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

`/process-pr` (Section 3.7) is a deliberate, documented exception to the rule above: it auto-posts GitHub replies and auto-commits + pushes **without** a confirmation gate. This is a conscious trade-off, not an oversight. It is justified by the loop's context: a single-user, fast review-iteration loop where the PR is already open, the human is actively reviewing it, and every change the command makes is visible in the PR diff and revertable from git history. Adding a gate before each reply or push would defeat the purpose of a tight address-and-re-review cycle.

The command does retain one in-session checkpoint — it presents its triage plan (which comments it will address, and how) to the human before editing any files. And human-in-the-loop reasoning is preserved at the code level: the command pushes back on change-requests it judges wrong rather than implementing them blindly. What is dropped is only the confirmation gate on the outbound GitHub actions, not the judgment behind them.

## 5. Edit rules: who edits what, when

The matrix below resolves any ambiguity about which session is allowed to touch which artifact.

| Artifact                | `/next-step` | implementation     | `/merge-main` | `/pre-pr`              |
| ----------------------- | ------------ | ------------------ | ------------- | ---------------------- |
| Roadmap (tick)          | no           | yes                | no            | yes                    |
| Roadmap (add/mod/rm)    | no           | yes (pre-approved) | no            | yes (human-approved)   |
| Architecture docs       | no           | yes                | yes if needed | yes (reconcile)        |
| Feature docs            | no           | yes                | yes if needed | yes (reconcile)        |
| CLAUDE.md               | no           | yes if needed      | no            | yes (reconcile)        |
| Knowledge base (other)  | no           | yes if needed      | no            | yes if needed          |
| Code                    | no           | yes                | yes (merge)   | yes (review-driven)    |
| Handoff file            | yes (write)  | no (read-only)     | no            | no                     |
| CI config               | no           | yes if in scope    | no            | yes (human-approved)   |

The `next-step` session is read-only on the repo. This keeps its job narrow: read, discuss, write the handoff. Everything else happens in worktrees.

## 6. Known gaps and deferred design

Three areas are intentionally out of scope for the first version of the template.

**Greenfield bootstrap.** How a project gets its first roadmap, its first CLAUDE.md, and its first architecture skeleton. Exploratory work (research, prototyping, reading) generally happens outside Claude Code. A `/bootstrap` command could plausibly take a project brief and a draft roadmap and produce structured starting files, but the exploratory work itself doesn't fit cleanly inside the git + Claude Code substrate. Worth revisiting once the template has been used on a few greenfield projects.

The current recommended approach for greenfield bootstrap is to run `bootstrap-cdd-project.sh` from the CDD repo root (see `template/BOOTSTRAP.md` for the procedure): it copies the template into a fresh directory, performs the placeholder substitution non-interactively, and runs the initial `git init` + scaffold commit. The up-front thinking — language, tooling, top-level architecture, the thin initial roadmap (three to five phases, a handful of tasks each) — still happens outside Claude Code. The roadmap will be refined during the first few `/next-step` sessions; the workflow is designed for that. Resist the urge to make it perfect before starting.

**Parallel-merge structure.** When two worktrees land in sequence, the second needs to integrate the first. Today this is partly automated (`/merge-main` covers it) and partly manual (the human decides when to trigger). A more structured approach, perhaps with a "second worktree must re-run pre-pr after merge-main", may be warranted once parallel work is common. The invariant is clear: a feature branch must integrate main and re-pass pre-pr before it's ready to merge.

**Template opinionation per project type.** The current template encodes the workflow, but the project-specific bits (build commands, language constraints, module layout) are placeholders. Different project archetypes (firmware, web app, library, data pipeline) probably want different opinionated defaults for those placeholders. Worth deriving from real usage rather than guessing up front.

**Adapting an existing project.** Out of scope for now. A retrofit process likely looks like: write CLAUDE.md, write an initial architecture doc by having Claude survey the codebase, generate a roadmap from the current backlog, then start using the workflow. The doc-reconciliation discipline is the bigger ask; existing projects without it will have a painful first few PRs as the docs are made to reflect reality. Revisit after greenfield template is stable.

## 7. Template directory layout

The template ships as a directory copied into a new project root by `bootstrap-cdd-project.sh` (which lives at the CDD repo root, not inside `template/`). The bootstrapped tree looks like:

```
<PROJECT_DIR>/
├── CLAUDE.md                                 # skeleton with placeholders, filled by hand after bootstrap
├── .claude/
│   └── commands/
│       ├── next-step.md
│       ├── pre-pr.md
│       └── merge-main.md
├── doc/
│   ├── architecture/
│   │   └── index.md                          # placeholder
│   ├── features/
│   │   └── index.md                          # placeholder
│   └── knowledge_base/
│       ├── roadmap.md                        # placeholder
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
4. Write the initial roadmap by hand (or generate with a one-off Claude session).
5. Start the first `/next-step` session (it creates the per-repo handoff directory `~/.claude-handoffs/<repo-name>/` on demand).

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
