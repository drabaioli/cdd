# 0029: Ship the practices checker

**Status:** Accepted

## Context

ADR 0028 made Enforced mean "a named check-runner gate holds it" and checked only this repo's
contract: a downstream checker needs to learn the runner's gate names, and only two of eight
downstream runners had a `list` mode, which was required only when CI fans out (issue #164).

## Decision

1. **`list` is mandatory.** Every check runner prints its gate names one per line, the name as
   the line's first field, and runs one gate by name (process doc §2.14).
2. **The checker ships in the template** as `scripts/practices-check.sh`, CDD-managed: a project
   does not edit it, and `/cdd-retrofit` carries CDD's changes into it. This repo runs its own
   `scripts/practices-check.sh`, and the `practices-contract` gate fails unless the two copies are
   identical — the `install-deps.sh` precedent.
3. **The runner is the argument.** `scripts/practices-check.sh <runner command>…` runs
   `<runner command> list` from the repo root. No argument is a usage error (exit 2); a `list` that
   fails or prints nothing fails, naming the command; a missing contract fails. A missing input
   fails, never skips (ADR 0013).
4. **A runner gate**, registered by the project's runner, so CI runs it too.
5. **An unfilled status marker fails.** A heading status still a `<…>` placeholder is one finding
   ("status marker not resolved"); its section is otherwise not checked, so a raw skeleton reads as
   unfilled rather than as "names no gate".
6. **Bootstrap writes the runner; retrofit proposes.** `/cdd-bootstrap` writes each project's runner,
   `list` mode and practices gate included. `/cdd-retrofit` proposes adding a missing `list` mode,
   per file — permanently on first install, transitionally on upgrade (#166) — and, on upgrade only
   (transitional, #166), registering the gate. On first install the contract is still unfilled, so
   the template roadmap's bootstrap phase carries the registration as a task instead.

## Rejected alternatives

- An installed, self-updating tool like `cdd-state.sh`: CI machines have no `~/.cdd`, and an
  Enforced claim needs a gate CI runs.
- Finding the runner by parsing `CLAUDE.md`'s Build & test block: a fragile new seam, plus
  placeholder handling; passing the runner as the argument needs neither.
- A `/cdd-pre-pr` step: CI never runs it, and gates stay gates (process doc §2.19).
- A runner skeleton in the template: it reverses "CDD ships the practice, not a script" (§2.14) and
  collides with an existing project's runner on retrofit.
- A symlink from this repo's `scripts/` to the template copy: symlinks break on Windows checkouts.
- This repo's gate running the template copy directly: CDD's own tooling would then live in
  `template/`.
- Keeping the only copy in this repo's `scripts/` and copying it out at bootstrap: the bootstrap
  script would need a special case outside `template/`, and retrofit's three-way merge, which
  renders the old template, would never see the file.
- Registering the gate on retrofit install: the contract is unfilled then, so CI would fail until
  the first task fills it.

## Consequences

- A downstream project's Enforced claims are checked once its runner registers the gate.
- Projects upgraded before #166 closes get the transitional proposals.
- A bootstrapped runner is written by Claude per project; this repo does not test it.
