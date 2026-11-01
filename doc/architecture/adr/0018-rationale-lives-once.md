# 0018: Rationale lives once, at its altitude

**Status:** Accepted

## Context

One argument was written out in five or six places (issue #102). The process doc's "Document
altitude" note said where a passage *belongs* — workflow level in the process doc, mechanics next
to the code — but not what every other location should carry instead. So each new location that
needed to mention a rule got the whole argument behind it, and the copies drifted apart.

The issue's worked example was the check runner's missing-tool rule: its reasoning sat in process
doc §2.14, `doc/architecture/overview.md`, ADR 0013, both engineering-practices files, `CLAUDE.md`
and several script headers. #123 changed the rule itself ("a missing tool is a failure, never a
skip"), and 45328e3 then had to trim the copies by hand; a sweep afterwards still found stale script
headers saying the opposite.

Two forces keep producing copies. Doc reconciliation (`/cdd-implement`, `/cdd-pre-pr`) propagates a
change by rewriting each mention at full length, so an argument grows a copy per site it touches.
And every doc is loaded by some session, so each copy is paid for in context on every read. ADR 0005
already showed that a convention nobody measures drifts back.

## Decision

1. **The rule.** The process doc is normative: for each artifact, contract or rule it states what
   it is, one sentence of why, and a pointer for the rest. The reasoning behind a decision lives in
   its ADR; mechanics, and the reasoning behind a mechanism no ADR records, live in code comments and
   `doc/architecture/`. Every other location carries the rule plus a pointer, never the argument
   again.

2. **The places allowed to hold rationale.**
   - An **ADR** — a decision's reasoning.
   - **`doc/architecture/`** — mechanics, and the reasoning of a mechanism no ADR records.
   - **Code comments** — that code's own mechanics, citing the ADR or architecture doc for the why.
   - **The process doc** — one sentence of why per contract.
   - **The template** — a restatement, only where a downstream project has no process doc to point
     at (the small-change heuristic, the roadmap cap conventions, "same list, same scripts").

   Everything else — `CLAUDE.md`, feature docs, the engineering-practices contract, the README,
   index files, other scripts' comments — carries the rule plus a pointer.

3. **No gate.** The issue's candidate — a phrase-list gate flagging a named concept that appears in
   more than N files with more than one sentence attached — was rejected:
   - A duplicated argument is paraphrased, not copied, so it is not grep-able the way an over-long
     roadmap line is.
   - A phrase list catches only the arguments already known — the ones this change fixed.
   - "More than one sentence attached" fires on legitimate rule-plus-pointer clauses.

   The fix is structural: fewer places are allowed to carry rationale.

4. **Applied in the same change** to every repeated argument a sweep found, and to stale pointers —
   text whose target no longer says what it claims.

5. **The slash commands are out of scope.** Teaching the doc-update steps of `/cdd-implement` and
   `/cdd-pre-pr` to shrink a non-home site to a pointer rather than restate it is issue #138's job.

## Consequences

- The process doc shrinks to normative prose wherever an ADR exists. Reasoning that lives only in
  the process doc today, with no ADR behind it, stays there; this decision does not require moving
  it.
- ADRs are append-only, so mechanics already inside old ADRs and their historical statements (e.g.
  ADR 0007's "§2.14's per-gate skip rule") stay as written; the live documents that cited them are
  corrected instead.
- Where no ADR carries a mechanism's reasoning, the mechanism's architecture doc becomes its home —
  the per-gate tool-detection argument moved from process doc §2.14 into `overview.md` this way.
- Drift is still possible. The mitigations are the short homes list, review, and #138.
- A template restatement is a deliberate second copy and must be updated with its home.
