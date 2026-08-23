# <PROJECT_NAME> Implementation Roadmap

Ordered implementation sequence for building <PROJECT_NAME>. Each phase builds on the previous one. Phases are roughly sequential, but some work within a phase can be parallelized in separate worktrees as long as the tasks touch non-overlapping modules.

This file is the central artifact of the Claude-Driven Development workflow. It is simultaneously a plan, a progress log, and a context document for future sessions. See "Annotation conventions" below for what (and what not) to write next to a completed checkbox.

## Phase 1: CDD bootstrap

Get the CDD substrate to reflect reality: survey what exists, write the initial docs, and turn this file into a real plan. On a greenfield project some of these tasks are near-trivial — do the thin version and move on. On an existing project retrofitted onto CDD without prior doc discipline they are the opposite of trivial: this is the first time the docs are forced to match the code, and it may take several heavier-than-usual PRs before they agree. That cost is expected, not a sign anything is wrong. Where the project already has documentation, reconcile and adopt it into this structure rather than overwriting it — preserve what the project already knows about itself. Common fold-ins seen in practice:

- Split architecture docs (e.g. `doc/backend/` + `doc/frontend/`, a top-level `system-architecture.md`) → `doc/architecture/`.
- A `future-work.md` / TODO / backlog doc → this roadmap.
- An oversized `CLAUDE.md` duplicating command/troubleshooting content → slim to pointers (it costs context every session).

On a greenfield project, write architecture guidelines and intentions rather than a survey, and expect `doc/features/` to start out empty. On an existing project, fold in what is already written — a README, design docs, feature notes — rather than starting from scratch.

- [ ] Survey the codebase and draft the initial architecture docs under `doc/architecture/`: an `overview.md` with the high-level shape, plus per-topic docs as warranted.
- [ ] Write the initial feature docs under `doc/features/`: one doc per existing user-visible capability.
- [ ] Fill in the project charter (`doc/knowledge_base/project-overview.md`) and the `CLAUDE.md` stubs: what the project is, goals, non-goals, constraints, build/test commands, module layout.
- [ ] Fill in the engineering-practices contract (`doc/knowledge_base/engineering-practices.md`): mark each practice *enforced* or *expected*, and fill the command placeholders that apply.
- [ ] Fill in this roadmap: replace the placeholder phases below with the project's real plan, slotting in items from "Suggested infrastructure tasks" where they fit.

**Milestone: the docs describe the project as it actually is, and the roadmap below is a real plan.**

## Phase 2: <Phase title>

<One paragraph: what this phase achieves and what milestone it ends on.>

- [ ] <Task description>
- [ ] <Task description>
- [ ] <Task description>

**Milestone: <one sentence describing the observable end state of this phase>.**

## Phase 3: <Phase title>

<One paragraph.>

- [ ] <Task description>

**Milestone: <observable end state>.**

## Phase N: <...>

<Continue as needed.>

## Suggested infrastructure tasks

Slot these into the phases above where they fit — usually spread across the early phases, not bundled into one. Drop the ones that don't apply; delete this section once it has been folded in. Each one the project commits to but hasn't mechanized yet is an *expected* practice in `doc/knowledge_base/engineering-practices.md`; closing it flips that row to *enforced*.

- Set up CI: build + tests on every PR.
- Add linting and a format check (and a pre-commit hook if wanted).
- Establish coding guidelines (under `doc/knowledge_base/`), if the language or team needs them.
- Add unit tests; add integration tests once there are module boundaries worth crossing.
- Write or refresh the README: what the project is, how to build and run it.
- Pin or lock dependencies; document the toolchain versions.
- Set up release / versioning conventions, if the project ships artifacts.

## Key principles

Use this section to record principles that apply across phases. Examples:

- <Principle: e.g. "Test in simulation before hardware">
- <Principle: e.g. "One layer at a time">
- <Principle: e.g. "Minimal viable first, refined later">

## Annotation conventions

**Every item — pending or completed — fits in 200 characters.** That is a PR-title-shaped description plus, at most, one short trailing clause after a semicolon. The cap is the whole line, `- [x] ` prefix included. Pending items are not exempt: a task too big to state in a line is a task whose scope belongs somewhere else. A one-line length check in this project's check runner keeps it honest, since a cap nobody measures drifts back.

The default is no annotation. Tick the box and stop.

Only add an inline annotation when a future session needs information that none of the other artifacts will carry — i.e. *not* in the commit, *not* in the PR description, *not* in an ADR, *not* in the process / architecture / feature docs (which you should be updating as part of the same change). Typical cases: a deferred sub-item, a surprising caveat, a scope change. Keep it to a single short clause. Do not restate what the task did or how it was implemented; that information already lives where readers will look for it.

```
- [x] <Task description>; <one short clause: deferred X / caveat Y / out-of-scope Z>
```

Detail that does not fit has a home, and it is never this file:

- a **GitHub issue**, referenced by number on the roadmap line — `/cdd-next-step #NN` sources a task straight from it, and issues are already the inbox feeding this roadmap;
- the **handoff file**, for detail the implementation session needs and nobody afterwards does.

When a task hinges on a design decision, the ADR is written when the decision is *taken*; the issue carries the thinking until then. ADRs record decisions, not pending scope.

Cite an ADR by number (`ADR 0002`), not by a full relative link: the link target alone can eat a third of the budget, and `doc/architecture/index.md` lists them all. Do not add a separate backlog or notes document — a second list of pending work is a second thing to keep in sync, and this roadmap is the source of truth.
