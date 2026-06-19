# <PROJECT_NAME> Engineering Practices

The engineering floor this project commits to. CDD distinguishes two kinds of practice:

- **Enforced** — a CDD gate guarantees it on every change. If an enforced practice is failing, `/cdd-pre-pr` reports it and the change is not ready to merge.
- **Expected** — the project is committed to growing this practice, but it is not yet mechanized here. Each expected practice is tracked as a roadmap task until it becomes enforced. "Expected" is a promise with a due date, not an opt-out.

When an expected practice gains its mechanism (a test command, a CI job, a linter), move it to **Enforced** in the same PR that lands the mechanism. Drop a row that genuinely does not apply to this project (e.g. integration tests in a pure library), but record *why* in a clause rather than deleting it silently.

## Documentation — Enforced

Architecture, feature, and roadmap docs are reconciled against the diff by `/cdd-pre-pr` (documentation reconciliation). A change isn't done until the docs match it.

## Tested behaviour — <Enforced once a test command exists; Expected until then>

New behaviour ships with a test, or an explicit, recorded reason it does not. `/cdd-pre-pr` (test-coverage reconciliation) checks this on every change.

- Test command: `<test command>`
- Integration test command: `<integration test command>`

## Continuous integration — <Enforced once CI runs on every change; Expected until then>

Build and checks run on every PR.

- CI entry point: `<ci workflow / command>`

## Lint & format — <Expected until a lint/format command exists>

- Lint command: `<lint command>`
- Format check command: `<format check command>`

## Dependency & toolchain hygiene — Expected

Dependencies are pinned or locked; toolchain versions are documented.

## How this list grows

New practices are added here as the project matures. `/cdd-pre-pr`'s CI-improvement check and the roadmap's "Suggested infrastructure tasks" feed it: when one of those surfaces a gap and the project closes it, add the corresponding row here or flip it from **Expected** to **Enforced**.
