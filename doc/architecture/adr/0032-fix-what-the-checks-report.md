# 0032: Fix what the checks report

**Status:** Accepted

## Context

ADR 0030's Context records issue #153's finding that tool output fed back to the agent beats
written rules (Blyth et al.), and its Consequences leave the checks to the code-level phase:
static analysis fed back and a duplicate-block check. The contract had no row for either, and
`/cdd-implement` and `/cdd-small-change` only reported a failing gate.

- Self-repair "is bottlenecked by the model's ability to provide feedback on its own code", and
  "when the cost of carrying out repair is taken into account, performance gains are often
  modest" (Olausson et al., ICLR 2024, arXiv 2306.09896). A check's output is that feedback.
- In repair loops "the first three to four repair iterations account for most achievable gains,
  while later iterations contribute only marginal improvements"; fixed limits exist to prevent
  "infinite repair cycles or oscillating behaviors" (Kiecker et al., arXiv 2607.05197, preprint).
- Most clones are harmless; the risk is changing one copy and not the others (Kapser & Godfrey,
  Juergens, cited in #153). Clone detectors already check only new duplication: jscpd's
  `--changed` "reports the clones of the files `git status` lists, matched against the whole
  project", and `--baseline-from-ref` "marks the clones that are absent from it as new"; in a
  SonarQube pull-request analysis "only the quality gate conditions applying to new code are
  used".

## Decision

1. **Two generic contract rows**, static analysis & security scanning and a duplicate-block check,
   each with a provisional status marker. No tool is named: each project picks its own analyser,
   scanner and clone detector.
2. **The duplicate check is scoped to the diff**: it catches new duplication only, in whichever
   form the tool offers (changed files matched against the project, or the whole project failing
   only on new clones).
3. **The implementing session fixes what a failing gate reports** (`/cdd-implement`,
   `/cdd-small-change`), re-runs that gate, then the runner whole. It fixes a failure with one
   clear fix, and leaves and reports, with output, one that needs a judgement call: silencing
   the check (a suppression, a skipped or weakened test), departing from the plan or a
   requirement, or more than one reasonable fix. On the small-change lane a fix that would widen the approved change goes back
   to its approval. The split is ADR 0025's, applied to tool output.
4. **Three rounds per gate**, then report.

## Rejected alternatives

- A Claude Code `PostToolUse` hook as the loop: session-local, so Upheld at best (ADR 0028), and
  the check runner is already the one gate source the commands run.
- Report only: the human pays a round trip for a fix with no decision in it (ADR 0025).
- Fix everything: a judgement call is the human's, and an unsupervised session making it would
  bypass the plan's approval; rules over-apply (ADR 0030).
- An unbounded loop: it can oscillate, and gains flatten after three or four rounds.
- A whole-codebase duplication threshold: most clones are harmless, so it flags what nobody needs
  to change.

## Consequences

- No checkpoint changes. The session still never grades its own homework: the signal is a tool's
  output, not self-review.
- Downstream projects get the rows through `/cdd-retrofit`'s three-way merge of
  `engineering-practices.md`; a row left unresolved fails their `practices` gate until it is
  resolved or dropped with a reason.
- This repo maps static analysis to its `shellcheck` gate and drops the duplicate-block row: its
  deliberate copies (the template's mirrors, held identical by gates) would drown any real
  finding.
