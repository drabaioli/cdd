# <PROJECT_NAME> — Claude Code Context

<one-paragraph project description: what it is, what it does, what it explicitly does not do>

## Key references

| Topic                            | Location                                          |
| -------------------------------- | ------------------------------------------------- |
| Project overview (charter)       | `doc/knowledge_base/project-overview.md`          |
| Documentation map                | `doc/index.md`                                    |
| System architecture & design     | `doc/architecture/index.md`                       |
| Architecture decision records    | `doc/architecture/adr/` (Nygard style)            |
| Feature documentation            | `doc/features/index.md`                           |
| Implementation roadmap           | `doc/knowledge_base/roadmap.md`                   |
| Engineering practices            | `doc/knowledge_base/engineering-practices.md`     |
| Design decisions                 | `doc/knowledge_base/` (decision records)          |

Each doc directory keeps an `index.md` pointer list: read the index, then load only the documents you need. **`index.md` files are pointer lists only — content belongs in named subdocuments, not in the index itself.**

**Read `doc/architecture/index.md` (and the linked docs you need) before planning any feature or structural change.**
**Read `doc/features/index.md` (and the relevant feature docs) before changing user-visible behaviour.**
Keep architecture and feature docs — and their indexes — current as part of every change.

## Critical constraints (quick reference)

<List the highest-frequency rules — the ones that bite within minutes if violated. Examples:>
<- Language version, compiler flags, allowed standard library subsets>
<- Banned constructs (e.g. exceptions, heap allocation, recursion)>
<- Naming conventions, file extensions>
<- Required idioms (error handling type, ownership conventions)>
<- Hard limits (no global mutable state, no blocking calls in X, etc.)>

Once a coding standard exists, link it from the Key references table and reference it here.

## Build & test

```bash
<check runner command>   # every gate, the one command CI runs (see below)
```

The individual gates the runner should call:

```bash
<build command>
<test command>
<integration test command>
<format check command>
<lint command>
```

Keep the runner the **single source of the gate sequence**: CI delegates to it and `/cdd-pre-pr` invokes it, so a gate is never listed twice and a local pass means CI will pass.

## Module layout

| Directory   | Purpose                  |
| ----------- | ------------------------ |
| `<dir>/`    | <what lives here>        |
| `<dir>/`    | <what lives here>        |

## Architecture

<2–4 sentences describing the high-level shape: how modules talk to each other, what the main data flow is, where the boundary with external systems sits. Pointer to the full doc.>

See `doc/architecture/index.md` for the full picture.

## Talking to the human

Anything printed for a human to decide on — a checkpoint digest, a session's closing report, a question — is **short, plainly worded, and only what changes their answer**.

- **Short.** A few lines. Long enough to decide against, short enough to be read rather than skimmed; a wall of text turns a checkpoint into a rubber stamp.
- **Plain.** Ordinary words, not the project's own vocabulary — "the tests that cover the parser all pass", not "the parser suite's coverage gate is green". Name a mechanism only when the human needs it to act.
- **Only what decides.** What the thing is, why, and anything that would change the answer. Leave out what they will see anyway at review time: the file list, the internal mechanics, the log of how you got there.

Correctness outranks brevity — if a point cannot be made both plainly and correctly in the space, say it correctly.

## Workflow

This project uses the Claude-Driven Development workflow. Every CDD session is a fresh context doing exactly one job.

- **To start a new task** (handoff session): run `/cdd-next-step` from the main worktree to produce a handoff, then run `cdd-worktree <branch>` to spin up the task worktree. `/cdd-next-step` has three front-ends: no argument picks the next roadmap item; a task prompt starts off-roadmap work (intent-driven); and an argument matching the resolved tracker's `ref_pattern` — `#NN` or a bare integer on the built-in `gh` rung — or the `issue`/`issues` keyword sources the task from an issue (issue-driven). Several refs may be given at once; they are recorded on the task's state record (`cdd-state issue-refs`), which is the only thing carrying them forward — branch names stay plain descriptive slugs in every mode.
- **To build the task** (plan session, then implementation session): `cdd-worktree <branch>` opens a session on `/cdd-plan`, which explores, takes plan approval, writes the plan file to `~/.cdd/handoffs/<PROJECT_DIR>/<branch>.plan.md`, and stops without touching the repo. Then open a **fresh** `claude` in that same worktree and run `/cdd-implement`, which builds from the plan file, updates the docs, and commits locally. The manual step between them is deliberate: it is where you read or edit the plan.
- **When the task is small enough to state in one sentence** (small-change lane): `/cdd-next-step` recommends the lane and records it, and `cdd-worktree <branch>` then opens the worktree on `/cdd-small-change` instead — one session that takes its own approval of the concrete change, makes it, updates the docs, and commits. It hands back to `/cdd-plan` in the same worktree if the task turns out not to be small. Anything missing (an old helper, no marker) falls back to the standard lane.
- **To pick up a task started on another machine** (resume): run `cdd-worktree-resume [<branch>]` from the main worktree. It recreates the worktree on the existing remote branch (no handoff needed) and `cd`s into it, then tells you what to run next based on the task's lane and stage: a small-change task not yet built resumes into `/cdd-small-change`; a task sitting at `plan_written` resumes into `/cdd-implement` (its plan rides the task ref along with the handoff and state record); anything else into `/cdd-process-pr`, `/cdd-merge-base`, or `/cdd-pre-pr`. With no argument it lists resumable remote branches.
- **When main has advanced under a feature branch** (merge session): run `/cdd-merge-base` in a fresh context on the feature branch.
- **Before opening a PR** (pre-PR session): run `/cdd-pre-pr` in a fresh context to verify CI gates pass and that architecture/feature docs and the roadmap reflect the change; it auto-commits its own reconciliation edits (local, no push) and ends with an opt-in step to open the PR (one close line per ref recorded on the state record, derived through the tracker's `issue-close-token`; with no usable record there are no close lines, said out loud rather than guessed).
- **When a PR review leaves comments** (PR-review session): run `/cdd-process-pr` in a fresh context on the feature branch.
- Keep `doc/architecture/`, `doc/features/`, and this file current as part of every change.
