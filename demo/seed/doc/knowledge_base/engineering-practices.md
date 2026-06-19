# <PROJECT_NAME> Engineering Practices

The engineering floor Markdown Renderer commits to. CDD distinguishes two kinds of practice:

- **Enforced** — a CDD gate guarantees it on every change. If an enforced practice is failing, `/cdd-pre-pr` reports it and the change is not ready to merge.
- **Expected** — committed to but not yet mechanized here; tracked as a roadmap task until it becomes enforced. "Expected" is a promise with a due date, not an opt-out.

When an expected practice gains its mechanism, move it to **Enforced** in the same PR that lands the mechanism.

## Documentation — Enforced

Architecture, feature, and roadmap docs are reconciled against the diff by `/cdd-pre-pr` (documentation reconciliation). A change isn't done until the docs match it.

## Tested behaviour — Enforced

New behaviour ships with a test, or an explicit, recorded reason it does not. `/cdd-pre-pr` (test-coverage reconciliation) checks this on every change, and `/cdd-pre-pr` build & QA runs the suites.

- Test command: `pytest`
- Integration test command: `pytest tests/integration`

## Continuous integration — Expected

The checks below run locally through `/cdd-pre-pr`, but nothing runs them automatically on every PR yet. Adding a CI workflow (build + tests + lint on every PR) is tracked on the roadmap.

- CI entry point: *none yet — expected*

## Lint & format — Enforced

`/cdd-pre-pr` build & QA runs both:

- Lint command: `python -m pyflakes app`
- Format check command: `black --check app tests`

## Dependency & toolchain hygiene — Expected

`requirements.txt` lists dependencies; pinning them to exact versions and documenting the Python toolchain version is *expected*.

## How this list grows

New practices are added here as the project matures. `/cdd-pre-pr`'s CI-improvement check and the roadmap's infrastructure tasks feed it — closing the CI task above flips "Continuous integration" from **Expected** to **Enforced**.
