# 0006: A small-change lane beside the standard plan/implement cycle

**Status:** Accepted

## Context

Early CDD carried a trivial-task escape hatch: a change small enough to state outright did not have
to go round the full cycle. It was dropped, deliberately — it was an unwritten judgement call with
no artifact behind it, and issue #68 objected to exactly that shape, a seam exercised only
sometimes and therefore never really tested. Dropping it closed a hole. It also opened a gap, and
this ADR is about the gap rather than about relitigating the hole.

The gap is concrete. Ticking one roadmap box, fixing a typo, adding a roadmap phase — each of these
now costs a handoff session, a plan session, an implementation session, and a pre-PR session. The
plan session has nothing to explore and writes a plan file nobody will read twice; the
implementation session re-reads files to rediscover a change that fitted in a sentence. The cost is
not the tokens, it is that a workflow whose cheapest path is four windows teaches its user to
route small work around it, which is how a process starts being observed selectively.

The counter-pressure is `CLAUDE.md`'s standing constraint that the six checkpoints of process doc §4
are load-bearing and are not to be weakened without explicit discussion. This ADR is that discussion.

## Decision

**Add a second lane through the middle of the cycle: `/cdd-small-change`, one session in place of
`/cdd-plan` + `/cdd-implement`.** The handoff before it and the merge, pre-PR, review and teardown
after it are untouched. Three windows instead of four, and the review is not shortened at all.

**A new command, not a mode of an existing one.** `/cdd-implement` states that it must never
improvise the work from the handoff alone, and that it needs no gate of its own precisely because
checkpoint 3 already fired in the session before it. A small-change session must carry its own
approval, so it is a different job — and process doc §3 names session types by job. Giving
`/cdd-implement` a second behaviour would also reintroduce #68's objection: a branch inside a
command, taken sometimes. Instead the branch lives in `cdd-worktree`, **before** any session
starts, where it is a routing decision on a recorded fact rather than a judgement made mid-prompt.

**The lane is recorded on the task state record, not inferred.** `/cdd-next-step` writes a `lane`
field at scoping, on the human's decision; `cdd-worktree` and `cdd-worktree-resume` read it. It is
additive and optional exactly as `base_branch` is, and every miss — no marker, no record, no `jq`,
a project that ships no `/cdd-small-change`, a helper too old to look — falls back to the standard
lane. The degrade is one-directional by design: a lost marker costs a window, where a marker
guessed by inference could skip a gate.

**The eligibility heuristic is one sentence**, stated verbatim in the process doc and in both
commands that apply it, and pinned across all three by a prompt-seam check: *"If you can state the
finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard
lane."* A disqualifier list was drafted and rejected as too strict and self-growing, and largely
redundant — an open design question is already a diff you cannot state. It is restated rather than
cited because the template ships no copy of the process doc, so a pointer would dangle downstream.

**The human decides, in either direction, unconditionally** — including declaring small a task the
heuristic did not. `/cdd-small-change` re-checks and takes an off-ramp into `/cdd-plan` in the same
worktree when the task turns out not to be small, which is what lets the heuristic stay this short.

**The count stays six; checkpoint 3 changes form only.** Checkpoints 1, 2, 4, 5 and 6 fire exactly
as before — `/cdd-next-step` and `/cdd-pre-pr` both still run, the PR is still reviewed and merged.
Checkpoint 3 still fires, still before anything is written, still as an explicit ask; what the human
approves is a stated diff rather than a plan file, because on this lane there is no plan file.

**Relationship to issue #89.** #89's currency for relaxing a gate is *mechanization*: an Enforced
practice buys the relaxation. This lane's currency is different — the human declares the task small
and then approves the actual change up front. The shape is ADR 0004's (a precise firing condition,
never the agent's own judgement), the argument is not. This lane is **not** a down payment on #89
Part 2, and it touches none of checkpoints 1, 5 and 6, which #89 fixes as never-changing.

**CI is not relaxed.** `/cdd-small-change` runs the check runner whole. Process doc §2.14 makes the
runner the sole source of the gate sequence, and per-diff gate selection is precisely the judgement
it exists to remove; CI runs on the PR regardless, so a local skip only moves a failure later. Gate
*cost* is a separate problem (issue #75).

## Rejected alternatives

- **Folding `/cdd-pre-pr` into the lane for a two-window path.** Saves one window; costs a
  duplicated eight-step command, a second consumer of the `Closes #NN` seam, a relocated checkpoint
  5, and an improvement check (ADR 0003) either dropped or duplicated. Revisit with evidence if the
  pre-PR window turns out to be the actual irritant.
- **A branch created in place, no worktree, switching back afterwards.** Every failure strands the
  main checkout, it needs a clean tree to start, and `/cdd-process-pr` pulls a worktree back in at
  review time anyway.
- **Batching small edits onto a standing chore branch.** Genuinely cheaper for typo-class work, and
  recorded here because it competes honestly rather than because it is weak.
- **Teaching `/cdd-implement` to work from the handoff when no plan exists.** Refused by that
  command's own rule against improvising from the handoff alone.
- **A `--small` flag on `/cdd-next-step`.** Smallness is only answerable once the task is known, and
  the `issues` browse front-end is exactly where it is not yet: `--small issues` is incoherent, not
  merely awkward.
- **A `--lane` flag on `cdd-state seed`, or a `scoped_small` stage.** The flag would make an older
  helper reject the whole seed and write no record at all, losing the base branch with it; a new
  stage would shift every index in the hand-mirrored stage list that two helpers compare against.

The roadmap's own annotation conventions say an ADR records decisions, not pending scope, which is
why the first entry above is a sentence and not a design, and why none of these opens an issue.

## Consequences

- The cheapest honest path through CDD is now three windows, and small work has somewhere to go
  that is inside the workflow rather than around it.
- **"The six checkpoints" is again not a flat list to read at face value.** ADR 0004 made one of
  them conditional; this makes one of them take two forms. Anything counting or citing checkpoints
  has to pick both up, and §4 carries the qualification.
- **The eligibility heuristic is deliberately weak, and the off-ramp is what makes that acceptable.**
  If the off-ramp is ever weakened — made conditional, made a judgement call, quietly dropped — the
  heuristic has to get much stronger in the same change.
- The lane is invisible to an older `cdd-worktree`, which simply runs the standard lane. That is the
  intended failure, but it means a fleet with mixed helpers will see the same task take different
  paths on different machines, with no warning; the reverse-skew warning the plan/implement split
  needed has no counterpart here, because nothing stalls.
- The prompt-seam count moves from seven to nine, and the count is prose in four places rather than
  mechanically derived — a known soft spot, unchanged by this ADR but now carrying two more checks.
- A small-change task produces no plan file, so `/cdd-pre-pr` and the reviewer see the requirements
  and the diff and nothing else. That is the durability bound stated as a cost: if the reasoning
  behind a change would have been worth reading later, the task was never eligible.
