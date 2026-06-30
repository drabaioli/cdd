# CDD Roadmap

This is the central workflow artifact for the CDD project. Tasks are grouped into phases; each phase ends with a milestone. Completed tasks are annotated inline with what landed and any caveats.

## Phase 1: MVP shipped

Write the process document, draft the template, and get the repo self-hosting CDD on GitHub.

- [x] Write the process document (`doc/knowledge_base/claude-driven-development.md`).
- [x] Draft the template files (CLAUDE.md skeleton, slash commands, worktree helper, doc skeletons, template README).
- [x] Establish the CDD-uses-CDD pattern: process doc in `doc/knowledge_base/`, template under `template/`, repo gets its own thin CDD scaffolding.
- [x] Initialise the GitHub repo with the structure above and push.
- [x] Source `tools/cdd-worktree.sh` from `~/.bashrc` and verify the worktree helpers work end-to-end on this repo.
- [x] Run `/cdd-next-step` once on the CDD repo itself to confirm the workflow is usable on the meta-project.

**Milestone:** CDD repo on GitHub, self-hosting CDD, ready to be used for a real downstream project.

## Phase 2: First downstream dogfooding

Run the workflow end-to-end on a first real downstream project and capture every awkward or missing piece.

- [x] Pick a small greenfield project to use as the first CDD trial. — Markdown Renderer (paste Markdown → live preview → copy as rich text for email/docs); see `demo/`
- [x] Do the exploratory work outside CDD: language, tooling, top-level architecture, hand-written initial roadmap. — done in the `/cdd-next-step` discussion: Python/Flask, `markdown` library, an actions-pipeline architecture, and a 6-phase roadmap (`demo/seed/`)
- [x] Bootstrap the new project from `template/`, including the placeholder substitution. — automated by `demo/setup.sh`, which wraps `bootstrap-cdd-project.sh --overlay demo/seed`
- [x] Run the first `/cdd-next-step` → implementation → `/cdd-pre-pr` → PR cycle on the downstream project. — mdr_demo_01
- [x] Keep a friction log: every awkward or missing piece, recorded outside the downstream project. — landed as `doc/knowledge_base/friction-log.md`; retired after mdr_demo_01 (friction addressed directly or via roadmap)
- [x] Complete at least three task cycles before drawing conclusions. — mdr_demo_01
- [x] Build the `demo/` subsystem: a filled-in seed (`demo/seed/`) plus create/teardown automation (`demo/setup.sh`, `demo/teardown.sh`) that doubles as a reproducible demo of the task cycle and the dogfooding greenfield. — third repo artifact alongside `template/` and `scripts/`

**Milestone:** one real downstream project running CDD, with friction from early usage folded back into the template.

## Phase 3: Template refinement from real usage

Refine the template and commands from real usage; tasks here are driven by friction surfaced during dogfooding.

