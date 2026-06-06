# The template

A copy-paste directory (`template/`) plus a non-interactive bootstrap script (`bootstrap-cdd-project.sh` at the CDD repo root) that together start a new project on CDD. Template contents:

- `CLAUDE.md` skeleton with placeholders for project-specific content.
- `.claude/commands/{next-step,pre-pr,merge-main,process-pr}.md`: the four slash commands.
- `.claude/settings.json`: auto-allows worktree sessions to read their handoff file (`~/.claude-handoffs/<PROJECT_DIR>/**`), substituted at bootstrap.
- `doc/index.md` plus `doc/{architecture,features,knowledge_base}/`: the documentation map and doc directory skeletons; the architecture and features skeletons follow the index-plus-per-topic-docs convention.
- `doc/knowledge_base/roadmap.md`: roadmap skeleton with a pre-filled Phase 1 of CDD bootstrap tasks (codebase survey, initial architecture and feature docs, CLAUDE.md stubs, roadmap fill) plus a suggested-infrastructure task list (CI, linting, tests, …) to distribute across the project's real phases.
- `tools/PROJECT-worktree.sh`: worktree helper, renamed and substituted to `<PROJECT_SLUG>-worktree.sh` by the bootstrap script.
- `BOOTSTRAP.md`: meta-documentation for the bootstrap recipe. Not copied into the bootstrapped tree.

The bootstrap script substitutes the three identifiers (`<PROJECT_NAME>`, `<PROJECT_SLUG>`, `<PROJECT_DIR>`) and the bare `PROJECT` token inside the worktree helper, writes the baseline marker `.claude/cdd-baseline` (the CDD repo commit the template was rendered from), runs `git init`, and creates the scaffold commit. It also offers a render-only mode (`--stage`, with `--dir` and `--template-dir` overrides) that skips the git steps; `/retrofit` drives it. A GitHub Actions workflow (`template-smoke`) exercises the script on every PR — including a staged render — and asserts that the bootstrapped tree has no stale placeholders, no dangling internal links, and a well-formed marker.

Audience: developers starting a new project who have decided to use CDD.

## The `/retrofit` command

A CDD-repo-only slash command (`.claude/commands/retrofit.md`, deliberately not shipped in the template) for bringing CDD to projects that already exist. Run from a CDD-repo session with the target path as argument, it auto-detects between two modes:

- **Install** — the target has no CDD scaffolding: a files-only install of the template via the bootstrap script's stage mode. Missing files are copied; collisions (an existing `CLAUDE.md`, say) are merged interactively per file. The codebase survey, initial architecture doc, and roadmap generation arrive as the template roadmap's pre-filled bootstrap tasks, which the project's first `/next-step` proposes as the first task.
- **Upgrade** — the target already runs CDD: a three-way comparison anchored on the `.claude/cdd-baseline` marker applies template improvements, preserves local customizations, and surfaces general-looking local improvements as candidates to upstream into the CDD repo. Pre-marker projects fall back to two-way diffing and get the marker going forward.

Audience: maintainers adopting CDD on an existing codebase, and maintainers keeping CDD projects in sync with template improvements.
