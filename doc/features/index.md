# CDD Repository Features

The CDD repo provides three user-facing things:

## 1. The Claude-Driven Development process

A documented, human-in-the-loop workflow for evolving software projects with Claude Code. The full description lives in `doc/knowledge_base/claude-driven-development.md`. Users read it to understand the philosophy, the lifecycle, the artifacts, and the edit rules.

Audience: developers considering whether to adopt CDD on their own projects; contributors to CDD itself.

## 2. The template

A copy-paste directory (`template/`) plus a non-interactive bootstrap script (`bootstrap-cdd-project.sh` at the CDD repo root) that together start a new project on CDD. Template contents:

- `CLAUDE.md` skeleton with placeholders for project-specific content.
- `.claude/commands/{next-step,pre-pr,merge-main,process-pr}.md`: the four slash commands.
- `.claude/settings.json`: auto-allows worktree sessions to read their handoff file (`~/.claude-handoffs/<PROJECT_DIR>/**`), substituted at bootstrap.
- `doc/{architecture,features,knowledge_base}/`: doc directory skeletons.
- `tools/PROJECT-worktree.sh`: worktree helper, renamed and substituted to `<PROJECT_SLUG>-worktree.sh` by the bootstrap script.
- `BOOTSTRAP.md`: meta-documentation for the bootstrap recipe. Not copied into the bootstrapped tree.

The bootstrap script substitutes the three identifiers (`<PROJECT_NAME>`, `<PROJECT_SLUG>`, `<PROJECT_DIR>`) and the bare `PROJECT` token inside the worktree helper, runs `git init`, and creates the scaffold commit. A GitHub Actions workflow (`template-smoke`) exercises the script on every PR and asserts that the bootstrapped tree has no stale placeholders and no dangling internal links.

Audience: developers starting a new project who have decided to use CDD.

## 3. The demo

A `demo/` subsystem that instantiates a concrete project ("Markdown Renderer") from a filled-in seed, for two uses from one source:

- A reproducible, **visual demo** of CDD's task cycle: one reviewable PR, two parallel branches that hit a guaranteed merge conflict, and a `/merge-main` that resolves the conflict *and* delivers a cross-branch dependency.
- The **dogfooding greenfield** for roadmap Phase 2.

Contents:

- `demo/seed/`: filled-in `CLAUDE.md`, a 6-phase roadmap, and architecture/features docs for the Markdown Renderer (CDD scaffolding only — the app itself is built by running CDD cycles on a created instance).
- `demo/setup.sh`: create an instance — wraps `bootstrap-cdd-project.sh --overlay demo/seed`, then always creates and pushes a GitHub repo. Auto-numbers disposable demo instances (`mdr_demo_NN`) checking both local dirs and existing repos; `mdr` is the kept dogfood instance.
- `demo/teardown.sh`: reclaim an instance — remove the local directory and delete its GitHub repo (needs the `gh` `delete_repo` scope).

Audience: anyone demoing CDD to others, and the maintainer dogfooding CDD on a real project. See `demo/README.md` for the create/teardown commands and the phases 1–3 demo script.

## Status

All three are usable. The process doc is complete enough to follow. The template + bootstrap script have been used to bootstrap the first downstream project (`sprint-planning-automation-poc`); the friction surfaced there is recorded in `doc/knowledge_base/friction-log.md` and folded back into the template and process doc. The manual sed recipe that was the known weak spot has been replaced by the non-interactive script and is CI-guarded.

See `doc/knowledge_base/roadmap.md` for the planned work.