- [x] Refine `/cdd-merge-main` based on first real merge encountered — first real merge (mdr_demo_01 Phase 3, ACTIONS/toolbar conflict + `inline_styles()` delivery) succeeded with no changes needed.
- [x] Improve the placeholder-substitution recipe in the template README (current weak spot, known limitation). — README renamed to `template/BOOTSTRAP.md`; sed recipe replaced by `bootstrap-cdd-project.sh`
- [x] Add a `bootstrap.sh` script to the template that does rename + substitution non-interactively. — script lives under `tools/` (`tools/bootstrap-cdd-project.sh`), not under `template/`; two-identifier model (`<PROJECT_NAME>` / `<PROJECT_DIR>`)
- [x] Add a `template-smoke` CI workflow that asserts the bootstrap produces a clean, link-valid tree. — `.github/workflows/template-smoke.yml` + `scripts/template-smoke-assert.sh`
- [x] Resolve any divergence between `./.claude/commands/` and `template/.claude/commands/` introduced during Phase 2. — reconciled; enforced mechanically by `scripts/command-drift-check.sh` going forward
- [x] Add a `/cdd-pre-pr` check (in the CDD repo) for unintended drift between the two command sets.
- [x] Add a `/cdd-process-pr` command: triage and address the open PR's review feedback, post in-thread replies, commit + push. — `.claude/commands/cdd-process-pr.md` + template copy; process doc §3.7, §4.1.
- [x] Auto-allow worktree sessions to read their handoff file so `cdd-worktree` no longer prompts on first launch. — `.claude/settings.json` + template copy.
- [x] Fix readable handoff path in `/cdd-next-step`: replace bash contraption with `<PROJECT_DIR>` placeholder (template) / `cdd` literal (CDD repo); add bash allow rules to settings.json. — mdr_demo_01 friction round
- [x] rc-install in demo setup/teardown: `demo/setup.sh` appends a marker-guarded sourcing block to `~/.bashrc`; `demo/teardown.sh` removes it by marker. — mdr_demo_01 friction round
- [x] Index-as-pointers rule: encode in process doc + template CLAUDE.md + skeleton index.md files; restructure demo seed docs into subdocuments. — mdr_demo_01 friction round
- [x] ADRs: Nygard-style `doc/architecture/adr/NNNN-title.md`; ship template + CDD repo ADR directory; reference in process doc and CLAUDE.md. — mdr_demo_01 friction round
- [x] Encode the session taxonomy: named session types in process doc §3, edit-rules matrix keyed by them, fresh-context-per-job stated as a blanket invariant; mirrored in README and both CLAUDE.md workflow sections.
- [x] Reconcile README.md (bootstrap one-liner, BOOTSTRAP.md link, dogfooding status) and add it to `/cdd-pre-pr` doc reconciliation in both command copies.
- [x] Replace the hand-maintained command-drift list with a render-then-diff check (`scripts/command-drift-check.sh` + whitelist), run by CI and `/cdd-pre-pr`; includes the handoff-schema assertion, worktree-helper body comparison, and a template `cdd-only`-marker guard.
- [x] Add shellcheck to CI over all repo shell scripts.
- [x] Worktree helpers: main-worktree guard on `cdd-worktree`; default branch derived from origin's HEAD (fallback `main`), `origin` assumption documented in BOOTSTRAP.md.
- [x] Restrict bootstrap placeholder substitution to text files so binary overlay assets survive.

**Milestone:** template is ergonomic enough that bootstrapping a new project takes under five minutes.

## Phase 4: Greenfield bootstrap automation

Turn the manual greenfield start into a single `/cdd-bootstrap` command. Depends on Phases 2 and 3 surfacing what the manual flow actually looks like.

- [x] Design a `/cdd-bootstrap` slash command that *guides the user through producing* the project definition and a draft roadmap via conversation, then feeds the result into `bootstrap-cdd-project.sh` — discovery is part of the command, not a precondition.
- [x] Decide where `/cdd-bootstrap` runs: outside any project (one-shot CLI), inside the empty target directory, or inside the CDD repo with an output path argument. — CDD-repo-only, like `/cdd-retrofit`
- [x] Implement `/cdd-bootstrap` (guided discovery → overlay → one bootstrap invocation) and validate it by bootstrapping a second greenfield project end-to-end.

**Milestone:** a new project can be bootstrapped end-to-end through one guided `/cdd-bootstrap` session — definition, overview, and real roadmap included.

## Phase 5: Retrofit existing projects

Bring CDD to projects that already exist: files-only install, baseline-anchored upgrade, and a first real retrofit trial.

- [x] Implement a /cdd-retrofit command (CDD repo) that installs CDD into an existing project (files-only) or upgrades a project already on CDD, preserving local customizations and surfacing upstreamable improvements.
- [x] Have a freshly bootstrapped or retrofitted project propose the codebase survey + initial docs as its first task. — landed as a pre-filled bootstrap phase in the template roadmap; scope refined to files-only starts only (retrofit install + manual bootstrap script), since guided `/cdd-bootstrap` writes those docs through discovery and ships a real roadmap without the phase
- [x] Trial the retrofit on one existing project. — Colibri (Zephyr/C++); surfaced the change-isolation defect below.
- [x] Make `/cdd-retrofit` stage its changes on a dedicated branch + worktree in the target rather than the target's current branch, and commit them there for review.
- [x] Document the doc-reconciliation cost and make the retrofit path honest about it: name the cost in the process doc, strengthen template Phase 1 for the existing-project case with don't-disrupt-existing-docs guidance (keeping the greenfield thin path), describe the upgrade-vs-first-time distinction, and have `/cdd-retrofit` flag the slow first `/cdd-next-step`.

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
- [ ] Design task selection visibility: how `/cdd-next-step` sees other team members' in-flight worktrees.
- [ ] Define the team approval mechanism for structural roadmap edits (likely PR-against-roadmap).
- [ ] Adapt slash commands and worktree helpers for the chosen team-mode design.
- [ ] Trial team mode on a real team.

**Milestone:** CDD usable by a small team without process workarounds.

## Phase 8: In-session workflow ergonomics

