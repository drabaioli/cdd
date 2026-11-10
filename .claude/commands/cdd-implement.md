Implement the task from its approved plan file, update the docs, and commit locally: `/cdd-implement` (takes no argument).

Run in a **fresh** context in the feature worktree. The plan was approved at checkpoint 3: take no approval of your own, and do not quietly decide anything the plan does not say.

**Project extension.** First, check for `.cdd/extensions/cdd-implement.md`. If it exists, read it and follow it alongside this command: it adds steps under `##` headings that name, by title rather than number, the step of this command each one attaches to. It cannot remove, skip, reorder or weaken anything here — least of all a point where this command waits for the human. Where it would, follow this command and say so in one line; never resolve the conflict silently. If it names a step this command does not have, say so in one line and ask where it goes. With no file, carry on.

## 1. Read the plan

Derive the task's paths from git — no argument is passed:

```bash
repo="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
branch="$(git rev-parse --abbrev-ref HEAD)"
echo "plan:    ~/.cdd/handoffs/$repo/$branch.plan.md"
echo "handoff: ~/.cdd/handoffs/$repo/$branch.md"
```

Read the plan first, in full; its `## Summary` orients you. Then read the handoff's `## Requirements`: those acceptance criteria are the done-test.

How to treat the plan's sections:

- `## File map` names the files to open and the conclusion reached about each. Re-read those files.
- `## External findings` is quoted verbatim. Trust it; do not re-run the searches. Act on each finding's disposition, and check a "to verify" finding the way `## Verification` says.
- `## Dead ends` lists rejected approaches. Do not re-explore them.
- `## Open questions resolved` answers are settled; do not reopen them unilaterally.

## 2. Deviation rule: stop and report, never improvise

If reality contradicts the plan, **stop and report to the human**. Do not silently pick a different approach, and do not re-derive the task from the handoff.

Two expected cases:

- **The plan's anchors no longer match the tree** (e.g. a `/cdd-merge-base` ran since planning). If the cited `file:line` lines no longer say what the plan says, stop, report which anchors drifted, and offer to re-run `/cdd-plan` against the merged tree.
- **The plan file is not there** (an older worktree helper does not sync it). Say plainly the plan was not materialized on this machine, and offer to re-run `/cdd-plan`. **Never improvise the work from the handoff alone.**

Anything smaller — a stale line number, a renamed file, a step that turns out to be a no-op — is your judgement call; mention it in the final summary.

## 3. Implement

Work the plan's `## Approach` steps in order.

## 4. Update the docs

Apply the plan's `## Doc and roadmap edits`: the architecture and feature docs, `CLAUDE.md` where the change alters what it describes, and the roadmap (ticking the completed checkbox and applying any pre-approved edits). A change is not done until the docs match it.

Rationale lives once: where the change touches a rule whose argument already has a home, shrink any other restatement of it to the rule plus a pointer there, rather than rewriting it at full length.

## 5. Verify

Run what the plan's `## Verification` names — the check runner `CLAUDE.md` declares (with none declared, each gate it lists under Build & test), plus any assertions or tests the plan says to add or extend. Report failures with their output, not a summary of them.

## 6. Commit

Commit your own changes locally — **no push** — following the commit conventions in `CLAUDE.md`. Commit only the files you changed, adding them by path; never `git add -A`. If the tree holds changes you did not make, surface them rather than committing them.

Then advance the task **state record** (advisory; it skips silently if the record is absent):

```bash
cdd-state set implementation_done
```

## 7. Summary

Print a short summary, per the rule in `CLAUDE.md`: what was implemented, whether the checks passed, any deviation from the plan and why, and anything from the handoff's `## Requirements` you could not satisfy.

Then print:

```
Next: /cdd-merge-base if the base branch has moved, otherwise /cdd-pre-pr — each in a fresh session.
```
