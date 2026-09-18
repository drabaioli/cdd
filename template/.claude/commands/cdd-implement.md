Implement the task from its approved plan file, update the docs, and commit locally: `/cdd-implement` (takes no argument).

This is the second half of the implementation cycle, run in a **fresh** context in the same feature worktree that `/cdd-plan` ran in. Its input is the plan file. That file exists because a human approved it at checkpoint 3, which is why this session needs no gate of its own — and why it must not quietly decide something the plan does not say.

## 1. Read the plan

Derive the task's paths from git — no argument is passed:

```bash
repo="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
branch="$(git rev-parse --abbrev-ref HEAD)"
echo "plan:    ~/.cdd/handoffs/$repo/$branch.plan.md"
echo "handoff: ~/.cdd/handoffs/$repo/$branch.md"
```

Read the plan first, in full. Its `## Summary` is your orientation; the rest is the detail.

Then read the handoff, for its `## Requirements` — those acceptance criteria are the done-test, and they survived both windows precisely so that a plan which misread the intent is still caught here.

The plan's sections carry different weights, by design:

- `## File map` names the files to open and the conclusion already reached about each. Re-read those files — the plan cites repo facts rather than copying them because they are cheap for you to re-derive.
- `## External findings` is quoted verbatim because it **cannot** be re-derived here. Trust it; do not go re-run the searches.
- `## Dead ends` records approaches already tried and rejected. Do not re-explore them.
- `## Open questions resolved` records what the handoff deferred and what was agreed. Those answers are settled; do not reopen them unilaterally.

## 2. Deviation rule: stop and report, never improvise

If reality contradicts the plan, **stop and report to the human**. Do not silently pick a different approach, and do not fall back to re-deriving the task from the handoff. The plan was the thing that was approved; departing from it unsupervised discards the checkpoint.

Two cases must be handled explicitly, because both are expected rather than hypothetical:

- **The plan's anchors no longer match the tree.** The gap between planning and implementing is human-paced, so a `/cdd-merge-base` may have run in between and moved everything the plan's `file:line` pointers refer to. If the cited lines no longer say what the plan says they say, stop and report which anchors drifted; offer to re-run `/cdd-plan` against the merged tree.
- **The plan file is not there.** A machine running an older worktree helper materializes only the handoff and the state record from the task's sync ref, so a plan written elsewhere may never have landed here. Say plainly that the plan was not materialized on this machine, and offer to re-run `/cdd-plan`. **Never improvise the work from the handoff alone** — that silently reverts the task to the un-split flow with no approved plan behind it.

Anything smaller — a stale line number, a file renamed, a step that turns out to be a no-op — is a judgement call you may make and must mention in the final summary.

## 3. Implement

Work the plan's `## Approach` steps in order.

## 4. Update the docs

Apply the plan's `## Doc and roadmap edits`: the architecture and feature docs, `CLAUDE.md` where the change alters what it describes, and the roadmap (ticking the completed checkbox and applying any pre-approved edits). A change is not done until the docs match it.

## 5. Verify

Run what the plan's `## Verification` section names — the project's check runner, plus any assertions or tests the plan says to add or extend. Report failures with their output rather than summarising them away.

## 6. Commit

Commit your own changes locally — **no push** — following the commit conventions in `CLAUDE.md`. Commit only the files you changed, adding them by path; never `git add -A`. If the tree holds changes you did not make, surface them rather than committing them.

Then advance the task **state record** (advisory; it skips silently if the record is absent):

```bash
cdd-state set implementation_done
```

## 7. Summary

Print a short summary, per the rule in `CLAUDE.md`: what was implemented, whether the checks passed, any deviation from the plan and why, and anything from the handoff's `## Requirements` you could not satisfy. No file list — that shows up at review time.

Then print:

```
Next: /cdd-merge-base if the base branch has moved, otherwise /cdd-pre-pr — each in a fresh session.
```
