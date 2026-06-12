# Overview

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
│   ├── index.md                              # documentation map
│   ├── architecture/                         # how this repo is structured
│   ├── features/                             # what this repo provides
│   └── knowledge_base/                       # process doc, roadmap, decisions
├── scripts/                                  # template smoke assertions + command-set drift check (with whitelists)
├── template/                                 # copy-paste material for new projects
└── tools/
    └── cdd-worktree.sh                       # this repo's worktree helper
```

## Layer relationships

The process doc references the template by example (it describes what a CLAUDE.md should contain; the template provides a concrete skeleton). The template does not reference the process doc by default. A downstream project using the template does not get a copy of the process doc; the template is self-sufficient for users who don't need the philosophy.

The CDD repo's own `.claude/commands/` and `template/.claude/commands/` are conceptually the same files, with the repo's own copy free to drift if it needs CDD-specific behaviour. Unintended drift is a defect, and is checked mechanically: `scripts/command-drift-check.sh` (run by CI and `/pre-pr`) renders the template via the bootstrap script's stage mode with this repo's own identifiers and diffs the result against `.claude/commands/`, so substitution differences cancel out and only real divergence surfaces. Justified exceptions are either whole one-sided files listed in `scripts/command-drift-whitelist.txt` or CDD-meta sections of shared files fenced between `<!-- cdd-only-begin -->` / `<!-- cdd-only-end -->` markers in the repo copy. One command is deliberately one-sided: `/retrofit` (`.claude/commands/retrofit.md`) lives only in the CDD repo — it installs CDD into an existing project or upgrades a project already on CDD, operating *on* targets from a CDD-repo session, so the template ships no copy; the planned `/bootstrap` will follow the same pattern. See [Bootstrap & retrofit](bootstrap-and-retrofit.md) for how `/retrofit` shares the bootstrap pipeline.

## Open structural questions

- Whether per-project-type variants live as parallel template directories, as a single template with a variant flag, or as post-bootstrap transformation scripts. Deferred until there is enough usage to compare across project types.

These documents will grow as the structure stabilizes. They are intentionally thin while the repo is still small.
