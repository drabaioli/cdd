# 0018: Rationale lives once, at its altitude

**Status:** Accepted

## Context

One argument was written out in five or six places (issue #102): the "Document altitude" note said
where a passage *belongs*, not what other locations should carry instead. The check runner's
missing-tool rule was argued in process doc §2.14, `doc/architecture/overview.md`, ADR 0013, both
engineering-practices files, `CLAUDE.md` and several script headers; when #123 changed it, the
copies were trimmed by hand and stale headers survived. Doc reconciliation rewrites each mention at
full length, and every copy costs context on every read.

## Decision

1. **The rule.** The process doc states, for each artifact, contract or rule, what it is, one
   sentence of why, and a pointer. Every other location carries the rule plus a pointer, never the
   argument again.

2. **The places allowed to hold rationale.**
   - An **ADR** — a decision's reasoning.
   - **`doc/architecture/`** — mechanics, and the reasoning of a mechanism no ADR records.
   - **Code comments** — that code's own mechanics, citing the ADR or architecture doc for the why.
   - **The process doc** — one sentence of why per contract.
   - **The template** — a restatement, only where a downstream project has no process doc to point
     at (the small-change heuristic, the roadmap cap conventions, "same list, same scripts").

3. **No gate.** A phrase-list gate (a concept in more than N files with more than one sentence
   attached) was rejected: duplicated arguments are paraphrased, not copied, so they are not
   grep-able; a phrase list catches only the arguments already known; and "more than one sentence"
   fires on legitimate rule-plus-pointer clauses. The fix is structural: few places may carry
   rationale.

4. **Out of scope: the slash commands.** Teaching the doc-update steps of `/cdd-implement` and
   `/cdd-pre-pr` to shrink a non-home site to a pointer is issue #138.

## Consequences

- The same change cuts every repeated argument and stale pointer a sweep found.
- ADRs are append-only: mechanics inside old ADRs stay as written; the live documents citing them
  are corrected instead.
- A template restatement is a deliberate second copy, updated with its home.
- Drift is still possible; the mitigations are the short homes list, review, and #138.
