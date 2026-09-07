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

- **Dispatching shims** for the commands that change no cwd: `cdd-worktree-list`, `cdd-worktree-gc` and `cdd-state`. The shim sources the installed helper and dispatches to the function, so the command works in non-interactive shells too. It first checks that the helper file exists and then that sourcing it actually defined the function, failing with exit 127 and a reinstall hint if either is false — without those guards a missing or broken helper leaves the function undefined and the shim's own dispatch re-resolves through `PATH` to the shim, recursing without bound instead of erroring. The `cdd-state` shim is load-bearing for the workflow: the slash commands invoke `cdd-state set` from the non-interactive Bash tool, and without the shim every state write would silently no-op.
- **Refuse-loudly shims** for the three commands that `cd` the caller's shell (`cdd-worktree`, `cdd-worktree-resume`, `cdd-worktree-done`). A shim runs in a subshell and cannot change its parent's cwd, so dispatching would strand the caller in the old directory while claiming success; the shim instead fails with an explanation to run the command as a sourced shell function.

## The first prompt and its capability probe

`cdd-worktree` is the one place where behaviour depends on the project's baseline: which prompt it hands the new session. It resolves that by **probing the ground truth** — whether the worktree it just created contains `.claude/commands/cdd-plan.md` — rather than by consulting a recorded version or marker, neither of which can be kept honest across a fleet. A retrofitted project is launched on `/cdd-plan`; one that is not gets the pre-split prose prompt naming the handoff's `## Implementation prompt` heading, which is why that heading is frozen. The `else` branch is the deprecation seam, removable once every project is retrofitted.

