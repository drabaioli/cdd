# Claude-Driven Development (CDD) Template

This directory is a copy-paste template for starting a new project that uses the Claude-Driven Development workflow. The workflow itself is described in `claude-driven-development.md` (the process document); this README covers how to bootstrap a new project from the template.

## What you get

```
<your project>/
├── CLAUDE.md                                 # entry point Claude Code reads
├── .claude/
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
    └── PROJECT-worktree.sh                   # worktree helper (rename + edit)
```

## Placeholder convention

The template uses two placeholder forms:

- `<PROJECT_NAME>`: replace with your project's display name.
- `PROJECT` (used in shell function names and the script filename): replace with your project's identifier, lowercase, no spaces.
- `<...>` (any other angle-bracketed text): free-form fill-in for project-specific content.

A simple way to apply the rename:

```bash
PROJECT_NAME="My Project"
PROJECT="myproject"

# Rename the worktree script file.
mv tools/PROJECT-worktree.sh "tools/${PROJECT}-worktree.sh"

# Replace placeholders in all files.
grep -rl '<PROJECT_NAME>' . | xargs sed -i "s/<PROJECT_NAME>/${PROJECT_NAME}/g"
grep -rl 'PROJECT' "tools/${PROJECT}-worktree.sh" | xargs sed -i "s/PROJECT/${PROJECT}/g"
```

After this you should have no `<PROJECT_NAME>` or bare `PROJECT` literals left (the angle-bracketed free-form placeholders like `<one-paragraph project description>` are intentional and need manual filling).

## Bootstrap procedure

1. **Copy the template into your new project root.**

   ```bash
   cp -r <path-to-template>/* <path-to-your-project>/
   ```

2. **Rename and substitute placeholders** as shown above.

3. **Source the worktree script from your shell rc.** Add to `~/.bashrc` (or `~/.zshrc`):

   ```bash
   [[ -f "$HOME/Code/<your project>/tools/<project>-worktree.sh" ]] && \
     source "$HOME/Code/<your project>/tools/<project>-worktree.sh"
   ```

   Open a new shell or `source ~/.bashrc`.

4. **Fill in `CLAUDE.md`**: the one-paragraph description, the critical constraints quick reference, the build/test commands, and the module layout (which you may not have yet, that's fine, leave it as a stub and fill it in as the structure emerges).

5. **Write the initial roadmap** in `doc/knowledge_base/roadmap.md`. This is the one piece of content the template does not generate for you. Phases and tasks should reflect what you actually want to build.

6. **Commit the initial state** to git and push. (`/next-step` creates the per-repo handoff directory `~/.claude-handoffs/<repo-name>/` on demand the first time you run it.)

7. **Start the first task**: run `claude` from your project root and invoke `/next-step`.

## Per-project customization

A few things you will want to add or change as the project takes shape:

- **A coding standard** under `doc/knowledge_base/`, referenced from `CLAUDE.md`. The template does not ship one because it is language-specific.
- **Decision records** under `doc/knowledge_base/` as you make significant tooling or design choices. These are append-only.
- **Build commands** in `CLAUDE.md` and in `pre-pr.md` step 2. The template uses `<build command>` style placeholders; replace them with the actual commands.
- **Test categories** in `pre-pr.md` step 2. Add or remove jobs as appropriate.

## Required CLI tools

The workflow depends on:

- `git` (with worktree support, any modern version).
- `gh` (GitHub CLI), used by `PROJECT-worktree-done` and `PROJECT-worktree-list` to query PR state. Optional but recommended.
- A clipboard tool (one of `wl-copy`, `xclip`, or `pbcopy`), used by `PROJECT-worktree` to copy the first prompt to the clipboard. Optional, the prompt is printed if no tool is available.
- `claude` (Claude Code CLI).

## Reference

The full philosophy, lifecycle, and edit rules are in `claude-driven-development.md`. Read it once before you start; the slash commands assume you understand the workflow they're part of.
