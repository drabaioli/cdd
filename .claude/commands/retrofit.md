Install CDD into an existing project, or upgrade a project already running CDD, at the path given as argument: `/retrofit <target-path>`.

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

- If the target is not a git repo, warn the user (retrofit changes won't be revertable via git) and ask whether to proceed.
- If the working tree is **dirty**, warn and require an explicit go-ahead; recommend committing or stashing first so the retrofit's changes land in isolation and are reviewable.

Also note `<target>/.gitignore`: if any path the retrofit will write (`.claude/`, `doc/`, `tools/`) is gitignored, warn that those writes will not show in `git status`, and include this in the final summary.

## 2. Detect the mode

Probe for CDD scaffolding in the target:

```bash
ls <target>/.claude/commands/next-step.md <target>/doc/knowledge_base/roadmap.md 2>/dev/null
```

- Either file present → **upgrade mode** (section 4).
- Neither present → **install mode** (section 3).

State the detected mode and the evidence to the user before proceeding, and let them override if the detection is wrong (e.g. a half-finished previous install).

## 3. Install mode

A files-only install of the template. No codebase survey, no generated architecture doc or roadmap — the project's first `/next-step` proposes that as the first task (the template's survey hook fires when the docs are still skeletons).

### 3.1 Confirm the three identifiers

Propose, then confirm with the user before rendering (never pick silently):

- `<PROJECT_DIR>` — basename of the target path. Must match `^[a-z][a-z0-9_-]*$`; if it doesn't, ask the user for a conforming value (this only affects rendered paths like the handoff dir, not the actual directory name).
- `<PROJECT_SLUG>` — propose the dir slug, sanitized to `^[a-z][a-z0-9_-]*$`. This becomes the `<slug>-worktree` command the user will type; let them shorten it.
- `<PROJECT_NAME>` — propose a title-cased form of the directory name; free text.

### 3.2 Render the template into a staging directory

Reuse the bootstrap script's substitution — do not reimplement it:

```bash
STAGE=$(mktemp -d)
./bootstrap-cdd-project.sh --stage \
  --name "<PROJECT_NAME>" --slug <PROJECT_SLUG> --dir <PROJECT_DIR> \
  --path "$STAGE/render"
```

The staging tree is fully substituted, has no `.git`, and contains the baseline marker `.claude/cdd-baseline`.

### 3.3 Copy staging → target, per file

Walk every file in `$STAGE/render`:

- **Absent in the target** → copy it directly (create parent dirs as needed). This covers the slash commands, doc skeletons, the worktree helper, `.claude/settings.json`, and the marker in the common case.
- **Present in the target** (collision — typically `CLAUDE.md`, sometimes `doc/` files or `.claude/settings.json`) → propose a merge interactively, one file at a time:
  - `CLAUDE.md`: keep the project's existing content; propose adding the CDD pieces it lacks (the Key references table rows for `doc/`, and the Workflow section referencing `/next-step`, `/pre-pr`, `/merge-main`). Show the proposed result; apply only on approval.
  - `.claude/settings.json`: merge the `permissions.allow` arrays (union); show the result before writing.
  - Anything else: show both versions and propose the merge; the user decides per file.
- Never delete or move existing target files.

### 3.4 Finish

- Remove `$STAGE`.
- Do **not** run any git commands in the target (the project owns its git history); suggest the user review and commit the new files themselves.
- Print next steps, mirroring the bootstrap script's output: the exact `source` line for `<target>/tools/<PROJECT_SLUG>-worktree.sh` to add to `~/.bashrc`; fill in any `CLAUDE.md` stubs; then run `/next-step` in the target — it will propose the codebase survey + initial architecture doc + roadmap generation as the first task.

## 4. Upgrade mode

Sync improvements the CDD template has accrued into the target **without changing the behavior of the project's current workflow**: local adaptations are preserved, and general-looking local improvements are surfaced as candidates to upstream into the CDD repo.

### 4.1 Establish the baseline

Read `<target>/.claude/cdd-baseline`.

