# <PROJECT_NAME> Implementation Roadmap

Ordered implementation sequence for building <PROJECT_NAME>. Each phase builds on the previous one. Phases are roughly sequential, but some work within a phase can be parallelized in separate worktrees as long as the tasks touch non-overlapping modules.

This file is the central artifact of the Claude-Driven Development workflow. It is simultaneously a plan, a progress log, and a context document for future sessions. See "Annotation conventions" below for what (and what not) to write next to a completed checkbox.

The bootstrap script has already initialised the git repository and laid down the CDD scaffold (`CLAUDE.md`, `.claude/commands/`, `doc/`, `tools/`). Phase 1 should start from "add language/tooling scaffold" or whatever the first project-specific step actually is — not from "initialise the repo".

## Phase 1: <Phase title>

<One paragraph: what this phase achieves and what milestone it ends on.>

- [ ] <Task description>
- [ ] <Task description>
- [ ] <Task description>

**Milestone: <one sentence describing the observable end state of this phase>.**

## Phase 2: <Phase title>

<One paragraph.>

- [ ] <Task description>

**Milestone: <observable end state>.**

## Phase N: <...>

<Continue as needed.>

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
