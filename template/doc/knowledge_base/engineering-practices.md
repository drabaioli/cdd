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

## Static analysis & security scanning — <Enforced once the check runner registers a static-analysis or security-scan gate; Expected until then>

A static analyser, and a security scanner where the language has one, check every change; the implementing session fixes what they report and re-runs them. The tools are the project's choice; a linter that already does this analysis may back this row too, its gate named under both.

- Static analysis command: `<static analysis command>`
- Security scan command: `<security scan command>`
- Gates: <the runner gate(s) that run them>

## Duplicate-block check — <Enforced once the check runner registers a gate that checks the diff for duplicated blocks; Expected until then>

A change that adds a block duplicating code already in the project is caught on the diff, so it reuses the existing code or says why it copies. Scoped to new duplication, not the whole codebase: most existing duplicates are harmless; the risk is a new copy drifting from its original. The clone detector is the project's choice.

- Duplicate check command: `<duplicate check command>`
- Gates: <the runner gate that runs it>

## Test protection — <Upheld once test paths are declared below; Expected until then>

An edit to an existing test file asks the human first, unless the approved plan's `## File map` names it, so a test cannot be quietly rewritten to make the code pass; a new test file is not held. Upheld by the test-guard hook CDD ships (`.claude/hooks/cdd-test-guard.sh`, wired in `.claude/settings.json`), which reads the patterns below: shell patterns matched against the repo-relative path, `*` also matching `/` (`tests/*`, `*_test.go`). With none declared the hook holds nothing. Edits made through the shell are not held; `/cdd-pre-pr`'s code review of the diff is the backstop.

- Test paths: `<test path pattern>`

## Dependency & toolchain hygiene — Expected

Dependencies are pinned or locked; toolchain versions are documented, including the host tools the check runner's scripts assume and any of their behaviours that differ between machines and so are off-limits.

- Install-dependencies script: `scripts/install-deps.sh` — installs CDD's required tools, the bound adapters' tools and this project's toolchain; it checks first and installs only what is missing.

## How this list grows

New practices are added here as the project matures. Three things feed it: `/cdd-pre-pr`'s CI-improvement check, its workflow-improvement check (a rule the code review applied from inference rather than from a written standard belongs here), and the roadmap's "Suggested infrastructure tasks". When one of those surfaces a gap and the project closes it, add the corresponding row here or flip it from **Expected** to **Enforced** or **Upheld**.
