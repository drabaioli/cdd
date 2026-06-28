Install CDD into an existing project, or upgrade a project already running CDD, at the path given as argument: `/cdd-retrofit <target-path>`.

Run this command from a CDD-repo session (it needs the CDD repo's `template/`, `bootstrap-cdd-project.sh`, and git history). The mode — **install** or **upgrade** — is auto-detected from the target. This command exists only in the CDD repo; it deliberately has no counterpart in `template/.claude/commands/` (it operates *on* target projects, so downstream projects have no use for it — see the process doc, Section 2.7).

**Checkpoint discipline:** every write that touches a pre-existing file in the target is approved per file by the user. Never overwrite a project file silently. Identifier choices (name/slug/dir) are confirmed before anything is rendered.

Target path: `$ARGUMENTS`

## 1. Resolve and validate the target

Resolve the argument to an absolute path. It must exist and be a directory; otherwise stop and report.

Check the target's git state:

```bash
git -C <target> rev-parse --is-inside-work-tree 2>/dev/null
git -C <target> status --porcelain 2>/dev/null
```

- If the target is not a git repo, warn the user (retrofit changes won't be revertable via git, and the isolated-worktree step in section 2.5 won't run) and ask whether to proceed.
- A **dirty working tree no longer blocks the retrofit**: section 2.5 writes into a fresh worktree branched from HEAD, so the target's current checkout is untouched. Do *not* hard-stop on a dirty tree. There is one nuance to warn about: because the worktree is taken from HEAD, any **uncommitted local edits to CDD-managed files** (the set listed in section 4.4) are invisible to the upgrade comparison. If `git status --porcelain` shows uncommitted changes to those files, tell the user to commit them first or they won't be considered, then let them decide whether to proceed.

Also note `<target>/.gitignore`: if any path the retrofit will write (`.claude/`, `doc/`, `tools/`) is gitignored, warn that those writes will not show in `git status` (and won't be staged by the retrofit commit in sections 3.4 / 4.6), and include this in the final summary.

## 2. Detect the mode

Probe for CDD scaffolding in the target:

```bash
ls <target>/.claude/commands/cdd-next-step.md <target>/doc/knowledge_base/roadmap.md 2>/dev/null
```

- Either file present → **upgrade mode** (section 4).
- Neither present → **install mode** (section 3).

State the detected mode and the evidence to the user before proceeding, and let them override if the detection is wrong (e.g. a half-finished previous install).

## 2.5 Create the isolated worktree

Retrofit changes must land on a dedicated branch, isolated from the target's current checkout, so the user reviews and merges them through a normal PR instead of finding scaffolding strewn across the current branch (usually the default branch). Set this up **before** rendering or copying anything; every write in sections 3 and 4 goes into the worktree, referred to below as `$WT`.

Derive the branch and path (mirroring `tools/cdd-worktree.sh` conventions — sibling of the target):

```bash
BRANCH=cdd-retrofit
WT="$(dirname "<target>")/$(basename "<target>")-$BRANCH"
```

- **Collision:** if `$BRANCH` already exists (`git -C <target> rev-parse --verify --quiet "$BRANCH"`) or `$WT` already exists, append a numeric suffix (`cdd-retrofit-2`, `-3`, …) until both are free, or ask the user for a name. Never reuse or clobber an existing branch or worktree.
- **Create it** from the target's HEAD:

  ```bash
  git -C <target> worktree add -b "$BRANCH" "$WT"
  ```

  On success, set `$WT` as the destination for all subsequent writes and the source for any reads of the project's current files (in upgrade mode the worktree is identical to HEAD).

- **Fallbacks — warn, then degrade; never silently skip isolation:**
  - Target is **not a git repo** (from section 1) → no worktree possible. Warn, set `$WT` = `<target>` (in-place writes, today's behavior), and **skip the commit step** in sections 3.4 / 4.6.
  - Target git repo has **no commits / unborn or detached HEAD** (`worktree add -b` fails) → warn and fall back to a plain `git -C <target> switch -c "$BRANCH"` in the existing checkout, with `$WT` = `<target>`; if even that fails, fall back to in-place writes and skip the commit step.

## 3. Install mode

A files-only install of the template. No codebase survey, no generated architecture doc or roadmap — the template roadmap ships with a pre-filled bootstrap phase (survey the codebase, draft the initial architecture docs, write the feature docs, fill in the roadmap), so the project's first `/cdd-next-step` picks those up as the next unchecked tasks.

### 3.1 Confirm the two identifiers

Propose, then confirm with the user before rendering (never pick silently):

- `<PROJECT_DIR>` — basename of the target path. Must match `^[A-Za-z][A-Za-z0-9_-]*$`; if it doesn't, ask the user for a conforming value (this only affects rendered paths like the handoff dir, not the actual directory name).
- `<PROJECT_NAME>` — propose a title-cased form of the directory name; free text.

### 3.2 Render the template into a staging directory

Reuse the bootstrap script's substitution — do not reimplement it:

```bash
STAGE=$(mktemp -d)
./tools/bootstrap-cdd-project.sh --stage \
  --name "<PROJECT_NAME>" --dir <PROJECT_DIR> \
  --path "$STAGE/render"
```

The staging tree is fully substituted, has no `.git`, and contains the baseline marker `.claude/cdd-baseline`.

### 3.3 Copy staging → worktree, per file

Walk every file in `$STAGE/render`. All writes go into `$WT` (the isolated worktree from section 2.5), and presence is judged against `$WT` — which, for a fresh worktree, mirrors the target's HEAD:

- **Absent in `$WT`** → copy it directly (create parent dirs as needed). This covers the slash commands, doc skeletons, the worktree helper, `.claude/settings.json`, and the marker in the common case.
- **Present in `$WT`** (collision — typically `CLAUDE.md`, sometimes `doc/` files or `.claude/settings.json`) → propose a merge interactively, one file at a time:
  - `CLAUDE.md`: keep the project's existing content; propose adding the CDD pieces it lacks (the Key references table rows for `doc/`, and the Workflow section referencing `/cdd-next-step`, `/cdd-pre-pr`, `/cdd-merge-base`). Show the proposed result; apply only on approval.
  - `.claude/settings.json`: merge the `permissions.allow` arrays (union); show the result before writing.
  - Anything else: show both versions and propose the merge; the user decides per file.
- Never delete or move existing files.

### 3.4 Finish

- Remove `$STAGE`.
- **Commit on the retrofit branch** (skip this if section 2.5 fell back to in-place writes with no branch). The retrofit session holds the context for a good message, so write a real one:

  ```bash
  git -C "$WT" add -A
  git -C "$WT" commit -m "Install CDD scaffolding" -m "<short body: files added/merged>"
  ```

  Stage with `add -A` — the worktree was fresh, so this captures exactly the retrofit's writes. Gitignored paths won't be staged (see the section 1 gitignore warning). Commit only on this dedicated branch; never commit onto the target's existing branches.
- Print next steps: the one-time worktree-helper install (`./tools/cdd-worktree.sh install` in the CDD repo — project-independent, only needed if the user hasn't installed it before; nothing is added per project); how to review and merge the branch (`git -C "$WT" show`, then open a PR from `cdd-retrofit`); and that once merged they can remove the worktree with `git -C <target> worktree remove "$WT"`. Then run `/cdd-next-step` in the target — it will pick up the roadmap's pre-filled bootstrap tasks (codebase survey, initial architecture and feature docs, CLAUDE.md stubs, roadmap fill) as the first task. Warn the user: on an existing project without prior doc discipline this first task is a doc reconciliation that forces the docs to match the code for the first time, so it may be slow and span several early PRs — that is expected, not a fault. Where docs already exist, it reconciles and adopts them rather than overwriting.

## 4. Upgrade mode

Sync improvements the CDD template has accrued into the target **without changing the behavior of the project's current workflow**: local adaptations are preserved, and general-looking local improvements are surfaced as candidates to upstream into the CDD repo.

### 4.1 Establish the baseline

Read `$WT/.claude/cdd-baseline` (the section 2.5 worktree, which mirrors HEAD).

- **Present and a valid commit in this CDD repo** (`git cat-file -e <hash>^{commit}`) → three-way mode.
- **Missing, `unknown`, or not a known commit** → pre-marker fallback: two-way mode (target vs. current template only), where *every* difference is presented to the user to classify as "apply the template's version", "keep local", or "merge". Be conservative; when in doubt, keep local. The marker is written at the end regardless, so the next upgrade gets the three-way path.

### 4.2 Recover the target's identifiers

The marker stores only the hash, so re-infer and confirm with the user:

- `<PROJECT_DIR>`: basename of the target path.
- `<PROJECT_NAME>`: from the title of `$WT/CLAUDE.md` if recognizable; otherwise ask.

### 4.3 Render both template versions with the target's identifiers

Current template:

```bash
STAGE=$(mktemp -d)
./tools/bootstrap-cdd-project.sh --stage \
  --name "<PROJECT_NAME>" --dir <PROJECT_DIR> \
  --path "$STAGE/current"
```

Old (baseline) template, extracted from this repo's history and rendered through the same substitution path:

```bash
OLD_TPL=$(mktemp -d)
git archive <baseline-hash> template | tar -x -C "$OLD_TPL"
./tools/bootstrap-cdd-project.sh --stage \
  --name "<PROJECT_NAME>" --dir <PROJECT_DIR> \
  --template-dir "$OLD_TPL/template" \
  --path "$STAGE/old"
```

(Skip the old render in two-way fallback mode.)

### 4.4 Three-way comparison, per CDD-managed file

The CDD-managed set is what the template ships: `.claude/commands/*.md`, `.claude/settings.json`, `doc/index.md`, `doc/architecture/index.md`, `doc/features/index.md`, `doc/knowledge_base/README.md`. (The worktree helper is no longer part of this set — it is a single project-independent script installed once, not a per-project template file. `CLAUDE.md` and `doc/knowledge_base/roadmap.md` are project-owned content after bootstrap — leave them out unless a structural template change clearly applies, and then only with explicit per-file approval.)

For each file, with `old` = staged old render, `current` = staged current render, `target` = the project's file **read from `$WT`** (the section 2.5 worktree, which mirrors HEAD; this is why section 1 warns when CDD-managed files have uncommitted edits — those won't be reflected here):

| Comparison | Meaning | Action |
| --- | --- | --- |
| target == old, current != old | template evolved, project untouched | propose applying the upgrade (show the diff; apply on approval) |
| target != old, current == old | local customization, template unchanged | preserve; assess for upstreaming (4.5) |
| target != old, current != old | both changed | show both diffs; propose a merge that keeps the local intent while adopting the template improvement; apply on approval |
| all equal | nothing to do | skip silently |
| file absent in old render | newer than the project's baseline | propose adding it as a new file |
| file absent in target | project deleted it | ask: deliberate removal (respect it) or accident (restore)? |

Every application is per-file interactive: show the diff, get approval, write into `$WT`.

### 4.5 Upstream candidates

For each preserved local customization, judge whether it is project-specific (mentions the project's name/slug/domain, encodes its build commands) or **general** (a workflow improvement any CDD project would want). Do not silently keep general improvements local: collect them into a report — file, hunk, why it looks upstreamable — and present it at the end as candidates to port into `template/` (and the process doc) via a normal CDD task in this repo. Do not auto-apply anything to the CDD repo in this session.

### 4.6 Update the marker and commit

After all approved changes are applied, write the marker into the worktree (run `git rev-parse` from the CDD repo root, redirect into `$WT`):

```bash
git rev-parse HEAD > "$WT/.claude/cdd-baseline"
```

Then **commit on the retrofit branch** (skip if section 2.5 fell back to in-place writes with no branch):

```bash
git -C "$WT" add -A
git -C "$WT" commit -m "Upgrade CDD scaffolding to $(git rev-parse --short HEAD)" -m "<short body: files upgraded/merged/preserved>"
```

(The `$(git rev-parse --short HEAD)` runs in the CDD repo before `-C "$WT"` takes effect — capture it into a variable first if needed.) Commit only on this dedicated branch; never onto the target's existing branches. Then clean up `$STAGE` and `$OLD_TPL`.

## 5. Summary

Report, in both modes:

- Mode detected, identifiers used.
- The isolation: the worktree path (`$WT`), the branch name, and the commit hash made on it — or, if section 2.5 fell back, that writes landed in place with no commit and why.
- Files copied / upgraded / merged / preserved (and any the user declined).
- The marker value written.
- Upstream candidates surfaced (upgrade mode), with a pointer to file them as a roadmap item in the CDD repo.
- Any gitignore warnings from step 1.
- The next steps for the user: review the retrofit branch and open a PR from it; remove the worktree once merged (`git -C <target> worktree remove "$WT"`); `/cdd-next-step` for fresh installs — noting that for a first-time install without prior doc discipline that first `/cdd-next-step` is a doc reconciliation that may be slow and span several early PRs (expected, not a fault).
