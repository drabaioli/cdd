# 0002: Scope prompt "CI" to deterministic seam checks; reject LLM-as-judge evals

**Status:** Accepted

## Context

Issue #23 asked how to "CI/test" CDD's prompts: on a normal codebase, code is unit-tested, linted, and formatted to keep it reliable; a prompt can't be unit-tested, so what guards against a prompt edit silently breaking the rest of the workflow? (The motivating example: editing `cdd-next-step.md` could change the handoff file's shape and strand the downstream `cdd-worktree` step or the implementation session.)

Investigation split the worry into two failure classes that need different treatment:

1. **Seam / contract drift — *deterministic.*** The workflow's steps hand artifacts to each other (a producer step and a consumer step must agree on the artifact's shape). This is testable with grep/diff — no LLM required. The repo had already discovered the pattern without naming it: `command-drift-check.sh` and `template-smoke-assert.sh` already pin contracts at some seams.
2. **Behavioral correctness — *non-deterministic.*** "Does the prompt actually make Claude do the right thing?" This is eval / LLM-as-judge territory (promptfoo et al.).

The investigation proposed three tiers (full reasoning in the issue #23 comment):

- **Tier 1** — extend the deterministic seam-pinning to the seams not yet covered (cheap, high value, no API keys, no flakiness).
- **Tier 2** — generalize Tier 1 into a standalone "prompt lint" framework (a packaging decision).
- **Tier 3** — behavioral LLM-as-judge evals (expensive, partly inapplicable).

Tier 1 shipped as `scripts/prompt-seam-check.sh` (PR #37). This ADR records the decision on Tiers 2 and 3, which were initially carried on the roadmap as deferred items and are now removed from it — a roadmap is a list of work intended to happen, and neither tier is.

## Decision

**Scope CDD's prompt "CI" to deterministic seam-contract checks (Tier 1). Do not pursue Tier 2 or Tier 3 as planned work; remove both from the roadmap.**

- **Tier 2 (generalize into a "prompt lint" framework) — not planned.** It is low-difficulty (the checks are grep-based; generalizing means lifting the hard-coded seams into a config/manifest-driven form), but premature: there is exactly one consumer today (this repo). Abstracting for a single consumer guesses at the wrong shape. If a second consumer appears, or if maintaining Tier 1 reveals real friction, revisit it then — but it is not roadmap work now.
- **Tier 3 (behavioral LLM-as-judge evals) — rejected on principle, not merely deferred for difficulty.** Running a CDD command faithfully means an agent loop against a live repo *with six human-in-the-loop checkpoints*. A headless eval can only run by removing those checkpoints — so it would test a degraded, checkpoint-stripped workflow that is not CDD. It also needs API budget in CI and tolerates flakiness, both of which the deterministic checks deliberately avoid. The honest behavioral safety net already exists: the `demo/` subsystem. The realistic behavioral practice is keeping `demo/` as a periodic **human-driven** dogfood run — a *process* practice, not a CI job.

## Consequences

- The reliability story for the workflow's own prompts is, and stays, deterministic: `command-drift-check.sh` + `prompt-seam-check.sh` + the smoke asserts, all grep/diff, no API keys, no flakiness. That is the whole intended surface — there is no pending "behavioral eval" work implied by its absence.
- The roadmap no longer carries Tier 2 / Tier 3 as open items, so it doesn't misrepresent a rejected approach (Tier 3) or a premature one (Tier 2) as pending work. The rationale for the absence lives here instead.
- Behavioral confidence is owned by the `demo/` dogfood as a human-driven practice, not by CI. If that practice needs to become a tracked cadence, it belongs with the demo/dogfooding subsystem, not with prompt-CI tooling.
- Tier 2 remains available as an unplanned future option gated on a concrete trigger (a second consumer or Tier 1 maintenance friction); this ADR would be revisited rather than silently reversed.
