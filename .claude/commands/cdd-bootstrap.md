Scaffold a new greenfield project on the CDD workflow: `/cdd-bootstrap` (takes no argument).

Run this from a CDD-repo session: it needs the CDD repo's `template/` and `bootstrap-cdd-project.sh`. It creates a *new* project; `/cdd-retrofit` adapts an *existing* one.

This is a **guided** command: walk the user through defining the project, encode the result into the initial docs and roadmap, then scaffold the project in a single bootstrap invocation. The generated project starts with a real, filled-in overview, `CLAUDE.md`, and roadmap.

The project's name, directory, and location all come out of the conversation; the target path is proposed and confirmed in step 3.

**Checkpoint discipline:** confirm the project definition (step 1), then the draft roadmap (step 2), then the two identifiers and the target location (step 3) — each before moving on. Nothing is rendered or committed until all are approved. Outward-facing actions (creating a GitHub repo, editing `~/.bashrc`) are confirmed separately and never done silently.

## 1. Guided discovery

Have a conversation to define the project. No rigid questionnaire: ask in natural batches, probe vague or one-word answers, and reflect back what you heard. Cover, at minimum:

- **What it is** — one paragraph, plain terms.
- **Goals** — why it exists; the problem it solves or outcome it produces; what success looks like.
- **What it does** — the high-level capabilities, coarse-grained.
- **What it explicitly does not do** — the non-goals. Push for these.
- **Constraints** — language/platform, hard technical limits, regulatory/business constraints, compatibility, deadlines.
- **Architecture intentions** — intended high-level shape: major components, how they relate, external boundaries, structural principles the project commits to.
- **Audience** — who consumes it (end users, other services, a team, future-you).
- **Engineering floor** — what the project commits to for tested behaviour, continuous integration, lint & format, and dependency & toolchain hygiene (the negotiable rows of the template contract). Ask this as one batch; the answers are commitments, and most will honestly be *expected*.
- **Where issues and code review live** — the tracker (where issues live) and the code host (where pull requests are reviewed). Always ask; never assume. Offer GitHub (Issues + pull requests) as the default. The answer becomes the project's capability bindings in `.cdd/` (process doc Section 2.16), written by the bootstrap script in step 5:
  - **GitHub** — bind both to the shipped GitHub adapters.
  - **Jira for issues** — ask for the Jira site (e.g. `acme.atlassian.net`) and the project key (e.g. `ABC`) only. **Never ask for credentials**: tell the user they set `JIRA_EMAIL` and `JIRA_API_TOKEN` in their own shell. The code host is asked separately.
  - **GitLab** — for either capability or both (gitlab.com or a self-managed instance). Ask for the GitLab URL (default `gitlab.com`) and the project path (e.g. `group/project`) only. **Never ask for credentials**: tell the user they set `GITLAB_TOKEN` (a token with the `api` scope) in their own shell.
  - **Anything CDD ships no adapter for** (Bitbucket, …) — say in one line that no binding is written for it and the issue and PR features skip until one is bound; a project adapter can be written later against `doc/architecture/capability-adapters.md`.

Where the user has no firm answer, capture intent and mark the area open rather than inventing detail. This material becomes the project overview (`doc/knowledge_base/project-overview.md`) and seeds `CLAUDE.md`.

**Off-ramp:** if discovery reveals this isn't really a project — a single self-contained artifact, finished in essentially one sitting, used as-is by future-you — apply the shared scope-triage heuristic (`doc/features/template.md`, "Deliverable or project?") and **offer to drop to `/cdd-quick-create`** instead of scaffolding the full substrate. Surface the signals; the human decides.

**Checkpoint:** present a structured summary of the captured definition (the headings above, including the chosen tracker and code host). Get explicit confirmation or corrections before writing anything.

## 2. Draft the initial roadmap

From the discovery, propose a thin but real roadmap: three to five phases, a handful of tasks each, every phase ending in a milestone statement. Every practice the engineering floor leaves *expected* becomes one task, phrased so closing it flips that row to *enforced*; the template's suggested infrastructure tasks (README, coding guidelines, release/versioning) cover the rest. One set, not two.

Do **not** include the template's pre-filled "Phase 1: CDD bootstrap" survey phase; the roadmap starts at the project's real first phase.

Keep the roadmap's "Annotation conventions" and "Key principles" scaffolding from the template (adapt the principles to the project, or leave a short placeholder).

**Checkpoint:** show the drafted roadmap; the user approves or edits it. It is approved *now*: it goes into the initial scaffold commit (step 5), and there is no post-commit edit pass.

## 3. Confirm the identifiers and the target location

Propose all three; never pick silently (two-identifier model, process doc Section 2.9):

- `<PROJECT_NAME>` — the display name from discovery; free text, may contain spaces.
- `<PROJECT_DIR>` — the directory / repo slug, matching `^[A-Za-z][A-Za-z0-9_-]*$`. It is the working tree's directory name and the handoff-directory namespace.
- The target path — default `$HOME/Code/<PROJECT_DIR>`; the user may override it, but the basename should match `<PROJECT_DIR>`.

