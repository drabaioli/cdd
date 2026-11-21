# <PROJECT_NAME> Engineering Practices

The engineering floor Markdown Renderer commits to. CDD distinguishes three kinds of practice:

- **Enforced** — gate(s) of the project's check runner hold it on every change. If an enforced practice is failing, `/cdd-pre-pr` reports it and the change is not ready to merge. A practice no runner gate holds is not Enforced.
- **Upheld** — held on every change by a named mechanism other than a runner gate: a CDD command's step (`/cdd-pre-pr`'s reconciliation or build & QA), a Claude Code hook or deny rule, the code host's branch protection. Weaker than Enforced: CI does not run it, and a change made outside a session is not held.
- **Expected** — committed to but not yet mechanized here; tracked as a roadmap task until it becomes enforced. "Expected" is a promise with a due date, not an opt-out.

An Enforced section carries a ``- Gates: `<gate>`, …`` line naming its runner gates; only an Enforced section carries one. Markdown Renderer has no check runner yet, so nothing here is Enforced. When an expected practice gains its mechanism, move it to **Enforced**, naming its gate, or to **Upheld**, naming its mechanism, in the same PR that lands the mechanism.

## Documentation — Upheld

Architecture, feature, and roadmap docs are reconciled against the diff by `/cdd-pre-pr` (documentation reconciliation). A change isn't done until the docs match it.

## Tested behaviour — Upheld

New behaviour ships with a test, or an explicit, recorded reason it does not. `/cdd-pre-pr` (test-coverage reconciliation) checks this on every change, and `/cdd-pre-pr` build & QA runs the suites; no check runner runs them yet.

- Test command: `pytest`
- Integration test command: `pytest tests/integration`

## Continuous integration — Expected

The checks below run locally through `/cdd-pre-pr`, but nothing runs them automatically on every PR yet. Adding a CI workflow (build + tests + lint on every PR) is tracked on the roadmap.

- CI entry point: *none yet — expected*

## Lint & format — Upheld

`/cdd-pre-pr` build & QA runs both; no check runner runs them yet:

- Lint command: `python -m pyflakes app`
- Format check command: `black --check app tests`

## Static analysis & security scanning — Upheld (static analysis); Expected (security scan)

`pyflakes`, the lint command above, is the static analyser, run by `/cdd-pre-pr` build & QA. A security scanner for the Python code (`bandit`, say) is *expected*.

- Static analysis command: `python -m pyflakes app`
- Security scan command: *none yet — expected*

## Duplicate-block check — Expected

A clone detector that checks each change for new duplicated blocks is *expected*.

- Duplicate check command: *none yet — expected*

## Test protection — Upheld

An edit to an existing test file asks the human first, unless the approved plan's `## File map` names it, so a test cannot be quietly rewritten to make the code pass; a new test file is not held. Upheld by the test-guard hook CDD ships (`.claude/hooks/cdd-test-guard.sh`, wired in `.claude/settings.json`), which reads the patterns below. Edits made through the shell are not held; `/cdd-pre-pr`'s code review of the diff is the backstop.

- Test paths: `tests/*`

## Dependency & toolchain hygiene — Expected

`requirements.txt` lists dependencies; pinning them to exact versions and documenting the Python toolchain version is *expected*.

## How this list grows

New practices are added here as the project matures. `/cdd-pre-pr`'s CI-improvement check and the roadmap's infrastructure tasks feed it — closing the CI task above flips "Continuous integration" from **Expected** to **Upheld** (CI is held by the code host, not a runner gate).
