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

Every write is atomic — rendered to a temp file in the destination directory, then `mv`'d into place — so a crashed or concurrent write cannot leave a truncated record. The session chain's ids come from `CLAUDE_CODE_SESSION_ID`: an entry is appended only when the variable is non-empty and differs from the last entry's id (deduping repeated writes within one session); when it is unset (older Claude Code), the entry is omitted rather than guessed. Each entry also carries `dir`, the worktree root the session ran in (`git rev-parse --show-toplevel`) — the natural `cd` target before `claude --resume`. Seeding records the handoff session (`/cdd-next-step`, on the main worktree) as the first entry so it is resumable too, then `set` appends each in-worktree session thereafter. The helper is advisory end-to-end: absent `jq`, or an absent record, it no-ops rather than failing the workflow (writers never fabricate a record; only `/cdd-next-step` seeds one).

### Schema

`schema_version` lets consumers version their parser:

```json
{
  "schema_version": 1,
  "branch": "task_state_tracking",
  "stage": "plan_approved",
  "pr": null,
  "sessions": [ { "id": "<uuid>", "stage": "plan_approved", "dir": "<worktree-root>" } ]
}
```

`pr` is the integer PR number once a PR exists, else `null`. `sessions` is append-only; the last element is the most recent session, and a consumer derives the resume command as `claude --resume <id>`, run from `dir`. `dir` is additive and optional — not versioned by `schema_version`, so old and new records interoperate; a consumer that finds it absent falls back to the branch's known worktree path.

### Stages and writers

`stage` is a single enum (the record carries no separate status); each transition and its writer:

| `stage`               | written by                                          |
| --------------------- | --------------------------------------------------- |
| `scoped`              | `/cdd-next-step` — seeds the record and records itself as the first session `{id, stage: scoped, dir}` (empty `sessions` only when no session id is available); it runs on a different session, on the default branch |
| `plan_approved`       | implementation session — on plan approval, before any code |
| `implementation_done` | implementation session — after its local commit     |
| `merged`              | `/cdd-merge-base` — after a successful merge         |
| `checks_passed`       | `/cdd-pre-pr` — after the checklist + reconciliation commit |
| `pr_open`             | `/cdd-pre-pr` — after `gh pr create` (also sets `pr`) |
| `addressed`           | `/cdd-process-pr` — after a review round (sets `pr`) |

The implementation session has no command file, so its two `cdd-state set` calls are driven by a standing instruction in the handoff that `/cdd-next-step` generates.

## Resume discovery (`cdd-worktree-resume`)

The no-argument discovery mode fetches with `--prune`, so remote-tracking refs for branches deleted on the remote (as GitHub does when a PR merges) drop out before the listing. What remains — the default branch plus the feature branches still live on the remote, minus those already checked out locally — is exactly the resumable set, whether or not a branch has a PR yet.

## Task-ref sync (`refs/cdd/<branch>`)

The handoff (`<branch>.md`) and state record (`<branch>.state.json`) are out-of-tree, per-user files that would otherwise stay on the machine that created them. To carry them to a machine that resumes the task, `cdd-state` pushes them to a per-task ref and `cdd-worktree-resume` fetches and materializes them. The whole path is advisory: every step is best-effort and any failure (no `origin`, offline, missing `jq`, no ref on the remote) warns and continues — a resume with no ref behaves exactly as it did before the sync existed.

**Ref layout.** One ref per task at `refs/cdd/<branch>` on `origin`. The two files are bundled into a git *tree* under stable in-tree names — `handoff.md` and `state.json`, decoupled from the branch-named on-disk files — and the tree is wrapped in a **parentless (orphan) commit** that the ref points at. This is the side-ref-of-commits pattern git uses for `refs/stash` and `refs/notes/*`; a commit (rather than a bare tree/blob ref) is chosen because commits are push/fetch's native case and avoid cross-version transport surprises, and the commit can carry a message. `git notes` was rejected because it anchors metadata to a commit and so must chase the moving branch tip; the branch-keyed ref does not.

**Push (in `cdd-state`, on `seed` and `set`).** The state helper is the transition funnel, so folding the push in there means no slash command has to remember it and it cannot drift. It sits under `cdd-state`'s existing `jq` guard, so a machine without `jq` skips the whole thing. The ref is built with plumbing only — `git hash-object -w` each file that exists, `git mktree`, `git commit-tree` — so it never touches the index or working tree of the live worktree. The commit uses a fixed `cdd`/`cdd@local` author+committer identity, so it neither depends on nor fails from an unset user git identity. The push is a force-push (`git push --force origin <commit>:refs/cdd/<branch>`): the metadata is advisory, latest-wins, so whichever machine last advanced the task holds the truth. A fresh orphan commit per push is fine precisely because of the force-push — the commit SHA is never load-bearing (the round-trip smoke asserts on file contents, not hashes). `seed` is what first lands the immutable handoff `.md`; each `set` refreshes the `.json`.

**Fetch + materialize (in `cdd-worktree-resume`, before it finishes).** After the worktree is created, it fetches `refs/cdd/<branch>` (leaving the commit at `FETCH_HEAD`) and, if present, extracts the two blobs into `~/.cdd/handoffs/<repo>/`. Extraction streams `git show FETCH_HEAD:<name>` straight to a temp file then `mv`s it into place, so bytes are preserved exactly (no command-substitution newline mangling) and the write is atomic. The two files reconcile differently:

- **Handoff `.md`** is immutable after seed, so it is materialized only when absent locally — a present local handoff is never clobbered.
- **State `.json`** follows **most-advanced-stage wins**: the `.stage` of the ref's record and the local record are mapped to their index in the lifecycle enum (least → most advanced), and the ref overwrites local only when it is strictly further along; otherwise local is kept. Absent local → take the ref; absent ref blob → keep local; unparseable stage → treated as least advanced. When `jq` is unavailable the comparison can't run, so it falls back to write-only-if-absent (never clobber). The enum order is mirrored in `cdd-worktree.sh` (`cdd-worktree-stage-index`) with `cdd-state.sh`'s `cdd-state-stages` as the source of truth — a small, deliberate duplication because the two helpers are separate self-installing files.

**Cleanup (in `cdd-worktree-done`).** When `done` deletes the branch, it also best-effort deletes `refs/cdd/<branch>` on `origin` (`git push origin --delete`), so the namespace does not accumulate. Like everything else here, a failed delete warns and never blocks the teardown.
