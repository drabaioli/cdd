# 0002: Scope prompt "CI" to deterministic seam checks; defer LLM-as-judge evals

**Status:** Accepted

## Context

Issue #23 asked how to "CI/test" CDD's prompts: on a normal codebase, code is unit-tested, linted, and formatted to keep it reliable; a prompt can't be unit-tested, so what guards against a prompt edit silently breaking the rest of the workflow? (The motivating example: editing `cdd-next-step.md` could change the handoff file's shape and strand the downstream `cdd-worktree` step or the implementation session.)

Investigation split the worry into two failure classes that need different treatment:

1. **Seam / contract drift — *deterministic.*** The workflow's steps hand artifacts to each other (a producer step and a consumer step must agree on the artifact's shape). This is testable with grep/diff — no LLM required. The repo had already discovered the pattern without naming it: `command-drift-check.sh` and `template-smoke-assert.sh` already pin contracts at some seams.
2. **Behavioral correctness — *non-deterministic.*** "Does the prompt actually make Claude do the right thing?" This is eval / LLM-as-judge territory (promptfoo et al.).

The investigation proposed three tiers (full reasoning in the issue #23 comment):

- **Tier 1** — extend the deterministic seam-pinning to the seams not yet covered (cheap, high value, no API keys, no flakiness).
- **Tier 2** — generalize Tier 1 into a standalone "prompt lint" framework (a packaging decision).
- **Tier 3** — behavioral LLM-as-judge evals (expensive; deferred).

Tier 1 shipped as `scripts/prompt-seam-check.sh` (PR #37). This ADR records the decision on Tiers 2 and 3, which were initially carried on the roadmap as deferred items and are now removed from it — a roadmap lists work intended to happen next, and neither tier is that: Tier 2 is premature, and Tier 3 is deferred on cost and ROI.

## Decision

**Scope CDD's prompt "CI" to deterministic seam-contract checks (Tier 1). Do not pursue Tier 2 or Tier 3 as planned work; remove both from the roadmap.**

- **Tier 2 (generalize into a "prompt lint" framework) — not planned.** It is low-difficulty (the checks are grep-based; generalizing means lifting the hard-coded seams into a config/manifest-driven form), but premature: there is exactly one consumer today (this repo). Abstracting for a single consumer guesses at the wrong shape. If a second consumer appears, or if maintaining Tier 1 reveals real friction, revisit it then — but it is not roadmap work now.
- **Tier 3 (behavioral LLM-as-judge evals) — deferred on cost, effort, and ROI; *not* rejected on principle.** The realistic form is per-prompt / per-seam behavioral checks (e.g. promptfoo): feed a prompt a fixture, stub the human approval, and have an LLM judge whether the produced artifact — a handoff, a triage, a plan — is correct. Substituting a canned approval for the human is exactly what an eval *does* and is legitimate; it does not make the eval test "a different workflow," because the unit under test is the prompt's behavior between checkpoints, not the checkpoint itself. (An earlier draft of this ADR argued Tier 3 was inapplicable because a headless eval "strips the human checkpoints that define CDD." That objection only holds for a naive *full end-to-end* autonomous run, where the human is part of what makes the final output correct — but no one would build that, so it is not the case against Tier 3. The argument was overstated and is corrected here.) The real reasons to defer are practical:
  - **Cost** — manageable, not prohibitive: a `paths:`-filtered CI job can run the evals only when the command/doc files actually change, so unchanged prompts cost nothing.
  - **Effort** — the non-trivial work isn't wiring the tool, it's writing fixtures and *calibrating the judge* so its verdicts agree with human judgment.
  - **Flakiness** — LLM outputs and judges are non-deterministic, so the signal is noisy and needs threshold-tuning, unlike the crisp pass/fail of the grep checks.
  - **Maintenance + ROI** — every prompt change must keep the fixtures in sync, and for a single-maintainer repo the deterministic seam checks plus the human `demo/` dogfood already cover the high-frequency failure mode (seam drift). The marginal behavioral bug an eval would catch is rarer, so the ROI isn't there yet.

  The behavioral safety net meanwhile stays the `demo/` subsystem run as a periodic **human-driven** dogfood — a *process* practice, not a CI job. Revisit Tier 3 if behavioral regressions start slipping through that the deterministic checks and the dogfood miss.

## Consequences

- The reliability story for the workflow's own prompts is, and stays, deterministic: `command-drift-check.sh` + `prompt-seam-check.sh` + the smoke asserts, all grep/diff, no API keys, no flakiness. That is the whole intended surface — there is no pending "behavioral eval" work implied by its absence.
- The roadmap no longer carries Tier 2 / Tier 3 as open items, so it doesn't present a premature approach (Tier 2) or a cost-deferred one (Tier 3) as pending work. The rationale for the absence lives here instead.
- Behavioral confidence is owned by the `demo/` dogfood as a human-driven practice, not by CI. If that practice needs to become a tracked cadence, it belongs with the demo/dogfooding subsystem, not with prompt-CI tooling.
- Both deferred tiers remain available as future options gated on concrete triggers — Tier 2 on a second consumer or Tier 1 maintenance friction, Tier 3 on behavioral regressions slipping past the deterministic checks and the dogfood. This ADR would be revisited rather than silently reversed.
