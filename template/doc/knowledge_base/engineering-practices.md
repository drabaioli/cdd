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

Build and checks run on every PR, and every gate below is reachable from **one check runner** that is the single source of the gate sequence: CI delegates to it and `/cdd-pre-pr` invokes it, so no gate list is written twice. The guarantee is **same list, same scripts**: a green local run means CI runs the same gates through the same scripts, not that its verdict is identical — the scripts call host tools whose implementations differ between machines — so keep scripts to behaviour every assumed tool shares, and name those tools under dependency hygiene below. A missing tool is a failure, never a skip, locally and in CI: a gate whose tool is not installed fails without running and names the tool. Detection is per gate and the run is not fail-fast, so one run lists every tool to install and still reports every other gate.

- CI entry point: `<ci workflow / command>`
- Check runner: `<check runner command>`
- Slow gates: CI may fan out instead of calling the runner whole — one job lists the gates with `<check runner command> list`, and one job per gate runs `<check runner command> <gate>` — so the list still exists only once, in the runner.

## Lint & format — <Expected until a lint/format command exists>

- Lint command: `<lint command>`
- Format check command: `<format check command>`

## Dependency & toolchain hygiene — Expected

Dependencies are pinned or locked; toolchain versions are documented, including the host tools the check runner's scripts assume and any of their behaviours that differ between machines and so are off-limits.

## How this list grows

New practices are added here as the project matures. Three things feed it: `/cdd-pre-pr`'s CI-improvement check, its workflow-improvement check (a rule the code review applied from inference rather than from a written standard belongs here), and the roadmap's "Suggested infrastructure tasks". When one of those surfaces a gap and the project closes it, add the corresponding row here or flip it from **Expected** to **Enforced**.
