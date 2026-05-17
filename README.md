# Claude-Driven Development (CDD)

A human-in-the-loop workflow for evolving software projects together with Claude Code. Built around a self-updating `CLAUDE.md`, a roadmap, architecture and feature docs, and a small set of slash commands that drive task selection, implementation, merge, and PR review across git worktrees.

## What's in this repo

- **The process document**: [`doc/knowledge_base/claude-driven-development.md`](doc/knowledge_base/claude-driven-development.md). The philosophy, the lifecycle, the artifacts, the edit rules. Read this first if you want to understand what CDD is and why.
- **The template**: [`template/`](template/). Copy-paste material for bootstrapping a new project. See [`template/README.md`](template/README.md) for the bootstrap procedure.

This repo uses CDD on itself. Its own scaffolding (`CLAUDE.md`, `.claude/commands/`, `doc/`, `tools/cdd-worktree.sh`) sits at the root; the template is content this project ships, under `template/`.

## Quick start (using CDD on a new project)

```bash
git clone <this-repo> /tmp/cdd
mkdir -p ~/Code/<your-project> && cd ~/Code/<your-project>
cp -r /tmp/cdd/template/. .

# Substitute placeholders (see template/README.md for the recipe).
# Fill in CLAUDE.md and doc/knowledge_base/roadmap.md.
# Source tools/<project>-worktree.sh from ~/.bashrc.
# Create ~/.claude-handoffs/.
# Run `claude` and start with /next-step.
```

The placeholder substitution is currently manual; automating it is on the roadmap.

## Status

Early. The template has not yet been used on a real downstream project; the first dogfooding pass is the next milestone. See [`doc/knowledge_base/roadmap.md`](doc/knowledge_base/roadmap.md) for what's done and what's next.
