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
│   ├── commands/                             # this repo's slash commands
│   └── settings.json                         # auto-allows worktree sessions to read their handoff file
├── .github/
│   └── workflows/                            # CI (template-smoke runs the bootstrap end-to-end)
├── demo/                                     # filled-in seed + create/teardown automation (third artifact)
│   ├── seed/                                 # concrete "Markdown Renderer" project content
│   ├── setup.sh / teardown.sh / lib.sh       # create + tear down demo/dogfood instances
│   └── README.md                             # what the demo builds; the phases 1-3 demo script
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

The CDD repo's own `.claude/commands/` and `template/.claude/commands/` are conceptually the same files, with the repo's own copy free to drift if it needs CDD-specific behaviour. Unintended drift is a defect. One command is deliberately one-sided: `/retrofit` (`.claude/commands/retrofit.md`) lives only in the CDD repo — it installs CDD into an existing project or upgrades a project already on CDD, operating *on* targets from a CDD-repo session, so the template ships no copy.

Like `demo/setup.sh`, `/retrofit` does not duplicate substitution logic: its install mode drives `bootstrap-cdd-project.sh --stage`, a render-only mode (no `git init`, no scaffold commit) that stages a fully substituted template tree which the command then merges into the target interactively. Its upgrade mode additionally uses `--template-dir` to render an old template snapshot through the same single code path. The bootstrap script writes a one-line baseline marker, `.claude/cdd-baseline` (the CDD repo commit the template was rendered from), into every bootstrapped or staged tree; upgrade mode uses it as the three-way merge base for distinguishing template evolution from local customization.

## The demo layer

`demo/` is a **third artifact**, distinct from both layers above and from `scripts/`. It is *not* part of the template: it holds a **filled-in** seed project ("Markdown Renderer", under `demo/seed/`) plus create/teardown automation (`demo/setup.sh`, `demo/teardown.sh`, `demo/lib.sh`). Concrete, project-specific content is allowed here precisely because it lives under `demo/` and never leaks into `template/`, which stays generic.

The automation does not duplicate bootstrap logic: `setup.sh` wraps `bootstrap-cdd-project.sh` with its `--overlay` flag, which copies the seed over the template tree before placeholder substitution, so the seed's `<PROJECT_NAME>`/`<PROJECT_SLUG>`/`<PROJECT_DIR>` placeholders are substituted by the same single code path. The seed doubles as a reproducible demo of the CDD task cycle (one reviewable PR, two parallel branches that conflict, a `/merge-main` that both resolves the conflict and delivers a dependency) and as the Phase 2 dogfooding greenfield. See `demo/README.md`.

## Open structural questions

- Whether per-project-type variants live as parallel template directories, as a single template with a variant flag, or as post-bootstrap transformation scripts. Deferred until there is enough usage to compare across project types.

This document will grow as the structure stabilizes. It is intentionally thin while the repo is still small.
