# Claude-Driven Development (CDD)

[![template-smoke](https://github.com/drabaioli/cdd/actions/workflows/template-smoke.yml/badge.svg)](https://github.com/drabaioli/cdd/actions/workflows/template-smoke.yml)

CDD is a human-in-the-loop workflow for building real software with Claude Code — without losing control of the decisions, and without the docs, the roadmap, and the agent's context rotting as the project grows. The agent carries the implementation, verification, and documentation work across git worktrees; every decision passes through an explicit human checkpoint.

## Two big ideas

- **Every session is a fresh context doing exactly one job.** Sessions never share a chat window — they hand off through files (a handoff file, the roadmap, the docs). A new task, a merge, a pre-PR check, a review round: each is its own clean session.
- **Automate everything except decisions.** Six checkpoints are where automation deliberately stops. The human picks the task, approves the handoff, approves the plan, approves any merge, approves roadmap edits, and merges the PR. The agent does everything in between.

## The lifecycle

A task flows through up to five sessions, each driven by one slash command. The six numbered checkpoints across the top are the human-in-the-loop gates — the agent never proceeds past one without explicit confirmation (③ approving the plan is the key one).

![CDD task cycle: /cdd-next-step (queue) → worktree (isolate) → implementation in plan mode (build) → optional /cdd-merge-base → /cdd-pre-pr (self-review) → PR review → optional /cdd-process-pr → merged, with the six locked human checkpoints across the top and a repeat loop back to the start.](doc/assets/task-cycle.png)

The [process document](doc/knowledge_base/claude-driven-development.md) describes the full lifecycle, the artifacts, the edit rules, and the reasoning behind every checkpoint. Read it first if you want to understand what CDD is and why.

## Quick start

The front door is the **guided commands** — run them from a Claude Code session inside this repo:

- **`/cdd-bootstrap`** — guided greenfield start. Walks you through defining the project and drafting a real roadmap through conversation, then scaffolds the new project (overview, `CLAUDE.md`, and roadmap already filled in) in one go.
- **`/cdd-retrofit`** — install CDD into an *existing* project, or upgrade a project already on CDD, preserving local customizations.
- **`/cdd-quick-create`** — produce a one-off, self-contained deliverable (a single script plus a README), with no project substrate or roadmap.

### Manual path

If you'd rather drive the lower-level bootstrap yourself:

```bash
git clone https://github.com/drabaioli/cdd.git ~/Code/cdd && cd ~/Code/cdd
./tools/bootstrap-cdd-project.sh \
  --name "My Project" \
  --slug myproj \
  --path ~/Code/my-project
```

The script copies the template, substitutes the placeholders, and makes the initial scaffold commit. Then fill in `CLAUDE.md` and `doc/knowledge_base/roadmap.md`, source `tools/myproj-worktree.sh` from `~/.bashrc`, run `claude`, and start with `/cdd-next-step`. Full procedure in [`template/BOOTSTRAP.md`](template/BOOTSTRAP.md).

## Command reference

CDD ships seven slash commands, all prefixed `cdd-` so they autocomplete as a group.

**Per-task cycle** — shipped into every CDD project via the template:

| Command | What it does |
| --- | --- |
| `/cdd-next-step` | Scope the next task and write a handoff for a fresh implementation session. Three front-ends: the next roadmap item, a typed task prompt (off-roadmap), or a GitHub issue (`#NN` / a bare integer / the `issue` keyword). |
| `/cdd-merge-base` | Integrate the base branch into a feature branch when the base has advanced under you (dry-run first, then apply). |
| `/cdd-pre-pr` | Pre-PR checklist: CI gates, code review, and doc/roadmap reconciliation; ends with an opt-in step to open the PR. |
| `/cdd-process-pr` | Triage and address the open PR's review feedback, reply in-thread, and commit. |

**CDD-repo-only** — run from a session inside this repo; they operate *on* a target, so the template ships no copy:

| Command | What it does |
| --- | --- |
| `/cdd-bootstrap` | Guided greenfield: define the project + draft a roadmap through conversation, then scaffold it. |
| `/cdd-retrofit` | Install or upgrade CDD in an existing project. |
| `/cdd-quick-create` | Produce a one-off self-contained deliverable (script + README), no project substrate. |

`cdd-worktree` is a **shell helper** (sourced from your `~/.bashrc`), not a slash command — it spins up the per-task git worktree that an implementation session runs in.

## What's in this repo

- **The process document**: [`doc/knowledge_base/claude-driven-development.md`](doc/knowledge_base/claude-driven-development.md). The philosophy, the lifecycle, the artifacts, the edit rules.
- **The template**: [`template/`](template/). Copy-paste material for bootstrapping a new project. See [`template/BOOTSTRAP.md`](template/BOOTSTRAP.md) for the procedure.
- **The demo subsystem**: [`demo/`](demo/). A filled-in seed project ("Markdown Renderer") plus create/teardown automation, used both to demo the workflow and to dogfood it.

Changes flow **process-first, template-second**, and never from the demo back into the template. This repo uses CDD on itself: its own scaffolding (`CLAUDE.md`, `.claude/commands/`, `doc/`, `tools/cdd-worktree.sh`) sits at the root, and the template is content this project ships.

## Contributing

At this stage CDD accepts **GitHub issues only — no pull requests yet**. If you spot a bug, have a suggestion, or want to discuss the workflow, please [open an issue](https://github.com/drabaioli/cdd/issues). PRs are not being accepted for now; that will change later.

## Status

In active use. The workflow has been dogfooded end-to-end on a downstream demo project (see [`demo/`](demo/)), including full task cycles with real merges and PR reviews, and retrofitted onto existing real-world codebases — with the friction found along the way folded back into the template. See [`doc/knowledge_base/roadmap.md`](doc/knowledge_base/roadmap.md) for what's done and what's next.

## License

[MIT](LICENSE) © Diego Andres Rabaioli.
