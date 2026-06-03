# CDD Roadmap

This is the central workflow artifact for the CDD project. Tasks are grouped into phases; each phase ends with a milestone. Completed tasks are annotated inline with what landed and any caveats.

## Phase 1: MVP shipped

Status: in progress.

- [x] Write the process document (`doc/knowledge_base/claude-driven-development.md`).
- [x] Draft the template files (CLAUDE.md skeleton, slash commands, worktree helper, doc skeletons, template README).
- [x] Establish the CDD-uses-CDD pattern: process doc in `doc/knowledge_base/`, template under `template/`, repo gets its own thin CDD scaffolding.
- [x] Initialise the GitHub repo with the structure above and push.
- [x] Source `tools/cdd-worktree.sh` from `~/.bashrc` and verify the worktree helpers work end-to-end on this repo.
- [x] Run `/next-step` once on the CDD repo itself to confirm the workflow is usable on the meta-project.

**Milestone:** CDD repo on GitHub, self-hosting CDD, ready to be used for a real downstream project.

## Phase 2: First downstream dogfooding

Status: in progress.

- [x] Pick a small greenfield project to use as the first CDD trial. — Markdown Renderer (paste Markdown → live preview → copy as rich text for email/docs); see `demo/`
- [x] Do the exploratory work outside CDD: language, tooling, top-level architecture, hand-written initial roadmap. — done in the `/next-step` discussion: Python/Flask, `markdown` library, an actions-pipeline architecture, and a 6-phase roadmap (`demo/seed/`)
- [x] Bootstrap the new project from `template/`, including the placeholder substitution. — automated by `demo/setup.sh`, which wraps `bootstrap-cdd-project.sh --overlay demo/seed`
- [ ] Run the first `/next-step` → implementation → `/pre-pr` → PR cycle on the downstream project.
- [x] Keep a friction log: every awkward or missing piece, recorded outside the downstream project. — landed as `doc/knowledge_base/friction-log.md`
- [ ] Complete at least three task cycles before drawing conclusions.
- [x] Build the `demo/` subsystem: a filled-in seed (`demo/seed/`) plus create/teardown automation (`demo/setup.sh`, `demo/teardown.sh`) that doubles as a reproducible demo of the task cycle and the dogfooding greenfield. — third repo artifact alongside `template/` and `scripts/`

**Milestone:** one real downstream project running CDD, with a friction log feeding back into the CDD roadmap.

## Phase 3: Template refinement from real usage

Status: not started. Tasks here will be refined based on the friction log from Phase 2.

- [ ] Refine `/merge-main` based on first real merge encountered (logic is currently untested).
- [x] Improve the placeholder-substitution recipe in the template README (current weak spot, known limitation). — README renamed to `template/BOOTSTRAP.md`; sed recipe replaced by `bootstrap-cdd-project.sh`
- [x] Add a `bootstrap.sh` script to the template that does rename + substitution non-interactively. — script lives at the CDD repo root (`bootstrap-cdd-project.sh`), not under `template/`; three-identifier model (`<PROJECT_NAME>` / `<PROJECT_SLUG>` / `<PROJECT_DIR>`)
- [x] Add a `template-smoke` CI workflow that asserts the bootstrap produces a clean, link-valid tree. — `.github/workflows/template-smoke.yml` + `scripts/template-smoke-assert.sh`
- [ ] Resolve any divergence between `./.claude/commands/` and `template/.claude/commands/` introduced during Phase 2.
- [x] Add a `/pre-pr` check (in the CDD repo) for unintended drift between the two command sets.
- [x] Add a `/process-pr` command: triage and address the open PR's review feedback, post in-thread replies, commit + push. — `.claude/commands/process-pr.md` + template copy; process doc §3.7, §4.1.
- [x] Auto-allow worktree sessions to read their handoff file so `cdd-worktree` no longer prompts on first launch. — `.claude/settings.json` + template copy.

**Milestone:** template is ergonomic enough that bootstrapping a new project takes under five minutes.

## Phase 4: Greenfield bootstrap automation

Status: not started. Depends on Phase 2 and 3 surfacing what the manual flow actually looks like.

- [ ] Design a `/bootstrap` slash command that takes a project brief and a draft roadmap and produces structured starting files.
- [ ] Decide where `/bootstrap` runs: outside any project (one-shot CLI), inside the empty target directory, or inside the CDD repo with an output path argument.
- [ ] Implement `/bootstrap` and validate against a second greenfield project.

**Milestone:** a new project can be bootstrapped end-to-end with a single command and a brief.

## Phase 5: Retrofit existing projects

Status: not started. Depends on the greenfield path being solid.

- [ ] Design a retrofit playbook: survey existing codebase with Claude, produce initial architecture doc, generate roadmap from current backlog, install slash commands and worktree helper.
- [ ] Trial the retrofit on one existing project.
- [ ] Document the doc-reconciliation cost: existing projects without prior discipline will likely have a painful first few PRs as the docs are made to reflect reality.

**Milestone:** at least one existing (non-greenfield) project running CDD.

## Phase 6: Per-project-type variants

Status: not started. Depends on having two or three filled-in `CLAUDE.md` files across project types to compare.

- [ ] Identify variant axes (language, build tooling, test categories, deployment shape).
- [ ] Propose a minimal set of opinionated variants (e.g. firmware, web app, library, data pipeline).
- [ ] Design variant selection: separate template directories, a single template with a variant flag, or a post-bootstrap script.
- [ ] Implement and validate one variant against a real project.

**Milestone:** at least one opinionated variant in use, with the trade-offs of the chosen variant-selection mechanism documented.

## Phase 7: Team-mode extensions

Status: not started. Depends on single-user usage being solid across several projects.

- [ ] Decide where handoff files live in team mode (shared filesystem, repo-tracked under `.handoffs/`, or issue-tracker integration).
- [ ] Design task selection visibility: how `/next-step` sees other team members' in-flight worktrees.
- [ ] Define the team approval mechanism for structural roadmap edits (likely PR-against-roadmap).
- [ ] Adapt slash commands and worktree helpers for the chosen team-mode design.
- [ ] Trial team mode on a real team.

**Milestone:** CDD usable by a small team without process workarounds.
