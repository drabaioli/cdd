# <PROJECT_NAME> — Claude Code Context

<one-paragraph project description: what it is, what it does, what it explicitly does not do>

## Key references

| Topic                            | Location                                          |
| -------------------------------- | ------------------------------------------------- |
| System architecture & design     | `doc/architecture/` (start with `index.md`)       |
| Feature documentation            | `doc/features/` (start with `index.md`)           |
| Coding standards                 | `doc/knowledge_base/<coding-standard-filename>.md`|
| Implementation roadmap           | `doc/knowledge_base/roadmap.md`                   |
| Design decisions                 | `doc/knowledge_base/` (decision records)          |

**Read `doc/architecture/` before planning any feature or structural change.**
**Read `doc/features/` before changing user-visible behaviour.**
Keep architecture and feature docs current as part of every change.

## Critical constraints (quick reference)

<List the highest-frequency rules — the ones that bite within minutes if violated. Examples:>
<- Language version, compiler flags, allowed standard library subsets>
<- Banned constructs (e.g. exceptions, heap allocation, recursion)>
<- Naming conventions, file extensions>
<- Required idioms (error handling type, ownership conventions)>
<- Hard limits (no global mutable state, no blocking calls in X, etc.)>

Full details in the coding standard linked above.

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

This project uses the Claude-Driven Development workflow.

- **Before opening a PR**: run `/pre-pr` to verify CI gates pass and that architecture/feature docs and the roadmap reflect the change.
- **To start a new task**: run `/next-step` from the main worktree to produce a handoff, then run `<PROJECT_NAME>-worktree <branch>` to spin up the implementation worktree.
- **When main has advanced under a feature branch**: run `/merge-main` from the feature branch.
- Keep `doc/architecture/`, `doc/features/`, and this file current as part of every change.
