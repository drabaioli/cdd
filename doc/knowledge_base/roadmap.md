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
- [x] Do the exploratory work outside CDD: language, tooling, top-level architecture, hand-written initial roadmap. — Python/Flask, an actions-pipeline architecture, a 6-phase roadmap (`demo/seed/`)
- [x] Bootstrap the new project from `template/`, including the placeholder substitution. — automated by `demo/setup.sh`, which wraps `bootstrap-cdd-project.sh --overlay demo/seed`
- [x] Run the first `/cdd-next-step` → implementation → `/cdd-pre-pr` → PR cycle on the downstream project. — mdr_demo_01
- [x] Keep a friction log: every awkward or missing piece, recorded outside the downstream project. — landed as `friction-log.md`; retired after mdr_demo_01
- [x] Complete at least three task cycles before drawing conclusions. — mdr_demo_01
- [x] Build the `demo/` subsystem: a filled-in seed (`demo/seed/`) plus create/teardown automation that doubles as a reproducible demo and the dogfooding greenfield. — third repo artifact

**Milestone:** one real downstream project running CDD, with friction from early usage folded back into the template.

## Phase 3: Template refinement from real usage

Refine the template and commands from real usage; tasks here are driven by friction surfaced during dogfooding.

- [x] Refine `/cdd-merge-main` based on the first real merge encountered. — the mdr_demo_01 Phase 3 merge (ACTIONS/toolbar conflict) succeeded with no changes needed
- [x] Improve the placeholder-substitution recipe in the template README. — README renamed to `template/BOOTSTRAP.md`; the sed recipe replaced by `bootstrap-cdd-project.sh`
- [x] Add a script that does rename + placeholder substitution non-interactively. — landed as `tools/bootstrap-cdd-project.sh`, outside `template/`; two-identifier model
- [x] Add a `template-smoke` CI workflow that asserts the bootstrap produces a clean, link-valid tree. — `.github/workflows/template-smoke.yml` + `scripts/template-smoke-assert.sh`
- [x] Resolve the divergence between `.claude/commands/` and `template/.claude/commands/` introduced during Phase 2. — enforced mechanically by `scripts/command-drift-check.sh` thereafter
- [x] Add a `/cdd-pre-pr` check (in the CDD repo) for unintended drift between the two command sets.
- [x] Add a `/cdd-process-pr` command: triage and address the open PR's review feedback, post in-thread replies, commit + push. — process doc §3.7, §4.1
- [x] Auto-allow worktree sessions to read their handoff file so `cdd-worktree` no longer prompts on first launch. — `.claude/settings.json` + template copy.
- [x] Fix the readable handoff path in `/cdd-next-step`: a `<PROJECT_DIR>` placeholder in the template, the `cdd` literal in the CDD repo. — mdr_demo_01 friction round
- [x] rc-install in demo setup/teardown: `demo/setup.sh` appends a marker-guarded sourcing block to `~/.bashrc`; `demo/teardown.sh` removes it by marker. — mdr_demo_01 friction round
- [x] Index-as-pointers rule: encode in process doc + template CLAUDE.md + skeleton index.md files; restructure demo seed docs into subdocuments. — mdr_demo_01 friction round
- [x] ADRs: Nygard-style `doc/architecture/adr/NNNN-title.md`; ship template + CDD repo ADR directory; reference in process doc and CLAUDE.md. — mdr_demo_01 friction round
- [x] Encode the session taxonomy: named session types in process doc §3, an edit-rules matrix keyed by them, fresh-context-per-job as a blanket invariant.
- [x] Reconcile README.md (bootstrap one-liner, BOOTSTRAP.md link, dogfooding status) and add it to `/cdd-pre-pr` doc reconciliation in both command copies.
- [x] Replace the hand-maintained command-drift list with a render-then-diff check (`scripts/command-drift-check.sh` + whitelist), run by CI and `/cdd-pre-pr`.
- [x] Add shellcheck to CI over all repo shell scripts.
- [x] Worktree helpers: main-worktree guard on `cdd-worktree`; default branch derived from origin's HEAD (fallback `main`), `origin` assumption documented in BOOTSTRAP.md.
- [x] Restrict bootstrap placeholder substitution to text files so binary overlay assets survive.

