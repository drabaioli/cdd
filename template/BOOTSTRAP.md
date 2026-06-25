# Bootstrapping a project from the CDD template

This document lives **inside** the template directory but is **not** copied into the bootstrapped project; the bootstrap script (`tools/bootstrap-cdd-project.sh` in the CDD repo) excludes it. Its audience is the person about to run the bootstrap script, not the future maintainer of the bootstrapped project.

The Claude-Driven Development workflow itself is described in `doc/knowledge_base/claude-driven-development.md` in the CDD repo. Read that once before bootstrapping; the slash commands assume you understand the workflow they're part of.

## What you get

After bootstrap, the new project directory contains:

```
<PROJECT_DIR>/
├── CLAUDE.md                                 # entry point Claude Code reads
├── .claude/
│   ├── cdd-baseline                          # CDD repo commit the template was rendered from
│   ├── settings.json                         # auto-allows worktree sessions to read their handoff file
│   └── commands/
│       ├── cdd-next-step.md                      # handoff session
│       ├── cdd-pre-pr.md                         # pre-PR session
│       ├── cdd-merge-base.md                     # merge session (merge from main, with dry-run)
│       └── cdd-process-pr.md                     # PR-review session (address PR review feedback)
├── doc/
│   ├── index.md                              # documentation map (pointer to the directories below)
│   ├── architecture/index.md                 # what the system is, structurally (pointer index)
│   ├── features/index.md                     # what the system does (pointer index)
│   └── knowledge_base/
│       ├── project-overview.md               # project charter skeleton (what it is, goals, non-goals)
│       ├── roadmap.md                        # central workflow artifact, Phase 1 pre-filled
│       └── README.md                         # explains the knowledge base
```

(No `tools/` directory: the worktree helper is a single project-independent script you install once — see below — not a per-project file.)

The bootstrap script also runs `git init -b main` and creates a single "Initial CDD scaffold" commit.

## The two-identifier model

A CDD project carries two distinct identifiers. The template encodes them as separate placeholders so substitution can't conflate them:

| Placeholder       | Role                                       | Example                              |
| ----------------- | ------------------------------------------ | ------------------------------------ |
| `<PROJECT_NAME>`  | Display name; may contain spaces.          | `Sprint Planning Automation POC`     |
| `<PROJECT_DIR>`   | Directory / repo slug; the working tree's directory name. May be CamelCase to match the repo folder. | `sprint-planning-automation-poc` or `PyGroundControl` |

Other angle-bracketed text in the template (e.g. `<one-paragraph project description>`, `<build command>`) is free-form fill-in: the bootstrap script leaves it alone, and you fill it in by hand after bootstrap.

## Bootstrap procedure

From the CDD repo root:

```bash
./tools/bootstrap-cdd-project.sh \
  --name "My Project Display Name" \
  --path ../my-project
```

`--path` is where the project will be created (absolute or relative to the current directory). Its basename becomes the directory slug (`<PROJECT_DIR>`). The path must not exist, or must be an empty directory.

The script will:

1. Refuse to proceed if the target directory exists and is non-empty.
2. Copy `template/` into the target, excluding this `BOOTSTRAP.md`.
3. Substitute `<PROJECT_NAME>` and `<PROJECT_DIR>`.
4. Write the baseline marker `.claude/cdd-baseline` (the CDD repo commit hash the template was rendered from; used later by `/cdd-retrofit`'s upgrade mode).
5. Run `git init -b main` and create an initial scaffold commit.
6. Print a "next steps" block pointing at the one-time worktree-helper install.

## After bootstrap

1. **Install the shared worktree helper (one-time, project-independent).** If you haven't installed it for an earlier CDD project, run it once from the CDD repo:

   ```bash
   ./tools/cdd-worktree.sh install
   ```

   This copies the helper to `~/.cdd/tools/cdd-worktree.sh` and wires `~/.bashrc` and `~/.zshrc` to source it (idempotent). Open a new shell. After this, `cdd-worktree` works in every CDD project — there is nothing per-project to add. `/cdd-next-step` prints the install command if `cdd-worktree` isn't found, so a missing install is a one-paste fix rather than a hunt.

2. **Fill in `CLAUDE.md`**: the one-paragraph description, the critical constraints, the build/test commands, the module layout. Anything still wrapped in `<...>` is a stub waiting for you. Likewise fill in the project charter at `doc/knowledge_base/project-overview.md` — what the project is, its goals, what it does and explicitly does not do, its constraints and architecture intentions. (The Phase 1 bootstrap tasks also cover this; doing the thin version now is fine.)

3. **Look at the roadmap** in `doc/knowledge_base/roadmap.md`. The template ships Phase 1 pre-filled with the CDD bootstrap tasks (codebase survey, initial architecture and feature docs, CLAUDE.md stubs, roadmap fill) plus a suggested-infrastructure task list (CI, linting, tests, …) to slot into the real phases; the phases after Phase 1 are placeholders for the project's actual plan. You can write that plan by hand now, or let the Phase 1 "fill in this roadmap" task drive it through the workflow.

4. **Start the first task**: run `claude` from the project root and invoke `/cdd-next-step`. The per-repo handoff directory `~/.cdd/handoffs/<PROJECT_DIR>/` is created on demand.

## Per-project customisation

A few things you'll want to add or change as the project takes shape:

- **A coding standard** under `doc/knowledge_base/`, referenced from `CLAUDE.md`. The template does not ship one and does not reserve a row for one in `CLAUDE.md`'s Key references table; add the row when you add the standard.
- **Decision records** under `doc/knowledge_base/` as you make significant tooling or design choices. Append-only.
- **Build commands** in `CLAUDE.md` and in `cdd-pre-pr.md` step 2. Replace the `<build command>`-style placeholders with the actual commands.
- **Test categories** in `cdd-pre-pr.md` step 2. Add or remove jobs as appropriate.
- **Remote name**: the worktree helper assumes the remote is named `origin`. It derives the default branch from `origin`'s HEAD (falling back to `main`), so repos whose default branch is `master` work unchanged; a differently-named remote requires editing the shared helper at `~/.cdd/tools/cdd-worktree.sh`.

## Required CLI tools

- `git` (with worktree support, any modern version).
- `gh` (GitHub CLI), used by `cdd-worktree-done` and `cdd-worktree-list` to query PR state. Optional but recommended.
- `claude` (Claude Code CLI).
