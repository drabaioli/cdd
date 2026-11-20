# <PROJECT_NAME> Engineering Practices

The engineering floor this project commits to. CDD distinguishes three kinds of practice:

- **Enforced** — gate(s) of the project's check runner hold it on every change. If an enforced practice is failing, `/cdd-pre-pr` reports it and the change is not ready to merge. A practice no runner gate holds is not Enforced.
- **Upheld** — held on every change by a named mechanism other than a runner gate: a CDD command's step (`/cdd-pre-pr`'s reconciliation), a Claude Code hook or deny rule, the code host's branch protection. Weaker than Enforced: CI does not run it, and a change made outside a session, or on a machine without the hook, is not held. It names what holds it; it is not a parking place.
- **Expected** — the project is committed to growing this practice, but it is not yet mechanized here. Each expected practice is tracked as a roadmap task until it becomes enforced. "Expected" is a promise with a due date, not an opt-out.

An Enforced section carries a line ``- Gates: `<gate>`[, `<gate>`]`` naming its gates by the name the check runner registers them under; only an Enforced section carries one. An Upheld section names its mechanism in its text. A section whose practices differ splits its marker into parts, e.g. `## Lint & format — Enforced (lint); Expected (format)`, its `Gates:` line backing the Enforced part(s); there is no "partially enforced" marker. The check runner's `practices` gate (`scripts/practices-check.sh`) checks this file: every name on a `Gates:` line is one the runner's `list` mode prints, an Enforced section has one, and no status marker stays a `<…>` placeholder.

When an expected practice gains its mechanism (a test command, a CI job, a linter), move it to **Enforced**, naming its gate, or to **Upheld**, naming its mechanism, in the same PR that lands the mechanism. Drop a row that genuinely does not apply to this project (e.g. integration tests in a pure library), but record *why* in a clause rather than deleting it silently.

## Documentation — Upheld

Architecture, feature, and roadmap docs are reconciled against the diff by `/cdd-pre-pr` (documentation reconciliation). A change isn't done until the docs match it.

## Tested behaviour — <Enforced once the check runner registers a test gate; Expected until then>

New behaviour ships with a test, or an explicit, recorded reason it does not — upheld by `/cdd-pre-pr` (test-coverage reconciliation) on every change.

- Test command: `<test command>`
- Integration test command: `<integration test command>`
- Gates: <the runner gate(s) that run the tests>

## Continuous integration — <Upheld once CI runs the check runner on every change; Expected until then>

Build and checks run on every PR, and every gate below is reachable from **one check runner** that is the single source of the gate sequence: CI delegates to it and `/cdd-pre-pr` invokes it, so no gate list is written twice. Host tools differ between machines, so a green local run can still fail CI: keep scripts to behaviour every tool named under dependency hygiene below shares. A missing tool fails its gate, never skips it, locally and in CI. CI is held by the code host, not by a runner gate; a project may make it Enforced with a gate that checks the CI config.

- CI entry point: `<ci workflow / command>`
- Check runner: the one `CLAUDE.md` declares under Build & test — its only declaration.
- Slow gates: CI may fan out instead of calling the runner whole — one job lists the gates with the runner's `list` mode, and one job per gate runs the runner with that gate's name — so the list still exists only once, in the runner.

## Lint & format — <Enforced once the check runner registers a lint/format gate; Expected until then>

- Lint command: `<lint command>`
- Format check command: `<format check command>`
- Gates: <the runner gate(s) that run lint and the format check>

## Dependency & toolchain hygiene — Expected

Dependencies are pinned or locked; toolchain versions are documented, including the host tools the check runner's scripts assume and any of their behaviours that differ between machines and so are off-limits.

- Install-dependencies script: `scripts/install-deps.sh` — installs CDD's required tools, the bound adapters' tools and this project's toolchain; it checks first and installs only what is missing.

## How this list grows

New practices are added here as the project matures. Three things feed it: `/cdd-pre-pr`'s CI-improvement check, its workflow-improvement check (a rule the code review applied from inference rather than from a written standard belongs here), and the roadmap's "Suggested infrastructure tasks". When one of those surfaces a gap and the project closes it, add the corresponding row here or flip it from **Expected** to **Enforced** or **Upheld**.
