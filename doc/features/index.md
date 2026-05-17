# CDD Repository Features

The CDD repo provides two user-facing things:

## 1. The Claude-Driven Development process

A documented, human-in-the-loop workflow for evolving software projects with Claude Code. The full description lives in `doc/knowledge_base/claude-driven-development.md`. Users read it to understand the philosophy, the lifecycle, the artifacts, and the edit rules.

Audience: developers considering whether to adopt CDD on their own projects; contributors to CDD itself.

## 2. The template

A copy-paste directory (`template/`) that a user drops into a new project to start using CDD. Contents:

- `CLAUDE.md` skeleton with placeholders for project-specific content.
- `.claude/commands/{next-step,pre-pr,merge-main}.md`: the three slash commands.
- `doc/{architecture,features,knowledge_base}/`: doc directory skeletons.
- `tools/PROJECT-worktree.sh`: worktree helper to be renamed and sourced from the user's shell rc.
- `README.md`: the bootstrap procedure.

Audience: developers starting a new project who have decided to use CDD.

## Status

Both features are usable but unproven. The process doc is complete enough to follow. The template is complete enough to copy, but the placeholder-substitution step is manual and a known weak spot. The first downstream project will surface what needs refining.

See `doc/knowledge_base/roadmap.md` for the planned work.
