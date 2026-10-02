# 0012: Drop the built-in `gh` rung

**Status:** Accepted

Partially supersedes [0007](0007-extend-cdd-through-capability-adapters.md) (the ladder's third
rung, "built-in behaviour") and [0010](0010-code-host-rename-and-broken-adapter-rule.md) (a
missing adapter "goes to the next rung", and the helpers' silent built-in rung). The rest of
both stands.

## Context

ADR 0007 gave the resolution ladder a last rung — the `gh` calls the commands and helpers made
before adapters existed — so that a project with no adapter behaved as before. That was the
right default while nothing bound a project to an adapter. [ADR 0011](0011-bind-adapters-through-a-machine-global-library.md)
changed it: `/cdd-bootstrap` and `/cdd-retrofit` now write `.cdd/` bindings, GitHub by default,
so a project CDD set up or upgraded has an adapter. The built-in rung is left serving only a
project that has not been upgraded, and it costs a second code path in every caller: each prompt
carries a `gh` branch beside its adapter branch, the shell helpers carry `gh pr list` and
`gh issue close` beside their adapter calls, and the seam checks and gates pin both.

## Decision

1. **The ladder is project → machine → nothing.** `.cdd/<capability>`, then
   `~/.cdd/adapters/<capability>`. No command or helper calls `gh` for a tracker or code-host
   job; the adapters still do, internally. The machine rung stays: one shop with many repos is
   the reason it exists, and none of that changed.

2. **A missing adapter behaves like ADR 0010's unsupported verb** — the feature is skipped,
   with one line — **except where the feature is the whole point of the invocation**, which
   stops. The line is the same everywhere, so it is also the migration signal:
   - prompts: `No <capability> adapter is installed; run /cdd-retrofit in this project to
     install one.`
   - helpers: `<capability>: no adapter installed; run /cdd-retrofit in this project to install
     one`, then what was skipped.

3. **Per call site.**
   - `/cdd-next-step`: roadmap and intent modes need no adapter. The `issue` keyword still
     dispatches, then stops with the line. The built-in `ref_pattern` `^#?[0-9]+$` goes with the
     rung: with no tracker resolved, no argument is issue-shaped.
   - `/cdd-pre-pr`: no code host skips the PR step; no tracker opens the PR with no close lines,
     and says so. `/cdd-process-pr`: no code host stops.
   - `cdd-worktree-done`: no code host means merged-PR detection is skipped, so a branch git
     cannot prove merged falls to the existing keep/delete/abort prompt — never reaped silently,
     and a task with issue refs keeps its record. No tracker means the issues are not closed,
     the PR is not linked, and the record is kept for `cdd-worktree-gc` to retry.
   - `cdd-worktree-gc`: no code host cannot tell a merged task from a scoped one, so it reaps
     nothing, with one advisory line. No tracker keeps a merged task that recorded refs.
   - `cdd-worktree-list` and `-resume`: no PR column, one line.

4. **Settings allowlist.** The five read-only `gh` entries (`pr view/list/checks`, `issue
   view/list`) are replaced by the read-only adapter verbs the prompts run (`describe`,
   `issue-read`, `issue-list`, `pr-for-branch`, `pr-comments`).

5. **Installers on a backend with no shipped adapter** write no binding and say the issue and PR
   features skip, instead of "the built-in path keeps serving".

Rejected: keeping the rung as a deprecated fallback with a warning (the second code path is the
cost being removed, and a warning every session is noise); auto-installing the GitHub adapter at
the machine rung (it would bind every repository on the machine, which ADR 0011 rules out).

## Consequences

- A project bootstrapped or retrofitted before ADR 0011 has no `.cdd/` and loses issue-driven
  `/cdd-next-step`, PR creation and replies, the close lines, and the helpers' PR-based cleanup
  until `/cdd-retrofit` binds it. The missing-adapter line says so at the point of use.
- The "no adapter installed" baseline that behaviour-neutrality was checked against is gone; the
  gates now assert that with no adapter nothing reaches `gh` and nothing is reaped, closed or
  force-deleted silently.
- `cdd-worktree-done` and `-gc` get more conservative with no adapter, never less.
