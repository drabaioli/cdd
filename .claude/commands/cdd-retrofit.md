Install CDD into an existing project, or upgrade a project already running CDD, at the path given as argument: `/cdd-retrofit <target-path>`.

Run this command from a CDD-repo session (it needs the CDD repo's `template/`, `bootstrap-cdd-project.sh`, and git history). The mode — **install** or **upgrade** — is auto-detected from the target. This command exists only in the CDD repo; it deliberately has no counterpart in `template/.claude/commands/` (it operates *on* target projects, so downstream projects have no use for it — see the process doc, Section 2.7).

**Checkpoint discipline:** nothing is written before the user has seen it. Clean, mechanical writes are collected into one batch, shown once before anything is written, and applied on a single approval; everything that needs judgement is approved per file (section 2.7). Never overwrite a project file silently. Identifier choices (name/slug/dir) are confirmed before anything is rendered. One approval is enough for the batch because every write lands on the dedicated retrofit branch (section 2.5) and reaches the project only through `/cdd-pre-pr` and a PR.

Target path: `$ARGUMENTS`

## 1. Resolve and validate the target

Resolve the argument to an absolute path. It must exist and be a directory; otherwise stop and report.

Check the target's git state:

```bash
git -C <target> rev-parse --is-inside-work-tree 2>/dev/null
git -C <target> status --porcelain 2>/dev/null
```

- If the target is not a git repo, warn the user (retrofit changes won't be revertable via git, and the isolated-worktree step in section 2.5 won't run) and ask whether to proceed.
- A **dirty working tree no longer blocks the retrofit**: section 2.5 writes into a fresh worktree branched from HEAD, so the target's current checkout is untouched. Do *not* hard-stop on a dirty tree. There is one nuance to warn about: because the worktree is taken from HEAD, any **uncommitted local edits to the files the template ships** (the two sets listed in section 4.4) are invisible to the upgrade comparison. If `git status --porcelain` shows uncommitted changes to those files, tell the user to commit them first or they won't be considered, then let them decide whether to proceed.

Also note `<target>/.gitignore`: if any path the retrofit will write (`.claude/`, `doc/`, `tools/`) is gitignored, warn that those writes will not show in `git status` (and won't be staged by the retrofit commit in sections 3.4 / 4.7), and include this in the final summary.

## 2. Detect the mode

Probe for CDD scaffolding in the target:

```bash
ls <target>/.claude/commands/cdd-next-step.md <target>/doc/knowledge_base/roadmap.md 2>/dev/null
```

- Either file present → **upgrade mode** (section 4). Check its baseline marker now, against section 4.1: an unusable one stops the run here, before section 2.5 creates anything.
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
  - Target is **not a git repo** (from section 1) → no worktree possible. Warn, set `$WT` = `<target>` (in-place writes, today's behavior), and **skip the commit step** in sections 3.4 / 4.7.
  - Target git repo has **no commits / unborn or detached HEAD** (`worktree add -b` fails) → warn and fall back to a plain `git -C <target> switch -c "$BRANCH"` in the existing checkout, with `$WT` = `<target>`; if even that fails, fall back to in-place writes and skip the commit step.

## 2.6 Capability bindings

Both modes offer a `.cdd/tracker` / `.cdd/code-host` binding to a shipped adapter (process doc Section 2.16), for each capability the project does not already bind. Detect the backends and show the evidence with each proposal:

```bash
git -C <target> remote get-url origin 2>/dev/null
git -C <target> log -n 500 --format='%D %s %b'
```

- **Origin host** containing `github` → propose GitHub for both. Containing `gitlab` → propose GitLab for both, deriving `--gitlab-url https://<host>` and `--gitlab-project <path>` from the remote (`git@host:grp/proj.git`, `ssh://git@host[:port]/grp/proj.git`, `https://host/grp/proj.git`: strip `.git`, drop an SSH port — the API is on the web host; for an `http(s)` remote ask whether a leading path segment is the instance's sub-path root rather than a group). Never ask for a credential: the user sets `GITLAB_TOKEN` in their own shell. Another host → ask which backend it is (it may be a self-managed GitLab); for a backend CDD ships no adapter for (Bitbucket, …) say in one line that no binding is written and the commands needing it skip. No origin → ask, as `/cdd-bootstrap` does.
- **Jira** → a key prefix recurring in branch names or commit subjects (`ABC-123`, several distinct numbers, not look-alikes like `UTF-8`) proposes the Jira tracker with that key; take the site from any `atlassian.net` URL, otherwise ask. Never ask for a credential: the user sets `JIRA_EMAIL` and `JIRA_API_TOKEN` in their own shell.

Approve each binding as its own file, render it with the matching flags on the section 3.2 / 4.3 render (never hand-write one), and never overwrite an existing `.cdd/<capability>`.

## 2.7 The batch and the per-file queue

Both modes write in the same shape. Sections 3 and 4 say which of their writes are batch entries and which are per-file items; this section is how both are presented and applied.

**Classify first, write nothing.** Walk every proposed write and sort it into the batch or the per-file queue before touching `$WT`. Two answers are taken before classification, because they decide what gets rendered or compared: the section 2.6 binding approvals and the section 4.4 rename pre-pass. Their writes (the `git mv`, the shim copy) run with the others, the `git mv` first.

**Show the batch once, before any write.** One line per entry — the path and its kind:

- install mode: `new`, `settings union`;
- upgrade mode: `upgrade`, `new`, `new (filled: <fields>)`, `auto-merged`, `no-op: <why>`.

Group the `auto-merged` entries apart from the rest — they are the only entries a merge produced rather than copied. A `no-op` entry writes nothing: it is a template change to a project-owned file that carries nothing for this project (section 4.4), listed so that it is seen rather than skipped. Put any caveat on the line under its entry (the section 3.3 `WebFetch` line, for one). End with how many per-file questions follow.

**One approval writes the whole batch into `$WT`.** Before answering, the user may ask for any entry's diff, or pull entries out — each pulled entry joins the per-file queue. Declining the batch sends every entry to the per-file queue, never drops it. An empty batch is one line saying so, then straight to the queue.

**Then the per-file queue, one file at a time:** show the diff (or both versions), propose, write into `$WT` on approval. The queue holds exactly:

- merge conflicts (section 4.4);
- files the project deleted (section 4.4);
- new files still carrying residual `<...>` placeholders after the best-effort fill (section 4.4);
- local hunks that swap in another backend — migrate into `.cdd/` (section 4.4);
- template changes to a project-owned file the project has also changed — `CLAUDE.md`, the roadmap, the filled-in knowledge-base docs (section 4.4);
- template renames (section 4.4) — asked before the batch, above, not again;
- legacy-sweep patches and the legacy helper (section 4.5);
- capability bindings (section 2.6) — asked before the batch, above, not again;
- install-mode collisions other than `.claude/settings.json` — `CLAUDE.md`, pre-existing `doc/` files, anything else (section 3.3);
- anything the user pulled out of the batch.

Whatever the queue leaves un-upgraded — a declined question, a deleted file left deleted — is listed as **behind the template** in section 5. Nothing stays at an older template version without being named.

A conflict-free merge can still be semantically wrong — two hunks that never touch the same lines can contradict each other — which is why `auto-merged` is its own kind; the PR is the backstop.

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
  --path "$STAGE/render" \
  --tracker github --code-host github   # the bindings approved per section 2.6; omit any declined
```

The staging tree is fully substituted, has no `.git`, and contains the baseline marker `.claude/cdd-baseline`, plus a `.cdd/<capability>` shim for each binding passed.

### 3.3 Copy staging → worktree

Walk every file in `$STAGE/render` and classify it (section 2.7). All writes go into `$WT` (the isolated worktree from section 2.5), and presence is judged against `$WT` — which, for a fresh worktree, mirrors the target's HEAD:

- **Absent in `$WT`** → batch entry `new` (copied with parent dirs created as needed). This covers the slash commands, the agent definitions, doc skeletons, `.claude/settings.json`, and the marker in the common case. A `.cdd/<capability>` binding is the exception: it is copied only under its own approval, and never over an existing one (section 2.6).
- **`.claude/settings.json` present in `$WT`** → batch entry `settings union`: merge the `permissions.allow` arrays and the `permissions.deny` arrays (each a union), and add the template's `hooks.PreToolUse` entries the project lacks, keeping its own. The merged result must still parse (`jq empty`); if it does not, it goes per file. If the project allows `WebFetch` outright, put one line under the entry saying this pre-approves every session's fetches, not only the researcher's, and leave the choice to the user.
- **Any other file present in `$WT`** (collision — typically `CLAUDE.md`, sometimes `doc/` files) → per file:
  - `CLAUDE.md`: keep the project's existing content; propose adding the CDD pieces it lacks (the Key references table rows for `doc/`, and the Workflow section referencing `/cdd-next-step`, `/cdd-pre-pr`, `/cdd-merge-base`). Show the proposed result; apply only on approval.
  - Anything else: show both versions and propose the merge; the user decides per file.
- Never delete or move existing files.

Once every file is classified, apply section 2.7: show the batch, write it on approval, then walk the per-file queue.

### 3.4 Finish

- Remove `$STAGE`.
- **Commit on the retrofit branch** (skip this if section 2.5 fell back to in-place writes with no branch). The retrofit session holds the context for a good message, so write a real one:

  ```bash
  git -C "$WT" add -A
  git -C "$WT" commit -m "Install CDD scaffolding" -m "<short body: files added/merged>"
  ```

  Stage with `add -A` — the worktree was fresh, so this captures exactly the retrofit's writes. Gitignored paths won't be staged (see the section 1 gitignore warning). Commit only on this dedicated branch; never commit onto the target's existing branches.
- Print next steps: the one-time worktree-helper install (`./tools/cdd-worktree.sh install` in the CDD repo — project-independent, only needed if the user hasn't installed it before; nothing is added per project; re-run it if it predates the adapter library a `.cdd/` binding runs); how to review and merge the branch (`git -C "$WT" show`, then — before opening the PR — `cd "$WT"` and start a fresh Claude session there to run `/cdd-pre-pr`, which reconciles and reviews the retrofit's own edits and catches doc skeletons left with unfilled placeholders; then open a PR from `cdd-retrofit`); and that once merged they can remove the worktree with `git -C <target> worktree remove "$WT"`. Then run `/cdd-next-step` in the target — it will pick up the roadmap's pre-filled bootstrap tasks (codebase survey, initial architecture and feature docs, CLAUDE.md stubs, roadmap fill) as the first task. Warn the user: on an existing project without prior doc discipline this first task is a doc reconciliation that forces the docs to match the code for the first time, so it may be slow and span several early PRs — that is expected, not a fault. Where docs already exist, it reconciles and adopts them rather than overwriting; the roadmap's Phase 1 intro carries a seed set of common fold-in patterns (split architecture docs → `doc/architecture/`, a `future-work.md`/TODO/backlog doc → the roadmap, an oversized `CLAUDE.md` → slim to pointers) so the reconciliation session has them on hand.

## 4. Upgrade mode

Sync improvements the CDD template has accrued into the target **without changing the behavior of the project's current workflow**: local adaptations are preserved, and general-looking local improvements are surfaced as candidates to upstream into the CDD repo.

### 4.1 Establish the baseline

Read `$WT/.claude/cdd-baseline` (the section 2.5 worktree, which mirrors HEAD). It must name a commit in this CDD repo (`git cat-file -e <hash>^{commit}`): that commit is the merge base for the three-way comparison in section 4.4. Section 2 has already checked this against the target, before anything was created.

There is no fallback mode. A marker that is missing, reads `unknown` (the bootstrap script writes that when run from a copy of CDD that is not a git checkout), or names a commit this repo lacks stops the run. Say which in one line, with the fix:

- **Unknown commit:** `git fetch` in this CDD repo — the project may come from a newer commit than this checkout has — then rerun.
- **Missing or `unknown`:** write the CDD commit the project was bootstrapped or last upgraded from into `.claude/cdd-baseline` on the project's default branch, then rerun.

Never guess a baseline. Every project bootstrapped or upgraded since the marker was introduced carries one.

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
  --path "$STAGE/current" \
  --tracker github --code-host github   # the bindings approved per section 2.6; omit any declined
```

Binding flags go on this current render only, never the old one; bindings are proposed per section 2.6, not compared in section 4.4.

Old (baseline) template, extracted from this repo's history and rendered through the same substitution path:

```bash
OLD_TPL=$(mktemp -d)
git archive <baseline-hash> template | tar -x -C "$OLD_TPL"
./tools/bootstrap-cdd-project.sh --stage \
  --name "<PROJECT_NAME>" --dir <PROJECT_DIR> \
  --template-dir "$OLD_TPL/template" \
  --path "$STAGE/old"
```

### 4.4 Three-way comparison, per template file

Every file the template ships is compared, in one of two sets:

- **Project-owned** — the template files a project fills with its own content: `CLAUDE.md`, `doc/knowledge_base/roadmap.md`, `doc/knowledge_base/engineering-practices.md`, `doc/knowledge_base/project-overview.md`.
- **CDD-managed** — every other file the template ships. Today that is `.claude/commands/*.md`, `.claude/agents/*.md`, `.claude/settings.json`, the four `index.md` files under `doc/`, and `doc/architecture/adr/0000-template.md`. A file the template adds later joins this set by default.

(The worktree helper is in neither set: it is a single project-independent script installed once, not a per-project template file.)

**DEPRECATION SEAM — the plan/implement split reaches a project through the project-owned `CLAUDE.md` rule below the table; make sure that proposal carries it, and never list it as `no-op`. Delete this paragraph once every project has been retrofitted past the split — issue #90, which also covers the matching fallback in `cdd-worktree.sh`.** The upgrade adds `cdd-plan.md` and `cdd-implement.md` to `.claude/commands/` for free (they are absent from any older baseline render, so the "file absent in old render" row below covers them), but the procedure change is not a file change: a project whose `CLAUDE.md` Workflow section still describes a single implementation session ends up with the commands installed and nothing telling anyone to use them. So when the target's baseline predates the split — check whether `.claude/commands/cdd-plan.md` existed in it before this run — the `CLAUDE.md` proposal must include the Workflow edit: `cdd-worktree <branch>` now opens on `/cdd-plan`, which writes a plan file and stops, and a fresh session then runs `/cdd-implement`; and `cdd-worktree-resume` sends a task parked at `plan_written` to `/cdd-implement`. Take the current template's `CLAUDE.md` Workflow bullets as the wording to adapt.

**Template path renames.** A file the template renamed between the baseline and now is a rename, not a delete plus an add, but the table below has no rename row: run untreated, it asks whether the project deliberately deleted the old path, and offers the new one as a file a project that already renamed it by hand has. So resolve each row below against the target *first*, then compare on the new path only.

| Old path | New path | Landed in |
| --- | --- | --- |
| `doc/knowledge_base/README.md` | `doc/knowledge_base/index.md` | #73 |

- **old present, new absent** → propose `git -C "$WT" mv <old> <new>` under the usual per-file approval, then compare the new path. Take this answer before classifying anything; the `git mv` runs as the first write (section 2.7).
- **new present, old absent** → the project already renamed it; say so and compare the new path.
- **both present** → do not guess: report both and ask which to keep.
- **neither present** → fall through to the table's "file absent in target" row on the new path.

**Land a rename in the template, add a row** — the same rule §4.5 states for path tokens. Like §4.5's rows these are transitional; retire a row once every project is past it (#93 tracks the reaping).

For each file, with `old` = staged old render, `current` = staged current render, `target` = the project's file **read from `$WT`** (the section 2.5 worktree, which mirrors HEAD; this is why section 1 warns when CDD-managed files have uncommitted edits — those won't be reflected here):

| Comparison | Meaning | Action |
| --- | --- | --- |
| target == old, current != old | template evolved, project untouched | batch entry `upgrade` |
| target != old, current == old | local customization, template unchanged | preserve; assess for upstreaming (4.6) |
| target != old, current != old | both changed | three-way text merge (below): clean → batch entry `auto-merged` with the merged result; conflict → per file: show both diffs, propose a merge that keeps the local intent while adopting the template improvement, apply on approval |
| all equal | nothing to do | skip silently |
| file absent in old render | newer than the project's baseline | add it as a new file — batch entry `new`, or per file, per "Added files" below |
| file absent in target | project deleted it | per file — ask: deliberate removal (respect it) or accident (restore)? |

For a both-changed file, merge the template's change into the project's file without touching `$WT`:

```bash
mkdir -p "$(dirname "$STAGE/merged/<path>")"
git merge-file -p "$WT/<path>" "$STAGE/old/<path>" "$STAGE/current/<path>" > "$STAGE/merged/<path>"
```

`-p` prints the result instead of overwriting the target. Exit 0 means conflict-free; a positive exit is the number of conflicts, a negative one an error — either goes per file. A conflict-free result still goes per file when a local hunk is a backend swap (migrate into `.cdd/`, below), or when the path is `.claude/settings.json` and the result no longer parses (`jq empty`).

**Project-owned files** go through the same table, with two differences:

- **A both-changed one never auto-merges.** It goes per file: show the template's change (old → current render), propose how to carry it into the project's version, and apply on approval. A clean `git merge-file` result makes a fair first draft. The exception is a template change that touches only skeleton text the project has since replaced, such as a placeholder it filled or the pre-filled bootstrap phase its roadmap no longer has. That carries nothing, so list it in the batch as `no-op: <why>` instead of asking. When in doubt, ask.
- **Section 4.6 does not assess them:** their local content is the project's own by definition.

Batch rows are collected, not written. Once every file is classified, apply section 2.7: show the batch, write it on approval, then walk the per-file queue — show the diff, get approval, write into `$WT`.

**Migrate into `.cdd/` — the third verdict.** A local hunk (the "local customization" or "both changed" rows) that swaps `gh issue …` / `gh pr …` for another backend (`jira`, `acli`, `glab`, `curl …atlassian.net/…`) is a backend to bind, not a customization to keep. Check for it before a both-changed file can join the batch. Propose, per file: restore the template's hunk and bind the capability instead — a shipped adapter if CDD has one (section 2.6), otherwise a project adapter written against `doc/architecture/capability-adapters.md`. If declined, preserve it like any customization.

**Added files — reconcile fill-in skeletons, don't ship them raw.** A file absent from the old render is newer than the project's baseline, and it may be a fill-in skeleton whose placeholder defaults would make false claims about a mature project (the motivating case: `engineering-practices.md` arriving with `<test command>` / `<lint command>` / `<ci workflow / command>` placeholders and provisional `<Enforced once …; Expected until then>` markers, claiming no gate exists in a project that already runs pytest, ruff, and CI). For every file you propose adding:

- **Scan the staged render for residual `<...>` tokens.** The render already substituted the two identifiers (`<PROJECT_NAME>`/`<PROJECT_DIR>`), so any remaining `<...>` is genuine fill-in content — a placeholder field or a provisional status marker.
- **If it carries residual placeholders, reconcile before writing.** Make a best-effort pass to fill the fields you can confidently detect from the target's actual state. A file left with no residual placeholder joins the batch as `new (filled: <fields>)` (plain `new` if nothing needed filling); one still carrying residual placeholders is proposed per file. Keep this lightweight: fill what you can confidently detect and leave the rest — do **not** build a general reconciliation engine (`/cdd-pre-pr` is the systematic backstop). Never fabricate a value to clear a placeholder; if you can't confidently determine it, leave the placeholder and let the summary flag it.
- **Worked example — `engineering-practices.md`.** Fill `<test command>` / `<integration test command>` / `<lint command>` / `<format check command>` / `<ci workflow / command>` from the commands you can detect (a `Makefile`/`pyproject.toml`/`package.json` test or lint target, a test-runner or linter config), and flip each provisional status marker to **Enforced** or **Expected** according to whether that gate actually exists — CI judged by a `.github/workflows/*.yml`, tests/lint by the presence of the corresponding runner or linter config. Apply the same shape to any other added fill-in doc.
- Anything left unreconciled after the approved edit still counts as residual and is carried into the section 5 summary flag.

### 4.5 Legacy-token sweep and helper migration

Section 4.4 migrated the CDD-managed files; anything **else** naming a pre-migration path or command is now dangling and unlooked-at. So this sweep covers every tracked text file, not just `*.md` — `tools/*.sh` bites hardest, because the pre-#24 per-project worktree helper lives there. **Upgrade mode only:** an install target carries no CDD-era tokens, and a hand-copied CDD install is detected as *upgrade* anyway (section 2 keys on `cdd-next-step.md` / `roadmap.md`; its manual override is the escape hatch).

**DEPRECATION SEAM — every row below is transitional.** Retire a row once every project on every machine is past that migration; removal of these five is tracked by issue #93. The step outlives its rows — a future rename adds one — and stays CDD's per-project migration mechanism until issue #80's fleet-versioning layer subsumes it (process doc §6), so do not build version negotiation here. **Land a rename or a path migration in CDD, add a row**: this table is the whole of how that change reaches already-bootstrapped projects. (`/bootstrap`, `/retrofit` and `/quick-create` are deliberately absent: #27 renamed them too, but they have always been CDD-repo-only.)

| Legacy token | Migrated to | Landed in |
| --- | --- | --- |
| `~/.claude-handoffs/` | `~/.cdd/handoffs/` | #24 |
| `/next-step`, `/pre-pr`, `/merge-main`, `/process-pr` | the `cdd-` prefixed names | #27 |
| `/cdd-merge-main` | `/cdd-merge-base` | #31 |
| a project-local `<slug>-worktree` / `-done` / `-list` function, or `tools/<slug>-worktree.sh` | the machine-global `cdd-worktree` | #24 |
| `<PROJECT_SLUG>`, and the bare `PROJECT` substitution token (only ever seen as the `PROJECT-worktree` / `PROJECT-state` shell identifier) | the two-identifier model | #24 |
| `doc/knowledge_base/README.md` | `doc/knowledge_base/index.md` | #73 |

**Sweep.** Tracked files only, so `.git/` and gitignored paths are out of scope; `-I` skips binaries:

```bash
git -C "$WT" grep -nI -F -e '.claude-handoffs' -e 'PROJECT_SLUG' -e 'PROJECT-worktree' -e 'PROJECT-state' -e 'knowledge_base/README.md'
git -C "$WT" grep -nIE -e '(^|[^A-Za-z0-9_-])/(next-step|pre-pr|merge-main|process-pr|cdd-merge-main)([^A-Za-z0-9_/-]|$)'
ls "$WT"/tools/*-worktree.sh "$WT"/tools/*-state.sh 2>/dev/null   # the legacy helper may carry no token at all
```

Both narrowings are load-bearing: unbounded, the second pattern matches `css/bootstrap.min.css`-shaped paths, and bare `PROJECT` is swept only as an identifier because alone it is an ordinary English word. If `$WT` is **not a git repo** (section 2.5's fallback, or a hand-copied install), `git grep` fails outright — degrade rather than skip: rerun both as `grep -rnI ... "$WT"`, and report in section 5 that the sweep covered the whole tree, so gitignored and build-output paths may appear among the hits.

**Classify every hit; suppress none** — a hit you decide not to act on is still reported, because a misclassification is only recoverable while it is visible. **Actionable** (a live reference a project-owned script, doc or `.claude/settings.json` actually follows) → propose the patch, approved per file (section 2.7). **Historical** (a changelog, ADR or roadmap line *recording* the old name rather than using it) → report it, propose nothing, let the human judge. **Surviving in a CDD-managed file** → say so plainly: 4.4 should have migrated it, so that is a defect in this command, not in the project.

**The legacy worktree helper — the loudest hit.** If the `ls` probe finds one, the project predates the machine-global helper. State the recommendation, don't offer a neutral menu:

- **Recommended — retire it.** One install per machine, not one script per project: propose deleting it from `$WT`, and tell the user to run `./tools/cdd-worktree.sh install` and `./tools/cdd-state.sh install` once from the CDD repo — the installer also moves handoffs out of the old location, so nothing in flight is stranded. The shell rc sourcing line is outside this command's write scope: print the exact line to delete and let the user do it. **Never edit a user's shell rc.**
- **Decline path — patch it in place.** Under the usual per-file approval, reconcile the kept helper with the migrated scaffolding: the handoff directory, the command names it prints, and the `<branch>.state.json` sidecar beside the handoff (absent from any pre-#38 helper). Say plainly that it is now a maintained-by-hand path.

Either way it is an outcome, not a silent success — section 5 reports it.

### 4.6 Upstream candidates

For each preserved local customization in a CDD-managed file — including the local hunks an `auto-merged` file kept — judge whether it is project-specific (mentions the project's name/slug/domain, encodes its build commands) or **general** (a workflow improvement any CDD project would want). Do not silently keep general improvements local: collect them into a report — file, hunk, why it looks upstreamable — and present it at the end as candidates to port into `template/` (and the process doc) via a normal CDD task in this repo. A general one that reaches a backend CDD ships no adapter for (typically a declined "migrate into `.cdd/`" hunk) is instead a candidate to **propose as an extension**: a new shipped adapter, not a prompt change. Do not auto-apply anything to the CDD repo in this session.

### 4.7 Update the marker and commit

After all approved changes are applied, write the marker into the worktree (run `git rev-parse` from the CDD repo root, redirect into `$WT`):

```bash
git rev-parse HEAD > "$WT/.claude/cdd-baseline"
```

Then **commit on the retrofit branch** (skip if section 2.5 fell back to in-place writes with no branch):

```bash
git -C "$WT" add -A
git -C "$WT" commit -m "Upgrade CDD scaffolding to $(git rev-parse --short HEAD)" -m "<short body: files upgraded/merged/preserved, and the section 5 behind-the-template list>"
```

(The `$(git rev-parse --short HEAD)` runs in the CDD repo before `-C "$WT"` takes effect — capture it into a variable first if needed.) Commit only on this dedicated branch; never onto the target's existing branches. Then clean up `$STAGE` and `$OLD_TPL`.

## 5. Summary

Report, in both modes:

- Mode detected, identifiers used.
- The isolation: the worktree path (`$WT`), the branch name, and the commit hash made on it — or, if section 2.5 fell back, that writes landed in place with no commit and why.
- The files, in four lists kept apart:
  - **applied in the batch** — path and kind;
  - **approved individually** — path and what was done, including entries pulled out of the batch;
  - **preserved** — each local customization kept, with one line on what it changes;
  - **behind the template** — every file the template would have changed that this run left as it was: a declined question, a deleted file left deleted, a project-owned change not carried over. Give each one's reason.

  Print the last list even when it is empty ("none"). It is the only record: the marker still advances, so the next upgrade reads a declined change as a local customization. Section 4.7 copies it into the commit body for the same reason.
- **Added — needs reconciliation** (upgrade mode): any added file that still contains residual `<...>` placeholders or provisional status markers after all approved edits, listed by path. Keep this as a distinct category from clean adds so it reads as an action item, not a silent success — the user must finish these, and the recommended `/cdd-pre-pr` pass below will also catch them.
- **Legacy migration** (upgrade mode): the sweep's outcome as a distinct category — *swept* (what was found, including the historical hits deliberately left alone), *patched* (files brought back into agreement, listed), and *recommended for removal* (a project-local worktree/state helper, with the exact shell rc line the user still has to delete by hand). An empty sweep says so in one line. Keep it separate from the file lists above: a legacy hit the user declined is an action item they carry away, not a closed row.
- **Capability bindings**: each `.cdd/<capability>` written (with its evidence), declined, or already present; each "no adapter for this backend" line; any upgrade-mode "migrate into `.cdd/`" hunk and its outcome; for Jira, the env vars the user sets; and, if `~/.cdd/tools/adapters/<capability>/<backend>.sh` is missing on this machine, that the bound capability stops until `./tools/cdd-worktree.sh install` runs.
- The marker value written.
- Upstream candidates surfaced (upgrade mode), each with its destination (port into `template/`, or propose as an extension), with a pointer to file them as a roadmap item in the CDD repo.
- Any gitignore warnings from step 1.
- The next steps for the user: review the retrofit branch, then — before opening the PR — `cd "$WT"` and run `/cdd-pre-pr` from a fresh Claude session there (its reconciliation + review pass catches doc inconsistencies the retrofit introduced, in both modes); then open a PR from it; remove the worktree once merged (`git -C <target> worktree remove "$WT"`); `/cdd-next-step` for fresh installs — noting that for a first-time install without prior doc discipline that first `/cdd-next-step` is a doc reconciliation that may be slow and span several early PRs (expected, not a fault).
