# CDD (Claude-Driven Development) — Claude Code Context

CDD is a human-in-the-loop workflow for evolving software projects together with Claude Code. This repository contains the process document (the philosophy and lifecycle) and the template (copy-paste material for bootstrapping new projects). The CDD repo itself uses CDD on itself; the template under `template/` is content this project ships, not the project's own scaffolding.

## Key references

| Topic                                                | Location                                          |
| ---------------------------------------------------- | ------------------------------------------------- |
| Process document (philosophy, lifecycle, edit rules) | `doc/knowledge_base/claude-driven-development.md` |
| Implementation roadmap                               | `doc/knowledge_base/roadmap.md`                   |
| Engineering practices (enforced, upheld, expected)         | `doc/knowledge_base/engineering-practices.md`     |
| Documentation map                                    | `doc/index.md`                                    |
| Architecture and layout of this repo                 | `doc/architecture/index.md`                       |
| Capability adapter contract (tracker and code-host verbs, shapes) | `doc/architecture/capability-adapters.md`         |
| Decision records (ADRs, every kind of decision)      | `doc/architecture/adr/` (Nygard style)            |
| Features of this repo                                | `doc/features/index.md`                           |
| Template (what gets copied into new projects)        | `template/`                                       |
| Bootstrap procedure for new projects                 | `template/BOOTSTRAP.md`                           |
| Guided greenfield bootstrap                          | `.claude/commands/cdd-bootstrap.md` (`/cdd-bootstrap`)    |
| Lightweight one-off deliverable                      | `.claude/commands/cdd-quick-create.md` (`/cdd-quick-create`) |
| Non-interactive bootstrap script                     | `tools/bootstrap-cdd-project.sh`                  |
| Demo / dogfooding subsystem (seed + automation)      | `demo/` (start with `demo/README.md`)             |
| Command extensions (project additions to shipped commands) | `.cdd/extensions/` (this repo: `cdd-pre-pr.md`, `cdd-process-pr.md`) |

**Read `doc/knowledge_base/claude-driven-development.md` before making any structural change to the workflow or template.** The process doc is the source of truth; the template is its instantiation. Changes flow process-first, template-second.

Each doc directory keeps an `index.md` pointer list: read the index, then load only the documents you need.

## Critical constraints (quick reference)

