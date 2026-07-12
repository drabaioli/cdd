# The shared shell helpers (`cdd-worktree`, `cdd-state`)

How the two project-independent helpers — `tools/cdd-worktree.sh` (worktree lifecycle, process doc §2.8) and `tools/cdd-state.sh` (per-task state record, process doc §2.13) — are installed, wired into shells, and kept compatible with every project from a single copy. The workflow-level contracts live in the process doc; this document carries the implementation mechanics. The scripts' own comments are the finest-grained reference.

## Install model

Both scripts are dual-mode: sourced, they define their shell functions; run directly with `install`, they set themselves up. `install` copies the script to a stable home under `~/.cdd/tools/` that does not depend on a live CDD checkout, appends a marker-guarded `source` line to `~/.bashrc` and `~/.zshrc`, and drops PATH shims into `~/.local/bin` (next section). The rc block is idempotent and self-repairing: re-running `install` re-enables a disabled block rather than skipping it because the marker is still present.

On a machine without the CDD repo checked out (a fresh clone of only a downstream project), the same one-time install is a single command — fetched to disk first, since `curl … | bash` can't work (the installer copies itself from its own file path, which a piped stdin does not provide):

```bash
curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/cdd-worktree.sh \
  --create-dirs -o ~/.cdd/tools/cdd-worktree.sh \
  && bash ~/.cdd/tools/cdd-worktree.sh install
```

(`tools/cdd-state.sh` supports the same form.)

`install` is also where one-shot migrations of the helpers' shared on-disk state live: when the layout the helpers depend on changes, the migration ships inside `install` and re-homes every project at once (the `~/.claude-handoffs/` → `~/.cdd/handoffs/` move is the precedent).

## PATH shims and the cwd constraint

The rc `source` line only reaches interactive shells (`~/.bashrc` returns early for non-interactive ones), so in a non-interactive shell — notably Claude Code's Bash tool — the functions are undefined and a bare command name would be "command not found". `install` therefore drops thin shims into `~/.local/bin`, of two kinds:

- **Dispatching shims** for the commands that change no cwd: `cdd-worktree-list` and `cdd-state`. The shim sources the installed helper and dispatches to the function, so the command works in non-interactive shells too. The `cdd-state` shim is load-bearing for the workflow: the slash commands invoke `cdd-state set` from the non-interactive Bash tool, and without the shim every state write would silently no-op.
- **Refuse-loudly shims** for the three commands that `cd` the caller's shell (`cdd-worktree`, `cdd-worktree-resume`, `cdd-worktree-done`). A shim runs in a subshell and cannot change its parent's cwd, so dispatching would strand the caller in the old directory while claiming success; the shim instead fails with an explanation to run the command as a sourced shell function.

## Runtime derivation

Nothing project-specific is configured or copied per project: the repo name (the handoff-directory namespace) is derived from the worktree's git common directory, and the default branch from `origin`'s HEAD (`git symbolic-ref refs/remotes/origin/HEAD`), falling back to `main`. The remote is assumed to be named `origin`; that assumption is documented in `template/BOOTSTRAP.md`.

## State-record writes (`cdd-state`)

Every write is atomic — rendered to a temp file in the destination directory, then `mv`'d into place — so a crashed or concurrent write cannot leave a truncated record. The session chain's ids come from `CLAUDE_CODE_SESSION_ID`: an entry is appended only when the variable is non-empty and differs from the last entry's id (deduping repeated writes within one session); when it is unset (older Claude Code), the entry is omitted rather than guessed. The helper is advisory end-to-end: absent `jq`, or an absent record, it no-ops rather than failing the workflow (writers never fabricate a record; only `/cdd-next-step` seeds one).

## Resume discovery (`cdd-worktree-resume`)

The no-argument discovery mode fetches with `--prune`, so remote-tracking refs for branches deleted on the remote (as GitHub does when a PR merges) drop out before the listing. What remains — the default branch plus the feature branches still live on the remote, minus those already checked out locally — is exactly the resumable set, whether or not a branch has a PR yet.
