# 0004: Make the merge-base approval checkpoint conditional

**Status:** Accepted

## Context

Human checkpoint 4 (process doc §4) sits between `/cdd-merge-base`'s dry run and its merge: the
human approves after seeing which files conflict and how hard the conflicts look. On most runs that
is a real decision. On one path it is not.

When `git merge-tree --write-tree --name-only` reports **zero** conflicting files and the dry run's
scan of the non-conflicting changes turns up nothing this branch should adopt, there is nothing for
the human to weigh. The command asked anyway — §3 said so explicitly: "skip to step 5 and ask the
user whether to proceed." The human confirms a merge git has already proven textually clean, on a
branch whose worktree §1 already proved clean. That is the shape process doc §1 names as a gap
rather than a gate: "automate everything except decisions … everywhere else, a recurring manual step
is a gap: convert it into a mechanism."

The counter-pressure is `CLAUDE.md`'s standing constraint that the six checkpoints are load-bearing
and are not to be weakened without explicit discussion. This ADR is that discussion.

## Decision

**`/cdd-merge-base` merges without asking when, and only when, all of these hold:**

1. The worktree is clean (already established in §1).
2. `git merge-tree --write-tree --name-only` reports **zero** conflicting files.
3. The §3 scan of the non-conflicting changes on the base branch flags **nothing** — no new
   convention, no new utility, no refactored interface relevant to this branch.
4. The post-merge verify (§7 build + tests) passes. This one is a *safety net, not a precondition*:
   it is evaluated after the merge exists.

Criteria 1–3 are checked before merging; if any fails, the §4 assessment is presented and the
command stops for explicit approval, exactly as before. If 4 fails after an automatic merge, the
command reports the failure plainly and offers `git reset --hard ORIG_HEAD`; it never leaves a
broken tree without saying so, and it never pushes.

Two smaller calls follow from this:

- **The §4 report becomes a post-hoc summary on the auto path.** The alternative — print the full
  assessment block, then merge without waiting — produces output that reads like a question but
  isn't. Instead the auto path prints a one-line notice naming the three facts on the way in, and
  §8's summary carries the assessment on the way out.
- **§6 ("adopt non-conflict improvements") is unreachable on the auto path, by construction.**
  Criterion 3 requires the scan flagged nothing, so there is nothing to adopt. This is stated in the
  command rather than left as an accident: an automatic merge never adopts improvements. If anything
  is worth adopting, the run was never trivial.

**Checkpoint 4 stays in the list; the count stays at six.** The process doc records it as
*conditional* — fires whenever human input is actually needed, skipped only on the mechanically
trivial path — with the rationale in §4.

## Rejected alternatives

- **An "easy/mechanical conflict → auto-resolve" tier.** The single most tempting extension, and the
  reason the rule is drawn where it is. "Zero conflicts" is a mechanical fact reported by git;
  "this conflict is mechanical" is the agent's own judgement — precisely the judgement checkpoint 4
  exists to check. The failure mode is concrete and silent: the agent classifies a conflict as
  mechanical, resolves it wrong, the tests do not cover that path, criterion 4 goes green, and the
  wrong resolution lands with no human ever having looked at it.
- **The original framing, "if no human input is needed, merge."** Same objection one level up: the
  agent self-assessing "I don't need the human here" is the judgement being guarded. The rule was
  narrowed to the four mechanical criteria above for that reason.
- **An opt-out flag.** `/cdd-merge-base` keeps taking no argument. A flag would put the width of the
  automatic path back in the hands of whoever is typing, which is the same problem in a different
  place, and it adds an argument to a command whose whole interface today is its name.
- **A mechanical seam check pinning the criteria list to the process-doc wording.** Considered and
  skipped. `scripts/command-drift-check.sh` already keeps the two command copies honest, which is
  the drift that actually bites; a grep seam over prose in a fourth location would pin wording, not
  behaviour. Consistent with ADR 0002's scoping of prompt CI to deterministic checks that earn their
  keep.

## Consequences

- The common case of `/cdd-merge-base` — base advanced, no textual collision — becomes a single
  uninterrupted run. The human's attention is spent only where conflicts or adoptable changes exist.
- **The residual risk is a semantic break with no textual conflict**: two sides that never touch the
  same lines can still contradict each other, and criteria 3 and 4 only catch what the scan notices
  and what the tests cover. This is the honest cost of the change. It is bounded by the merge being
  local and unpushed and fully revertable, and by checkpoint 6 (PR review) still standing.
- The rule is deliberately conservative and may prove *too* conservative — criterion 3 in particular
  will send runs to the approval path over a single flagged utility that the human would have waved
  through. That is the intended direction of error. Revisit with evidence from real runs, not by
  reasoning about it further.
- Checkpoint 4 is now the first checkpoint whose firing is conditional, so "the six checkpoints" is
  no longer a flat list to read at face value. §4 carries the qualification; anything counting or
  citing checkpoints must pick it up.
