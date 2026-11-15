# 0022: Say nothing when all is normal

**Status:** Accepted

Partially supersedes [0010](0010-code-host-rename-and-broken-adapter-rule.md) (decision 4: the
prompts announce every rung) and [0011](0011-bind-adapters-through-a-machine-global-library.md)
(a bound project shows the helpers' "using adapter" line). The rest of both stands.

## Context

`/cdd-next-step` reported outcomes that needed no decision — the checkout is current, there are
no stale handoffs, the issue is open and single-PR so no roadmap line — and every adapter call
announced which rung served it. Since ADR 0011 the installers bind projects at the project rung,
so that announcement printed on nearly every command and helper run, saying only that the
committed binding was in use. Lines that never change the human's answer teach them to skip the
ones that do.

## Decision

1. **A normal outcome prints nothing.** A check that passed or a default that held gets no line;
   only what needs the human or changes their answer does. The rule lives once, in "Talking to
   the human" in `CLAUDE.md` (and the template's). Commands drop wording that invites a
   normal-case line rather than each gaining a "stay quiet" clause: `/cdd-next-step` recommends a
   phase only for a multi-PR issue and points at `cdd-worktree-list` only beside a stale handoff;
   `/cdd-pre-pr` says "no close lines" only when the task has no state record.
2. **Only the machine rung is announced.** A call served by `~/.cdd/adapters/<capability>` says so
   in one line at the point of use, in prompts and helpers alike; one served by the project's own
   `.cdd/<capability>` is silent. The machine rung is invisible from the repo and binds every
   repository on the machine, so serving from it is worth a line; the project binding is
   committed and reviewed. The broken-adapter and missing-adapter lines are unchanged.

## Rejected alternatives

- A "stay quiet" clause in each command: the rule repeated per command, and still missing from
  the next one.
- Dropping the announcement entirely: a machine-rung adapter serving a repo that never chose it
  would go unnoticed.

## Consequences

- No stop condition or human wait point changes. A single-PR issue is no longer called out; the
  human can still ask for a phase when approving the handoff.
- The `code-host-ladder` and `adapter-bindings` gates pin the silent project rung; the
  `issue-close` gate, which binds at the machine rung, still pins the announcement.
