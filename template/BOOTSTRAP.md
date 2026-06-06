# Bootstrapping a project from the CDD template

This document lives **inside** the template directory but is **not** copied into the bootstrapped project; the bootstrap script (`bootstrap-cdd-project.sh` at the CDD repo root) excludes it. Its audience is the person about to run the bootstrap script, not the future maintainer of the bootstrapped project.

The Claude-Driven Development workflow itself is described in `doc/knowledge_base/claude-driven-development.md` in the CDD repo. Read that once before bootstrapping; the slash commands assume you understand the workflow they're part of.

## What you get

After bootstrap, the new project directory contains:

```
<PROJECT_DIR>/
├── CLAUDE.md                                 # entry point Claude Code reads
├── .claude/
│   ├── cdd-baseline                          # CDD repo commit the template was rendered from
│   └── commands/
│       ├── next-step.md                      # exploratory session
│       ├── pre-pr.md                         # verification session
│       └── merge-main.md                     # merge from main, with dry-run
├── doc/
│   ├── architecture/index.md                 # what the system is, structurally
│   ├── features/index.md                     # what the system does
│   └── knowledge_base/
│       ├── roadmap.md                        # central workflow artifact
│       └── README.md                         # explains the knowledge base
└── tools/
    └── <PROJECT_SLUG>-worktree.sh            # worktree helper, already renamed
```

The bootstrap script also runs `git init -b main` and creates a single "Initial CDD scaffold" commit.

## The three-identifier model

A CDD project carries three distinct identifiers. The template encodes them as separate placeholders so substitution can't conflate them:

| Placeholder       | Role                                       | Example                              |
| ----------------- | ------------------------------------------ | ------------------------------------ |
| `<PROJECT_NAME>`  | Display name; may contain spaces.          | `Sprint Planning Automation POC`     |
| `<PROJECT_SLUG>`  | Shell-command slug; valid shell identifier prefix (lowercase, hyphens OK). Used wherever `<slug>-worktree` is referenced. | `spa-poc`                            |
| `<PROJECT_DIR>`   | Directory / repo slug. Used in `$HOME/Code/<PROJECT_DIR>/...` and as the working tree's directory name. Often equal to the slug, allowed to differ. | `sprint-planning-automation-poc`     |

A fourth, internal-only token — bare `PROJECT` — appears inside `template/tools/PROJECT-worktree.sh` where shell function names are defined. Angle-bracketed placeholders aren't valid shell identifiers, so the template uses `PROJECT-worktree()` and the bootstrap script substitutes the bare token with the same value as `<PROJECT_SLUG>`. You shouldn't need to think about this — `bootstrap-cdd-project.sh` handles it.

Other angle-bracketed text in the template (e.g. `<one-paragraph project description>`, `<build command>`) is free-form fill-in: the bootstrap script leaves it alone, and you fill it in by hand after bootstrap.

## Bootstrap procedure

From the CDD repo root:

```bash
./bootstrap-cdd-project.sh \
  --name "My Project Display Name" \
  --slug myproject \
  --path ../my-project
```

`--path` is where the project will be created (absolute or relative to the current directory). Its basename becomes the directory slug (`<PROJECT_DIR>`). The path must not exist, or must be an empty directory.

The script will:

1. Refuse to proceed if the target directory exists and is non-empty.
2. Copy `template/` into the target, excluding this `BOOTSTRAP.md`.
3. Rename `tools/PROJECT-worktree.sh` → `tools/<slug>-worktree.sh`.
4. Substitute `<PROJECT_NAME>`, `<PROJECT_SLUG>`, `<PROJECT_DIR>`, and the in-script bare `PROJECT` token, in that order.
5. Write the baseline marker `.claude/cdd-baseline` (the CDD repo commit hash the template was rendered from; used later by `/retrofit`'s upgrade mode).
6. Run `git init -b main` and create an initial scaffold commit.
7. Print a "next steps" block including the exact `source` line to add to your `~/.bashrc`.

## After bootstrap

1. **Add the worktree-helper source line to `~/.bashrc`.** The script prints the exact line; copy it as-is. The line looks like:

   ```bash
   [[ -f "$HOME/Code/<PROJECT_DIR>/tools/<PROJECT_SLUG>-worktree.sh" ]] && source "$HOME/Code/<PROJECT_DIR>/tools/<PROJECT_SLUG>-worktree.sh"
   ```

   Open a new shell or `source ~/.bashrc`. The slash commands rely on `<PROJECT_SLUG>-worktree` being on `PATH`; `/next-step` prints a reminder of this line after the `Next:` instruction so a missing source line is a one-paste fix rather than a hunt.

2. **Fill in `CLAUDE.md`**: the one-paragraph description, the critical constraints, the build/test commands, the module layout. Anything still wrapped in `<...>` is a stub waiting for you.

3. **Write the initial roadmap** in `doc/knowledge_base/roadmap.md`. The template ships an empty Phase 1 / Phase 2 / Phase N skeleton; the content is yours to write. Note that bootstrap has already initialised git and laid down the CDD scaffold, so Phase 1 should start from "add language/tooling scaffold" rather than "initialise the repo".

4. **Start the first task**: run `claude` from the project root and invoke `/next-step`. The per-repo handoff directory `~/.claude-handoffs/<PROJECT_DIR>/` is created on demand.

## Per-project customisation

A few things you'll want to add or change as the project takes shape:

- **A coding standard** under `doc/knowledge_base/`, referenced from `CLAUDE.md`. The template does not ship one and does not reserve a row for one in `CLAUDE.md`'s Key references table; add the row when you add the standard.
- **Decision records** under `doc/knowledge_base/` as you make significant tooling or design choices. Append-only.
- **Build commands** in `CLAUDE.md` and in `pre-pr.md` step 2. Replace the `<build command>`-style placeholders with the actual commands.
- **Test categories** in `pre-pr.md` step 2. Add or remove jobs as appropriate.

## Required CLI tools

- `git` (with worktree support, any modern version).
- `gh` (GitHub CLI), used by `<PROJECT_SLUG>-worktree-done` and `<PROJECT_SLUG>-worktree-list` to query PR state. Optional but recommended.
- `claude` (Claude Code CLI).
