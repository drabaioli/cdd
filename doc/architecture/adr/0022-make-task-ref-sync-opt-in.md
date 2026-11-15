# 0022: Make task-ref sync opt-in

**Status:** Accepted

## Context

`cdd-state` pushed the handoff, the plan file and the state record to `refs/cdd/<branch>` on
`origin` on every record write, with no opt-out. That published private scoping notes, the plan,
session ids and absolute local paths (`sessions[].dir`) to anyone who can read the remote — on a
public repository, everyone.

With `Bash(cdd-state *)` pre-approved, no session was ever asked first. That contradicts ADR
0015's rule that a session holding private data has no unprompted way to send it out (0015, "Only
the researcher fetches without a prompt"). Issue #149.

## Decision

1. **Off by default.** The push runs only when `git config --bool cdd.syncTaskRef` is true, set
   per clone or with `--global`. Unset or false means no push and nothing printed. A value git
   cannot read as a boolean means no push and one warning line: it fails closed.
2. **Why a git config key.**
   - It is the human's switch and lives outside the tree. It is never committed, so a fork or a
     fresh clone does not inherit it.
   - It works per clone or machine-wide.
   - `git config` is not pre-approved, so a session cannot turn the sync on without the human
     seeing it. The `Bash(cdd-state *)` allowlist entry stays as it is.
3. **Private repositories only.** The ref publishes the handoff and plan to everyone who can read
   the remote. The docs say so wherever they say how to enable it.
4. **When on, the pushed record omits `sessions[].dir`.** It is an absolute local path,
   meaningless on another machine, and consumers already fall back without it. The local record
   keeps it. A failure to filter skips the push rather than sending the unfiltered record.
5. **`cdd-state` says nothing when the sync is off.** A hint in a session's output invites the
   session to turn it on. The hint lives in `cdd-worktree-resume`'s no-ref message, which the
   human runs and where the cost shows.
6. **Cleanup ignores the setting.** `cdd-worktree-done` and `cdd-worktree-gc` still delete and
   enumerate `refs/cdd/*`, so refs pushed before this change, or while the sync was on, are
   reaped as their tasks merge.
   - Refs of tasks still in flight, or abandoned, stay on origin until then. Nothing deletes them
     automatically.
   - List them with `git ls-remote origin 'refs/cdd/*'`; delete one with
     `git push origin --delete refs/cdd/<branch>`.

## Rejected alternatives

- **Opt-out** (keep pushing unless disabled): keeps the leak as the default for every public repo.
- **Prompting before each push:** `cdd-state` runs inside sessions, several times a task, and a
  per-write prompt becomes a rubber stamp.
- **An environment variable:** it has to be set in every shell, and a session could set it on the
  same command line it runs. A git config write is a separate, unapproved command.
- **A committed setting (in `.cdd/`):** it travels with the repo, so every clone and fork inherits
  it, and a session could commit it.
- **Detecting public vs private through the code-host adapter:** a new verb on every adapter and a
  network call per write. A wrong answer leaks, and a repo's visibility can change after the fact.
- **Encrypting the ref:** key distribution across machines, out of proportion to the problem.
- **Deleting refs already pushed:** a destructive remote action outside this change. It is
  documented instead.

## Consequences

- By default, cross-machine resume carries no handoff, plan or record. Review-side commands are
  unaffected: they read PR and branch state from git and the code host. A task parked at
  `plan_written` is hit hardest: the resuming machine has no plan to implement from and no record
  to route on. The plan file must be copied over, or the sync turned on at the originating
  machine.
- `cdd-worktree-gc` on a machine that never held a task's record cannot read that task's issue refs
  from a ref that was never pushed, so it cannot close those issues. `done` and `gc` on the
  machine that holds the record still do.
- A record materialized from the ref has no `dir`.
- This repository is public, so its own task refs stop by default.
- The test gates that assert the push turn the setting on. `ref-sync` pins the default-off path, a
  non-boolean value and a per-clone "on"; `state-stage` pins the missing `dir` on the ref.