**Milestone:** template is ergonomic enough that bootstrapping a new project takes under five minutes.

## Phase 4: Greenfield bootstrap automation

Turn the manual greenfield start into a single `/cdd-bootstrap` command. Depends on Phases 2 and 3 surfacing what the manual flow actually looks like.

- [x] Design a `/cdd-bootstrap` command that guides the user through producing the project definition and a draft roadmap by conversation, then feeds it into the bootstrap script.
- [x] Decide where `/cdd-bootstrap` runs: outside any project, inside the empty target, or inside the CDD repo with an output path. — CDD-repo-only, like `/cdd-retrofit`
- [x] Implement `/cdd-bootstrap` (guided discovery → overlay → one bootstrap invocation) and validate it by bootstrapping a second greenfield project end-to-end.

**Milestone:** a new project can be bootstrapped end-to-end through one guided `/cdd-bootstrap` session — definition, overview, and real roadmap included.

## Phase 5: Retrofit existing projects

Bring CDD to projects that already exist: files-only install, baseline-anchored upgrade, and a first real retrofit trial.

- [x] Implement `/cdd-retrofit` (CDD repo): install CDD into an existing project, or upgrade one already on CDD, preserving local customizations.
- [x] Have a freshly bootstrapped or retrofitted project propose the codebase survey + initial docs as its first task. — a pre-filled bootstrap phase in the template roadmap; files-only starts
- [x] Trial the retrofit on one existing project. — Colibri (Zephyr/C++); surfaced the change-isolation defect below.
- [x] Make `/cdd-retrofit` stage its changes on a dedicated branch + worktree in the target rather than the target's current branch, and commit them there for review.
- [x] Make the retrofit path honest about the doc-reconciliation cost: name it in the process doc, strengthen template Phase 1 for the existing-project case, flag the slow first `/cdd-next-step`.

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

