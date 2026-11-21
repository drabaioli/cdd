# 0031: Narrow the pre-PR review

**Status:** Accepted

## Context

`/cdd-pre-pr`'s step-3 code review asked for "Design issues (coupling, responsibility boundaries,
API shape)" beside correctness, the coding standard and bloat, and fixes the clear defects it
finds (ADR 0025). Issue #153 found:

- "If you fix every finding, you end up with extra abstraction layers and tests for cases that
  can't happen"; limit reviewers to correctness and the stated requirements (Claude Code best
  practices).
- Models fix problems well once a tool or a failing test points at them, but find them poorly
  alone, and self-review without tool output can make correct code worse (Olausson et al.,
  ICLR 2024; Dolcetti et al., arXiv 2412.14841).

Design is settled earlier, at plan approval (checkpoint 3), and the human PR review
(checkpoint 6) remains. ADR 0030's rules are "held by review, not a gate".

## Decision

The pre-PR code review checks correctness, the handoff's `## Requirements`, the project coding
standard and every rule in "Writing changes" — the review that holds ADR 0030's rules. It has no
open-ended design bullet. This complements ADR 0030; it supersedes nothing.

## Rejected alternatives

- A constrained design bullet: still open-ended, and design belongs to plan approval.
- Design guidance in `/cdd-plan`: it already covers design (approach research, verification, the
  least-code rule, plan approval).
- Dropping the coding-standard bullet: it carries project-specific rules, the one kind of
  instruction #153 found useful.

## Consequences

- Fewer unrequested refactors land in the pre-PR fix commit.
- A design problem the plan missed is caught by the human at PR review, not by the agent.
- No checkpoint changes.
