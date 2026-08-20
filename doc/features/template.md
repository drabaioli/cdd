# The template

A copy-paste directory (`template/`) plus a non-interactive bootstrap script (`tools/bootstrap-cdd-project.sh`) that together start a new project on CDD. Template contents:

- `CLAUDE.md` skeleton with placeholders for project-specific content.
- `.claude/commands/{next-step,pre-pr,merge-main,process-pr}.md`: the four slash commands.
- `.claude/settings.json`: auto-allows worktree sessions to read their handoff file (`~/.cdd/handoffs/<PROJECT_DIR>/**`, substituted at bootstrap) and to run the `cdd-state` helper that maintains the colocated per-task state record.
- `doc/index.md` plus `doc/{architecture,features,knowledge_base}/`: the documentation map and doc directory skeletons; the architecture and features skeletons follow the index-plus-per-topic-docs convention.
- `doc/knowledge_base/project-overview.md`: the project-charter skeleton (what it is, goals, what it does and does not do, constraints, architecture intentions) — a living document, kept current. Filled by `/cdd-bootstrap` from discovery, or by hand otherwise.
- `doc/knowledge_base/roadmap.md`: roadmap skeleton with a pre-filled Phase 1 of CDD bootstrap tasks (codebase survey, initial architecture and feature docs, CLAUDE.md and overview stubs, engineering-practices fill, roadmap fill) plus a suggested-infrastructure task list (CI, linting, tests, …) to distribute across the project's real phases. The pre-filled phase serves files-only starts (`/cdd-retrofit` install + the manual script); `/cdd-bootstrap` writes those docs through discovery and ships a real roadmap without it.
- `doc/knowledge_base/engineering-practices.md`: the engineering-practices contract skeleton — each practice marked *enforced* (a CDD gate guarantees it) or *expected* (committed, tracked on the roadmap until mechanized), with placeholders for the project's own test/CI/lint commands. Resolved at project start: through `/cdd-bootstrap`'s discovery on the guided path, through the template roadmap's pre-filled bootstrap phase on a files-only start.
- `BOOTSTRAP.md`: meta-documentation for the bootstrap recipe. Not copied into the bootstrapped tree.

The template ships no shell helpers: the worktree helper (`tools/cdd-worktree.sh`) and the task-state helper (`tools/cdd-state.sh`) are project-independent scripts in the CDD repo that the user installs once, not per-project copies.

The bootstrap script substitutes the two identifiers (`<PROJECT_NAME>`, `<PROJECT_DIR>`), writes the baseline marker `.claude/cdd-baseline` (the CDD repo commit the template was rendered from), runs `git init`, and creates the scaffold commit. It also offers a render-only mode (`--stage`, with `--dir` and `--template-dir` overrides) that skips the git steps; `/cdd-retrofit` drives it. The `template-smoke` GitHub Actions workflow exercises the script on every PR — including a staged render — and asserts that the bootstrapped tree has no stale placeholders, no dangling internal links, and a well-formed marker. It does so through `scripts/ci.sh`, the check runner that is the single source of this repo's gate sequence and is also what `/cdd-pre-pr` invokes locally.

Audience: developers starting a new project who have decided to use CDD.

## The `/cdd-bootstrap` command

A CDD-repo-only slash command (`.claude/commands/cdd-bootstrap.md`, deliberately not shipped in the template) for starting a new greenfield project on CDD. Run from a CDD-repo session with no argument — the project's name, slug, directory, and target location all emerge from the conversation — it is a **guided** session rather than a brief-to-files converter: a discovery conversation defines the project (what it is, goals, non-goals, constraints, architecture intentions, audience), and from that it produces the project overview, a filled-in `CLAUDE.md`, a resolved engineering-practices contract, and a draft roadmap — each confirmed with the user, along with the target path (defaulting to `$HOME/Code/<PROJECT_DIR>`), before anything is rendered. It then writes those artifacts into a staging overlay and runs `bootstrap-cdd-project.sh --overlay` once (the `demo/setup.sh` path), so the filled docs land in the initial scaffold commit. Because the docs are written through discovery, the generated roadmap starts at the project's real first phase and carries no pre-filled survey phase. Optionally creates and pushes a GitHub repo on explicit confirmation.

Audience: developers starting a new project who want a guided setup rather than the manual `bootstrap-cdd-project.sh` recipe.

## The `/cdd-retrofit` command

A CDD-repo-only slash command (`.claude/commands/cdd-retrofit.md`, deliberately not shipped in the template) for bringing CDD to projects that already exist. Run from a CDD-repo session with the target path as argument, it auto-detects between two modes:

- **Install** — the target has no CDD scaffolding: a files-only install of the template via the bootstrap script's stage mode. Missing files are copied; collisions (an existing `CLAUDE.md`, say) are merged interactively per file. The codebase survey, initial architecture doc, and roadmap generation arrive as the template roadmap's pre-filled bootstrap tasks, which the project's first `/cdd-next-step` proposes as the first task.
- **Upgrade** — the target already runs CDD: a three-way comparison anchored on the `.claude/cdd-baseline` marker applies template improvements, preserves local customizations, and surfaces general-looking local improvements as candidates to upstream into the CDD repo. Files the template has newly accrued since the baseline are reconciled rather than shipped raw — obvious fields (test/lint/CI commands, enforced-vs-expected markers) filled from the project's detected state under per-file approval, with any file still carrying residual placeholders flagged in the summary as "needs reconciliation." Pre-marker projects fall back to two-way diffing and get the marker going forward.

