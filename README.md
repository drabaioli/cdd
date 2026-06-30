# Claude-Driven Development (CDD)

[![template-smoke](https://github.com/drabaioli/cdd/actions/workflows/template-smoke.yml/badge.svg)](https://github.com/drabaioli/cdd/actions/workflows/template-smoke.yml)

Build real software with Claude Code without handing over the wheel. CDD is a human-in-the-loop workflow: the agent carries the implementation, verification, and documentation across git worktrees, and every decision that matters passes through an explicit human gate. The docs, the roadmap, and the agent's context stay current as the project grows instead of rotting behind it.

## How it works

Every task moves through the same cycle. Each step is a fresh Claude Code session doing exactly one job, handing off to the next through files (a handoff file, the roadmap, the docs) rather than a shared chat window. A session loads only the context it needs to start, then follows links to the rest (the process doc, the architecture and feature docs) when a step actually calls for them, so context stays lean and never bloats with material the current job doesn't use. The locks across the top of the diagram are the human gates: the agent never crosses one without your explicit approval, and approving the plan is the load-bearing one.

![CDD task cycle: start a session and run /cdd-next-step to queue a task, spin up an isolated worktree, build in plan mode, optionally /cdd-merge-base, run /cdd-pre-pr to self-review and open the PR, review on GitHub, optionally /cdd-process-pr for review feedback, merge, then clean up and repeat, with locked human gates across the top.](doc/assets/task-cycle.png)

One full turn around the cycle:

1. **Pick the next task.** Start a session with `claude`, then run `/cdd-next-step`. It proposes what to work on: the next roadmap item, an off-roadmap prompt you type, or a GitHub issue (`#NN`).
2. **Confirm the intent.** You confirm the task is what you actually want and settle any roadmap-related decisions it raises. Once that's clear, it writes a handoff file for the implementation session.
3. **Spin up an isolated worktree.** Run `cdd-worktree <branch>` to create a dedicated git worktree and branch. It automatically launches the implementation session, which opens in plan mode.
4. **Review and approve the plan.** The session rebuilds its context from the handoff and the docs, then presents a plan. You approve it (this is the key gate), and it implements the task, updates the architecture/feature docs and the roadmap, and commits the work locally (no push yet).
5. **Integrate the base branch if it moved.** If the base branch advanced while you were working, run `/cdd-merge-base`. It does more than resolve textual conflicts: it performs a *logical* merge, adopting newer base-branch features where the task should now use them.
6. **Self-review and open the PR.** In a fresh session, run `/cdd-pre-pr`. It runs the CI gates, code-reviews the diff, reconciles the docs and roadmap, and ends by offering to open the PR, the point at which the branch is first pushed.
7. **Review on GitHub.** You read the diff on GitHub and leave review comments, exactly as you would on any PR.
8. **Address the feedback.** Run `/cdd-process-pr` on the branch. It triages the review comments, makes the requested changes, replies in each thread, and commits and pushes back to the PR.
9. **Merge.** You squash-merge the branch on GitHub.
10. **Clean up and repeat.** Back in your terminal, run `cdd-worktree-done` to remove the feature worktree and fast-forward your base branch to the freshly merged state. Then go again.

The [process document](doc/knowledge_base/claude-driven-development.md) describes the full lifecycle, the artifacts, the edit rules, and the reasoning behind every gate. Read it first if you want to understand what CDD is and why.

## Three objectives

CDD is built around three goals, in tension and balanced on purpose:

- **Automate everything except the decisions that matter.** The agent handles implementation, verification, and documentation. You keep control through explicit human gates: picking the task, approving the plan, approving any base-branch merge, merging the PR. Everything between the gates is automated; the gates never are.
- **Bake in engineering best practices.** Tests, linting, formatting, CI, and living documentation aren't bolted on at the end. The workflow expects them at every step and reconciles docs and roadmap with each change, so quality and context don't erode as the project grows.
- **Improve the workflow as you use it.** CDD is meant to be turned on itself. Friction surfaced in a session folds back into the process and the template, so the workflow gets sharper over time.

## Quick start

CDD's front door is its guided commands. Run them from a Claude Code session inside a clone of this repo (`git clone https://github.com/drabaioli/cdd.git && cd cdd && claude`).

**Start a brand-new project:** run `/cdd-bootstrap`. It walks you through defining the project and drafting a real roadmap through conversation, then scaffolds everything in one go (overview, `CLAUDE.md`, and roadmap already filled in), leaving you ready to run the task cycle above.

**Bring CDD to a project you already have:** run `/cdd-retrofit`. It installs CDD into an existing codebase, or upgrades a project already running CDD, preserving your local customizations along the way.

**Produce a one-off deliverable** that doesn't warrant a whole project (a single script plus a README, no roadmap or project substrate): run `/cdd-quick-create`.

## Command reference

CDD ships seven slash commands, all prefixed `cdd-` so they autocomplete as a group.

**Per-task cycle**, shipped into every CDD project via the template:

| Command | What it does |
| --- | --- |
| `/cdd‑next‑step` | Scope the next task and write a handoff for a fresh implementation session. Three front-ends: the next roadmap item, a typed task prompt (off-roadmap), or a GitHub issue (`#NN` / a bare integer / the `issue` keyword). |
| `/cdd‑merge‑base` | Integrate the base branch into a feature branch when the base has advanced under you (dry-run first, then apply). |
| `/cdd‑pre‑pr` | Pre-PR checklist: CI gates, code review, and doc/roadmap reconciliation; ends with an opt-in step to open the PR. |
| `/cdd‑process‑pr` | Triage and address the open PR's review feedback, reply in-thread, and commit and push. |

**CDD-repo-only**, run from a session inside this repo; they operate *on* a target, so the template ships no copy:

| Command | What it does |
| --- | --- |
| `/cdd‑bootstrap` | Guided greenfield: define the project and draft a roadmap through conversation, then scaffold it. |
| `/cdd‑retrofit` | Install or upgrade CDD in an existing project. |
| `/cdd‑quick‑create` | Produce a one-off self-contained deliverable (script + README), no project substrate. |

`cdd-worktree` (and its companions `cdd-worktree-done`, `cdd-worktree-list`, and `cdd-worktree-resume`) is a **shell helper**, not a slash command. It's a single project-independent script — a machine-global toolchain dependency, like `git` or `gh` — that you install once and that then works in every CDD project. From a CDD repo checkout: `tools/cdd-worktree.sh install`. On a fresh machine with only a downstream project (no CDD repo), one command fetches and installs it:

```bash
curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/cdd-worktree.sh \
  --create-dirs -o ~/.cdd/tools/cdd-worktree.sh \
  && bash ~/.cdd/tools/cdd-worktree.sh install
```

Either form wires `~/.bashrc` and `~/.zshrc` (idempotent); open a new shell afterwards. It spins up and tears down the per-task git worktree that an implementation session runs in, and `cdd-worktree-resume [<branch>]` recreates that worktree on a second machine — tracking the existing remote branch, no handoff needed — so a task started elsewhere can be picked up to run `/cdd-process-pr`, `/cdd-merge-base`, or `/cdd-pre-pr`.

## Questions?

The fastest way to understand how CDD works is to ask it directly: open your local clone with `claude` and ask Claude Code questions about the project. The process doc, the template, and these docs are all right there for it to read: "why the human gates?", "what does `/cdd-merge-base` actually do?", and so on.

## Contributing

At this stage CDD accepts **GitHub issues only; pull requests aren't open yet**. Bug reports, suggestions, and questions about the workflow are very welcome: please [open an issue](https://github.com/drabaioli/cdd/issues). Have a change in mind? Raise it as an issue first and we can discuss it there. Direct PRs aren't being accepted for now. That will change as the project opens up.

## Status

In active use, and dogfooded on itself. CDD has driven full task cycles end to end (real merges and PR reviews) on a downstream demo project (see [`demo/`](demo/)) and been retrofitted onto existing real-world codebases, with the friction found along the way folded back into the template. See [`doc/knowledge_base/roadmap.md`](doc/knowledge_base/roadmap.md) for what's done and what's next.

## License

[MIT](LICENSE) © Diego Andres Rabaioli.
