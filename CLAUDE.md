# CDD (Claude-Driven Development) — Claude Code Context

CDD is a human-in-the-loop workflow for evolving software projects together with Claude Code. This repository contains the process document (the philosophy and lifecycle) and the template (copy-paste material for bootstrapping new projects). The CDD repo itself uses CDD on itself; the template under `template/` is content this project ships, not the project's own scaffolding.

## Key references

| Topic                                                | Location                                          |
| ---------------------------------------------------- | ------------------------------------------------- |
| Process document (philosophy, lifecycle, edit rules) | `doc/knowledge_base/claude-driven-development.md` |
| Implementation roadmap                               | `doc/knowledge_base/roadmap.md`                   |
| Engineering practices (enforced vs expected)         | `doc/knowledge_base/engineering-practices.md`     |
| Documentation map                                    | `doc/index.md`                                    |
| Architecture of this repo                            | `doc/architecture/index.md`                       |
| Architecture decision records                        | `doc/architecture/adr/` (Nygard style)            |
| Features of this repo                                | `doc/features/index.md`                           |
| Template (what gets copied into new projects)        | `template/`                                       |
| Bootstrap procedure for new projects                 | `template/BOOTSTRAP.md`                           |
| Guided greenfield bootstrap                          | `.claude/commands/cdd-bootstrap.md` (`/cdd-bootstrap`)    |
| Lightweight one-off deliverable                      | `.claude/commands/cdd-quick-create.md` (`/cdd-quick-create`) |
| Non-interactive bootstrap script                     | `tools/bootstrap-cdd-project.sh`                  |
| Demo / dogfooding subsystem (seed + automation)      | `demo/` (start with `demo/README.md`)             |

**Read `doc/knowledge_base/claude-driven-development.md` before making any structural change to the workflow or template.** The process doc is the source of truth; the template is its instantiation. Changes flow process-first, template-second.

Each doc directory keeps an `index.md` pointer list: read the index, then load only the documents you need.

## Critical constraints (quick reference)

- Two layers, kept consistent: process doc (`doc/knowledge_base/claude-driven-development.md`) and template (`template/`). A PR that touches the process doc but not the template (or vice versa) is suspicious and should be justified explicitly.
- The process doc stays at workflow altitude: artifacts, lifecycle, edit rules, invariants — never how a script implements them. Implementation mechanics belong in code comments and `doc/architecture/` (e.g. `doc/architecture/shell-helpers.md`), with a one-line pointer left in the process doc. The editing test lives in the "Document altitude" note at the top of the process doc.
- Human-in-the-loop checkpoints are load-bearing. Do not propose removing or weakening any of the six checkpoints in section 4 of the process doc without explicit discussion.
- Template files use a two-identifier placeholder model — `<PROJECT_NAME>` (display) and `<PROJECT_DIR>` (directory/repo slug). Free-form `<...>` text is fill-in content. Do not introduce a templating engine; placeholders must remain plain text so the template stays human-readable and Claude-readable. See section 2.9 of the process doc for the model, and `template/BOOTSTRAP.md` for the bootstrap recipe.
- The template is generic. Do not introduce content drawn from a specific downstream project (e.g. firmware-specific conventions, web-specific build commands) into `template/` files. Per-project-type variants are deferred design (see process doc section 6).
- `demo/` is a third artifact, separate from `template/` and `scripts/`. Its filled-in seed (`demo/seed/`) holds concrete "Markdown Renderer" project content — which is allowed *because* it lives under `demo/`. None of it may leak into `template/`. `demo/setup.sh` must keep wrapping `bootstrap-cdd-project.sh` (via `--overlay`) rather than duplicating the substitution logic.
- The CDD repo's own `.claude/commands/` and the template's `.claude/commands/` may drift slightly if needed, but unintended drift is a defect. `scripts/command-drift-check.sh` (run by CI and `/cdd-pre-pr`) verifies this mechanically: it renders the template and diffs the command set, so only real divergence surfaces; justified exceptions live in `scripts/command-drift-whitelist.txt` or behind `cdd-only` markers. Justified one-sided cases: `/cdd-retrofit` (`.claude/commands/cdd-retrofit.md`), `/cdd-bootstrap` (`.claude/commands/cdd-bootstrap.md`), and `/cdd-quick-create` (`.claude/commands/cdd-quick-create.md`) live only in the CDD repo — all three operate *on* a target from a CDD session (retrofit adapts an existing project, bootstrap creates a new one, quick-create produces a one-off deliverable), so the template ships no copy.

## Build & test

This repo is documentation and shell scripts; there is no build step. Every check runs from one command:

```bash
./scripts/ci.sh                  # every gate, then a PASS/FAIL/SKIP summary
./scripts/ci.sh list             # the gate slugs
./scripts/ci.sh <gate> [<gate>]  # rerun one gate while iterating on a failure
```

`scripts/ci.sh` is the **single source of the gate sequence** (process doc §2.14) — the gate registry at the top of the script is the list, and there is no second copy. `.github/workflows/template-smoke.yml` holds no gate list at all: it checks out and calls the runner, so CI and a local run cannot drift. `/cdd-pre-pr` invokes the same command, so a green local run means a green CI run.

