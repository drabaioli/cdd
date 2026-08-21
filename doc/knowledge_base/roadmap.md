# CDD Roadmap

This is the central workflow artifact for the CDD project. Tasks are grouped into phases; each phase ends with a milestone. See "Annotation conventions" at the end of this file for what (and what not) to write next to a completed checkbox.

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
- [x] Fix the worktree PATH shims stranding the caller for cwd-changing commands, and make `install` self-repair a disabled rc block. — `tools/cdd-worktree.sh` + `tools/cdd-state.sh` + process doc §2.8 + `scripts/install-smoke-assert.sh`.

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
- [x] **Per-task base branch (gitflow: platform default ≠ integration branch).** Base-branch resolution generalized from "always the platform default" to "each task's own base", so the workflow is correct for arbitrary flows (daily work off `develop`, a `stable_release` cut from `develop`, recursively stacked `feature1`/`feature1_part1`/… where each part merges into its own parent), not just projects where feature branches cut from the platform default. The base is captured per task — `/cdd-next-step` records it on the state record (§2.13) from the branch it is standing on, immutable thereafter and synced across machines via `refs/cdd/<branch>`. `cdd-worktree` cuts the new branch from it; `cdd-merge-base` and `cdd-pre-pr` target it; all fall back to the platform default (`origin`'s HEAD, else `main`) when none was recorded, so single-integration-branch projects are unchanged with zero new config. A project-wide config was rejected because the base is per-task, not per-project.
- [x] **Retrofit reconciles newly-added fill-in docs instead of shipping raw skeletons.** In upgrade mode, when a template file newer than the target's baseline is added, retrofit reconciles obvious fields against detected project state under per-file approval, and flags any residual placeholders/provisional markers in the summary as "needs reconciliation" (issue #41). Fixed a Scribe upgrade landing `engineering-practices.md` with unfilled `<test command>`/`<ci workflow>` placeholders and provisional `<Enforced once…>` markers, factually wrong for a project already enforcing pytest, ruff, and CI. Install mode stays exempt (whole template lands as skeleton by design). Changes: `.claude/commands/cdd-retrofit.md` §4.4/§5 and the process doc's §6 existing-project section.
- [x] **Retrofit doc-reconciliation playbook for common pre-existing layouts.** PyGroundControl needed manual reconciliation that recurs across projects: a split architecture-doc layout (`doc/backend/`, `doc/frontend/`, a top-level `system-architecture.md`) folding into `doc/architecture/`; a `future-work.md`/TODO/backlog doc folding into `roadmap.md`; an oversized CLAUDE.md duplicating command/troubleshooting content that should be slimmed to pointers (per-session context cost). Capture these as explicit guidance/checklist in `/cdd-retrofit` (and the process doc's existing-project section) so they aren't rediscovered each time.

**Milestone:** CDD retrofits cleanly onto a project regardless of default-branch name, repo directory name/location, or pre-existing doc layout, without per-project manual fixes to the scaffolding.

## Phase 11: Founding-objective guardrails

Elevate the two under-guarded founding objectives — instilling engineering best practices, and workflow self-improvement — from implicit to named-and-tracked. Decision and reasoning in `doc/architecture/adr/0001-name-and-guard-founding-objectives.md`.

- [x] Audit the three founding objectives against the workflow and record the gap inventory. — ADR `0001-name-and-guard-founding-objectives.md`
- [x] Name the under-guarded objectives in §1: broaden "documents itself" into "holds itself to engineering standards", add "the workflow improves itself" (4 → 5 commitments).
- [x] Ship the engineering-practices contract (enforced vs expected): process doc §2.12 + template `doc/knowledge_base/engineering-practices.md`, instantiated in the CDD repo and the demo seed.
- [x] Add the `/cdd-pre-pr` test-coverage reconciliation step (both command copies) as the recurring objective-2 guardrail.
- [x] Objective-3 standing channel: a recurring mechanism that routes a discovered improvement into the roadmap/conventions (not a reintroduced standing log). — landed as the conditional workflow-improvement check in `/cdd-pre-pr` (discovery time) and the workflow-gap triage route in `/cdd-process-pr` (review time), both copies. Prompt-only; default silence; non-blocking.
- [x] Reinforce objective 2 at bootstrap: a required bootstrap-phase task and/or checklist, once the `/cdd-pre-pr` mechanism is proven. — landed as discovery questions plus a resolved contract rather than the anticipated task/checklist; guided path only, `/cdd-retrofit` install mode stays exempt. Pre-PR review added a sixth prompt seam pinning that discovery question to the contract's open rows.
- [x] Objective-1 mechanizations: `/cdd-merge-base` auto-merges the mechanically-trivial case with no approval prompt, making checkpoint 4 conditional, and `/cdd-pre-pr` reports base drift as an explicit commit count — the item's "mechanical gate-honored check" half was dropped as filler.
- [x] Deterministic prompt seam-contract checks (Tier 1; issue #23). `scripts/prompt-seam-check.sh` (+ whitelist) pins five grep-only seams between the workflow's own prompts, enumerated in the script header and `engineering-practices.md`. CDD-repo-only; wired into CI, `/cdd-pre-pr`, and the engineering-practices enforced list. A recurring objective-1 reliability guardrail. Scope decision — deterministic checks only, no generalized "prompt lint" framework and no LLM-as-judge evals — in ADR [`0002-scope-prompt-seam-checks-deterministic-only.md`](../architecture/adr/0002-scope-prompt-seam-checks-deterministic-only.md).
- [x] Trim process-doc references in the commands: filed against ~14 "read the process doc §N" pointers across the commands (PR #38 review), on the theory each pulls the large process doc into context per run. Verify-and-close audit of every process-doc reference in all 7 repo commands and their template copies found **zero load-bearing pointers**: every reference is a tight advisory/see-also/provenance pointer, and the state-record ones already carry the concrete `cdd-state set ...` command inline, so none forces the process doc into context. Resolved incidentally by prior refactors; no command edits needed.
- [x] One check runner shared by CI and `/cdd-pre-pr` (issue #36). `scripts/ci.sh` is the sole source of the gate sequence: a `slug|needs|description` registry of 15 gates, invoked identically by `.github/workflows/template-smoke.yml` (now two steps — checkout, then the runner — with no gate list of its own) and by `/cdd-pre-pr`. Collapses a sequence that was written out three times (workflow YAML, `CLAUDE.md`, the command) into one, and closes the larger gap it exposed: `/cdd-pre-pr` had been running only the drift and prompt-seam checks — never `bash -n`, `shellcheck`, or any of the six `*-assert.sh` scripts — so a green pre-PR run guaranteed very little and real failures surfaced only after the PR was open. **Host-direct, no Docker**, resolving the container question the issue left open: a gate whose tool is absent (`shellcheck`, `jq`) reports SKIPPED loudly and non-fatally, which knowingly relaxes the issue's "same pass/fail as CI, including shellcheck" acceptance line for the missing-tool case — a weaker verdict that says so, never a silent pass. Not fail-fast, so one run surfaces every problem; hermetic scratch dir + git config, so it needs no host setup and the workflow's git-identity step is gone. Consolidating the gates also exposed and fixed a long-standing hole in the syntax check: `bash -n a.sh b.sh` parses only the first file (the rest become positional parameters), so CI's three `bash -n <list>` lines had been checking 3 of 16 scripts and passing regardless of the other 13. The gate now runs one `bash -n` per file, and `ci-runner-assert.sh` pins it with a deliberately broken probe script. A recurring objective-2 guardrail: the mechanism behind the *enforced* rows of `engineering-practices.md`, verifiable before the PR rather than only in CI. Template ships the **pattern, not a script** (the gate list is inherently per-project): process doc §2.14 + the `<check runner command>` placeholder in the template's `/cdd-pre-pr`, `CLAUDE.md`, and engineering-practices, with the individual gate commands retained as the no-runner-yet fallback. Pre-PR review added a fifth prompt seam (`prompt-seam-check.sh` check 5): the gate count stated in prose in `CLAUDE.md` and `cdd-pre-pr.md` must match `ci.sh list`, so adding a gate cannot leave the prose a session reads silently stale. A second pre-PR pass caught one bug: `ci.sh -h` extracted its own header via `$BASH_SOURCE` *after* cd'ing to the repo root, so a relative invocation path from another directory printed a `sed: can't read` error and still exited 0. It now reads the fixed repo-relative `scripts/ci.sh`, and `ci-runner-assert.sh` check 6 pins it by invoking `-h` from the parent directory. That pass also surfaced, and closed, an asymmetry: `ci.sh` had a self-test but `prompt-seam-check.sh` — the guard the runner leans on hardest — had none, so its five checks could silently stop matching and report "clean" forever. `scripts/prompt-seam-assert.sh` (16th gate, `seams-contract`) closes it by **mutation**: it copies the working tree to a throwaway sandbox, breaks one seam at a time, and requires the checker to fail naming that seam, with two controls (unmutated copy passes; a whitelisted dangling reference is silenced) that keep the five from being satisfied by a checker that simply fails on everything. Deliberately mutation-based rather than assert-it-passes, since a guard that only ever passes is indistinguishable from a broken one — the same argument the sixth dangling process-doc reference made above. — process doc §2.12/§2.14/§2.7/§3.5, `scripts/ci.sh` + `scripts/ci-runner-assert.sh` + `scripts/prompt-seam-assert.sh` (new), `template-smoke.yml`, both `cdd-pre-pr.md` copies, both `CLAUDE.md` and both `engineering-practices.md`, `doc/architecture/overview.md`, `doc/features/template.md`, `scripts/template-smoke-whitelist.txt`.
- [x] Template-side process-doc references dangle: the template ships no `claude-driven-development.md` (`BOOTSTRAP.md` only names it as living in the CDD repo), so the `(process doc §N)` pointers in the four shipped commands resolve to nothing in a bootstrapped project. Harmless today — all of them are advisory, per the audit above — but a reader-visible dead reference. — surfaced in PR #55 review. Resolved by stripping all five references **symmetrically**, from the repo copy and its template counterpart alike: the §2.13 state-record pointers in `cdd-next-step.md`, `cdd-merge-base.md`, `cdd-pre-pr.md`, and `cdd-process-pr.md` (each already carries its concrete `cdd-state set …` command inline), plus the `/cdd-process-pr` header note's pointer to §4.1 (the note states the policy in full in its own sentence). Symmetric removal was chosen over fencing the repo copies `cdd-only` because it keeps `scripts/command-drift-check.sh` green with no fence or whitelist churn; shipping a trimmed workflow doc in `template/doc/knowledge_base/` was rejected as far more surface than five advisory pointers justify. A mechanical seam check was considered and deliberately skipped — the five are gone and the change is one grep away from re-verification. A **sixth** turned up afterwards, on the `gh_issue_36` branch's merge of this work: the PR-creation step of `cdd-pre-pr.md` carried a bare `(§2.13)`, which the original sweep missed because it matched on the `process doc §N` phrasing and this one omitted the prefix. Stripped symmetrically there on the same grounds (the `cdd-state set pr_open --pr NN` command is inline in the same sentence). That the sweep missed one is the argument *for* the seam check that was skipped; grep for a bare `§` in `template/.claude/commands/` if it comes up again. Untouched: `cdd-pre-pr.md`'s §2.6 reference (inside the existing `cdd-only` fence) and the `cdd-bootstrap.md` / `cdd-retrofit.md` references (CDD-repo-only, whitelisted — they resolve fine).

**Milestone:** all three founding objectives are named commitments in §1, each with at least one recurring guardrail or a tracked plan to add one.

## Phase 12: Open-source readiness

Prepare CDD to be open-sourced publicly: license it, rewrite the README to explain and demonstrate the workflow, and track the remaining open-source essentials. Contribution policy at launch is issues-only (no PRs yet).

- [x] Add a standard MIT `LICENSE` at the repo root (holder: Diego Andres Rabaioli; year 2026). Repo-root only — not added to `template/` or wired into `bootstrap-cdd-project.sh`, since the template is copied verbatim into downstream projects without dragging a license along.
- [x] Rewrite the README from scratch: what CDD is and how to use it; guided entry points (`/cdd-bootstrap`, `/cdd-retrofit`, `/cdd-quick-create`) lead the quick start with the manual `bootstrap-cdd-project.sh` recipe below; a complete reference of all 7 slash commands; the task-cycle image (`doc/assets/task-cycle.png`); a short issues-only Contributing section. Kept the two-big-ideas framing, the six-checkpoint concept, the `template-smoke` badge, and the Status section.
- [x] README re-framing + visual-polish pass (follow-up to the rewrite above, not a reopen): re-ordered the intro emphasis (AI agents / automation / human-in-the-loop first, context economy next, documentation de-emphasized to a closing mention) and folded in engineering-best-practices framing; simplified How it works (10 steps → 7), Quick start (guided flow leads), Questions, and Status; added a hero banner (`doc/assets/social-preview.png`), an expanded badge row (License, Built with Claude Code, Issues welcome, status — alongside the existing `template-smoke` CI badge), and tasteful heading emojis. README-only; no process-doc/template counterpart.
- [ ] `CONTRIBUTING.md` (full version, once PRs are accepted).
- [x] `CODE_OF_CONDUCT.md`. — Contributor Covenant 2.1 at the repo root; enforcement contact `drabaioli@gmail.com`. Repo-root only, not added to `template/`.
- [x] `.github/` issue templates: `bug_report.yml` and `idea.yml` forms plus `config.yml` (blank issues enabled). PR template deferred until PRs open.
- [x] `SECURITY.md`. — Repo-root file directing reporters to GitHub private vulnerability reporting (not email); wording assumes the repo setting is enabled (manual one-time toggle).
- [x] GitHub repo metadata: description, topics (via `gh repo edit`), and a 1280×640 social-preview image.
- [x] Confirm the public repo home / org and update the README badge + clone URLs accordingly (currently point at `github.com/drabaioli/cdd`). — Public home stays `github.com/drabaioli/cdd` (no org move); README badge, clone URL, and issues URL verified correct — no rewrite needed.

**Milestone:** CDD is presentable and safe to open-source publicly — licensed, with a README that explains and demonstrates the workflow — with the remaining open-source essentials tracked.

## Phase 13: Task state & observability

Give each task a machine-readable record of where it sits in its lifecycle and which Claude Code sessions have worked it, so tooling can show task state instead of inferring it from handoffs, branches, and `gh`.

- [x] Per-task state record + `cdd-state` helper: a `<branch>.state.json` sibling of the handoff, advanced through the lifecycle by the slash commands via `tools/cdd-state.sh` (atomic `seed`/`set`, self-installing). Advisory, local-only, append-only `{id, stage}` session chain. Full design in process doc §2.13; schema in `doc/architecture/shell-helpers.md`. — §2.13 + §2.6/§2.8/§3.3, all four command copies (repo + template), both `settings.json`, `tools/cdd-state.sh` (new) and `tools/cdd-worktree.sh` (deletion), architecture/feature docs, BOOTSTRAP.md.
- [x] Record the handoff session (and per-session working dir) in seeded records (issue #51, writer half; reader half is cdd-dash PR #10): `cdd-state seed` now records the `/cdd-next-step` handoff session as the first `sessions[]` entry so it is resumable, and every session entry carries a `dir` (the worktree root, the `cd` target for `claude --resume`). Additive/optional — no `schema_version` bump; old and new records interoperate. — `tools/cdd-state.sh` (seed + set), `doc/architecture/shell-helpers.md`, `scripts/install-smoke-assert.sh`.
- [ ] Consume the record: teach the `cdd-dash` dashboard to read `stage`/`sessions` instead of inferring task state. (`cdd-worktree-list` already infers worktree/branch/PR status fine and does not need the record — fold in only if a concrete need appears.)
- [x] Multi-machine resume — worktree + branch (issue #22): `cdd-worktree-resume [<branch>]` recreates a worktree on an existing remote branch (no handoff required, discovery mode when no branch given), ready for a resume-side command. — `tools/cdd-worktree.sh`, process doc §2.8/§2.13, `scripts/worktree-resume-assert.sh` (new) + CI step, README, both `CLAUDE.md` workflow sections.
- [x] Multi-machine resume — handoff + state sync (issue #22): the handoff (`<branch>.md`) and state record (`<branch>.state.json`) now sync across machines via a per-task ref `refs/cdd/<branch>` — a tree of the two files wrapped in a parentless commit, force-pushed (latest-wins) automatically inside `cdd-state` on `seed`/`set`, and fetched + materialized by `cdd-worktree-resume` before it finishes. Materialize reconciles by most-advanced-stage-wins (the handoff being immutable is never clobbered); `cdd-worktree-done` best-effort deletes the remote ref. Advisory end-to-end — no `origin`/offline/missing-`jq`/no-ref all warn-and-continue, so a resume with no ref behaves exactly as before. No slash-command changes (the push funnels through `cdd-state`). git notes was rejected (anchors to a commit, chases the moving tip). — `tools/cdd-state.sh` (push on seed/set), `tools/cdd-worktree.sh` (fetch/materialize in resume, remote-ref cleanup in done), process doc §2.8/§2.13, `doc/architecture/shell-helpers.md`, `scripts/ref-sync-assert.sh` (new) + CI step, README, CLAUDE.md build/workflow sections.
- [x] Per-repo main-worktree marker (issue #58): `~/.cdd/handoffs/<repo>/repo.json`, a `{schema_version, name, path}` sibling of the task records and the one artifact in that directory that is **not** task-scoped — so a repo stays locatable once every task is reaped and its directory goes empty (the case a consumer like `cdd-dash` cannot answer from records alone). `path` is the MAIN worktree (`dirname` of git's common dir, deliberately not `--show-toplevel`, which names the *feature* worktree whenever a task session is the writer). One writer, three callers: `cdd-state seed` and `cdd-state set` (the latter *before* its absent-record return, so a repo whose records are all reaped still gets one) plus `bootstrap-cdd-project.sh`, which sources its sibling helper rather than duplicating the shape. Overwrites unconditionally, so it self-heals when a repo moves or is re-cloned. Machine-local: excluded from `refs/cdd/<branch>` by construction (the ref bundles only `handoff.md` + `state.json`), and survives GC by construction (candidates glob `*.md` ∪ `*.state.json` ∪ `refs/cdd/*`). Advisory end-to-end — a failing `rev-parse`, an unwritable dir, or a missing `jq` warns and returns 0, so it can never fail the state write or the `set -e` bootstrap that called it. Consumers prefer a live `sessions[].dir` and fall back to the marker, so a stale marker can't outvote a directory a session is demonstrably using. — `tools/cdd-state.sh` (new `cdd-state-main-worktree` + `cdd-state-write-repo-marker`), `tools/bootstrap-cdd-project.sh`, process doc §2.13, `doc/architecture/shell-helpers.md` + index, `scripts/gc-assert.sh` (survival), `scripts/install-smoke-assert.sh` (main-worktree derivation), `scripts/ci.sh` (throwaway HOME for the three gates that bootstrap a real tree, + marker assertion).
- [x] Garbage-collect finished tasks' artifacts (`cdd-worktree-gc`): the per-task ref sync makes `cdd-worktree-done` the only reaper of the handoff, state record, and `refs/cdd/<branch>`, so they leak when `done` never runs, its ref delete fails offline, or a multi-machine resume leaves materialized copies behind on every machine but the one where `done` ran. `cdd-worktree-gc [--force]` sweeps them, reaping **only** tasks whose PR has merged (a merged PR is the sole trustworthy "done" signal — a scoped-but-unstarted task's handoff and ref exist before its branch does, so branch/ref presence can't distinguish them). Enumerates local handoffs ∪ `refs/cdd/*` so any machine can reap leaked refs and its own orphaned locals; dry-run unless `--force`; needs `gh`. — `tools/cdd-worktree.sh` (new command + PATH shim), process doc §2.8, `doc/architecture/shell-helpers.md`, `scripts/gc-assert.sh` (new) + CI step, README, CLAUDE.md.

**Milestone:** a task's lifecycle stage and its working sessions are recorded as data and surfaced by CDD tooling, not reconstructed by inference.

## Annotation conventions

The default is no annotation. Tick the box and stop.

Only add an inline annotation when a future session needs information that none of the other artifacts will carry — i.e. *not* in the commit, *not* in the PR description, *not* in an ADR, *not* in the process / architecture / feature docs (which you should be updating as part of the same change). Typical cases: a deferred sub-item, a surprising caveat, a scope change.

A completed item reads like a PR title or barely more. If you do annotate, keep it to a single short clause. Do not restate what the task did or how it was implemented; that information already lives where readers will look for it.

```
- [x] <Task description> — <one short clause: deferred X / caveat Y / out-of-scope Z>
```

Items above this line predating the convention are over-long; they are left as-is rather than rewritten, and are not a precedent.
