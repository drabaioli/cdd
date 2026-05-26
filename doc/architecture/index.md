# CDD Repository Architecture

The CDD repo has two layers, kept consistent:

1. **The process layer** (`doc/knowledge_base/claude-driven-development.md` plus this repo's own scaffolding). Describes the workflow abstractly. Source of truth for the philosophy, lifecycle, and edit rules.

2. **The template layer** (`template/`). Concrete copy-paste material for bootstrapping new projects. Instantiates the process for a downstream user.

Changes flow process-first, template-second. A PR that touches the process doc but not the template (or vice versa) should be justified explicitly.

## Top-level layout

```
.
├── CLAUDE.md                                 # this repo's Claude Code context
├── README.md                                 # repo entry point
├── bootstrap-cdd-project.sh                  # non-interactive bootstrap for new projects
├── .claude/
│   └── commands/                             # this repo's slash commands
├── .github/
│   └── workflows/                            # CI (template-smoke runs the bootstrap end-to-end)
├── doc/
│   ├── architecture/                         # this file
│   ├── features/                             # what this repo provides
│   └── knowledge_base/                       # process doc, roadmap, decisions
├── scripts/                                  # smoke-test assertions + whitelist for the template
├── template/                                 # copy-paste material for new projects
└── tools/
    └── cdd-worktree.sh                       # this repo's worktree helper
```

## Layer relationships

The process doc references the template by example (it describes what a CLAUDE.md should contain; the template provides a concrete skeleton). The template does not reference the process doc by default. A downstream project using the template does not get a copy of the process doc; the template is self-sufficient for users who don't need the philosophy.

The CDD repo's own `.claude/commands/` and `template/.claude/commands/` are conceptually the same files, with the repo's own copy free to drift if it needs CDD-specific behaviour. Unintended drift is a defect.

## Open structural questions

- Whether per-project-type variants live as parallel template directories, as a single template with a variant flag, or as post-bootstrap transformation scripts. Deferred until there is enough usage to compare across project types.

This document will grow as the structure stabilizes. It is intentionally thin while the repo is still small.
