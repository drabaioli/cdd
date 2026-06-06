# <PROJECT_NAME> Implementation Roadmap

Ordered implementation sequence for building <PROJECT_NAME>. Each phase builds on the previous one. Phases are roughly sequential, but some work within a phase can be parallelized in separate worktrees as long as the tasks touch non-overlapping modules.

This file is the central artifact of the Claude-Driven Development workflow. It is simultaneously a plan, a progress log, and a context document for future sessions. See "Annotation conventions" below for what (and what not) to write next to a completed checkbox.

## Phase 1: CDD bootstrap

Get the CDD substrate to reflect reality: survey what exists, write the initial docs, and turn this file into a real plan. On a greenfield project some of these tasks are near-trivial — do the thin version and move on.

- [ ] Survey the codebase and draft the initial architecture docs under `doc/architecture/`: an `overview.md` with the high-level shape, plus per-topic docs as warranted. For a greenfield project, write architecture guidelines and intentions instead.
- [ ] Write the initial feature docs under `doc/features/`: one doc per existing user-visible capability. Likely empty for a greenfield project.
- [ ] Fill in the `CLAUDE.md` stubs: project description, critical constraints, build/test commands, module layout.
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

Slot these into the phases above where they fit — usually spread across the early phases, not bundled into one. Drop the ones that don't apply; delete this section once it has been folded in.

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

The default is no annotation. Tick the box and stop.

Only add an inline annotation when a future session needs information that none of the other artifacts will carry — i.e. *not* in the commit, *not* in the PR description, *not* in the process / architecture / feature docs (which you should be updating as part of the same change). Typical cases: a deferred sub-item, a surprising caveat, a scope change.

If you do annotate, keep it to a single short clause. Do not restate what the task did or how it was implemented; that information already lives where readers will look for it.

```
- [x] <Task description> — <one short clause: deferred X / caveat Y / out-of-scope Z>
```
