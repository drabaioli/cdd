# CDD Engineering Practices

The engineering floor this repo — the CDD meta-project — commits to. CDD distinguishes two kinds of practice:

- **Enforced** — a CDD gate guarantees it on every change. If an enforced practice is failing, `/cdd-pre-pr` or CI reports it and the change is not ready to merge.
- **Expected** — committed to but not yet mechanized here; tracked as a roadmap task until it becomes enforced.

This repo is documentation and shell scripts: there is no compiled build, so "build" and "tests" take the shape of shell-syntax checks, the bootstrap smoke, and the command-drift check rather than a compiler and a unit-test runner. Every gate below runs from one command, `./scripts/ci.sh` — see `CLAUDE.md` → "Build & test".

## Documentation — Enforced

The process doc, template, architecture/feature docs, and roadmap are reconciled against the diff by `/cdd-pre-pr` (documentation reconciliation), and the two-layer consistency rule — process-doc-first, then template — is part of every change. A change isn't done until the docs match it. Roadmap items additionally obey a hard length cap, enforced as a gate rather than reconciled by judgement (see below, and ADR 0005).

## Tested behaviour — Enforced

There is no unit-test suite; behaviour is exercised by integration-style smoke and consistency checks, all reachable from `./scripts/ci.sh` — the same command CI runs and `/cdd-pre-pr` invokes:

- `bash -n` over all shell scripts (syntax).
- `./scripts/command-drift-check.sh` — repo `.claude/commands/` vs the rendered template, plus the handoff-schema and worktree-helper assertions.
- `./scripts/prompt-seam-check.sh` — deterministic seam contracts between the repo's own prompts: `/cdd-*` references resolve to a command file, the `gh_issue_NN` branch token is produced and consumed in agreement, backticked file paths resolve, each command keeps its load-bearing headings, the gate count stated in prose matches `./scripts/ci.sh list`, and every open row of the template's engineering-practices contract is named in `/cdd-bootstrap`'s engineering-floor question.
- `./scripts/roadmap-length-check.sh` — every item in this repo's roadmap and in the one the template ships, pending and completed alike, fits in 200 characters. The roadmap is loaded by every session, so an over-long item is a cost paid forever; the cap had been convention-only and 46 of 94 items had drifted past it. `demo/seed/`'s roadmap is excluded (throwaway demo content, not maintained). Carries an inline self-check (three fixtures either side of the cap, one multibyte) so a matcher that stopped matching cannot report clean. See ADR 0005.
- `./scripts/install-smoke-assert.sh` — the worktree/state helpers' `install` contract against a throwaway HOME: the copied helper, the marker-guarded rc block and its self-repair, the PATH shims (including the loud refusal the cwd-changing ones must give), the legacy handoff migration, and three properties of `cdd-state seed` — the recorded session, the synced `refs/cdd/<branch>`, and `repo.json` naming the MAIN worktree. Offline: the ref push is redirected at a throwaway bare origin, so the gate has no network dependency and no side effects. Its shim probes run `bash --norc --noprofile </dev/null` and assert that a `cdd-*` name resolves to a file, since bash otherwise sources the fake HOME's rc whenever the caller's stdin is a socket — which had the probes testing shell functions instead of the shims.
- End-to-end bootstrap smoke: `tools/bootstrap-cdd-project.sh` into a tmpdir + `scripts/template-smoke-assert.sh` (clean, link-valid tree) — in four shapes: plain, CamelCase dir, `--stage` render-only, and `--template-dir` snapshot.
- Demo seed-overlay smoke: `demo/setup.sh … --local-only`.
- `./scripts/ci-runner-assert.sh` — the check runner's own contract: registry and gate functions agree, an unknown gate is rejected, a missing tool yields a non-fatal SKIP, and the workflow delegates instead of holding its own gate list.
- `./scripts/prompt-seam-assert.sh` — the seam checker's own contract, by mutation: each of its six checks is required to *fail* on a tree where that one seam is broken, in a throwaway copy. Two controls (an unmutated copy passes; a whitelisted dangling reference is silenced) keep the six honest. A guard that only ever passes is indistinguishable from one that stopped working.

New behaviour in a script or the bootstrap path ships with the relevant smoke or assertion extended to cover it.

## Continuous integration — Enforced

`.github/workflows/template-smoke.yml` runs on every PR and holds **no gate list of its own**: it checks out and calls `./scripts/ci.sh`, the single source of the gate sequence (process doc §2.14). The same command is what `/cdd-pre-pr` invokes locally, so the local verdict is CI's verdict and no gate is ever listed twice. Mechanics in `doc/architecture/overview.md`.

## Lint & format — Enforced (lint); Expected (format)

- Lint: `shellcheck` over all repo shell scripts, as the runner's `shellcheck` gate. On a host without `shellcheck` installed the gate reports SKIPPED — loudly and non-fatally, never silently passed — so a local run may be weaker than CI's; on CI, where `shellcheck` is preinstalled, it always runs. Same for `jq` and the three state-record gates.
- Format: no automated formatter for Markdown or shell is enforced yet. *Expected.*

## Dependency & toolchain hygiene — Expected

The toolchain is bash + `gh` + standard POSIX tools, assumed present rather than pinned. Documenting or pinning the required tool versions is *expected*.
