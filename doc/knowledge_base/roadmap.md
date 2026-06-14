# CDD Roadmap

This is the central workflow artifact for the CDD project. Tasks are grouped into phases; each phase ends with a milestone. Completed tasks are annotated inline with what landed and any caveats.

## Phase 1: MVP shipped

Write the process document, draft the template, and get the repo self-hosting CDD on GitHub.

- [x] Write the process document (`doc/knowledge_base/claude-driven-development.md`).
- [x] Draft the template files (CLAUDE.md skeleton, slash commands, worktree helper, doc skeletons, template README).
- [x] Establish the CDD-uses-CDD pattern: process doc in `doc/knowledge_base/`, template under `template/`, repo gets its own thin CDD scaffolding.
- [x] Initialise the GitHub repo with the structure above and push.
- [x] Source `tools/cdd-worktree.sh` from `~/.bashrc` and verify the worktree helpers work end-to-end on this repo.
- [x] Run `/next-step` once on the CDD repo itself to confirm the workflow is usable on the meta-project.

**Milestone:** CDD repo on GitHub, self-hosting CDD, ready to be used for a real downstream project.

## Phase 2: First downstream dogfooding

Run the workflow end-to-end on a first real downstream project and capture every awkward or missing piece.

- [x] Pick a small greenfield project to use as the first CDD trial. — Markdown Renderer (paste Markdown → live preview → copy as rich text for email/docs); see `demo/`
- [x] Do the exploratory work outside CDD: language, tooling, top-level architecture, hand-written initial roadmap. — done in the `/next-step` discussion: Python/Flask, `markdown` library, an actions-pipeline architecture, and a 6-phase roadmap (`demo/seed/`)
- [x] Bootstrap the new project from `template/`, including the placeholder substitution. — automated by `demo/setup.sh`, which wraps `bootstrap-cdd-project.sh --overlay demo/seed`
- [x] Run the first `/next-step` → implementation → `/pre-pr` → PR cycle on the downstream project. — mdr_demo_01
- [x] Keep a friction log: every awkward or missing piece, recorded outside the downstream project. — landed as `doc/knowledge_base/friction-log.md`; retired after mdr_demo_01 (friction addressed directly or via roadmap)
- [x] Complete at least three task cycles before drawing conclusions. — mdr_demo_01
- [x] Build the `demo/` subsystem: a filled-in seed (`demo/seed/`) plus create/teardown automation (`demo/setup.sh`, `demo/teardown.sh`) that doubles as a reproducible demo of the task cycle and the dogfooding greenfield. — third repo artifact alongside `template/` and `scripts/`

**Milestone:** one real downstream project running CDD, with friction from early usage folded back into the template.

## Phase 3: Template refinement from real usage

Refine the template and commands from real usage; tasks here are driven by friction surfaced during dogfooding.

- [x] Refine `/merge-main` based on first real merge encountered — first real merge (mdr_demo_01 Phase 3, ACTIONS/toolbar conflict + `inline_styles()` delivery) succeeded with no changes needed.
- [x] Improve the placeholder-substitution recipe in the template README (current weak spot, known limitation). — README renamed to `template/BOOTSTRAP.md`; sed recipe replaced by `bootstrap-cdd-project.sh`
- [x] Add a `bootstrap.sh` script to the template that does rename + substitution non-interactively. — script lives at the CDD repo root (`bootstrap-cdd-project.sh`), not under `template/`; three-identifier model (`<PROJECT_NAME>` / `<PROJECT_SLUG>` / `<PROJECT_DIR>`)
- [x] Add a `template-smoke` CI workflow that asserts the bootstrap produces a clean, link-valid tree. — `.github/workflows/template-smoke.yml` + `scripts/template-smoke-assert.sh`
- [x] Resolve any divergence between `./.claude/commands/` and `template/.claude/commands/` introduced during Phase 2. — reconciled; enforced mechanically by `scripts/command-drift-check.sh` going forward
- [x] Add a `/pre-pr` check (in the CDD repo) for unintended drift between the two command sets.
- [x] Add a `/process-pr` command: triage and address the open PR's review feedback, post in-thread replies, commit + push. — `.claude/commands/process-pr.md` + template copy; process doc §3.7, §4.1.
- [x] Auto-allow worktree sessions to read their handoff file so `cdd-worktree` no longer prompts on first launch. — `.claude/settings.json` + template copy.
- [x] Fix readable handoff path in `/next-step`: replace bash contraption with `<PROJECT_DIR>` placeholder (template) / `cdd` literal (CDD repo); add bash allow rules to settings.json. — mdr_demo_01 friction round
- [x] rc-install in demo setup/teardown: `demo/setup.sh` appends a marker-guarded sourcing block to `~/.bashrc`; `demo/teardown.sh` removes it by marker. — mdr_demo_01 friction round
- [x] Index-as-pointers rule: encode in process doc + template CLAUDE.md + skeleton index.md files; restructure demo seed docs into subdocuments. — mdr_demo_01 friction round
- [x] ADRs: Nygard-style `doc/architecture/adr/NNNN-title.md`; ship template + CDD repo ADR directory; reference in process doc and CLAUDE.md. — mdr_demo_01 friction round
- [x] Encode the session taxonomy: named session types in process doc §3, edit-rules matrix keyed by them, fresh-context-per-job stated as a blanket invariant; mirrored in README and both CLAUDE.md workflow sections.
- [x] Reconcile README.md (bootstrap one-liner, BOOTSTRAP.md link, dogfooding status) and add it to `/pre-pr` doc reconciliation in both command copies.
- [x] Replace the hand-maintained command-drift list with a render-then-diff check (`scripts/command-drift-check.sh` + whitelist), run by CI and `/pre-pr`; includes the handoff-schema assertion, worktree-helper body comparison, and a template `cdd-only`-marker guard.
- [x] Add shellcheck to CI over all repo shell scripts.
- [x] Worktree helpers: main-worktree guard on `<slug>-worktree`; default branch derived from origin's HEAD (fallback `main`), `origin` assumption documented in BOOTSTRAP.md.
- [x] Restrict bootstrap placeholder substitution to text files so binary overlay assets survive.

