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
<build command>
<test command>
<integration test command>
<format check command>
<lint command>
```

## Module layout

| Directory   | Purpose                  |
| ----------- | ------------------------ |
| `<dir>/`    | <what lives here>        |
| `<dir>/`    | <what lives here>        |

## Architecture

<2–4 sentences describing the high-level shape: how modules talk to each other, what the main data flow is, where the boundary with external systems sits. Pointer to the full doc.>

See `doc/architecture/index.md` for the full picture.

## Workflow

This project uses the Claude-Driven Development workflow. Every CDD session is a fresh context doing exactly one job.

- **To start a new task** (handoff session): run `/cdd-next-step` from the main worktree to produce a handoff, then run `<PROJECT_SLUG>-worktree <branch>` to spin up the implementation worktree (implementation session, opens in plan mode). `/cdd-next-step` has three front-ends: no argument picks the next roadmap item; a task prompt starts off-roadmap work (intent-driven); and `#NN` / a bare integer / the `issue`/`issues` keyword sources the task from a GitHub issue (issue-driven), naming the branch `gh_issue_NN_<slug>`.
- **When main has advanced under a feature branch** (merge session): run `/cdd-merge-base` in a fresh context on the feature branch.
- **Before opening a PR** (pre-PR session): run `/cdd-pre-pr` in a fresh context to verify CI gates pass and that architecture/feature docs and the roadmap reflect the change; it auto-commits its own reconciliation edits (local, no push) and ends with an opt-in step to open the PR (adding `Closes #NN` when the branch carries the `gh_issue_NN` token).
- **When a PR review leaves comments** (PR-review session): run `/cdd-process-pr` in a fresh context on the feature branch.
- Keep `doc/architecture/`, `doc/features/`, and this file current as part of every change.
