Scaffold a new greenfield project on the CDD workflow: `/cdd-bootstrap` (takes no argument).

Run this command from a CDD-repo session (it needs the CDD repo's `template/` and `bootstrap-cdd-project.sh`). This command exists only in the CDD repo; it deliberately has no counterpart in `template/.claude/commands/` (it operates *on* a new target project, so downstream projects have no use for it — see the process doc, Section 2.7). It is the greenfield sibling of `/cdd-retrofit`: `/cdd-retrofit` adapts an *existing* project, `/cdd-bootstrap` creates a *new* one.

This is a **guided** command, not a brief-to-files converter. The discovery conversation is part of the job: you walk the user through defining the project, then encode the result into the initial docs and roadmap, then scaffold the project in a single bootstrap invocation. The generated project starts with a real, filled-in overview, `CLAUDE.md`, and roadmap — not the template's pre-filled "survey the codebase" bootstrap phase, which is for files-only installs.

The command takes **no argument**: the project's name, slug, directory, and location all emerge from the discovery conversation, so there is nothing meaningful to pass up front. The target path is proposed and confirmed in step 4, once the identifiers are settled.

**Checkpoint discipline:** confirm the project definition (step 1), then the draft roadmap (step 2), then the three identifiers and the target location (steps 3–4) — each before moving on. Nothing is rendered until all are approved. The scaffold commit is created only after the roadmap is approved. Outward-facing actions (creating a GitHub repo, editing `~/.bashrc`) are confirmed separately and never done silently.

## 1. Guided discovery

Have a conversation to define the project. Do not dump a rigid questionnaire; ask in natural batches, probe vague or one-word answers, and reflect back what you heard. Cover, at minimum:

- **What it is** — one paragraph, plain terms.
- **Goals** — why it exists; the problem it solves or outcome it produces; what success looks like.
- **What it does** — the high-level capabilities, coarse-grained.
- **What it explicitly does not do** — the non-goals. Push for these; they are load-bearing and easy to skip.
- **Constraints** — language/platform, hard technical limits, regulatory/business constraints, compatibility, deadlines.
- **Architecture intentions** — intended high-level shape: major components, how they relate, external boundaries, structural principles the project commits to.
- **Audience** — who consumes it (end users, other services, a team, future-you).

The user may not have firm answers for everything; capture intent and mark genuinely open areas rather than inventing detail. This material becomes the project overview (`doc/knowledge_base/project-overview.md`) and seeds `CLAUDE.md`.

**Off-ramp:** if discovery reveals this isn't really a project — a single self-contained artifact, finished in essentially one sitting, used as-is by future-you — apply the shared scope-triage heuristic (process doc, Section 6) and **offer to drop to `/cdd-quick-create`** instead of scaffolding the full substrate. Surface the signals; the human decides.

**Checkpoint:** present a structured summary of the captured definition (the seven headings above). Get explicit confirmation or corrections before writing anything.

## 2. Draft the initial roadmap

From the discovery, propose a thin but real roadmap: three to five phases, a handful of tasks each, every phase ending in a milestone statement. Slot in the template's suggested infrastructure tasks (CI, linting, tests, README, dependency pinning, release/versioning) where they fit the early phases.

Do **not** include the template's pre-filled "Phase 1: CDD bootstrap" survey phase. That phase exists for files-only starts where the docs haven't been written; here you are writing the docs through this conversation, so the roadmap starts at the project's real first phase.

Keep the roadmap's "Annotation conventions" and "Key principles" scaffolding from the template (adapt the principles to the project, or leave a short placeholder).

**Checkpoint:** show the drafted roadmap; the user approves or edits it. It is approved *now*, before the scaffold, because it will be committed as part of the initial scaffold commit (step 6) — there is no separate post-commit edit pass.

## 3. Confirm the three identifiers

Propose, then confirm with the user before rendering (never pick silently — see the three-identifier model, process doc Section 2.9):

- `<PROJECT_NAME>` — the display name from discovery; free text, may contain spaces.
- `<PROJECT_SLUG>` — a shell-safe slug derived from the name, matching `^[a-z][a-z0-9_-]*$`. This becomes the `<slug>-worktree` command the user will type; let them shorten it.
- `<PROJECT_DIR>` — the directory / repo slug, matching `^[a-z][a-z0-9_-]*$`. Propose the slug; let it differ if the user wants a more verbose directory name.

**Checkpoint:** confirm all three before proceeding.

## 4. Confirm the target location

The path is derived, not passed in. Propose the CDD convention `$HOME/Code/<PROJECT_DIR>` as the default and let the user override (the basename should match `<PROJECT_DIR>`, since the worktree helper and handoff paths assume it).

The bootstrap script refuses a path that already exists and is non-empty, so check before staging:

```bash
[[ -e "<target>" && -n "$(ls -A "<target>" 2>/dev/null)" ]] && echo "exists and non-empty"
```

If it exists and is non-empty, stop and ask for a different location — `/cdd-bootstrap` is for greenfield. (Suggest `/cdd-retrofit` if the user actually meant to install CDD into an existing project.) An absent path or an empty directory is fine.

**Checkpoint:** confirm the target path before staging the overlay.

## 5. Stage the overlay

Build a staging directory that mirrors the template layout and holds the filled-in artifacts. The bootstrap script applies it over the template before substitution, so these files override the template stubs:

```bash
OVERLAY=$(mktemp -d)
mkdir -p "$OVERLAY/doc/knowledge_base"
```

Write, into `$OVERLAY`:

- `doc/knowledge_base/project-overview.md` — the project charter, filled from the discovery summary (the section structure ships in the template skeleton: what it is / goals / what it does / what it explicitly does not do / constraints / architecture intentions / audience).
- `doc/knowledge_base/roadmap.md` — the roadmap approved in step 2.
- `CLAUDE.md` — filled from discovery: the one-paragraph description, the critical constraints you learned (leave genuinely-unknown build/test commands as the template's `<...>` stubs), and the module layout if the architecture intentions imply one. Keep the template's Key references table (including the `project-overview.md` row) and Workflow section.
- *Optionally* `doc/architecture/overview.md` — only if discovery produced enough concrete structural intent to be worth committing; otherwise leave the template's architecture index pointing at a doc the project writes in its first phase.

Author the identifiers as placeholders (`<PROJECT_NAME>`, `<PROJECT_SLUG>`, `<PROJECT_DIR>`) wherever they appear; the bootstrap script substitutes overlaid files too, so this keeps them consistent. Use concrete prose for everything else. Do not leave any of the four reserved tokens (`<PROJECT_NAME>`, `<PROJECT_SLUG>`, `<PROJECT_DIR>`, bare `PROJECT`) standing in for content you meant to write — only as genuine identifier placeholders.

## 6. Scaffold the project (one bootstrap invocation)

Reuse the bootstrap script — do not reimplement copying or substitution:

```bash
./tools/bootstrap-cdd-project.sh \
  --name "<PROJECT_NAME>" --slug <PROJECT_SLUG> \
  --path "<target>" \
  --overlay "$OVERLAY"
# add `--dir <PROJECT_DIR>` only if <PROJECT_DIR> differs from the basename of <target>
```

(`--dir` is only needed when `<PROJECT_DIR>` differs from the basename of `--path`; otherwise it is derived, so the example omits it.) This copies the template, applies the overlay (your filled-in files win over the stubs), substitutes the three identifiers plus the in-script bare `PROJECT` token, writes the baseline marker `.claude/cdd-baseline`, runs `git init -b main`, and creates the single "Initial CDD scaffold" commit — so the filled-in overview, roadmap, and `CLAUDE.md` are in that commit.

Then remove the overlay: `rm -rf "$OVERLAY"`.

## 7. Optional: create and push a GitHub repo

Only if the user wants it — this is outward-facing, so confirm explicitly (name, visibility) before running:

```bash
( cd "<target>" && gh repo create <PROJECT_DIR> --source . --push --private )   # or --public
```

Requires an authenticated `gh`. Skip this step entirely if the user wants to stay local.

## 8. Summary and next steps

Report:

- The identifiers used and the target path.
- What was written into the scaffold commit: project overview, roadmap (real first phase, no survey phase), `CLAUDE.md`, and whether an architecture overview was included.
- The baseline marker value and that the "Initial CDD scaffold" commit was created.
- The GitHub repo, if one was created (step 7).
- The exact `source` line for `<target>/tools/<PROJECT_SLUG>-worktree.sh` to add to `~/.bashrc` (offer to append it for the user — confirm first, since it edits their shell config):

  ```bash
  [[ -f "<target>/tools/<PROJECT_SLUG>-worktree.sh" ]] && source "<target>/tools/<PROJECT_SLUG>-worktree.sh"
  ```

- The next command: `cd <target>`, run `claude`, and `/cdd-next-step` — it picks up the real first phase of the roadmap. Unlike a files-only install, there is **no** codebase-survey bootstrap phase to clear first; the docs are already populated.

(The bootstrap script prints its own generic "fill in CLAUDE.md / look at the pre-filled roadmap" block; your summary supersedes it for the `/cdd-bootstrap` path, where those are already done.)
