# CDD Roadmap

This is the central workflow artifact for the CDD project. Tasks are grouped into phases; each phase ends with a milestone. See "Annotation conventions" at the end of this file for what (and what not) to write next to a completed checkbox.

## Phase 1: MVP shipped

Write the process document, draft the template, and get the repo self-hosting CDD on GitHub.

**Milestone:** CDD repo on GitHub, self-hosting CDD, ready to be used for a real downstream project.

## Phase 2: First downstream dogfooding

Run the workflow end-to-end on a first real downstream project and capture every awkward or missing piece.

**Milestone:** one real downstream project running CDD, with friction from early usage folded back into the template.

## Phase 3: Template refinement from real usage

Refine the template and commands from real usage; tasks here are driven by friction surfaced during dogfooding.

**Milestone:** template is ergonomic enough that bootstrapping a new project takes under five minutes.

## Phase 4: Greenfield bootstrap automation

Turn the manual greenfield start into a single `/cdd-bootstrap` command. Depends on Phases 2 and 3 surfacing what the manual flow actually looks like.

**Milestone:** a new project can be bootstrapped end-to-end through one guided `/cdd-bootstrap` session — definition, overview, and real roadmap included.

## Phase 5: Retrofit existing projects

Bring CDD to projects that already exist: files-only install, baseline-anchored upgrade, and a first real retrofit trial.

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

**Milestone:** starting an off-roadmap task — typed or sourced from a GitHub issue — is a first-class, structured `/cdd-next-step` flow.

## Phase 9: Lightweight one-off deliverables

Support producing a small, self-contained deliverable without the full CDD project substrate, with a clean escalation path when it turns out to be a project.

**Milestone:** a trivial standalone artifact can be produced through one guided `/cdd-quick-create` session, with an escalation path to `/cdd-bootstrap` when it turns out to be a project.

## Phase 10: Retrofit hardening (from real retrofit trials)

Defects and gaps surfaced by retrofitting CDD onto real existing projects. Each item is a general template/process fix, not a project-specific patch.

**Milestone:** CDD retrofits cleanly onto a project regardless of default-branch name, repo directory name/location, or pre-existing doc layout, without per-project manual fixes to the scaffolding.

## Phase 11: Founding-objective guardrails

Elevate the two under-guarded founding objectives — instilling engineering best practices, and workflow self-improvement — from implicit to named-and-tracked. Decision and reasoning in `doc/architecture/adr/0001-name-and-guard-founding-objectives.md`.

**Milestone:** all three founding objectives are named commitments in §1, each with at least one recurring guardrail or a tracked plan to add one.

## Phase 12: Open-source readiness

Prepare CDD to be open-sourced publicly: license it, rewrite the README to explain and demonstrate the workflow, and track the remaining open-source essentials. Contribution policy at launch is issues-only (no PRs yet).

**Milestone:** CDD is presentable and safe to open-source publicly — licensed, with a README that explains and demonstrates the workflow — with the remaining open-source essentials tracked.

## Phase 13: Task state & observability

Give each task a machine-readable record of where it sits in its lifecycle and which Claude Code sessions have worked it, so tooling can show task state instead of inferring it from handoffs, branches, and `gh`.

**Milestone:** a task's lifecycle stage and its working sessions are recorded as data and surfaced by CDD tooling, not reconstructed by inference.

## Phase 14: Extensibility — capability adapters

Make CDD adaptable to a project's tracker and code host without editing a shipped prompt: a fixed `.cdd/` namespace of capability adapters, resolved project → machine → built-in and falling back to today's behaviour when none is installed. The design detail — namespace, verb contracts, JSON shapes, exit codes, and the replace-vs-mirror rule that bounds what an extension may substitute — lives in GitHub issue #86.

**Milestone:** a project can run CDD with Jira as its tracker without editing a single shipped prompt, and `/cdd-retrofit` can migrate an existing project's local prompt edits onto the extension points.

## Annotation conventions

**Every item — pending or completed — fits in 200 characters.** That is a PR-title-shaped description plus, at most, one short trailing clause after a semicolon. The cap is the whole line, `- [x] ` prefix included, and it is enforced mechanically by `scripts/roadmap-length-check.sh` (the `roadmap-length` gate), so it is not a matter of judgement. Pending items are not exempt: a task too big to state in a line is a task whose scope belongs somewhere else.

The default is no annotation. Tick the box and stop.

Only add an inline annotation when a future session needs information that none of the other artifacts will carry — i.e. *not* in the commit, *not* in the PR description, *not* in an ADR, *not* in the process / architecture / feature docs (which you should be updating as part of the same change). Typical cases: a deferred sub-item, a surprising caveat, a scope change. Keep it to a single short clause. Do not restate what the task did or how it was implemented; that information already lives where readers will look for it.

```
- [x] <Task description>; <one short clause: deferred X / caveat Y / out-of-scope Z>
```

Detail that does not fit has a home, and it is never this file:

- a **GitHub issue**, referenced by number on the roadmap line — `/cdd-next-step #NN` sources a task straight from it, and issues are already the inbox feeding the roadmap;
- the **handoff file**, for detail the implementation session needs and nobody afterwards does.

When a task hinges on a design decision, the ADR is written when the decision is *taken*; the issue carries the thinking until then. ADRs record decisions, not pending scope.

Cite an ADR by number (`ADR 0002`), not by a full relative link: the link target alone can eat a third of the budget, and `doc/architecture/index.md` lists them all.

A separate backlog or notes document was considered and rejected — see ADR 0005, which also records why this file previously carried an escape clause grandfathering over-long items, and why it no longer does.