- [x] Extend `/cdd-next-step` with an optional intent prompt: a task prompt runs the intent-driven flow, no argument keeps the roadmap-driven one. One command, two front-ends.
- [x] Add a GitHub-issue front-end to `/cdd-next-step` (`#NN` or the `issue` keyword; branch `gh_issue_NN_<slug>`), plus an opt-in PR step in `/cdd-pre-pr` adding `Closes #NN`.
- [x] Auto-commit at workflow gates: the implementation session and `/cdd-pre-pr` commit their own changes locally, no push (issue #20). — one shared commit convention, process doc §2.11
- [x] Prefix every CDD slash command with `cdd-` so they autocomplete as a discoverable group (issue #27). — 11 command files renamed and every cross-reference swept
- [x] Unify the worktree helper into one self-installing, project-independent `cdd-worktree` (issues #24 + #18). — handoffs moved to `~/.cdd/handoffs/<repo>/`; placeholders collapsed to two
- [x] Fix the worktree PATH shims stranding the caller for cwd-changing commands, and make `install` self-repair a disabled rc block.

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

- [x] Second retrofit trial: PyGroundControl (Python/FastAPI + TypeScript SDK + React, default branch `devel`); install-mode retrofit plus heavy doc reconciliation. — surfaced the defects below
- [x] **Default branch is hardcoded to `main` in the commands.** Fixed: both commands resolve it via `origin/HEAD`, falling back to `main`. — `/cdd-merge-main` renamed to `/cdd-merge-base`
- [x] **The handoff path diverges when the repo dir isn't a valid `<PROJECT_DIR>`.** Fixed: the bootstrap regex is loosened so CamelCase dirs like `PyGroundControl` are accepted as-is.
- [x] **`cdd-next-step.md` hardcodes `~/Code/<PROJECT_DIR>` as the repo location.** Fixed: §8 resolves the repo root via `git rev-parse --show-toplevel` and embeds the actual path.
- [x] **Per-task base branch (gitflow: platform default ≠ integration branch).** Each task's base is captured on its state record, cut from by `cdd-worktree`, targeted by the resume-side commands.
- [x] **Retrofit reconciles newly-added fill-in docs instead of shipping raw skeletons** (issue #41): upgrade mode only, per-file approval, residual placeholders flagged. — install mode exempt
- [x] **Retrofit doc-reconciliation playbook for common pre-existing layouts** — split architecture docs, a future-work/backlog doc, an oversized CLAUDE.md — in `/cdd-retrofit` and the process doc.

**Milestone:** CDD retrofits cleanly onto a project regardless of default-branch name, repo directory name/location, or pre-existing doc layout, without per-project manual fixes to the scaffolding.

## Phase 11: Founding-objective guardrails

Elevate the two under-guarded founding objectives — instilling engineering best practices, and workflow self-improvement — from implicit to named-and-tracked. Decision and reasoning in `doc/architecture/adr/0001-name-and-guard-founding-objectives.md`.

- [x] Audit the three founding objectives against the workflow and record the gap inventory. — ADR 0001
- [x] Name the under-guarded objectives in §1: broaden "documents itself" into "holds itself to engineering standards", add "the workflow improves itself" (4 → 5 commitments).
- [x] Ship the engineering-practices contract (enforced vs expected): process doc §2.12 + template `doc/knowledge_base/engineering-practices.md`, instantiated in the CDD repo and the demo seed.
- [x] Add the `/cdd-pre-pr` test-coverage reconciliation step (both command copies) as the recurring objective-2 guardrail.
- [x] Objective-3 standing channel routing a discovered improvement into the roadmap/conventions. — the `/cdd-pre-pr` improvement check plus `/cdd-process-pr` gap triage; ADR 0003
- [x] Reinforce objective 2 at bootstrap. — landed as discovery questions plus a resolved contract rather than the anticipated task/checklist; guided path only, retrofit install mode exempt
- [x] Objective-1 mechanizations: `/cdd-merge-base` auto-merges the mechanically-trivial case, making checkpoint 4 conditional, and `/cdd-pre-pr` reports base drift as a commit count. — ADR 0004
- [x] Deterministic prompt seam-contract checks (Tier 1; issue #23): `scripts/prompt-seam-check.sh` pins the grep-only seams between the workflow's own prompts. — scope: ADR 0002
- [x] Audit the process-doc references in all 7 repo commands and their template copies for context cost (PR #38 review). — zero load-bearing pointers; no command edits needed
- [x] One check runner shared by CI and `/cdd-pre-pr` (issue #36): `scripts/ci.sh` is the sole source of the gate sequence. — pre-PR review added the `seams-contract` mutation gate
- [x] Strip the dangling `(process doc §N)` pointers from the shipped commands, symmetrically in repo and template copies (PR #55). — a sixth, a bare `(§2.13)`, turned up later
- [x] Recompact every roadmap item to a 200-char cap, pending and completed alike, enforced by the `roadmap-length` gate. — detail now goes to an issue or a Proposed ADR; ADR 0005

**Milestone:** all three founding objectives are named commitments in §1, each with at least one recurring guardrail or a tracked plan to add one.

## Phase 12: Open-source readiness

Prepare CDD to be open-sourced publicly: license it, rewrite the README to explain and demonstrate the workflow, and track the remaining open-source essentials. Contribution policy at launch is issues-only (no PRs yet).

- [x] Add a standard MIT `LICENSE` at the repo root (holder: Diego Andres Rabaioli; 2026). — repo-root only; the template is copied verbatim into downstream projects
- [x] Rewrite the README from scratch: what CDD is, guided entry points first, a reference of all 7 slash commands, the task-cycle image, an issues-only Contributing section.
- [x] README re-framing + visual-polish pass: AI-agents/automation framing first, How it works 10 → 7 steps, a hero banner and an expanded badge row. — README-only; no template counterpart
- [ ] `CONTRIBUTING.md` (full version, once PRs are accepted).
- [x] `CODE_OF_CONDUCT.md`. — Contributor Covenant 2.1 at the repo root; enforcement contact `drabaioli@gmail.com`. Repo-root only, not added to `template/`.
- [x] `.github/` issue templates: `bug_report.yml` and `idea.yml` forms plus `config.yml` (blank issues enabled). PR template deferred until PRs open.
- [x] `SECURITY.md`. — Repo-root file directing reporters to GitHub private vulnerability reporting (not email); wording assumes the repo setting is enabled (manual one-time toggle).
- [x] GitHub repo metadata: description, topics (via `gh repo edit`), and a 1280×640 social-preview image.
- [x] Confirm the public repo home / org and update the README badge + clone URLs. — home stays `github.com/drabaioli/cdd`; the URLs were already correct, no rewrite needed

**Milestone:** CDD is presentable and safe to open-source publicly — licensed, with a README that explains and demonstrates the workflow — with the remaining open-source essentials tracked.

## Phase 13: Task state & observability

Give each task a machine-readable record of where it sits in its lifecycle and which Claude Code sessions have worked it, so tooling can show task state instead of inferring it from handoffs, branches, and `gh`.

- [x] Per-task state record + `cdd-state` helper: a `<branch>.state.json` sibling of the handoff, advanced through the lifecycle by the slash commands. — advisory; process doc §2.13
- [x] Record the handoff session and each session's working dir in seeded state records (issue #51, writer half). — additive and optional; no `schema_version` bump
- [ ] Consume the record: teach the `cdd-dash` dashboard to read `stage`/`sessions` instead of inferring task state. — `cdd-worktree-list` infers fine and does not need it
- [x] Multi-machine resume — worktree + branch (issue #22): `cdd-worktree-resume [<branch>]` recreates a worktree on an existing remote branch, no handoff required.
- [x] Multi-machine resume — handoff + state sync across machines via a per-task ref `refs/cdd/<branch>` (issue #22). — advisory end-to-end; design in `doc/architecture/shell-helpers.md`
- [x] Per-repo main-worktree marker `~/.cdd/handoffs/<repo>/repo.json` (issue #58), so a repo stays locatable once all its task records are reaped. — design in `doc/architecture/shell-helpers.md`
- [x] Garbage-collect finished tasks' artifacts: `cdd-worktree-gc [--force]` reaps the handoff, state record, and ref of any task whose PR has merged. — the backstop for `cdd-worktree-done`

**Milestone:** a task's lifecycle stage and its working sessions are recorded as data and surfaced by CDD tooling, not reconstructed by inference.

## Annotation conventions

**Every item — pending or completed — fits in 200 characters.** That is a PR-title-shaped description plus, at most, one short trailing clause after an em dash. The cap is the whole line, `- [x] ` prefix included, and it is enforced mechanically by `scripts/roadmap-length-check.sh` (the `roadmap-length` gate), so it is not a matter of judgement. Pending items are not exempt: a task too big to state in a line is a task whose scope belongs somewhere else.

The default is no annotation. Tick the box and stop.

Only add an inline annotation when a future session needs information that none of the other artifacts will carry — i.e. *not* in the commit, *not* in the PR description, *not* in an ADR, *not* in the process / architecture / feature docs (which you should be updating as part of the same change). Typical cases: a deferred sub-item, a surprising caveat, a scope change. Keep it to a single short clause. Do not restate what the task did or how it was implemented; that information already lives where readers will look for it.

```
- [x] <Task description> — <one short clause: deferred X / caveat Y / out-of-scope Z>
```

Detail that does not fit has a home, and it is never this file:

- a **GitHub issue**, referenced by number on the roadmap line — `/cdd-next-step #NN` sources a task straight from it, and issues are already the inbox feeding the roadmap;
- an **ADR with `Status: Proposed`** when the detail *is* a design decision, so the alternatives are recorded before the work starts;
- the **handoff file**, for detail the implementation session needs and nobody afterwards does.

Cite an ADR by number (`ADR 0002`), not by a full relative link: the link target alone can eat a third of the budget, and `doc/architecture/index.md` lists them all.

A separate backlog or notes document was considered and rejected — see ADR 0005, which also records why this file previously carried an escape clause grandfathering over-long items, and why it no longer does.
