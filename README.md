# Claude-Driven Development (CDD)

A human-in-the-loop workflow for evolving software projects together with Claude Code. Built around a self-updating `CLAUDE.md`, a roadmap, architecture and feature docs, and a small set of slash commands that drive task selection, implementation, merge, and PR review across git worktrees.

## What's in this repo

- **The process document**: [`doc/knowledge_base/claude-driven-development.md`](doc/knowledge_base/claude-driven-development.md). The philosophy, the lifecycle, the artifacts, the edit rules. Read this first if you want to understand what CDD is and why.
- **The template**: [`template/`](template/). Copy-paste material for bootstrapping a new project. See [`template/BOOTSTRAP.md`](template/BOOTSTRAP.md) for the bootstrap procedure.
- **The demo subsystem**: [`demo/`](demo/). A filled-in seed project ("Markdown Renderer") plus create/teardown automation, used both to demo the workflow and to dogfood it.

This repo uses CDD on itself. Its own scaffolding (`CLAUDE.md`, `.claude/commands/`, `doc/`, `tools/cdd-worktree.sh`) sits at the root; the template is content this project ships, under `template/`.

## Quick start (using CDD on a new project)

```bash
git clone <this-repo> ~/Code/cdd && cd ~/Code/cdd
./bootstrap-cdd-project.sh \
  --name "My Project" \
  --slug myproj \
  --path ~/Code/my-project
```

The script copies the template, substitutes the placeholders, and makes the initial scaffold commit. Then fill in `CLAUDE.md` and `doc/knowledge_base/roadmap.md`, source `tools/myproj-worktree.sh` from `~/.bashrc`, run `claude`, and start with `/next-step`. Full procedure in [`template/BOOTSTRAP.md`](template/BOOTSTRAP.md). To install CDD into an *existing* project, use `/retrofit` from a Claude Code session in this repo instead.

## The lifecycle

Every CDD session is a fresh Claude Code context doing exactly one job. A task flows through up to five of them:

| Session            | Command                                    | What it does                                                       |
| ------------------ | ------------------------------------------ | ------------------------------------------------------------------ |
| **Handoff**        | `/next-step` (on main)                     | Pick the next task with the human, write a handoff file.           |
| **Implementation** | auto-started by `<slug>-worktree <branch>` | Plan (human approves), implement, update docs and roadmap, commit. |
| **Merge** (opt.)   | `/merge-main`                              | Integrate main into the feature branch when main has advanced.     |
| **Pre-PR**         | `/pre-pr`                                  | Run the CI gates, review the diff, reconcile docs and roadmap.     |
| **PR-review** (opt.) | `/process-pr`                            | Triage and address PR review comments, reply in-thread, push.      |

The human stays in the loop at six explicit checkpoints (task selection, handoff approval, plan approval, merge approval, roadmap edits, PR merge); everything between them is automated. See the [process document](doc/knowledge_base/claude-driven-development.md) for the full picture.

## Status

In active use. The workflow has been dogfooded end-to-end on a downstream demo project (see [`demo/`](demo/)), including full task cycles with real merges and PR reviews, and the friction found has been folded back into the template. See [`doc/knowledge_base/roadmap.md`](doc/knowledge_base/roadmap.md) for what's done and what's next.
