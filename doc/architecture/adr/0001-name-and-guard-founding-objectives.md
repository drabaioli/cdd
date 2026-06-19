# 0001: Name and guard CDD's under-guarded founding objectives

**Status:** Accepted

## Context

CDD has three founding objectives as stated by the project owner:

1. **Automate as much as possible, but keep human approval at the important gates.**
2. **Instil engineering best practices into any adopting project without invading how it works** — so juniors and non-engineers inherit architecture excellence, structured documentation, thorough unit/integration tests, and strong CI.
3. **Self-improvement** — whenever CDD or a CDD project finds a workflow improvement (a better `CLAUDE.md`, a command/CI/test/doc improvement), it incorporates it.

Two of these were under-guarded. Objective 2's testing/CI/lint half was only *suggested* — no shipped CI workflow, no test scaffolding, no lint config, and no canonical best-practices artifact in either layer — while its documentation half was already enforced. Objective 3 had no standing channel in steady state: upstreaming existed only via `/cdd-retrofit` upgrade mode and CDD-on-CDD dogfooding, with the friction log deliberately retired.

**Structural root cause:** §1 named exactly four commitments. Objective 2's testing/CI half was unnamed (only its documentation half was elevated), and objective 3 was entirely unnamed. The philosophy can only guard what it names.

## Decision

Elevate the two under-guarded objectives to named commitments, and give each a concrete guardrail:

- **§1 reframed, 4 → 5 commitments.** "The project documents itself" broadened to "the project holds itself to engineering standards as it grows" — documentation as the leading *enforced* exemplar; tests/CI/lint instilled by **mechanism and floor, not prescription**. Added a fifth commitment: "the workflow improves itself."
- **An engineering-practices contract (§2.12)** — a canonical, enforced-vs-expected artifact, shipped in the template as `doc/knowledge_base/engineering-practices.md` and instantiated in both the CDD repo and the demo seed.
- **A test-coverage reconciliation step in `/cdd-pre-pr`** (both command copies) — the recurring objective-2 guardrail, parallel to doc reconciliation: it surfaces and records coverage drift but adds no new checkpoint.

Objective 3 is named this session but its mechanism is deferred (see below); the decision is to name the commitment now and design the channel separately rather than reintroduce a standing friction log.

## Consequences

- Objective 2 now has a named commitment, a canonical enumerated artifact, and a recurring guardrail — closing the largest gap. Tests/CI/lint are held to a floor by mechanism rather than prescribed per project type, preserving the "without invading how it works" constraint.
- The engineering-practices contract is a third thing to keep consistent across the two layers (process doc + template) and the demo seed; drift there is now a defect like any other cross-layer drift.
- The `/cdd-pre-pr` reconciliation step adds work to every pre-PR run, but deliberately *records* rather than *blocks* — it does not become a seventh checkpoint.
- **Deferred (roadmap Phase 11):**
  - *Objective-3 standing channel* — a recurring mechanism routing a discovered improvement into the roadmap/conventions (not a reintroduced log). Recorded as a §6 known gap.
  - *Objective-1 mechanizations* — codifying when `/cdd-merge-main` should be recommended or auto-triggered, and any mechanical gate-honored check.
  - *Objective-2 reinforcement at bootstrap* — a required bootstrap-phase task and/or checklist, once the recurring `/cdd-pre-pr` mechanism is proven.
