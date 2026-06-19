# Investigation note: founding-objectives audit (2026-06)

An audit of whether CDD's workflow still *guards* its three founding objectives, with a gap inventory and a record of what was fixed versus deferred. This is a durable investigation note — it records the state at the time of the `principle_guardrails` work and the reasoning behind the Phase 11 roadmap items, not a living document.

## The three founding objectives (as stated by the project owner)

1. **Automate as much as possible, but keep human approval at the important gates.**
2. **Instil engineering best practices into any adopting project without invading how it works** — so that juniors and non-engineers inherit architecture excellence, structured documentation, thorough unit/integration tests, and strong CI.
3. **Self-improvement** — whenever CDD or a CDD project finds a workflow improvement (a better `CLAUDE.md`, a command/CI/test/doc improvement), it incorporates it.

## Findings

### Objective 1 — well guarded

- Named in §1 by two of the founding commitments ("the human is in the loop at every gate" and "automate everything except decisions").
- Six explicit checkpoints in §4; every one is load-bearing and none is silently skipped.
- Every relaxation of automation is documented and reasoned: local auto-commits (§2.11) are reversible and explicitly *not* a seventh checkpoint; the `/cdd-process-pr` up-front gate (§4.1) trades per-action confirmation for a single approved triage plan, with stated rationale; the PR-open step (§3.5) is human-gated.
- **No gate leaks found.** The remaining opportunity is on the *positive* side of the commitment — recurring manual steps not yet mechanized (when to trigger `/cdd-merge-main`; nothing mechanically checks that gates are honored). These are mechanization opportunities, not guard failures → Phase 11 (objective-1 mechanizations).

### Objective 2 — half guarded (the largest gap)

- **Documentation is enforced**: architecture/feature/ADR docs, the index-as-pointers rule, doc reconciliation as a `/cdd-pre-pr` gate, and code review.
- **Testing, CI, lint, and dependency hygiene were only *suggested***: the template shipped no CI workflow, no test scaffolding, and no lint config — only a "Suggested infrastructure tasks" bullet list in the template roadmap (designed to be "folded in and deleted") and `<build/test command>` placeholders in `/cdd-pre-pr` and `CLAUDE.md`. Nothing recurring confirmed a project ever grew tests or CI.
- **No canonical, enumerated best-practices artifact existed** in either layer.

### Objective 3 — weak in steady state

- Upstreaming existed only via `/cdd-retrofit` upgrade mode (an in-session report the human must act on manually; not persisted) and CDD-on-CDD dogfooding (§7.1).
- A project merely *running* CDD day to day had no standing channel to flag "this looks general — capture or upstream it."
- The friction log was deliberately retired (roadmap Phase 2) once friction was routed into the roadmap, with nothing replacing the steady-state capture path.

### Structural root cause

§1 named exactly four commitments. Objective 2's testing/CI half was unnamed (only its documentation half — "the project documents itself" — was elevated), and objective 3 was entirely unnamed. Guarding the two under-guarded objectives meant elevating them to named commitments, then giving each a concrete guardrail.

## What this session landed

- **§1 reframed, 4 → 5 commitments.** "Documents itself" broadened to "the project holds itself to engineering standards as it grows" (documentation as the leading enforced exemplar; tests/CI/lint instilled by *mechanism and floor, not prescription*); added "the workflow improves itself."
- **The engineering-practices contract** — a canonical, enforced-vs-expected artifact — added to the process doc (§2.12) and shipped in the template (`doc/knowledge_base/engineering-practices.md`), with filled-in instances in the CDD repo and the demo seed.
- **A test-coverage reconciliation step in `/cdd-pre-pr`** (both command copies) — the recurring objective-2 guardrail, parallel to doc reconciliation; surfaces and records, adds no new checkpoint.
- **Roadmap Phase 11** capturing the deferred items.

## Deferred (Phase 11)

- **Objective-3 standing channel** — a recurring mechanism that routes a discovered improvement into the roadmap/conventions (not a reintroduced standing log). Recorded as a §6 known gap. The commitment is named this session; the mechanism is its own design.
- **Objective-1 mechanizations** — codifying when `/cdd-merge-main` should be recommended or auto-triggered, and any mechanical gate-honored check.
- **Objective-2 reinforcement at bootstrap** — a required bootstrap-phase task and/or a bootstrap checklist, once the recurring `/cdd-pre-pr` mechanism is proven.
