# Claude-Driven Development (CDD)

[![template-smoke](https://github.com/drabaioli/cdd/actions/workflows/template-smoke.yml/badge.svg)](https://github.com/drabaioli/cdd/actions/workflows/template-smoke.yml)

You want to build real software with Claude Code without losing control of the decisions — and without the docs, the roadmap, and the agent's context rotting as the project grows. CDD is a human-in-the-loop workflow for exactly that: the agent carries the implementation, verification, and documentation work across git worktrees, while every decision passes through an explicit human checkpoint.

Two ideas do most of the work:

- **Every session is a fresh context doing exactly one job.** Sessions hand off through files (a handoff file, the roadmap, the docs), never by sharing a chat window.
- **Automate everything except decisions.** Six checkpoints are where automation deliberately stops; the human chooses, approves, and merges — the agent does the rest.

## The lifecycle

A task flows through up to five sessions, each driven by one slash command:

```mermaid
flowchart TD
    NS(["Handoff session<br>/next-step, on the main worktree"]):::agent
    IMPL(["Implementation session<br>opens in plan mode — ③ plan approved —<br>implement, update docs + roadmap, commit"]):::agent
    MM(["Merge session<br>/merge-main: integrate main, dry-run first"]):::opt
    PP(["Pre-PR session<br>/pre-pr: CI gates, code review, doc reconciliation"]):::agent
    REV["Human reviews the PR on GitHub"]:::human
    PPR(["PR-review session<br>/process-pr: triage + address review comments"]):::opt
    DONE["Squash-merge, worktree teardown"]:::human

    NS -->|"① task selected  ② handoff approved<br>a fresh worktree is spun up"| IMPL
    IMPL --> PP
    IMPL -.->|"main moved?"| MM
    MM -.->|"④ merge approved"| PP
    PP -->|"⑤ roadmap edits approved"| REV
    REV -.->|"review left comments"| PPR
    PPR -.-> REV
    REV -->|"⑥ human merges"| DONE

    classDef agent fill:#1f6feb,stroke:#1158c7,color:#ffffff
    classDef opt fill:#6e40c9,stroke:#553098,color:#ffffff,stroke-dasharray: 6 4
    classDef human fill:#238636,stroke:#1a6329,color:#ffffff
```

Blue boxes are Claude sessions (fresh context, one job each), green are human/GitHub steps, dashed are optional side-loops. ①–⑥ are the six human checkpoints — the agent never proceeds past one without explicit confirmation. The [process document](doc/knowledge_base/claude-driven-development.md) describes the full lifecycle, the artifacts, and the edit rules.

## Quick start (using CDD on a new project)

```bash
git clone https://github.com/drabaioli/cdd.git ~/Code/cdd && cd ~/Code/cdd
./bootstrap-cdd-project.sh \
  --name "My Project" \
  --slug myproj \
  --path ~/Code/my-project
```

The script copies the template, substitutes the placeholders, and makes the initial scaffold commit. Then fill in `CLAUDE.md` and `doc/knowledge_base/roadmap.md`, source `tools/myproj-worktree.sh` from `~/.bashrc`, run `claude`, and start with `/next-step`. Full procedure in [`template/BOOTSTRAP.md`](template/BOOTSTRAP.md). To install CDD into an *existing* project, use `/retrofit` from a Claude Code session in this repo instead.

## What's in this repo

```mermaid
flowchart LR
    PD["Process document<br>doc/knowledge_base/"]:::layer
    T["Template<br>template/ + bootstrap-cdd-project.sh"]:::layer
    NEW["Your project, running CDD"]:::out
    DEMO["Demo / dogfood instance<br>demo/"]:::out

    PD -->|"instantiated as"| T
    T -->|"bootstrap"| NEW
    T -->|"bootstrap --overlay demo/seed"| DEMO

    classDef layer fill:#1f6feb,stroke:#1158c7,color:#ffffff
    classDef out fill:#238636,stroke:#1a6329,color:#ffffff
```

- **The process document**: [`doc/knowledge_base/claude-driven-development.md`](doc/knowledge_base/claude-driven-development.md). The philosophy, the lifecycle, the artifacts, the edit rules. Read this first if you want to understand what CDD is and why.
- **The template**: [`template/`](template/). Copy-paste material for bootstrapping a new project. See [`template/BOOTSTRAP.md`](template/BOOTSTRAP.md) for the bootstrap procedure.
- **The demo subsystem**: [`demo/`](demo/). A filled-in seed project ("Markdown Renderer") plus create/teardown automation, used both to demo the workflow and to dogfood it.

Changes flow process-first, template-second, and never from the demo back into the template. This repo uses CDD on itself: its own scaffolding (`CLAUDE.md`, `.claude/commands/`, `doc/`, `tools/cdd-worktree.sh`) sits at the root, and the template is content this project ships.

## Status

In active use. The workflow has been dogfooded end-to-end on a downstream demo project (see [`demo/`](demo/)), including full task cycles with real merges and PR reviews, and the friction found has been folded back into the template. See [`doc/knowledge_base/roadmap.md`](doc/knowledge_base/roadmap.md) for what's done and what's next.
