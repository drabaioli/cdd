# 0025: The pre-PR review fixes clear defects

**Status:** Accepted

## Context

`/cdd-pre-pr` fixed stale docs directly but only flagged what its code review found. Sessions
read that differently: some fixed a bug anyway, others reported an obvious one-line defect and
left it, so it reached the PR open, or was fixed only when the human asked.

## Decision

The code review **fixes a clear defect itself** — one with a single obvious fix inside the
branch's scope — reruns the gates it touches, and commits the fix with the session's
reconciliation edits. It **flags** only what needs a judgement call: a design change, wider
scope, or more than one reasonable fix. The summary lists both.

## Rejected alternatives

- Flag only: the human pays a round trip for a fix with no decision in it.
- Fix everything found: a design or scope call is the human's, and a fresh session making it
  unasked would bypass the plan's approval.

## Consequences

- No checkpoint changes: the fix is local and unpushed (§2.11 rule 5), and the human still
  reviews the whole PR.
- The implementation session still never grades its own homework: the fix comes from the
  fresh pre-PR session.
