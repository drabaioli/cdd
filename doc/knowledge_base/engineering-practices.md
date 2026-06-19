# CDD Engineering Practices

The engineering floor this repo — the CDD meta-project — commits to. CDD distinguishes two kinds of practice:

- **Enforced** — a CDD gate guarantees it on every change. If an enforced practice is failing, `/cdd-pre-pr` or CI reports it and the change is not ready to merge.
- **Expected** — committed to but not yet mechanized here; tracked as a roadmap task until it becomes enforced.

This repo is documentation and shell scripts: there is no compiled build, so "build" and "tests" take the shape of shell-syntax checks, the bootstrap smoke, and the command-drift check rather than a compiler and a unit-test runner. See `CLAUDE.md` → "Build & test" for the exact commands.

## Documentation — Enforced

The process doc, template, architecture/feature docs, and roadmap are reconciled against the diff by `/cdd-pre-pr` (documentation reconciliation), and the two-layer consistency rule — process-doc-first, then template — is part of every change. A change isn't done until the docs match it.

## Tested behaviour — Enforced

There is no unit-test suite; behaviour is exercised by integration-style smoke and consistency checks, run in CI by `.github/workflows/template-smoke.yml` and by hand per `CLAUDE.md`:

- `bash -n` over all shell scripts (syntax).
- `./scripts/command-drift-check.sh` — repo `.claude/commands/` vs the rendered template, plus the handoff-schema and worktree-helper assertions.
- End-to-end bootstrap smoke: `tools/bootstrap-cdd-project.sh` into a tmpdir + `scripts/template-smoke-assert.sh` (clean, link-valid tree).
- Demo seed-overlay smoke: `demo/setup.sh … --local-only`.

New behaviour in a script or the bootstrap path ships with the relevant smoke or assertion extended to cover it.

## Continuous integration — Enforced

`.github/workflows/template-smoke.yml` runs shellcheck, the command-drift check, the end-to-end bootstrap smoke, and the demo seed-overlay step on every PR.

## Lint & format — Enforced (lint); Expected (format)

- Lint: `shellcheck` over all repo shell scripts, in CI.
- Format: no automated formatter for Markdown or shell is enforced yet. *Expected.*

## Dependency & toolchain hygiene — Expected

The toolchain is bash + `gh` + standard POSIX tools, assumed present rather than pinned. Documenting or pinning the required tool versions is *expected*.