Make the per-task session loop nicer to drive once a project is already on CDD.

- [x] Extend `/cdd-next-step` with an optional intent prompt: with a task prompt it runs an intent-driven flow (skip candidate proposal, adaptive context load, overlap check, roadmap-belonging decision recorded for the implementation session); with no argument it keeps the roadmap-driven flow. One command, two front-ends. — process doc §3.1 + both `cdd-next-step.md` copies + both CLAUDE.md workflow bullets.
- [x] Add a GitHub-issue front-end to `/cdd-next-step` (an issue number or the `issue`/`issues` keyword sources the task; branch named `gh_issue_NN_<slug>`), plus an opt-in "open the PR?" step in `/cdd-pre-pr` that adds `Closes #NN` on `gh_issue_NN` branches. — process doc §3.1/§3.5/§3.6 + both `cdd-next-step.md` + both `cdd-pre-pr.md` copies + both CLAUDE.md workflow bullets.
- [x] Auto-commit at workflow gates: the implementation session and `/cdd-pre-pr` commit their own changes automatically (local, no push) in a non-disruptive way; `/cdd-process-pr` and `/cdd-merge-main` reviewed to fit one shared commit convention. — issue #20. Process doc §2.11 (new) + §3.3/§3.5/§3.7/§4 + both `cdd-pre-pr.md` and `cdd-next-step.md` copies + both CLAUDE.md `/cdd-pre-pr` bullets.
- [x] Prefix every CDD slash command with `cdd-` (`/cdd-next-step`, `/cdd-pre-pr`, `/cdd-merge-main`, `/cdd-process-pr`, `/cdd-bootstrap`, `/cdd-retrofit`, `/cdd-quick-create`) so they autocomplete as a discoverable group. — issue #27. Renamed all 11 command files (7 repo + 4 template), swept every cross-reference across the process doc, template, demo, and docs, and updated `scripts/command-drift-whitelist.txt` + `scripts/command-drift-check.sh`. Scope was slash commands only; the worktree helper was unified separately (next item).
- [x] Unify the worktree helper into a single, self-installing, project-independent `cdd-worktree` — issues #24 + #18. Deleted the per-project `template/tools/PROJECT-worktree.sh`; the canonical `tools/cdd-worktree.sh` is now dual-mode (sourced → defines the functions; `install` → copies itself to `~/.cdd/tools/`, wires `~/.bashrc` + `~/.zshrc` idempotently, migrates old handoffs). Handoffs moved `~/.claude-handoffs/<repo>/` → `~/.cdd/handoffs/<repo>/`. Collapsed the placeholder model three → two (`<PROJECT_SLUG>` and the bare `PROJECT` token removed; `--slug` dropped from the bootstrap script). Demo installs the shared helper once instead of per-instance rc blocks; drift/smoke checks no longer compare a rendered helper. — process doc §2.6/§2.8/§2.9 + bootstrap script + both settings.json + both `cdd-next-step.md` + `cdd-bootstrap.md`/`cdd-retrofit.md`/`cdd-pre-pr.md` + template/BOOTSTRAP.md + both CLAUDE.md + README + demo subsystem + scripts + CI.

**Milestone:** starting an off-roadmap task — typed or sourced from a GitHub issue — is a first-class, structured `/cdd-next-step` flow.

## Phase 9: Lightweight one-off deliverables

Support producing a small, self-contained deliverable without the full CDD project substrate, with a clean escalation path when it turns out to be a project.

- [x] Document the shared scope-triage heuristic ("deliverable or project?") once in the process doc, referenced by both commands.
- [x] Implement `/cdd-quick-create`: lightweight guided discovery, files-first write, optional smoke test, separately-offered local commit and GitHub repo.
- [x] Add the bidirectional off-ramps: `/cdd-quick-create` → `/cdd-bootstrap` when project-signals trip, and `/cdd-bootstrap` → `/cdd-quick-create` when the task is a trivial single artifact.
- [x] Register `/cdd-quick-create` as CDD-repo-only in the command-drift whitelist (no template copy).
- [ ] Validate `/cdd-quick-create` end-to-end against a real one-off deliverable.

**Milestone:** a trivial standalone artifact can be produced through one guided `/cdd-quick-create` session, with an escalation path to `/cdd-bootstrap` when it turns out to be a project.

## Phase 10: Retrofit hardening (from real retrofit trials)

Defects and gaps surfaced by retrofitting CDD onto real existing projects. Each item is a general template/process fix, not a project-specific patch.