- Two layers, kept consistent: process doc (`doc/knowledge_base/claude-driven-development.md`) and template (`template/`). A PR that touches the process doc but not the template (or vice versa) is suspicious and should be justified explicitly.
- The process doc stays at workflow altitude — what things are, never how a script implements them — and an argument lives once: in its ADR, or `doc/architecture/` for mechanics, with every other site carrying the rule plus a pointer (the notes atop the process doc; ADR 0018).
- Slash commands carry instructions only: steps, decisions, stop conditions, shell commands, exact printed output, checkpoints. A reason appears only as a pointer to its home, nothing is repeated within a command, and behaviour is never traded for size — the rule above, applied to `.claude/commands/` (and the template's copies) whenever a command is edited or added.
- Human-in-the-loop checkpoints are load-bearing. Do not propose removing or weakening any of the six checkpoints in section 4 of the process doc without explicit discussion.
- Template files use a two-identifier placeholder model — `<PROJECT_NAME>` (display) and `<PROJECT_DIR>` (directory/repo slug). Free-form `<...>` text is fill-in content. Do not introduce a templating engine; placeholders must remain plain text so the template stays human-readable and Claude-readable. See section 2.9 of the process doc for the model, and `template/BOOTSTRAP.md` for the bootstrap recipe.
- The template is generic. Do not introduce content drawn from a specific downstream project (e.g. firmware-specific conventions, web-specific build commands) into `template/` files. Per-project-type variants are deferred design (see process doc section 6).
- `demo/` is a third artifact, separate from `template/` and `scripts/`. Its filled-in seed (`demo/seed/`) holds concrete "Markdown Renderer" project content — which is allowed *because* it lives under `demo/`. None of it may leak into `template/`. `demo/setup.sh` must keep wrapping `bootstrap-cdd-project.sh` (via `--overlay`) rather than duplicating the substitution logic.
- The CDD repo's own `.claude/commands/` and the template's `.claude/commands/` may drift slightly if needed, but unintended drift is a defect. `scripts/command-drift-check.sh` (run by CI and `/cdd-pre-pr`) verifies this mechanically: it renders the template and diffs the command set, the agent definitions (`.claude/agents/`), the hooks (`.claude/hooks/`) and `.claude/settings.json`, so only real divergence surfaces; this repo's own additions to a shipped command live in `.cdd/extensions/`, like a downstream project's, so its copies equal the rendered template; justified exceptions are whole files listed in `scripts/command-drift-whitelist.txt` — a CDD-only `settings.json` entry costs a whitelist line for the whole file. Justified one-sided cases: `/cdd-retrofit` (`.claude/commands/cdd-retrofit.md`), `/cdd-bootstrap` (`.claude/commands/cdd-bootstrap.md`), and `/cdd-quick-create` (`.claude/commands/cdd-quick-create.md`) live only in the CDD repo — all three operate *on* a target from a CDD session (retrofit adapts an existing project, bootstrap creates a new one, quick-create produces a one-off deliverable), so the template ships no copy.

## Build & test

This repo is documentation and shell scripts; there is no build step. Every check runs from one command:

```bash
./scripts/ci.sh                  # every gate, then a PASS/FAIL summary
./scripts/ci.sh list             # the gate slugs
./scripts/ci.sh <gate> [<gate>]  # rerun one gate while iterating on a failure
```

`scripts/ci.sh` is the **single source of the gate sequence** (process doc §2.14): CI (Ubuntu and macOS) and `/cdd-pre-pr` both call it, and neither holds a gate list. The 34 gates are the registry at the top of the script, one line each saying what it checks; each gate's script under `scripts/` also runs standalone. Needs bash >= 4, `shellcheck`, `jq` and `tar` (the runner stubs `claude` itself) — **a missing tool fails its gate, never skips it**. `scripts/install-deps.sh` installs this repo's tools: CDD's required set plus `gh`, `shellcheck` and `tar` (`--check` only reports). The run is not fail-fast. Mechanics: `doc/architecture/overview.md`.

What `/cdd-pre-pr` adds in this repo — the macOS caveat and how to triage the `drift` and `seams` gates — lives in `.cdd/extensions/cdd-pre-pr.md`.

## Talking to the human

Anything printed for the human — a checkpoint digest, a session's closing report, a question — is **short, plainly worded, and only what changes their answer**.

- **Short.** A few lines. Long enough to decide against, short enough to be read rather than skimmed; a wall of text turns a checkpoint into a rubber stamp.
- **Plain.** Ordinary words, not the project's own vocabulary — "the tests that cover the parser all pass", not "the parser suite's coverage gate is green". Name a mechanism only when the human needs it to act.
- **Only what decides.** What the thing is, why, and anything that would change the answer. Leave out what they will see anyway at review time: the file list, the internal mechanics, the log of how you got there.
- **Silent when normal.** A check that passed or a default that held prints nothing; only what needs the human or changes their answer gets a line.

Correctness outranks brevity — if a point cannot be made both plainly and correctly in the space, say it correctly.

## Writing changes

Write every change in the least code, prose and structure that still delivers the best solution. Bloat is repeated code, abstractions nothing needs yet, handling for errors that can't happen, comments or docs that only restate the code, and wordy prose. This is about how each change is written, not how much a task touches: fixing an unrelated bug or improving quality along the way stays welcome.

Coding agents go wrong in a few documented ways. Each rule below names one, and stops where following it further would add code:

- **Duplicated helpers.** Before writing a helper, look for one the project already has and use it if it fits as is. Don't reshape working code just to share it.
- **Hidden failures.** Don't swallow an error or fall back silently: what the code can't handle surfaces. Validate input where it enters from outside (users, files, the network, other services), and trust it after.
- **Gamed or bug-locking tests.** A test checks what the code should do: take its expected values from the requirement, not from what the code returns, and don't weaken, skip or special-case a test to make it pass. If a test or the task looks wrong, stop and say so. A test may change with behaviour that is meant to change; say which.
- **Made-up dependencies.** Before adding a package, check on its registry that it exists and is the one you mean, and that nothing the project already uses covers the need. Hand-rolling what an established library does is not the alternative.

Language-specific rules belong in the project's linter config and coding standard, not here.

## Workflow

This project uses CDD on itself. Every CDD session is a fresh context doing exactly one job (see process doc section 3 for the session taxonomy).

- **To start a new task** (handoff session): run `/cdd-next-step` from the main worktree to produce a handoff, then run `cdd-worktree <branch>` to spin up the task worktree. `/cdd-next-step` has three front-ends: no argument picks the next roadmap item; a task prompt starts off-roadmap work (intent-driven); and an argument matching the resolved tracker's `ref_pattern` — or the `issue`/`issues` keyword sources the task from an issue (issue-driven). Several refs may be given at once; they are recorded on the task's state record (`cdd-state issue-refs`), which is the only thing carrying them forward — branch names stay plain descriptive slugs in every mode.
- **To build the task** (plan session, then implementation session): `cdd-worktree <branch>` opens a session on `/cdd-plan`, which explores, researches at the depth the handoff set (through web-only `cdd-researcher` subagents), takes plan approval, writes the plan file to `~/.cdd/handoffs/cdd/<branch>.plan.md`, and stops without touching the repo. Then open a **fresh** `claude` in that same worktree and run `/cdd-implement`, which builds from the plan file, updates the docs, and commits locally. The manual step between them is deliberate: it is where you read or edit the plan.
- **When the task is small enough to state in one sentence** (small-change lane): `/cdd-next-step` recommends the lane and records it, and `cdd-worktree <branch>` then opens the worktree on `/cdd-small-change` instead — one session that takes its own approval of the concrete change, makes it, updates the docs, and commits. It hands back to `/cdd-plan` in the same worktree if the task turns out not to be small. Anything missing (an old helper, no marker) falls back to the standard lane.
- **To pick up a task started on another machine** (resume): run `cdd-worktree-resume [<branch>]` from the main worktree. It recreates the worktree on the existing remote branch (no handoff needed) and `cd`s into it, then tells you what to run next based on the task's lane and stage: a small-change task not yet built resumes into `/cdd-small-change`; a task sitting at `plan_written` resumes into `/cdd-implement` (its plan rides the task ref along with the handoff and state record when task-ref sync is on: `git config cdd.syncTaskRef true`, off by default, private repos only); anything else into `/cdd-process-pr`, `/cdd-merge-base`, or `/cdd-pre-pr`. With no argument it lists resumable remote branches.
- **When main has advanced under a feature branch** (merge session): run `/cdd-merge-base` in a fresh context on the feature branch.
- **Before opening a PR** (pre-PR session): run `/cdd-pre-pr` in a fresh context to verify the process doc and template are consistent and the roadmap reflects what landed; it auto-commits its own reconciliation edits (local, no push) and ends with an opt-in step to open the PR (one close line per ref recorded on the state record, derived through the tracker's `issue-close-token` — none for an issue it judges the PR only partly does, which stays open; with no usable record there are no close lines, said out loud rather than guessed).
- **When a PR review leaves comments** (PR-review session): run `/cdd-process-pr` in a fresh context on the feature branch.
- **To clean up finished tasks' artifacts** (maintenance, not a session): run `cdd-worktree-gc` from the main worktree. It reaps the handoff, plan file, state record, and synced `refs/cdd/<branch>` of any task whose PR has merged, first closing the issues recorded on its state record (a partial one stays open) and linking the merged PR on each — the backstop for `cdd-worktree-done` (which closes them itself once the PR is confirmed merged) never running or its ref cleanup failing across machines. Dry-run by default; `--force` to delete.
- **To add a project step to a CDD command**: write `.cdd/extensions/<command>.md` (e.g. `.cdd/extensions/cdd-pre-pr.md`), one `##` heading per step it attaches to, named by that step's title. Never edit `.claude/commands/cdd-*.md`. An extension only adds; a deterministic pass/fail check belongs in the check runner instead.
- Keep the process doc, template, and roadmap consistent as part of every change. Process-first, then template.
