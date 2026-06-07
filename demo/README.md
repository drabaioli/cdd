# CDD Demo — Markdown Renderer

This directory is a **third artifact** of the CDD repo, alongside `template/` and `scripts/`. It is not part of the template, and nothing in it should leak into `template/` (the template stays generic). The filled-in seed under `demo/seed/` is concrete project content precisely because it lives here.

The `demo/` subsystem serves two purposes from one shared seed:

- **Demo** — a reproducible, visual walkthrough of CDD's task cycle: one reviewable PR, two parallel branches that conflict, and a `/merge-main` that resolves the conflict *and* delivers a dependency.
- **Dogfooding** — a real greenfield project (CDD roadmap Phase 2) so working past the demo is genuine work.

The seed project is **Markdown Renderer**: a small local Flask app where you paste Markdown, see it rendered live, and copy the result as **rich text** so it pastes formatted into Gmail, Google Docs, or Word — not as raw `# Heading` source. The key technical spine: pasting into email clients needs `text/html` on the clipboard, and email strips `<style>` blocks, so formatting only survives if CSS is **inlined** (`<p style="...">`). That inline-styling step is the heart of Phases 2–3.

## What the seed contains

```
demo/seed/
├── CLAUDE.md                              # filled-in project context (Flask + markdown lib, actions pipeline)
└── doc/
    ├── knowledge_base/roadmap.md          # the 6-phase roadmap
    ├── architecture/
    │   ├── index.md                       # pointer list
    │   ├── overview.md                    # the actions-pipeline architecture
    │   └── adr/0000-template.md           # ADR template
    └── features/
        ├── index.md                       # pointer list
        └── overview.md                    # planned features by phase
```

The seed ships only the CDD scaffolding for the project — **no app code**. The Flask app is built by running CDD cycles (`/next-step` → implement → `/pre-pr` → PR) on a created instance; that is the demo/dogfooding itself.

The seed files carry the same three placeholders the template uses (`<PROJECT_NAME>`, `<PROJECT_SLUG>`, `<PROJECT_DIR>`); `setup.sh` substitutes them per instance via the bootstrap script's `--overlay` flag.

## Instances

- **Dogfood instance (kept):** display name "Markdown Renderer", slug & dir `mdr`. Not auto-numbered.
- **Demo instances (numbered, disposable):** `mdr_demo_01`, `mdr_demo_02`, … — slug and dir both equal the numbered name, so each instance is fully self-contained (its own `<name>-worktree` command and its own `~/.claude-handoffs/<name>/` directory). Numbering (rather than one reusable `mdr_demo`) lets you park one demo with interesting state while spinning up the next.

By default instances are created under `~/Code/<name>`; override with `--base DIR` or the `CDD_DEMO_BASE` environment variable.

## Create

```bash
demo/setup.sh                 # next free demo instance (mdr_demo_NN)
demo/setup.sh mdr             # the kept dogfood instance "Markdown Renderer"
demo/setup.sh mdr_demo_07     # a specific instance
```

`setup.sh` wraps the repo-root `bootstrap-cdd-project.sh` (it does **not** reimplement substitution): bootstrap copies `template/`, overlays `demo/seed/` via `--overlay`, substitutes the identifiers, runs `git init`, and makes the scaffold commit. Then `setup.sh` creates and pushes a GitHub repo with `gh repo create --source . --push` (private by default; pass `--public` to share).

After setup, `setup.sh` appends a marker-guarded block to `~/.bashrc` (default) so the instance's worktree helper is sourced automatically in new shells:

```bash
# --- CDD demo: mdr_demo_01 BEGIN ---
[[ -f "$HOME/Code/mdr_demo_01/tools/mdr_demo_01-worktree.sh" ]] && source "$HOME/Code/mdr_demo_01/tools/mdr_demo_01-worktree.sh"
# --- CDD demo: mdr_demo_01 END ---
```

The marker embeds the instance name so multiple parked demos coexist in the same rc file, and teardown removes exactly its own block. Use `--rc FILE` to target a different rc file. Under `--local-only` the rc file is not touched.

Auto-numbering checks **both** local directories under the base **and** existing GitHub repos, so a parked demo (local or remote) never gets a colliding number.

Options: `--name "Display Name"`, `--base DIR`, `--public`, `--rc FILE`, `--local-only` (skip GitHub steps and rc update — used by the smoke test).

## Teardown

```bash
demo/teardown.sh mdr_demo_03         # remove the local dir and delete the GitHub repo
demo/teardown.sh mdr_demo_03 --local-only   # remove only the local directory
```

Teardown removes the instance's marker-guarded block from `~/.bashrc` (default) before removing the local directory. Use `--rc FILE` to target the same file you passed to `setup.sh`. Under `--local-only`, the rc file is not touched.

Teardown refuses to delete a directory that does not look like a bootstrapped CDD project (it checks for `CLAUDE.md` + `tools/*-worktree.sh`), and prompts for confirmation unless you pass `--yes`.

> **`gh` scope caveat:** deleting the GitHub repo needs the `delete_repo` scope on your `gh` token. If teardown fails on the delete step, run:
>
> ```bash
> gh auth refresh -s delete_repo
> ```
>
> The local directory is removed first regardless, so a missing scope only leaves the remote repo behind.

## The demo script (Phases 1–3)

The roadmap (`demo/seed/doc/knowledge_base/roadmap.md`) is designed so a fresh instance reproduces the full CDD task cycle:

1. **Phase 1 — one reviewable PR.** `/next-step` → implement core render + live preview + the "Copy rendered" action, establishing the `ACTIONS = [...]` registry (Python) and the `<div class="actions">` toolbar (HTML) as the shared seam. Phase 1 carries a natural review surface — HTML-escaping of `<` (injection), nested emphasis, empty input, clipboard MIME — so the demo includes a "comment + fix during review" beat. Merge to `main`.

2. **Phases 2 & 3 — two parallel branches that conflict.** Off `main` (post-Phase-1), spin up two worktrees side by side:
   - **Branch A (Phase 2):** add `inline_styles(html)` and a `CopyEmailSafeAction`, registered in the `ACTIONS` list and a button in the toolbar.
   - **Branch B (Phase 3):** add `ExportStandaloneAction` / `ExportEmailAction`, registered in the **same** `ACTIONS` region and the **same** toolbar region — a guaranteed merge conflict. Branch B's email export depends on Phase 2's `inline_styles()`, which doesn't exist on the branch yet, so it ships the standalone export and leaves the email export blocked.

3. **Merge — `/merge-main` does two jobs.** Land PR2 (Phase 2) first; `main` advances. On branch B, run `/merge-main`: it (a) resolves the `ACTIONS`/toolbar conflict with Phase 2 **and** (b) brings `inline_styles()` onto the branch, unblocking the email export. This shows `/merge-main` resolving a conflict *and* delivering a dependency — not a trivial fast-forward.

## Verifying the subsystem

```bash
bash -n demo/setup.sh demo/teardown.sh demo/lib.sh

# End-to-end without touching GitHub:
rm -rf /tmp/cdd-demo-smoke
demo/setup.sh mdr_demo_99 --base /tmp/cdd-demo-smoke --local-only
```
