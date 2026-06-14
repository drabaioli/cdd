# Bootstrap & retrofit pipeline

All template rendering flows through a single code path: `bootstrap-cdd-project.sh`. Nothing else reimplements placeholder substitution.

(The third CDD-repo-only command, `/quick-create`, is deliberately *not* part of this pipeline: it produces a one-off deliverable by writing plain files directly, with no `template/`, no substitution, and no scaffold commit, so it never touches the bootstrap script. It is documented with its siblings in the [overview](overview.md) and the [feature doc](../features/template.md).)

Like `demo/setup.sh`, `/retrofit` does not duplicate substitution logic: its install mode drives `bootstrap-cdd-project.sh --stage`, a render-only mode (no `git init`, no scaffold commit) that stages a fully substituted template tree which the command then merges into the target interactively. Its upgrade mode additionally uses `--template-dir` to render an old template snapshot through the same single code path.

`/bootstrap` (greenfield) also routes through the script, but via the `demo/setup.sh` path rather than the retrofit path: it writes the guided-discovery artifacts (project overview, filled `CLAUDE.md`, real roadmap) into a staging overlay and runs `bootstrap-cdd-project.sh --overlay` once, in normal mode. The overlay overrides the template stubs before substitution, so `git init` + the scaffold commit capture the filled-in docs — no `--stage`, no post-hoc copying.

The bootstrap script writes a one-line baseline marker, `.claude/cdd-baseline` (the CDD repo commit the template was rendered from), into every bootstrapped or staged tree; upgrade mode uses it as the three-way merge base for distinguishing template evolution from local customization.

`/retrofit` isolates its writes from the target's current checkout: before rendering, it creates a dedicated `cdd-retrofit` branch and a sibling worktree off the target's HEAD, writes everything there, and makes a single commit on the branch for the user to review and merge via PR. This is the one place CDD runs history-mutating git inside a target, and it is scoped to the dedicated branch only — never the target's existing branches. When the target is not a git repo, or has no commits, or the worktree can't be created, the command warns and degrades (a plain branch in the existing checkout, or in-place writes with no commit).