In both modes the writes are isolated: before rendering anything, the command creates a dedicated branch (`cdd-retrofit`) and a sibling worktree off the target's HEAD, directs every write there, and makes a single commit on the branch — so the user reviews and merges the scaffolding through a normal PR instead of finding it strewn across the current branch. A dirty target tree no longer blocks the retrofit (the worktree is taken from HEAD); the command only warns when CDD-managed files have uncommitted edits, since those won't be seen by the upgrade comparison. If the target is not a git repo (or the worktree can't be created), it warns and falls back to writing in place. The recommended path before opening the PR is a fresh session in the retrofit worktree running `/cdd-pre-pr`, so the retrofit's own edits get the standard reconciliation pass — this is how a newly-added skeleton doc left with unfilled placeholders gets caught before review.

Audience: maintainers adopting CDD on an existing codebase, and maintainers keeping CDD projects in sync with template improvements.

### Where retrofitting actually costs

The `/cdd-retrofit` session itself is cheap — it installs or upgrades files. The cost lands on the **first few PRs afterward**, as the project's architecture and feature docs are forced to reflect reality for the first time. That reconciliation is deliberately not done during `/cdd-retrofit` (that session is context-heavy; surveying the docs needs its own focused session): it is deferred to the project's first `/cdd-next-step`, which picks up the template roadmap's pre-filled "CDD bootstrap" phase. For a greenfield project those tasks are near-trivial; for an existing project without prior doc discipline they may span several heavier-than-usual early PRs before the docs and the code agree.

Two things temper this. First, the don't-disrupt-existing-docs stance: a retrofitted project often already has *some* documentation, and the first reconciliation should reconcile and adopt it into CDD's structure rather than overwrite it into the template layout — guidance, not an algorithm. Recurring shapes seen in practice (a seed set, not exhaustive):

- `doc/backend/` + `doc/frontend/` + a top-level `system-architecture.md` → `doc/architecture/`
- `future-work.md` / TODO / backlog doc → `roadmap.md`
- an oversized `CLAUDE.md` duplicating command/troubleshooting content → slim to pointers (per-session context cost)

Second, the cost is a **first-time** cost: an upgrade retrofit can assume the discipline already holds — its docs already track the code — so the heavy reconciliation does not recur. Only a first-time install faces the full bill.

## The `/cdd-quick-create` command

A CDD-repo-only slash command (`.claude/commands/cdd-quick-create.md`, deliberately not shipped in the template) for producing a small, self-contained deliverable — a script plus a README — without any of the project substrate (no roadmap, no `doc/` tree, no worktree helper, no baseline marker, no `/cdd-pre-pr` lifecycle). It is the third sibling of `/cdd-bootstrap` and `/cdd-retrofit`, but unlike them it needs **neither** `template/` nor the bootstrap script: a one-off has no template, so it writes plain files directly into the target. Run from a CDD-repo session with an optional one-line description, it is a **guided but deliberately lighter** session: a scope check against the shared deliverable-or-project heuristic (below), a few discovery questions (what / goal / non-goals), then a files-first write of the artifact(s) and a focused README into the target (default: a sibling of the CDD repo). A smoke test, a local commit, and a GitHub repo are each offered separately and never done by default. The engineering floor is a focused README and clean single-purpose code (required); declaring dependencies inline where the language supports it (e.g. PEP723), a quick smoke run, and a license/authorship header are offered, not forced. If a deliverable later grows into a project, `/cdd-retrofit` can install CDD onto it.

Audience: developers who want a one-off artifact produced with a little guided discipline, without committing to the full CDD project lifecycle.

### Deliverable or project? The shared scope-triage heuristic

Both `/cdd-quick-create` and `/cdd-bootstrap` apply the same heuristic to decide which of them a task deserves. A task is a **project** (use `/cdd-bootstrap`) when any of these hold: it is expected to evolve across many sessions and needs a roadmap to track phases; it has more than one cooperating component, or an architecture worth documenting; it involves multiple collaborators or handoffs; it is long-lived and will accrete features over time. A task is a **deliverable** (use `/cdd-quick-create`) when none of those hold: a single self-contained artifact, finished in essentially one sitting, used as-is by future-you.

The heuristic runs in both directions as an off-ramp: `/cdd-quick-create` checks it early and, if project-signals trip, surfaces them and offers to switch to `/cdd-bootstrap`; `/cdd-bootstrap`'s discovery does the inverse, offering to drop to `/cdd-quick-create` when the task turns out to be a trivial single artifact. As with every structural choice in CDD, the human decides at the checkpoint — the command surfaces the signals and recommends, it does not switch unilaterally.
