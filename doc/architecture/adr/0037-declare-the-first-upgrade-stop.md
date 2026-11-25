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

A fourth, #90, also covers `cdd-worktree`'s pre-split fallback, a helper piece.

## Decision

1. **One stop retires all three** (batching, ADR 0035 §2). Each stop costs an old project one
   extra retrofit run, so one stop beats three.
2. **The stop is `287ad43`**, the commit that added the markers: the oldest `main` commit carrying
   every retired piece. Every baseline written since passes it without a second hop, and a project
   routed through it goes on to the latest CDD anyway.
3. **#90 waits.** Its helper piece needs every project on every machine past the plan/implement
   split (ADR 0035 §3), which is not yet confirmed.
4. **#93's marker covers the rename row too**, so it goes with the token rows. The legacy-token
   step and the rename pre-pass stay, as permanent steps with empty tables; the worktree-helper
   retirement advice served only a deleted row and goes with it.
5. **The `transitional` gate's self-test uses `#0`**, a number no issue has, so the pending-removal
   listing (process doc §2.20) never names a closed issue.

## Rejected alternatives

- **A newer stop.** Buys nothing, and sends every project retrofitted since `287ad43` through an
  extra run.
- **One stop per issue.** Three extra runs for an old project.
- **Keeping `#148` as the gate fixture.** The pending-removal listing would name a closed issue
  forever.

## Consequences

- A project whose baseline predates `287ad43` retrofits twice: once at the stop, then to the latest.
- The fourth verdict, the upgrade-path `list`-mode and practices-gate proposals, the legacy-token
  and rename rows, and the legacy worktree-helper advice are gone from `/cdd-retrofit`.
- `/cdd-pre-pr`'s open-issue check flags the new `#0` fixture once, on this branch; expected.
