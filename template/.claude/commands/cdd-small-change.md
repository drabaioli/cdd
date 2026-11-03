Make a small, pre-stated change end to end in one session: `/cdd-small-change` (takes no argument).

This is the build half of the **small-change lane**: it replaces `/cdd-plan` *and* `/cdd-implement` for a task the human declared small at scoping. It runs in the task's feature worktree. There is no plan file on this lane, so this session takes its own approval (step 3).

## 1. Read the handoff

Derive the task's paths from git — no argument is passed:

```bash
repo="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
branch="$(git rev-parse --abbrev-ref HEAD)"
echo "handoff: ~/.cdd/handoffs/$repo/$branch.md"
```

Read it in full. Its `## Requirements` are the done-test (normally one or two criteria), and `## Notes` carries any caveat or roadmap edit agreed at scoping. It has no `## Implementation prompt` and no `## Research`.

Then read only what the change itself touches. Do not rebuild the project's full context: a task that needs it is not small (step 2).

## 2. Confirm the task is still small (the off-ramp)

The eligibility heuristic, as applied at scoping:

> If you can state the finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard lane.

Both bounds must hold. **Discovery**: there is nothing to find out — the one-sentence test. **Durability**: there is no reasoning worth carrying into the next window (the small-change lane writes no plan file). The bar is **not** line count.

Judge it again now. If the task is not small — the diff cannot be stated, a design question is hiding in it, the reasoning behind it would be worth reading later — then **stop, write nothing, and tell the user to run `/cdd-plan` in this same worktree**, saying in one line which bound failed. A task that needs research — anything to look up outside the repo — fails the discovery bound: take the off-ramp, and never spawn researchers on this lane. `/cdd-plan` works from this handoff as it stands.

Take the off-ramp rather than talk yourself past it.

## 3. Checkpoint: approve the concrete change

Checkpoint 3 in its small-change form: the human approves the actual change, not a written plan. State the change in short — what it does and why — plus any doc or roadmap edit step 5 will apply. Follow the rule in `CLAUDE.md`: short, plain, only what changes the answer. If stating the change takes more than a few lines, step 2's answer was wrong.

Then ask for approval, and iterate until you get it. **Write nothing — inside the repo or out of it — until the answer is yes.**

## 4. Make the change

Make exactly the change that was approved. If reality contradicts it — the file does not say what you said it says, the edit turns out to need a second one — go back to step 3 with the correction rather than widening the change silently.

## 5. Update the docs

A change is not done until the docs match it. Update the architecture and feature docs the change affects, `CLAUDE.md` where the change alters what it describes, and the roadmap — ticking the completed checkbox and applying any edit the handoff's `## Notes` pre-approved.

Rationale lives once: where the change touches a rule whose argument already has a home, shrink any other restatement of it to the rule plus a pointer there, rather than rewriting it at full length.

## 6. Verify

Run the project's check runner, whole — the same gate list CI runs, not a subset chosen for a small diff.

Report failures with their output, not a summary of them. A gate whose tool is missing has failed, not skipped — say which tool to install.

## 7. Commit

Commit your own changes locally — **no push** — following the commit conventions in `CLAUDE.md`. Commit only the files you changed, adding them by path; never `git add -A`. If the tree holds changes you did not make, surface them rather than committing them.

Then advance the task **state record** (advisory; it skips silently if the record is absent):

```bash
cdd-state set implementation_done
```

This lane skips `plan_written`; that is expected.

## 8. Print the next command

Print a short summary first, per the rule in `CLAUDE.md`: what changed and why, whether the checks passed, and anything from the handoff's `## Requirements` you could not satisfy.

Then print:

```
Next: /cdd-merge-base if the base branch has moved, otherwise /cdd-pre-pr — each in a fresh session.
```