- **Present and a valid commit in this CDD repo** (`git cat-file -e <hash>^{commit}`) → three-way mode.
- **Missing, `unknown`, or not a known commit** → pre-marker fallback: two-way mode (target vs. current template only), where *every* difference is presented to the user to classify as "apply the template's version", "keep local", or "merge". Be conservative; when in doubt, keep local. The marker is written at the end regardless, so the next upgrade gets the three-way path.

### 4.2 Recover the target's identifiers

The marker stores only the hash, so re-infer and confirm with the user:

- `<PROJECT_SLUG>`: from the worktree helper filename `<target>/tools/*-worktree.sh` (most reliable); fall back to asking.
- `<PROJECT_DIR>`: basename of the target path.
- `<PROJECT_NAME>`: from the title of `<target>/CLAUDE.md` if recognizable; otherwise ask.

### 4.3 Render both template versions with the target's identifiers

Current template:

```bash
STAGE=$(mktemp -d)
./bootstrap-cdd-project.sh --stage \
  --name "<PROJECT_NAME>" --slug <PROJECT_SLUG> --dir <PROJECT_DIR> \
  --path "$STAGE/current"
```

Old (baseline) template, extracted from this repo's history and rendered through the same substitution path:

```bash
OLD_TPL=$(mktemp -d)
git archive <baseline-hash> template | tar -x -C "$OLD_TPL"
./bootstrap-cdd-project.sh --stage \
  --name "<PROJECT_NAME>" --slug <PROJECT_SLUG> --dir <PROJECT_DIR> \
  --template-dir "$OLD_TPL/template" \
  --path "$STAGE/old"
```

(Skip the old render in two-way fallback mode.)

### 4.4 Three-way comparison, per CDD-managed file

The CDD-managed set is what the template ships: `.claude/commands/*.md`, `.claude/settings.json`, `doc/architecture/index.md`, `doc/features/index.md`, `doc/knowledge_base/README.md`, `tools/<slug>-worktree.sh`. (`CLAUDE.md` and `doc/knowledge_base/roadmap.md` are project-owned content after bootstrap — leave them out unless a structural template change clearly applies, and then only with explicit per-file approval.)

For each file, with `old` = staged old render, `current` = staged current render, `target` = the project's file:

| Comparison | Meaning | Action |
| --- | --- | --- |
| target == old, current != old | template evolved, project untouched | propose applying the upgrade (show the diff; apply on approval) |
| target != old, current == old | local customization, template unchanged | preserve; assess for upstreaming (4.5) |
| target != old, current != old | both changed | show both diffs; propose a merge that keeps the local intent while adopting the template improvement; apply on approval |
| all equal | nothing to do | skip silently |
| file absent in old render | newer than the project's baseline | propose adding it as a new file |
| file absent in target | project deleted it | ask: deliberate removal (respect it) or accident (restore)? |

Every application is per-file interactive: show the diff, get approval, write.

### 4.5 Upstream candidates

For each preserved local customization, judge whether it is project-specific (mentions the project's name/slug/domain, encodes its build commands) or **general** (a workflow improvement any CDD project would want). Do not silently keep general improvements local: collect them into a report — file, hunk, why it looks upstreamable — and present it at the end as candidates to port into `template/` (and the process doc) via a normal CDD task in this repo. Do not auto-apply anything to the CDD repo in this session.

### 4.6 Update the marker

After all approved changes are applied:

```bash
git rev-parse HEAD > <target>/.claude/cdd-baseline
```

(Run from the CDD repo root.) Clean up `$STAGE` and `$OLD_TPL`.

## 5. Summary

Report, in both modes:

- Mode detected, identifiers used.
- Files copied / upgraded / merged / preserved (and any the user declined).
- The marker value written.
- Upstream candidates surfaced (upgrade mode), with a pointer to file them as a roadmap item in the CDD repo.
- Any gitignore warnings from step 1.
- The next command for the user to run (review + commit in the target; `/next-step` for fresh installs).
