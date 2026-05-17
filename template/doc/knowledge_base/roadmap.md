# <PROJECT_NAME> Implementation Roadmap

Ordered implementation sequence for building <PROJECT_NAME>. Each phase builds on the previous one. Phases are roughly sequential, but some work within a phase can be parallelized in separate worktrees as long as the tasks touch non-overlapping modules.

This file is the central artifact of the Claude-Driven Development workflow. It is simultaneously a plan, a progress log, and a context document for future sessions. Completed items are annotated inline with what landed, what was deferred, and any caveats, this is how context is preserved across sessions.

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

When a task is completed, tick its checkbox and add an inline annotation describing what landed and what was deferred. Example:

```
- [x] <Task description> — <one-line summary of what landed; deferred items: <list>; caveats: <list>>
```

This annotation is read by future Claude Code sessions to understand the current state without re-reading the entire commit history. Keep it accurate.