The probe covers only the helper-newer-than-project direction. For the reverse — a retrofitted project meeting a `cdd-state` that predates `plan_written`, which would reject the write and stall the task invisibly — the helper asks `cdd-state stages` (a read-only accessor answered before `cdd-state`'s own `jq` guard, so a host without `jq` still gets the true answer) and prints one warning line if the stage is missing. One direction it cannot cover at all is an outdated `cdd-worktree` itself: it has no code with which to warn about its own age. Both cases are pinned by `scripts/base-branch-assert.sh`.

## Runtime derivation

Nothing project-specific is configured or copied per project: the repo name (the handoff-directory namespace) is derived from the worktree's git common directory, and the default branch from `origin`'s HEAD (`git symbolic-ref refs/remotes/origin/HEAD`), falling back to `main`. The remote is assumed to be named `origin`; that assumption is documented in `template/BOOTSTRAP.md`.

The default branch is the *fallback* base for a task, not always its actual base. Each task records its own base branch (§ below); `cdd-worktree` cuts the new branch from that base and the resume-side commands target it, both falling back to the runtime-derived default branch when a task recorded none.

## State-record writes (`cdd-state`)

Every write is atomic — rendered to a temp file in the destination directory, then `mv`'d into place — so a crashed or concurrent write cannot leave a truncated record. The session chain's ids come from `CLAUDE_CODE_SESSION_ID`: an entry is appended only when the variable is non-empty and differs from the last entry's id (deduping repeated writes within one session); when it is unset (older Claude Code), the entry is omitted rather than guessed. Each entry also carries `dir`, the worktree root the session ran in (`git rev-parse --show-toplevel`) — the natural `cd` target before `claude --resume`. Seeding records the handoff session (`/cdd-next-step`, on the main worktree) as the first entry so it is resumable too, then `set` appends each in-worktree session thereafter. The helper is advisory end-to-end: absent `jq`, or an absent record, it no-ops rather than failing the workflow (writers never fabricate a record; only `/cdd-next-step` seeds one).

`seed` also records the task's base branch when passed `--base <branch>` (`/cdd-next-step` supplies the branch it is standing on); without the flag the field is `null`. It is set once at seed and never mutated: `set` rewrites only `stage`/`pr`/`sessions`, so `base_branch` rides through every later write untouched (`jq` passes unreferenced fields through), and the whole-record materialize on resume carries it to other machines for free. A read accessor, `cdd-state get <field>`, prints `.<field>` from the cwd-derived record (empty on absent `jq`, absent record, or an absent/`null` field) — the resume-side commands read `base_branch` through it.

### Schema

`schema_version` lets consumers version their parser:

```json
{
  "schema_version": 1,
  "branch": "task_state_tracking",
  "stage": "plan_approved",
  "pr": null,
  "base_branch": "develop",
  "sessions": [ { "id": "<uuid>", "stage": "plan_approved", "dir": "<worktree-root>" } ]
}
```

`pr` is the integer PR number once a PR exists, else `null`. `base_branch` is the branch the task was cut from and merges back into, recorded once at seed and immutable thereafter; `null` (or absent, on records predating the field) means "no base recorded", and consumers fall back to the runtime-derived default branch. Like `dir`, it is additive and optional — not versioned by `schema_version`, so old and new records interoperate. `sessions` is append-only; the last element is the most recent session, and a consumer derives the resume command as `claude --resume <id>`, run from `dir`. `dir` is additive and optional — not versioned by `schema_version`, so old and new records interoperate; a consumer that finds it absent falls back to the branch's known worktree path.

### Per-repo marker (`repo.json`)

Everything else in `~/.cdd/handoffs/<repo>/` is task-scoped: handoffs and state records are named after a branch and reaped when that task merges (`cdd-worktree-done`, `cdd-worktree-gc`). So a repo whose tasks have all landed leaves an *empty* directory, and nothing on disk still says where that repo is checked out. `repo.json` is the one artifact in there that is not task-scoped:

```json
{
  "schema_version": 1,
  "name": "cdd",
  "path": "/home/you/Code/cdd"
}
```

`path` is the repo's **main worktree** — `dirname` of `git rev-parse --path-format=absolute --git-common-dir`, deliberately *not* `--show-toplevel`, which names the *feature* worktree whenever a task session is the one writing (the common case: every `cdd-state set` after `seed` runs from a worktree). `name` is that path's basename, i.e. the same repo name that namespaces the directory. `schema_version` is versioned independently of the state record's: the two files carry unrelated shapes and can evolve apart.

**One writer, three callers.** `cdd-state-write-repo-marker` renders the JSON and writes it through the same atomic `cdd-state-write`. `cdd-state seed` and `cdd-state set` both call it — `set` *before* its absent-record return, so a repo whose records have all been reaped still gets one (the "writers never fabricate a record" rule is about the *task* record) — and `bootstrap-cdd-project.sh` calls it after `git init`, by sourcing its sibling `cdd-state.sh` (dual-mode: sourcing defines functions only) rather than duplicating the shape. Not in `--stage` mode: that path does no `git init` and its target is a staging dir, not a repo. Each write **overwrites unconditionally**, so the marker self-heals when a repo moves or is re-cloned — latest writer wins, like the task ref.

It is **advisory** like the rest of the helper: a failing `rev-parse`, an unwritable directory, or a missing/failing `jq` warns once and returns 0, so it can never fail the state write that called it (nor the `set -e` bootstrap that sources it).

**Machine-local by design.** The path is true only on the machine that wrote it, so the marker is never carried across machines: `cdd-state-push-ref` bundles `handoff.md`, `plan.md` and `state.json` and nothing else, so `refs/cdd/<branch>` excludes it by construction. Each machine writes its own on its first `cdd-state` call in that repo. It also survives GC by construction — the candidate set globs `*.md` ∪ `plans/*.md` ∪ `*.state.json` ∪ `refs/cdd/*`, and `repo.json` matches none (pinned by `scripts/gc-assert.sh`).

**Consumer rule.** Prefer a live resolution from `sessions[].dir` when one is available, and fall back to the marker; a marker can be stale (repo moved, never rewritten since), and a stale one must not outvote a directory a session is demonstrably using. The marker's value is the case where no record exists at all.

### Stages and writers

`stage` is a single enum (the record carries no separate status); each transition and its writer:

| `stage`               | written by                                          |
| --------------------- | --------------------------------------------------- |
| `scoped`              | `/cdd-next-step` — seeds the record and records itself as the first session `{id, stage: scoped, dir}` (empty `sessions` only when no session id is available); it runs on a different session, on the default branch |
| `plan_approved`       | `/cdd-plan` — on plan approval, before the plan file is written |
| `plan_written`        | `/cdd-plan` — after writing the plan file; this write is what carries it onto the task ref |
| `implementation_done` | `/cdd-implement` — after its local commit           |
| `merged`              | `/cdd-merge-base` — after a successful merge         |
| `checks_passed`       | `/cdd-pre-pr` — after the checklist + reconciliation commit |
| `pr_open`             | `/cdd-pre-pr` — after `gh pr create` (also sets `pr`) |
| `addressed`           | `/cdd-process-pr` — after a review round (sets `pr`) |

Every stage is written by a command file; nothing rides on a standing instruction in the handoff any more. Note the asymmetry between the two `/cdd-plan` writes: `plan_approved` records that the checkpoint cleared, `plan_written` that the artifact exists — so a session that dies between them is distinguishable from one that never got approval.

## Resume discovery (`cdd-worktree-resume`)

The closing "Next:" line branches on the resumed task's `stage`: a task parked at `plan_written` has an approved plan on disk and no code, so it is sent to `/cdd-implement`; anything else gets the review-side commands. The stage is read straight from the materialized record with `jq` rather than through `cdd-state`, keeping the two separately-installed helpers independent at runtime — the same derivation `cdd-worktree` already does for `base_branch`.

The no-argument discovery mode fetches with `--prune`, so remote-tracking refs for branches deleted on the remote (as GitHub does when a PR merges) drop out before the listing. What remains — the default branch plus the feature branches still live on the remote, minus those already checked out locally — is exactly the resumable set, whether or not a branch has a PR yet.

## Task-ref sync (`refs/cdd/<branch>`)

The handoff (`<branch>.md`), the plan file (`plans/<branch>.md`) and the state record (`<branch>.state.json`) are out-of-tree, per-user files that would otherwise stay on the machine that created them. To carry them to a machine that resumes the task, `cdd-state` pushes them to a per-task ref and `cdd-worktree-resume` fetches and materializes them. The whole path is advisory: every step is best-effort and any failure (no `origin`, offline, missing `jq`, no ref on the remote) warns and continues — a resume with no ref behaves exactly as it did before the sync existed.

**Ref layout.** One ref per task at `refs/cdd/<branch>` on `origin`. The three files are bundled into a git *tree* under stable in-tree names — `handoff.md`, `plan.md` and `state.json`, decoupled from the branch-named on-disk files (and, conveniently, already in the name order `git mktree` requires) — and the tree is wrapped in a **parentless (orphan) commit** that the ref points at. This is the side-ref-of-commits pattern git uses for `refs/stash` and `refs/notes/*`; a commit (rather than a bare tree/blob ref) is chosen because commits are push/fetch's native case and avoid cross-version transport surprises, and the commit can carry a message. `git notes` was rejected because it anchors metadata to a commit and so must chase the moving branch tip; the branch-keyed ref does not.

**Push (in `cdd-state`, on `seed` and `set`).** The state helper is the transition funnel, so folding the push in there means no slash command has to remember it and it cannot drift. It sits under `cdd-state`'s existing `jq` guard, so a machine without `jq` skips the whole thing. The ref is built with plumbing only — `git hash-object -w` each file that exists, `git mktree`, `git commit-tree` — so it never touches the index or working tree of the live worktree. The commit uses a fixed `cdd`/`cdd@local` author+committer identity, so it neither depends on nor fails from an unset user git identity. The push is a force-push (`git push --force origin <commit>:refs/cdd/<branch>`): the metadata is advisory, latest-wins, so whichever machine last advanced the task holds the truth. A fresh orphan commit per push is fine precisely because of the force-push — the commit SHA is never load-bearing (the round-trip smoke asserts on file contents, not hashes). `seed` is what first lands the immutable handoff `.md`; each `set` refreshes the `.json`. The plan file is written after seed, by `/cdd-plan` on approval, so the `set plan_written` that follows it is the push that first carries it — which is why `cdd-state-push-ref` derives the plan path from the handoff path rather than taking a third argument: both call sites stay two-argument and cannot forget it.

**Fetch + materialize (in `cdd-worktree-resume`, before it finishes).** After the worktree is created, it fetches `refs/cdd/<branch>` (leaving the commit at `FETCH_HEAD`) and, if present, extracts the three blobs into `~/.cdd/handoffs/<repo>/`. Extraction streams `git show FETCH_HEAD:<name>` straight to a temp file then `mv`s it into place, so bytes are preserved exactly (no command-substitution newline mangling) and the write is atomic. The three files reconcile differently:

- **Handoff `.md`** is immutable after seed, so it is materialized only when absent locally — a present local handoff is never clobbered.
- **State `.json`** follows **most-advanced-stage wins**: the `.stage` of the ref's record and the local record are mapped to their index in the lifecycle enum (least → most advanced), and the ref overwrites local only when it is strictly further along; otherwise local is kept. Absent local → take the ref; absent ref blob → keep local; unparseable stage → treated as least advanced. When `jq` is unavailable the comparison can't run, so it falls back to write-only-if-absent (never clobber).
- **Plan `.md`** is **mutable** — the human may edit it before implementing — so neither of the other two rules fits. It travels *with* the state record instead: taken when absent locally, or when the ref's record won the stage comparison; kept otherwise. Plan and record therefore never disagree about which machine's version of the task is current.

The enum order is mirrored in `cdd-worktree.sh` (`cdd-worktree-stage-index`) with `cdd-state.sh`'s `cdd-state-stages` as the source of truth — a small, deliberate duplication because the two helpers are separate self-installing files.

**Cleanup (in `cdd-worktree-done`).** When `done` deletes the branch, it also best-effort deletes `refs/cdd/<branch>` on `origin` (`git push origin --delete`), so the namespace does not accumulate. Like everything else here, a failed delete warns and never blocks the teardown.

## Garbage collection (`cdd-worktree-gc`)

`cdd-worktree-done` is the primary reaper, but it only fires when a human runs it from the worktree, and its remote-ref delete is a single best-effort attempt. Three gaps leak artifacts: `done` is never run; its ref delete fails while offline and is never retried; or a task resumed on several machines leaves a materialized handoff/plan/state on each, while `done` (run on one machine) cleans only that one. `cdd-worktree-gc` is the periodic sweep that closes them.

**Reap predicate — merged PR only.** The tempting signal, "the branch no longer exists on `origin`", is wrong: a freshly scoped task has a handoff and a `refs/cdd/<branch>` ref *before* `cdd-worktree` ever creates the branch (`cdd-state seed` pushes the ref; the branch reaches `origin` only at first push), so it is byte-for-byte indistinguishable from a merged-and-branch-deleted task by ref or branch presence alone. The only trustworthy "done" signal is a **merged PR** — the same signal `cdd-worktree-done` trusts (`gh pr list --head <branch>`). So GC reaps a task iff its PR state is `MERGED`; anything else (open PR, or no PR yet) is treated as in-flight or scoped and left untouched. This makes `gh` a hard dependency for GC: without an authenticated `gh` it cannot tell a finished task from a fresh one, so it reaps nothing and says so.

**What it enumerates and removes.** Candidates are the union of local handoff/plan/state basenames in `~/.cdd/handoffs/<repo>/` and the `refs/cdd/*` names from `git ls-remote origin` — so a machine that never held a task's files can still reap that task's leaked remote ref, and a machine holding orphaned local copies can reap them even after the ref is already gone. For each merged candidate it removes whichever of the four artifacts are present (local `.md`, local `plans/<branch>.md`, local `.state.json`, remote ref). The plan glob is a separate line in the candidate set precisely because plan files live one level down: that is what keeps them out of the flat `*.md` glob, so they are reaped deliberately and can never surface as a phantom task in `cdd-worktree-list` (both pinned by `scripts/gc-assert.sh`). It is **dry-run by default** — printing `reap … would remove …` / `keep …` lines — and only deletes under `--force`. Being conservative and idempotent, it is safe to run (or schedule) routinely.
