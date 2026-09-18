Make a small, pre-stated change end to end in one session: `/cdd-small-change` (takes no argument).

This is the whole build half of the **small-change lane** — it replaces `/cdd-plan` *and* `/cdd-implement` for a task the human declared small at scoping. It runs in the task's feature worktree, which `cdd-worktree <branch>` opened on this command because the task's state record marks the lane.

There is no plan file on this lane, and there will not be one. That is why this session carries its own approval gate (step 3) rather than inheriting one: the standard lane's implementing session needs no gate because the plan was already approved, and nothing was approved here yet.

The tail of the cycle is unchanged: `/cdd-merge-base` if the base moved, then `/cdd-pre-pr`, the PR, and `/cdd-process-pr`. This lane shortens the middle, not the review.

## 1. Read the handoff

Derive the task's paths from git — no argument is passed:

```bash
repo="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
branch="$(git rev-parse --abbrev-ref HEAD)"
echo "handoff: ~/.cdd/handoffs/$repo/$branch.md"
```

Read it in full. A small-change handoff is deliberately thin: its `## Requirements` are the done-test (normally one or two criteria), and `## Notes` carries any caveat or roadmap edit agreed at scoping. It carries no `## Implementation prompt` — on this lane there is nothing to say that the requirements do not already say.

Then read only what the change itself touches. Do not rebuild the project's full context: a task that needs it is not small, which is what step 2 is for.

## 2. Confirm the task is still small (the off-ramp)

The eligibility heuristic, as it was applied at scoping:

> If you can state the finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard lane.

Two bounds, and both must hold. **Discovery**: there is nothing to find out — that is the one-sentence test. **Durability**: there is no reasoning worth carrying into the next window, because this lane writes no plan file and only the requirements plus the diff reach `/cdd-pre-pr` and the reviewer. The bar is **not** line count.

Judge it again now that you have the handoff in front of you. If the task turns out not to be small — the diff cannot be stated, a design question is hiding in it, the reasoning behind it would be worth reading later — then **stop, write nothing, and tell the user to run `/cdd-plan` in this same worktree**. Say in one line which bound failed. `/cdd-plan` works from this handoff as it stands; it reads `## Requirements` and `## Notes` and never needs an `## Implementation prompt`.

The off-ramp costs one session start. It is the safety net that lets the heuristic stay this short, so take it rather than talk yourself past it.

## 3. Checkpoint: approve the concrete change

This is checkpoint 3 in its small-change form: the human approves the actual change instead of a written plan. State the change in short — what it does and why — plus any doc or roadmap edit step 5 will apply, if there is one. Follow the rule in `CLAUDE.md`: short, plain, only what changes the answer. Leave out the file list; the human sees that at review time. If stating the change takes more than a few lines, step 2's answer was wrong.

Then ask for approval, and iterate until you get it.

Nothing mechanical stops you from writing here, so **write nothing — inside the repo or out of it — until the answer is yes**.

## 4. Make the change

Make exactly the change that was approved. If reality contradicts it — the file does not say what you said it says, the edit turns out to need a second one — go back to step 3 with the correction rather than widening the change silently.

## 5. Update the docs

The same obligation the standard lane carries: a change is not done until the docs match it. Update the architecture and feature docs the change affects, `CLAUDE.md` where the change alters what it describes, and the roadmap — ticking the completed checkbox and applying any edit the handoff's `## Notes` pre-approved.

## 6. Verify

Run the project's check runner, whole — the same command CI runs, not a subset chosen for a small diff.
<!-- cdd-only-begin -->

In this repo the runner is `./scripts/ci.sh`. It is not fail-fast, so one invocation surfaces every problem; `./scripts/ci.sh <gate>` reruns one while iterating on a failure.
<!-- cdd-only-end -->

Report failures with their output rather than summarizing them away. A gate that skipped because its tool is missing is a skip, not a pass — say so.

## 7. Commit

Commit your own changes locally — **no push** — following the commit conventions in `CLAUDE.md`. Commit only the files you changed, adding them by path; never `git add -A`. If the tree holds changes you did not make, surface them rather than committing them.

Then advance the task **state record** (advisory; it skips silently if the record is absent):

```bash
cdd-state set implementation_done
```

This lane never passes through `plan_written`, and that is a non-event: consumers compare stages by index, so a stage that was never written is simply one they never observe.

## 8. Print the next command

Print a short summary first, per the rule in `CLAUDE.md`: what changed and why, whether the checks passed, and anything from the handoff's `## Requirements` you could not satisfy. No file list — that shows up at review time.

Then print:

```
Next: /cdd-merge-base if the base branch has moved, otherwise /cdd-pre-pr — each in a fresh session.
```