**Milestone:** template is ergonomic enough that bootstrapping a new project takes under five minutes.

## Phase 4: Greenfield bootstrap automation

Turn the manual greenfield start into a single `/bootstrap` command. Depends on Phases 2 and 3 surfacing what the manual flow actually looks like.

- [x] Design a `/bootstrap` slash command that *guides the user through producing* the project definition and a draft roadmap via conversation, then feeds the result into `bootstrap-cdd-project.sh` — discovery is part of the command, not a precondition.
- [x] Decide where `/bootstrap` runs: outside any project (one-shot CLI), inside the empty target directory, or inside the CDD repo with an output path argument. — CDD-repo-only, like `/retrofit`
- [x] Implement `/bootstrap` (guided discovery → overlay → one bootstrap invocation) and validate it by bootstrapping a second greenfield project end-to-end.

**Milestone:** a new project can be bootstrapped end-to-end through one guided `/bootstrap` session — definition, overview, and real roadmap included.

## Phase 5: Retrofit existing projects

Bring CDD to projects that already exist: files-only install, baseline-anchored upgrade, and a first real retrofit trial.

- [x] Implement a /retrofit command (CDD repo) that installs CDD into an existing project (files-only) or upgrades a project already on CDD, preserving local customizations and surfacing upstreamable improvements.
- [x] Have a freshly bootstrapped or retrofitted project propose the codebase survey + initial docs as its first task. — landed as a pre-filled bootstrap phase in the template roadmap; scope refined to files-only starts only (retrofit install + manual bootstrap script), since guided `/bootstrap` writes those docs through discovery and ships a real roadmap without the phase
- [x] Trial the retrofit on one existing project. — Colibri (Zephyr/C++); surfaced the change-isolation defect below.
- [x] Make `/retrofit` stage its changes on a dedicated branch + worktree in the target rather than the target's current branch, and commit them there for review.
- [ ] Document the doc-reconciliation cost: existing projects without prior discipline will likely have a painful first few PRs as the docs are made to reflect reality.

**Milestone:** at least one existing (non-greenfield) project running CDD.

## Phase 6: Per-project-type variants

Offer opinionated template variants per project archetype. Depends on having two or three filled-in `CLAUDE.md` files across project types to compare.

- [ ] Identify variant axes (language, build tooling, test categories, deployment shape).
- [ ] Propose a minimal set of opinionated variants (e.g. firmware, web app, library, data pipeline).
- [ ] Design variant selection: separate template directories, a single template with a variant flag, or a post-bootstrap script.
- [ ] Implement and validate one variant against a real project.

**Milestone:** at least one opinionated variant in use, with the trade-offs of the chosen variant-selection mechanism documented.

## Phase 7: Team-mode extensions

Extend CDD from a single human in the loop to a small team. Depends on single-user usage being solid across several projects.

- [ ] Decide where handoff files live in team mode (shared filesystem, repo-tracked under `.handoffs/`, or issue-tracker integration).
- [ ] Design task selection visibility: how `/next-step` sees other team members' in-flight worktrees.
- [ ] Define the team approval mechanism for structural roadmap edits (likely PR-against-roadmap).
- [ ] Adapt slash commands and worktree helpers for the chosen team-mode design.
- [ ] Trial team mode on a real team.

**Milestone:** CDD usable by a small team without process workarounds.

## Phase 8: In-session workflow ergonomics

Make the per-task session loop nicer to drive once a project is already on CDD.

- [x] Extend `/next-step` with an optional intent prompt: with a task prompt it runs an intent-driven flow (skip candidate proposal, adaptive context load, overlap check, roadmap-belonging decision recorded for the implementation session); with no argument it keeps the roadmap-driven flow. One command, two front-ends. — process doc §3.1 + both `next-step.md` copies + both CLAUDE.md workflow bullets.

**Milestone:** starting an off-roadmap task is a first-class, structured `/next-step` flow.