The 16 gates: `syntax` and `shellcheck` over every shell script; `drift` (repo `.claude/commands/` vs the rendered template), `seams` (prompt-seam contracts) and `seams-contract` (the seam checker's own contract, mutation-tested); the helper assertions `install-smoke`, `worktree-resume`, `ref-sync`, `gc`, `base-branch`; the render smokes `bootstrap`, `bootstrap-camelcase`, `stage-render`, `snapshot-render`; `demo-seed` (seed overlay, no GitHub side effects); and `runner` (the runner's own contract, `scripts/ci-runner-assert.sh`). Each gate's own script under `scripts/` still runs standalone if you want it directly.

Two behaviours worth knowing: a gate whose tool is missing (`shellcheck`, `jq`) is reported **SKIPPED — loudly and non-fatally**, so a host without it gets a weaker verdict, not a wrong one; and the run is **not fail-fast**, so one invocation surfaces every problem. The runner provisions its own scratch dir and a throwaway git identity, so it needs no host setup and is unaffected by your git signing config.

When `/cdd-pre-pr` runs in this repo, the "build / format / lint / test" gates collapse into `./scripts/ci.sh` plus a doc reconciliation pass.

## Module layout

| Directory                          | Purpose                                                   |
| ---------------------------------- | --------------------------------------------------------- |
| `doc/knowledge_base/`              | Process doc, roadmap, engineering practices, decision records |
| `doc/architecture/`                | How this repo is structured                               |
| `doc/features/`                    | What this repo provides (process + template)              |
| `template/`                        | Copy-paste material for new projects                      |
| `template/.claude/commands/`       | Slash commands shipped to new projects                    |
| `template/doc/`                    | Doc skeletons shipped to new projects                     |
| `template/BOOTSTRAP.md`            | Bootstrap recipe (not copied into the bootstrapped tree)  |
| `tools/bootstrap-cdd-project.sh`   | Non-interactive bootstrap script                          |
| `demo/`                            | Demo / dogfooding subsystem (third artifact)              |
| `demo/seed/`                       | Filled-in "Markdown Renderer" project content (not template) |
| `demo/{setup,teardown}.sh`         | Create/teardown demo & dogfood instances; `lib.sh` shared |
| `scripts/`                         | `ci.sh` (the check runner: the gate registry) + the gate scripts it calls — smoke assertions, install smoke, command-set drift check, prompt-seam check (with whitelists) |
| `.github/workflows/`               | CI: `template-smoke.yml` delegates to `scripts/ci.sh`     |
| `.claude/commands/`                | This repo's own slash commands                            |
| `tools/`                           | Bootstrap script + the canonical shared helpers (`cdd-worktree.sh`, `cdd-state.sh`, both self-installing) |

## Architecture

Two layers. The process doc describes the workflow abstractly: artifacts, lifecycle, edit rules, checkpoints. The template instantiates the workflow as concrete files a new project can copy. Changes should land in the process doc first, then propagate to the template, never the other way around. A third artifact, `demo/`, instantiates a concrete project from a filled-in seed to both demo and dogfood the workflow; it is downstream of the template and never feeds back into it. Architecture docs for this repo will grow as the structure stabilizes; for now, the layout above is the architecture.

See `doc/knowledge_base/claude-driven-development.md` for the full picture.

## Workflow

This project uses CDD on itself. Every CDD session is a fresh context doing exactly one job (see process doc section 3 for the session taxonomy).

- **To start a new task** (handoff session): run `/cdd-next-step` from the main worktree to produce a handoff, then run `cdd-worktree <branch>` to spin up the implementation worktree (implementation session, opens in plan mode). `/cdd-next-step` has three front-ends: no argument picks the next roadmap item; a task prompt starts off-roadmap work (intent-driven); and `#NN` / a bare integer / the `issue`/`issues` keyword sources the task from a GitHub issue (issue-driven), naming the branch `gh_issue_NN_<slug>`.
- **To pick up a task started on another machine** (resume): run `cdd-worktree-resume [<branch>]` from the main worktree. It recreates the worktree on the existing remote branch (no handoff needed) and `cd`s into it, ready for you to run `/cdd-process-pr`, `/cdd-merge-base`, or `/cdd-pre-pr`; with no argument it lists resumable remote branches.
- **When main has advanced under a feature branch** (merge session): run `/cdd-merge-base` in a fresh context on the feature branch.
- **Before opening a PR** (pre-PR session): run `/cdd-pre-pr` in a fresh context to verify the process doc and template are consistent and the roadmap reflects what landed; it auto-commits its own reconciliation edits (local, no push) and ends with an opt-in step to open the PR (adding `Closes #NN` when the branch carries the `gh_issue_NN` token).
- **When a PR review leaves comments** (PR-review session): run `/cdd-process-pr` in a fresh context on the feature branch.
- **To clean up finished tasks' artifacts** (maintenance, not a session): run `cdd-worktree-gc` from the main worktree. It reaps the handoff, state record, and synced `refs/cdd/<branch>` of any task whose PR has merged — the backstop for `cdd-worktree-done` never running or its ref cleanup failing across machines. Dry-run by default; `--force` to delete.
- Keep the process doc, template, and roadmap consistent as part of every change. Process-first, then template.
