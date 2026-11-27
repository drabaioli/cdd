# 0037: Declare the first upgrade stop

**Status:** Accepted

## Context

[ADR 0035](0035-mark-transitional-changes-retire-through-stops.md) marked every transitional piece
with its removal issue and made upgrade stops the way `/cdd-retrofit` pieces are retired. Three
removals were pending that touch only `/cdd-retrofit` and the docs describing it:

- #148 — the fourth verdict, moving local edits in shipped commands onto declarations or
  extensions ([ADR 0020](0020-extend-commands-through-project-owned-extensions.md));
- #166 — the upgrade-path proposals of a check-runner `list` mode and the practices gate
  ([ADR 0029](0029-ship-the-practices-checker.md));
- #93 — the legacy-token rows of section 4.5 and the template-rename row of section 4.4.

A fourth, #90, covered both a `/cdd-retrofit` piece (the plan/implement split's `CLAUDE.md`
Workflow edit) and `cdd-worktree`'s pre-split fallback, a helper piece; four projects on the
maintainer's machine still lack `/cdd-plan`.

## Decision

1. **One stop retires them all** (batching, ADR 0035 §2). Each stop costs an old project one
   extra retrofit run, so one stop beats four.
2. **The stop is `287ad43`**, the commit that added the markers: the oldest `main` commit carrying
   every retired piece. Every baseline written since passes it without a second hop, and a project
   routed through it goes on to the latest CDD anyway.
3. **#90 is split.** Its retrofit piece goes with this stop; its helper piece moves to #181 and
   waits for every project on every machine to have `/cdd-plan` (ADR 0035 §3), so each issue
   covers one kind and none waits on another's signal.
4. **#93's marker covers the rename row too**, so it goes with the token rows. The legacy-token
   step and the rename pre-pass stay, as permanent steps with empty tables; the worktree-helper
   retirement advice served only a deleted row and goes with it.
5. **The `transitional` gate's self-test uses `#0`**, a number no issue has, so the pending-removal
   listing (process doc §2.20) never names a closed issue.

## Rejected alternatives

- **A newer stop.** Buys nothing, and sends every project retrofitted since `287ad43` through an
  extra run.
- **One stop per issue.** Three extra runs for an old project.
- **Keeping #90 whole.** Its retrofit piece would wait on a fleet check it does not need.
- **Keeping `#148` as the gate fixture.** The pending-removal listing would name a closed issue
  forever.

## Consequences

- A project whose baseline predates `287ad43` retrofits twice: once at the stop, then to the latest.
- The fourth verdict, the upgrade-path `list`-mode and practices-gate proposals, the legacy-token
  and rename rows, the legacy worktree-helper advice and the split's Workflow-edit instruction are
  gone from `/cdd-retrofit`.
- `cdd-worktree`'s pre-split fallback stays, marked `TRANSITIONAL(#181)`.
- `/cdd-pre-pr`'s open-issue check flags the new `#0` fixture once, on this branch; expected.