Before presenting them, check the proposed path (the bootstrap script refuses one that exists and is non-empty), and rerun it whenever the path changes at the checkpoint (an override, or a changed `<PROJECT_DIR>`):

```bash
[[ -e "<target>" && -n "$(ls -A "<target>" 2>/dev/null)" ]] && echo "exists and non-empty"
```

If it exists and is non-empty, stop and ask for a different location — `/cdd-bootstrap` is for greenfield; suggest `/cdd-retrofit` if the user meant to install CDD into an existing project. An absent path or an empty directory is fine.

**Checkpoint:** confirm `<PROJECT_NAME>`, `<PROJECT_DIR>` and the target path together before staging the overlay.

## 4. Stage the overlay

Build a staging directory that mirrors the template layout and holds the filled-in artifacts. The bootstrap script applies it over the template before substitution, so these files override the template stubs:

```bash
OVERLAY=$(mktemp -d)
mkdir -p "$OVERLAY/doc/knowledge_base"
```

Write, into `$OVERLAY`:

- `doc/knowledge_base/project-overview.md` — the project charter, filled from the discovery summary (the section structure ships in the template skeleton: what it is / goals / what it does / what it explicitly does not do / constraints / architecture intentions / audience).
- `doc/knowledge_base/roadmap.md` — the roadmap approved in step 2.
- `doc/knowledge_base/engineering-practices.md` — every row marked **Enforced** or **Expected** from the engineering-floor answers, with no `<…>` status marker left standing. Documentation is enforced from day one; fill a command placeholder only where a command was actually chosen, never to clear the placeholder.
- `CLAUDE.md` — filled from discovery: the one-paragraph description, the critical constraints you learned (build/test commands as settled in the contract; leave unchosen ones as the template's `<...>` stubs), and the module layout if the architecture intentions imply one. Keep the template's Key references table (including the `project-overview.md` row) and Workflow section.
- *Optionally* `doc/architecture/overview.md` — only if discovery produced enough concrete structural intent to be worth committing; otherwise leave the template's architecture index pointing at a doc the project writes in its first phase.

Write the identifiers as the placeholders `<PROJECT_NAME>` and `<PROJECT_DIR>` wherever they appear (the script substitutes overlaid files too), and concrete prose for everything else. Never leave either token standing in for content you meant to write.

## 5. Scaffold the project (one bootstrap invocation)

Reuse the bootstrap script — do not reimplement copying or substitution:

```bash
./tools/bootstrap-cdd-project.sh \
  --name "<PROJECT_NAME>" \
  --path "<target>" \
  --overlay "$OVERLAY" \
  --tracker github --code-host github
# add `--dir <PROJECT_DIR>` only if <PROJECT_DIR> differs from the basename of <target>
```

Pass the binding flags from step 1's answer: `--tracker github`, `--tracker jira --jira-site <site> --jira-key <KEY>` or `--tracker gitlab`, and `--code-host github` or `--code-host gitlab`; either `gitlab` adds `--gitlab-project <path>` (and `--gitlab-url <url>` for a self-managed instance), given once. Leave a flag out for a backend CDD ships no adapter for; the script refuses one.

The script copies the template, applies the overlay, substitutes the two identifiers, writes the capability bindings into `.cdd/` and the baseline marker `.claude/cdd-baseline`, runs `git init -b main`, and creates the single "Initial CDD scaffold" commit.

Then remove the overlay: `rm -rf "$OVERLAY"`.

## 6. Optional: create and push a GitHub repo

Only if the user wants it. Confirm explicitly (name, visibility) before running:

```bash
( cd "<target>" && gh repo create <PROJECT_DIR> --source . --push --private )   # or --public
```

Requires an authenticated `gh`. Skip this step entirely if the user wants to stay local.

## 7. Summary and next steps

Report:

- The identifiers used and the target path.
- What was written into the scaffold commit: project overview, roadmap (real first phase, no survey phase), `CLAUDE.md`, and whether an architecture overview was included.
- The baseline marker value and that the "Initial CDD scaffold" commit was created.
- The GitHub repo, if one was created (step 6).
- The capability bindings written into `.cdd/` (or, per capability, the one line saying none was written and those features skip). For Jira, name `JIRA_EMAIL` and `JIRA_API_TOKEN` as the environment variables the user sets in their own shell.
- The one-time worktree-helper install, if the user hasn't already run it for an earlier CDD project (offer to run it for them — confirm first, since it edits their shell config). One install serves every CDD project. It also installs the adapter library the `.cdd/` bindings run: if `~/.cdd/tools/adapters/<capability>/<backend>.sh` is missing for a bound capability, offer the same install — until it runs, that capability stops with the install command rather than falling back.

  ```bash
  ./tools/cdd-worktree.sh install
  ```

- The next command: `cd <target>`, run `claude`, and `/cdd-next-step` — it picks up the roadmap's real first phase; there is **no** codebase-survey phase to clear first.

The bootstrap script prints its own generic "fill in CLAUDE.md / look at the pre-filled roadmap" block; your summary supersedes it.