- [x] Second retrofit trial: PyGroundControl (Python/FastAPI + TypeScript SDK + React, default branch `devel`). Install-mode retrofit + heavy doc reconciliation (split `doc/backend`+`doc/frontend`→`doc/architecture/`, loose docs→`knowledge_base/`, CLAUDE.md slimmed 396→129 lines). Surfaced the three defects below.
- [x] **Default branch is hardcoded to `main` in the commands.** Fixed: both `cdd-merge-base.md` and `cdd-pre-pr.md` now resolve the default branch dynamically via `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`, falling back to `main`. `/cdd-merge-main` renamed to `/cdd-merge-base` ("base branch" is standard PR terminology). Gitflow case (platform default ≠ integration branch) is out of scope — tracked below.
- [x] **Handoff path diverges when the repo dir isn't already a valid `<PROJECT_DIR>`.** Fixed: the `<PROJECT_DIR>` regex in `bootstrap-cdd-project.sh` is loosened to `^[A-Za-z][A-Za-z0-9_-]*$`, so CamelCase dirs like `PyGroundControl` are accepted as-is. The rendered handoff path now matches the actual directory basename the worktree helper derives at runtime.
- [x] **`cdd-next-step.md` hardcodes `~/Code/<PROJECT_DIR>` as the repo location** (the suggested source line). Fixed: `cdd-next-step.md` §8 now instructs resolving the repo root via `git rev-parse --show-toplevel` and embedding the actual path in the printed source line.
- [ ] **Gitflow case: platform default ≠ integration branch** (e.g. `main` is the release branch but daily work branches off `devel`). `cdd-merge-base` and `cdd-pre-pr` target the platform default branch — correct for the PyGroundControl case (`devel` *is* the platform default), but wrong for gitflow projects where the platform default is the release branch. Fix requires an explicit `BASE_BRANCH` config mechanism.
- [ ] **Retrofit doc-reconciliation playbook for common pre-existing layouts.** PyGroundControl needed manual reconciliation that recurs across projects: a split architecture-doc layout (`doc/backend/`, `doc/frontend/`, a top-level `system-architecture.md`) folding into `doc/architecture/`; a `future-work.md`/TODO/backlog doc folding into `roadmap.md`; an oversized CLAUDE.md duplicating command/troubleshooting content that should be slimmed to pointers (per-session context cost). Capture these as explicit guidance/checklist in `/cdd-retrofit` (and the process doc's existing-project section) so they aren't rediscovered each time.

**Milestone:** CDD retrofits cleanly onto a project regardless of default-branch name, repo directory name/location, or pre-existing doc layout, without per-project manual fixes to the scaffolding.

## Phase 11: Founding-objective guardrails

Elevate the two under-guarded founding objectives — instilling engineering best practices, and workflow self-improvement — from implicit to named-and-tracked. Decision and reasoning in `doc/architecture/adr/0001-name-and-guard-founding-objectives.md`.

- [x] Audit the three founding objectives against the workflow and record the gap inventory. — ADR `0001-name-and-guard-founding-objectives.md`
- [x] Name the under-guarded objectives in §1: broaden "documents itself" into "holds itself to engineering standards", add "the workflow improves itself" (4 → 5 commitments).
- [x] Ship the engineering-practices contract (enforced vs expected): process doc §2.12 + template `doc/knowledge_base/engineering-practices.md`, instantiated in the CDD repo and the demo seed.
- [x] Add the `/cdd-pre-pr` test-coverage reconciliation step (both command copies) as the recurring objective-2 guardrail.
- [ ] Objective-3 standing channel: a recurring mechanism that routes a discovered improvement into the roadmap/conventions (not a reintroduced standing log). — §6 known gap; design deferred.
- [ ] Reinforce objective 2 at bootstrap: a required bootstrap-phase task and/or checklist, once the `/cdd-pre-pr` mechanism is proven.
- [ ] Objective-1 mechanizations: codify when `/cdd-merge-base` is recommended/auto-triggered; consider a mechanical gate-honored check.
- [x] Deterministic prompt seam-contract checks (Tier 1; issue #23). `scripts/prompt-seam-check.sh` (+ whitelist) pins four grep-only seams between the workflow's own prompts — the four are enumerated in the script header and `engineering-practices.md`. CDD-repo-only; wired into CI, `/cdd-pre-pr`, and the engineering-practices enforced list. A recurring objective-1 reliability guardrail. Scope decision — deterministic checks only, no generalized "prompt lint" framework and no LLM-as-judge evals — in ADR [`0002-scope-prompt-seam-checks-deterministic-only.md`](../architecture/adr/0002-scope-prompt-seam-checks-deterministic-only.md).
- [ ] Trim process-doc references in the commands: ~14 "read the process doc §N" pointers across the 7 commands pull a large file into context on each run; embed the needed snippet or a tighter pointer instead. Efficiency, not correctness. — surfaced in PR #38 review.

**Milestone:** all three founding objectives are named commitments in §1, each with at least one recurring guardrail or a tracked plan to add one.

## Phase 12: Open-source readiness

Prepare CDD to be open-sourced publicly: license it, rewrite the README to explain and demonstrate the workflow, and track the remaining open-source essentials. Contribution policy at launch is issues-only (no PRs yet).

- [x] Add a standard MIT `LICENSE` at the repo root (holder: Diego Andres Rabaioli; year 2026). Repo-root only — not added to `template/` or wired into `bootstrap-cdd-project.sh`, since the template is copied verbatim into downstream projects without dragging a license along.
- [x] Rewrite the README from scratch: what CDD is and how to use it; guided entry points (`/cdd-bootstrap`, `/cdd-retrofit`, `/cdd-quick-create`) lead the quick start with the manual `bootstrap-cdd-project.sh` recipe below; a complete reference of all 7 slash commands; the task-cycle image (`doc/assets/task-cycle.png`); a short issues-only Contributing section. Kept the two-big-ideas framing, the six-checkpoint concept, the `template-smoke` badge, and the Status section.
- [ ] `CONTRIBUTING.md` (full version, once PRs are accepted).
- [x] `CODE_OF_CONDUCT.md`. — Contributor Covenant 2.1 at the repo root; enforcement contact `drabaioli@gmail.com`. Repo-root only, not added to `template/`.
- [x] `.github/` issue templates: `bug_report.yml` and `idea.yml` forms plus `config.yml` (blank issues enabled). PR template deferred until PRs open.
- [x] `SECURITY.md`. — Repo-root file directing reporters to GitHub private vulnerability reporting (not email); wording assumes the repo setting is enabled (manual one-time toggle).
- [x] GitHub repo metadata: description, topics (via `gh repo edit`), and a 1280×640 social-preview image.
- [x] Confirm the public repo home / org and update the README badge + clone URLs accordingly (currently point at `github.com/drabaioli/cdd`). — Public home stays `github.com/drabaioli/cdd` (no org move); README badge, clone URL, and issues URL verified correct — no rewrite needed.

**Milestone:** CDD is presentable and safe to open-source publicly — licensed, with a README that explains and demonstrates the workflow — with the remaining open-source essentials tracked.

## Phase 13: Task state & observability

Give each task a machine-readable record of where it sits in its lifecycle and which Claude Code sessions have worked it, so tooling can show task state instead of inferring it from handoffs, branches, and `gh`.

- [x] Per-task state record + `cdd-state` helper: a `<branch>.state.json` sibling of the handoff, advanced through the lifecycle by the slash commands via `tools/cdd-state.sh` (atomic `seed`/`set`, self-installing). Advisory, local-only, append-only `{id, stage}` session chain. Full design and schema in process doc §2.13. — §2.13 + §2.6/§2.8/§3.3, all four command copies (repo + template), both `settings.json`, `tools/cdd-state.sh` (new) and `tools/cdd-worktree.sh` (deletion), architecture/feature docs, BOOTSTRAP.md.
- [ ] Harden the one outcome transition a tool call owns: a `PostToolUse` hook on `gh pr create` that parses the PR number and writes `pr_open`/`pr=NN` mechanically (`cdd-state` as the hook target), removing the model-remembering dependency. (A `UserPromptSubmit` hook fires deterministically on every `/cdd-*` call, but only at invocation — it can stamp "stage started", not outcomes like `checks_passed` or the PR number, which stay model-driven via `cdd-state set`.)
- [ ] Consume the record: teach the `cdd-dash` dashboard to read `stage`/`sessions` instead of inferring task state. (`cdd-worktree-list` already infers worktree/branch/PR status fine and does not need the record — fold in only if a concrete need appears.)
- [ ] Multi-machine resume: regenerate this state from a remote branch so a task can be picked up on another machine (issue #22). Needs a sync mechanism (git notes/refs) — explicitly out of scope for the local cache above.

**Milestone:** a task's lifecycle stage and its working sessions are recorded as data and surfaced by CDD tooling, not reconstructed by inference.
