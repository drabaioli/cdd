# 0014: Keep the install current by syncing on pull

**Status:** Accepted

## Context

The shared helpers install as a *copy* under `~/.cdd/tools/` (process doc §2.8), so that the
commands keep working when no CDD checkout is around. The cost of a copy is that it goes stale.
Merging a helper fix updates nothing on a machine until someone re-runs `install`, and nothing
says so. Issue #124 was fixed by PR #125, and `cdd-worktree-done` then hit the fixed bug again
about 40 seconds after the merge: the install still held the old script. Three helper PRs in a
row (#122, #123, #125) had touched the helpers, so this is the normal case, not a rare one.

Two more gaps sit next to it:

- **Open shells.** A shell (or tmux pane) that sourced the helpers keeps the functions it
  sourced, even after a reinstall.
- **Machines without a checkout.** A machine that installed with curl can only update by
  re-running three long curl incantations, and has nothing to compare against.

The rule to respect is §2.8's: the helper "probes the ground truth rather than assuming or
versioning", and installs are "newest wins, always from latest `main`".

## Decision

Three small pieces, none of which runs in the background or reaches the network on its own:

1. **Sync on pull.** `install`, run from a CDD git checkout, writes a managed `post-merge` and
   `post-rewrite` hook into that checkout (between them, every `git pull` variant). After a
   pull that lands on the default branch, the hook runs the just-pulled checkout's own
   `cdd-worktree.sh sync`, which reinstalls both helpers and the adapter library when any of
   them differs from the install — by content (`cmp`), never a recorded version — and prints
   one line. Pulls on other branches never install. The hook **reinstalls**, it does not just
   warn: reinstalling is a mechanical step with nothing to decide, and §2.8 already says the
   newest always wins. A hook the user wrote is never overwritten; under `core.hooksPath`
   nothing is written. Both cases print a note. `cdd-worktree-done` already pulls the default
   branch, so finishing a task updates the install.
2. **Self-reloading shells.** Each helper records its file's `cksum` when sourced. Each public
   command re-sources the file when it has changed and re-dispatches to the new definition, in
   the same shell, silently.
3. **One update command.** `bash ~/.cdd/tools/cdd-worktree.sh update` fetches upstream `main`'s
   `tools/` (a shallow, blobless, sparse clone), compares it with the install, and installs it
   when anything differs. It runs only when asked. `cdd-state`'s unknown-verb and invalid-stage
   errors, the usual symptom of a project newer than its helper, name it.

Rejected:

- **A version stamp** in the install. It violates §2.8, and a content comparison costs nothing.
- **A symlink install** (`~/.cdd/tools/*` pointing into the checkout). It needs no code, but it
  breaks "works without a live checkout", follows whatever branch the main worktree has checked
  out, and dangles once `cdd-worktree-done` removes the feature worktree it came from.
- **Warning at every command** (the first plan): `install` records its source checkout, and
  every `cdd-worktree*` command compares that checkout with the install. It also had a
  throttled background fetch of upstream for curl installs, a scan of the project's command
  prompts for `cdd-state` verbs the helper lacks, and hooks written into downstream clones. It
  worked, but it was rejected at plan approval as too heavy and too invasive. The hook makes the
  per-command comparison redundant, and the loud `cdd-state` error now explains itself.
- **A `post-checkout` hook.** No pull needs it, and it fires on every branch switch.
- **Re-running `done` after its own pull** to pick up a fix mid-run. `done` is not re-entrant
  once it has moved to the main worktree.

## Consequences

- Merging a helper PR and pulling `main` is enough: the next command anywhere on the machine
  runs the new code. Nothing prints while the install is current.
- The hook writes `~/.cdd/tools` during a `git pull`. That is its purpose, and it happens only
  on the default branch of a checkout the user installed from.
- Known limits: the one command whose own pull brings a fix (`done`) still runs the old code to
  the end. Shells opened before this change have no reload guard and need one restart. A
  checkout first needs one manual `install` to get its hook. A curl install stays as old as its
  last `update`.
- Downstream projects get nothing new: no hooks, no command changes. The template tells them
  how the install stays current.
- The gates that run `install` now install from a copy of `tools/` outside any repo, so a check
  run never hooks the developer's checkout. A new `toolchain-sync` gate covers the hook, the
  reload and `update` (against a local stub upstream).
