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
- `./scripts/prompt-seam-check.sh` — deterministic seam contracts between the repo's own prompts: `/cdd-*` references resolve to a command file, the `gh_issue_NN` branch token is produced and consumed in agreement, backticked file paths resolve, each command keeps its load-bearing headings (matched by title, so renumbering a step is a no-op), the gate count stated in prose matches `./scripts/ci.sh list`, every open row of the template's engineering-practices contract is named in `/cdd-bootstrap`'s engineering-floor question, every plan-file section `/cdd-plan` writes is still named by `/cdd-implement`, the small-change lane's routing marker is still written and still read on both routing paths, the lane's eligibility heuristic is stated verbatim everywhere it is applied, and the seam-check count restated in prose in four files matches `./scripts/prompt-seam-check.sh list`.
- `./scripts/roadmap-length-check.sh` — every item in all three roadmaps the repo ships (its own, the template's, the demo seed's), pending and completed alike, fits in 200 characters. The roadmap is loaded by every session, so an over-long item is a cost paid forever; the cap had been convention-only and 46 of 94 items had drifted past it. Carries an inline self-check (three fixtures either side of the cap, one multibyte) so a matcher that stopped matching cannot report clean. See ADR 0005.
- `./scripts/install-smoke-assert.sh` — the worktree/state helpers' `install` contract against a throwaway HOME: the copied helper, the marker-guarded rc block and its self-repair, the PATH shims (including the loud refusal the cwd-changing ones must give), the legacy handoff migration, the option-shaped-branch rejection in all three commands that take a branch positionally, and three properties of `cdd-state seed` — the recorded session, the synced `refs/cdd/<branch>`, and `repo.json` naming the MAIN worktree. Offline: the ref push is redirected at a throwaway bare origin, so the gate has no network dependency and no side effects. Its shim probes run `bash --norc --noprofile </dev/null` and assert that a `cdd-*` name resolves to a file, since bash otherwise sources the fake HOME's rc whenever the caller's stdin is a socket — which had the probes testing shell functions instead of the shims.
- `./scripts/adapter-conformance-check.sh` — the shipped tracker adapter against the contract in `doc/architecture/capability-adapters.md`: `describe` is hermetic and contract-shaped, every verb it declares dispatches to a real implementation, an undeclared verb exits 3, a usage error exits 2, a missing backend exits 4 with an actionable line, and nothing secret-shaped is committed alongside it. Offline by construction — it runs the adapter under a scratch `PATH` holding a stub `gh`, so no probe-mode flag has to exist in the contract for the gate's benefit. Its verb probe proves dispatch *reaches* an implementation, not that the implementation is correct; that limit is stated in the contract doc rather than left for a reader to discover.
- `./scripts/adapter-conformance-assert.sh` — the conformance checker's own contract, by mutation: ten broken adapters, one defect each, every one of which the checker must *fail* on and name. Two controls (an unmutated copy passes; an adapter omitting the optional `create_target` passes) pin the other direction, and every mutation is verified to have actually changed the file, so an anchor that rotted away cannot masquerade as a detection. The argument is sharper here than for the two checkers above: the only adapter in this tree is a conformant one, so the gate passes on every run whether or not it still works.
- End-to-end bootstrap smoke: `tools/bootstrap-cdd-project.sh` into a tmpdir + `scripts/template-smoke-assert.sh` (clean, link-valid tree) — in four shapes: plain, CamelCase dir, `--stage` render-only, and `--template-dir` snapshot.
- Demo seed-overlay smoke: `demo/setup.sh … --local-only`.
- `./scripts/ci-runner-assert.sh` — the check runner's own contract: registry and gate functions agree, an unknown gate is rejected, a missing tool yields a non-fatal SKIP, the workflow delegates instead of holding its own gate list, and gates are isolated — a gate cannot leak a shell variable or a cd into a later one.
- `./scripts/prompt-seam-assert.sh` — the seam checker's own contract, by mutation: each of its 10 checks is required to *fail* on a tree where that one seam is broken, in a throwaway copy. Three controls (an unmutated copy passes; a whitelisted dangling reference is silenced; a renumbered heading still passes) keep the 10 checks honest, and a structural assertion pairs the registry with the check functions both ways. A guard that only ever passes is indistinguishable from one that stopped working.

New behaviour in a script or the bootstrap path ships with the relevant smoke or assertion extended to cover it.

## Continuous integration — Enforced

`.github/workflows/template-smoke.yml` runs on every PR and holds **no gate list of its own**: it checks out and calls `./scripts/ci.sh`, the single source of the gate sequence (process doc §2.14). The same command is what `/cdd-pre-pr` invokes locally, so the local verdict is CI's verdict and no gate is ever listed twice. Mechanics in `doc/architecture/overview.md`.

## Lint & format — Enforced (lint); Expected (format)

- Lint: `shellcheck` over all repo shell scripts, as the runner's `shellcheck` gate. On a host without `shellcheck` installed the gate reports SKIPPED — loudly and non-fatally, never silently passed — so a local run may be weaker than CI's; on CI, where `shellcheck` is preinstalled, it always runs. Same for `jq` and the three state-record gates.
- Format: no automated formatter for Markdown or shell is enforced yet. *Expected.*

## Dependency & toolchain hygiene — Expected

The toolchain is bash + `gh` + standard POSIX tools, assumed present rather than pinned. Documenting or pinning the required tool versions is *expected*.
