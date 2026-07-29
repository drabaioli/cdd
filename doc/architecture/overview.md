# Overview

The CDD repo has two layers, kept consistent:

1. **The process layer** (`doc/knowledge_base/claude-driven-development.md` plus this repo's own scaffolding). Describes the workflow abstractly. Source of truth for the philosophy, lifecycle, and edit rules.

2. **The template layer** (`template/`). Concrete copy-paste material for bootstrapping new projects. Instantiates the process for a downstream user.

Changes flow process-first, template-second. A PR that touches the process doc but not the template (or vice versa) should be justified explicitly.

## Top-level layout

```
.
├── CLAUDE.md                                 # this repo's Claude Code context
├── LICENSE                                   # MIT (repo-root only; not shipped in template/)
├── README.md                                 # repo entry point
├── .claude/
│   ├── commands/                             # this repo's slash commands
│   └── settings.json                         # auto-allows sessions to read the handoff + run the cdd-state helper
├── .github/
│   └── workflows/                            # CI (template-smoke; delegates to scripts/ci.sh)
├── demo/                                     # filled-in seed + create/teardown automation (third artifact)
│   ├── seed/                                 # concrete "Markdown Renderer" project content
│   ├── setup.sh / teardown.sh / lib.sh       # create + tear down demo/dogfood instances
│   └── README.md                             # what the demo builds; the phases 1-3 demo script
├── doc/
│   ├── index.md                              # documentation map
│   ├── architecture/                         # how this repo is structured
│   ├── features/                             # what this repo provides
│   └── knowledge_base/                       # process doc, roadmap, engineering practices, decisions
├── scripts/                                  # ci.sh (the check runner) + the gate scripts it calls: smoke assertions, drift check, prompt-seam check (with whitelists)
├── template/                                 # copy-paste material for new projects
└── tools/
    ├── bootstrap-cdd-project.sh              # non-interactive bootstrap for new projects
    ├── cdd-worktree.sh                       # shared worktree helper (self-installing)
    └── cdd-state.sh                          # shared task-state helper (self-installing)
```

## Layer relationships

The process doc references the template by example (it describes what a CLAUDE.md should contain; the template provides a concrete skeleton). The template never references the process doc: a bootstrapped project gets no copy of it, so a `(process doc §N)` pointer in a shipped file would dangle for its reader. Shipped files carry whatever they need inline; a pointer that is genuinely CDD-meta belongs behind a `cdd-only` fence or in a one-sided command. The template is self-sufficient for users who don't need the philosophy.

The CDD repo is itself a CDD project and dogfoods the workflow on its own evolution — the meta-project hosting its own template is the cleanest available demonstration of CDD's value, and anything awkward about applying CDD to itself is treated as a real bug in the workflow. The repo therefore carries two layers of the same shape: its own scaffolding at the root (`./CLAUDE.md`, `./.claude/commands/`, `./doc/`), which is how Claude Code works on this repo, and the template under `./template/`, which is content the project ships. The process doc lives under `doc/knowledge_base/` because it is the project's founding design document — the special case of a founding doc that is also the shipped product, so unlike an ordinary founding document it is kept current.

The CDD repo's own `.claude/commands/` and `template/.claude/commands/` are conceptually the same files, with the repo's own copy free to drift if it needs CDD-specific behaviour. Unintended drift is a defect, and is checked mechanically: `scripts/command-drift-check.sh` (run by CI and `/cdd-pre-pr`) renders the template via the bootstrap script's stage mode with this repo's own identifiers and diffs the result against `.claude/commands/`, so substitution differences cancel out and only real divergence surfaces. Justified exceptions are either whole one-sided files listed in `scripts/command-drift-whitelist.txt` or CDD-meta sections of shared files fenced between `<!-- cdd-only-begin -->` / `<!-- cdd-only-end -->` markers in the repo copy. The script also rejects `cdd-only` markers appearing in the template itself, where they would be stripped from both sides of the diff and hide real drift. Three commands are deliberately one-sided: `/cdd-retrofit` (`.claude/commands/cdd-retrofit.md`), `/cdd-bootstrap` (`.claude/commands/cdd-bootstrap.md`), and `/cdd-quick-create` (`.claude/commands/cdd-quick-create.md`) live only in the CDD repo — `/cdd-retrofit` installs CDD into an existing project or upgrades one already on CDD, `/cdd-bootstrap` scaffolds a new greenfield one, and `/cdd-quick-create` produces a lightweight one-off deliverable — all operating *on* a target from a CDD-repo session, so the template ships no copy of any of them. `/cdd-retrofit` and `/cdd-bootstrap` share the bootstrap pipeline; `/cdd-quick-create` uses neither it nor `template/`, because a one-off has no template. See [Bootstrap & retrofit](bootstrap-and-retrofit.md) for the shared pipeline.

A sibling guard of the same family, `scripts/prompt-seam-check.sh` (also run by CI and `/cdd-pre-pr`), pins the seam contracts *between* the repo's own prompts with grep only — no LLM, no API key. It verifies that every `/cdd-*` reference across the repo's markdown resolves to a command file, that the `gh_issue_NN` branch token produced in `cdd-next-step.md` is still consumed (as a `Closes #NN` line) in `cdd-pre-pr.md`, that backticked repo-relative file paths resolve, that each `cdd-*.md` keeps its load-bearing headings, and that the gate count stated in prose (`CLAUDE.md`, `cdd-pre-pr.md`) matches what `ci.sh list` registers — the runner's registry is the source of truth, and the prose is what a pre-PR session reads to describe what it ran. Justified non-resolving tokens (shell helpers, marker paths, retired names, downstream-only paths) live in `scripts/prompt-seam-whitelist.txt`. Like the drift check it is CDD-repo-only and not shipped in the template.

## The check runner (`scripts/ci.sh`)

Both checks above, and every other gate, are reached through one script. `scripts/ci.sh` is this repo's instance of the check runner (process doc §2.14): the **sole source of the gate sequence**, invoked identically by `.github/workflows/template-smoke.yml` and by `/cdd-pre-pr`. The workflow is two steps — checkout, then `./scripts/ci.sh` — and holds no gate list, so there is nothing for CI and a local run to disagree about.

Its mechanics:

- **Registry.** A `GATES` array of `slug|needs|description` entries in run order, each paired with a `gate_<slug>` function (kebab slug → snake function name). `scripts/ci-runner-assert.sh` pins the two together in both directions — every slug has a function, every `gate_*` function is in the registry — so the list and the implementations cannot drift apart. That is also why the runner's own helpers are named `registry_*` / `fn_for_slug` rather than `gate_*`.
- **Modes.** No argument runs everything; `ci.sh <slug>...` runs a subset (the iteration path, which is why there is no fast/full tier split — the full run is seconds); `ci.sh list` prints the slugs, which is what the assertion script consumes.
- **Missing tools.** A gate whose `needs` command is absent is reported `SKIP`, both in the summary table and repeated in the closing line, and never fails the run. `shellcheck` and `jq` are the real cases. The three state-record gates already self-skipped internally when `jq` was missing, but with exit 0 — indistinguishable from a pass; declaring `needs jq` in the registry makes that visible. This is a deliberate relaxation of "local == CI": a host missing a tool gets a *weaker* verdict, not a wrong one, and says so.
- **Not fail-fast.** Every gate runs and the exit status is non-zero if any failed, so one invocation surfaces every problem. The gates are independent.
- **Lint scope.** The `syntax` and `shellcheck` gates glob `tools/*.sh scripts/*.sh demo/*.sh`, so the runner and its assertion script lint themselves and a newly added script is covered without editing the registry. The `syntax` gate runs one `bash -n` **per file**: `bash -n a.sh b.sh` parses only `a.sh` and turns the rest into positional parameters, so the pre-runner CI's `bash -n scripts/*.sh` had been checking a single file and passing regardless of the others. `ci-runner-assert.sh` pins the fix by dropping a deliberately broken script into the scope and requiring the gate to fail.
- **Isolation.** One `mktemp -d` per run (override with `CDD_CI_TMPDIR`), removed on exit, replacing the `/tmp/smoke` paths the workflow used to hardcode; plus a throwaway `GIT_CONFIG_GLOBAL` (identity, `init.defaultBranch`, signing off) as `ref-sync-assert.sh` and `gc-assert.sh` already do. Consequently the workflow needs no git-identity step, and a contributor with commit signing enabled can run the bootstrap gates locally.
- **Output.** Each gate folds into a `::group::` under GitHub Actions and a plain banner elsewhere; a failure also emits an `::error::` annotation. Per-step names in the Actions UI were traded away for the guarantee that the gate list exists exactly once.

## Open structural questions

- Whether per-project-type variants live as parallel template directories, as a single template with a variant flag, or as post-bootstrap transformation scripts. Deferred until there is enough usage to compare across project types.

These documents will grow as the structure stabilizes. They are intentionally thin while the repo is still small.
