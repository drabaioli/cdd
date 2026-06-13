# Bootstrap & retrofit pipeline

All template rendering flows through a single code path: `bootstrap-cdd-project.sh`. Nothing else reimplements placeholder substitution.

Like `demo/setup.sh`, `/retrofit` does not duplicate substitution logic: its install mode drives `bootstrap-cdd-project.sh --stage`, a render-only mode (no `git init`, no scaffold commit) that stages a fully substituted template tree which the command then merges into the target interactively. Its upgrade mode additionally uses `--template-dir` to render an old template snapshot through the same single code path.

`/bootstrap` (greenfield) also routes through the script, but via the `demo/setup.sh` path rather than the retrofit path: it writes the guided-discovery artifacts (project overview, filled `CLAUDE.md`, real roadmap) into a staging overlay and runs `bootstrap-cdd-project.sh --overlay` once, in normal mode. The overlay overrides the template stubs before substitution, so `git init` + the scaffold commit capture the filled-in docs — no `--stage`, no post-hoc copying.

The bootstrap script writes a one-line baseline marker, `.claude/cdd-baseline` (the CDD repo commit the template was rendered from), into every bootstrapped or staged tree; upgrade mode uses it as the three-way merge base for distinguishing template evolution from local customization.
