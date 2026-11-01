# 0017: Hold the task stage at pr_open once a PR exists

**Status:** Accepted

## Context

`cdd-state set <stage>` overwrote `.stage` unconditionally: every command writes the stage it stands
for when it finishes, whatever the record already says. Several commands are meant to be re-run
after a PR exists, so the record could move backwards while `.pr` stayed set (issue #134):

- `/cdd-process-pr`, then `/cdd-pre-pr` re-run to confirm the gates still pass: `addressed` →
  `checks_passed`. Common.
- `/cdd-merge-base` after the base advanced under an open PR: → `merged`, and then the recommended
  `/cdd-pre-pr`: → `checks_passed`. Common; `/cdd-merge-base` itself tells the user to re-run
  `/cdd-pre-pr` before opening or updating the PR.
- `/cdd-implement` re-run on a task with a PR: → `implementation_done`. Rare.

After any of these a task whose PR is open looks as if it has no PR yet. Two documented assumptions
break with it. Consumers compare stages by index, so a dashboard that keys "ask whether the PR
merged, and offer `cdd-worktree-done`" on `pr_open`/`addressed` gets the wrong default action on the
most common end-of-task path. And the cross-machine sync keeps the most advanced copy of a record,
so the newer, regressed record loses to an older one: the outcome depends on which side regressed,
not on which side is newer. `/cdd-pre-pr` §11 also offered to open a second PR.

Before a PR the same regressions are meaningful and must keep working. `merged` sits below
`checks_passed` precisely because checks must run again after a base merge, and a re-plan from
`implementation_done` back to `plan_written` is deliberate.

## Decision

Put a floor in the one chokepoint every command already goes through, `cdd-state set`. Once the
record has a PR — after applying `--pr`, so a PR given in the same call counts — a requested stage
below `pr_open` is **held**: `.stage` keeps its current value and the helper prints one line saying
so (`State: x.state.json stays addressed (PR #42 open; checks_passed not recorded as stage)`). The
session entry is still appended with the requested stage, and the task ref still syncs. With no PR
there is no floor.

Stage order comes from `cdd-state stages` and is compared in shell; jq only receives a boolean, so
nothing depends on how a given jq version treats `index` on an array. Whether a write was held
follows from the condition (a PR present and the requested stage below `pr_open`), not from
comparing old and new stage, so a legacy record already sitting below the floor with a PR is held
too.

`/cdd-pre-pr` §11 asks the code host for an open PR on the branch before offering to open one,
falling back to the record's `pr` when the adapter cannot answer, and on a hit says the PR is
already open and to push to update it.

The floor is pinned by its own gate, `state-stage`.

## Rejected alternatives

- **Fix each command** (have `/cdd-pre-pr`, `/cdd-merge-base` and `/cdd-implement` skip their write
  when a PR exists). A project with an older command set stays broken until its commands are
  upgraded; the helper updates on its own, so a floor there covers every project at once.
- **Raise a low write to `pr_open`.** The record would claim a stage nothing wrote, which is the
  thing a writer must never do.
- **Reject the write.** The writer is advisory and must never fail a command.
- **A floor before a PR exists.** It would break `merged` after `checks_passed` (checks re-required)
  and a deliberate re-plan.
- **A post-merge `done` stage.** A separate question, out of scope here.
- **Reordering the enum.** Out of scope; the order already says what each stage means.

## Consequences

- `.stage` now means "the furthest point the task has reached", and `sessions[-1].stage` means
  "what ran last". No information is lost and no field is added.
- Comparing stages by index and the most-advanced-wins sync are sound once a PR is recorded.
- A PR opened by hand and never recorded gives no floor; only `/cdd-pre-pr` §11 sees it, through
  the code host.
- A consumer that wants to know a `/cdd-merge-base` ran after the PR opened reads it from
  `sessions[]`, not from `.stage`.
