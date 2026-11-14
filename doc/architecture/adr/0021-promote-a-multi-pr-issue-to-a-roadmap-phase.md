# 0021: Promote a multi-PR issue to a roadmap phase; promotion closes it

**Status:** Accepted

## Context

Issue-driven `/cdd-next-step` treated an issue as one task and, by default, added no roadmap item
(process doc §3.1): the issue already tracked the work. That breaks for an issue spanning several
PRs — an epic, such as #145. Its first PR closed it through the `/cdd-pre-pr` close line, and the
remaining work then had no place on the roadmap. Epics had been handled by hand; issue #146 asked
for it in the command.

## Decision

1. **Roles: the tracker is the inbox, the roadmap is the plan.** An issue is either done straight
   off the tracker (one PR, which closes it) or promoted onto the roadmap. Promotion is what
   closes a multi-PR issue: "closed" means planned, not done. From then on the roadmap owns order
   and progress, and the issue is reference material, read through the reference on each line.
2. **Multi-PR is a judgement, made like the lane (ADR 0006).** The session recommends in one line,
   naming the signal — the issue lays out, up front, several separately shippable steps whose
   order is worth planning, or asks for a phase — and the human decides. An issue merely likely
   to take two or three PRs is not an epic.
3. **Promotion is a phase of roadmap edits in the handoff.** One task line per PR, each ending with
   the issue's reference and within the 200-character cap (ADR 0005); the issue keeps the detail.
   The handoff session still never edits the roadmap (§2.2). The first task adds the phase, and the
   human chooses whether it also does the phase's first line. When the issue asks for a
   convergence step first (decisions to confirm, research to finish), that step is the first line,
   and the implementation lines are added or confirmed only once the human approves the final
   shape.
4. **The first task records the issue's reference; later tasks record none.** The first task is
   issue-driven as before, so its PR closes the issue. The later ones are picked roadmap-driven:
   the issue is already closed, and a close line on a PR that closes nothing is noise. Closing it
   again would be harmless — `issue-transition` returns `changed: false` — so this is about noise,
   not safety.
5. **Roadmap-driven mode reads the chosen line's cited issue**, open or closed, as part of the
   task's context: the issue holds the detail the line leaves out. Failing to read it stops the
   command, as in issue-driven mode.
6. **Issue-driven mode refuses a closed issue.** `/cdd-next-step <ref>` on a closed issue says so
   and stops: the issue is either done or promoted, and a promoted phase's next line comes from
   plain `/cdd-next-step`.

## Rejected alternatives

- **Keep the issue open until its last line is ticked.** An open epic keeps coming back as an entry
  point (`/cdd-next-step <ref>`, the `issues` browse list) when the next step should come from
  plain `/cdd-next-step`; and every task recording its reference would emit a close line that
  closes it after the first merge anyway.
- **Record the reference on every later task.** Harmless, but noise (decision 4).

## Consequences

- No change to `cdd-state`, `/cdd-pre-pr` or the tracker adapters: every adapter's `issue-read`
  returns closed issues, and the first task records its reference exactly as before.
- A reader seeing a closed issue cited by pending roadmap lines must read "closed" as planned.
- Out of scope: an issue that grows mid-implementation — a single task whose PR does only part of
  it. It is not an epic and gets no phase: the human leaves it open with a progress comment, and a
  later `/cdd-next-step <ref>` resumes it from the comments. Supporting it in the tooling is a
  follow-up (#151): today the state record makes `/cdd-pre-pr` emit a close line, and `cdd-worktree-done`
  / `-gc` close the issue after the merge, regardless.
- #145 is the first issue to use this.
