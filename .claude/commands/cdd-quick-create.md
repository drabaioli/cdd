Produce a small, self-contained deliverable — a script plus a README, not a full CDD project: `/cdd-quick-create` (takes an optional one-line description of what to build).

Run this from a CDD-repo session. Sibling of `/cdd-bootstrap` (new project) and `/cdd-retrofit` (existing project): this one creates a one-off *deliverable* with no project substrate — no roadmap, no `doc/` tree, no `.claude/commands/`, no worktree helper, no baseline marker, no `/cdd-pre-pr` lifecycle. It uses neither `template/` nor the bootstrap script; it writes plain files directly (`doc/features/template.md`).

Guided but light: a few natural questions, not `/cdd-bootstrap`'s full discovery.

**Checkpoints:** scope (step 1), definition (step 2), name and target (step 3), each confirmed before moving on. Files are written first (step 4), before any version control. The local commit (step 6) and GitHub repo (step 7) are each offered separately and confirmed individually; never done silently or by default.

## 1. Scope check (the gate)

Confirm this is a deliverable, not a project, using the shared heuristic (`doc/features/template.md`, "Deliverable or project?"). It is a **project** (→ `/cdd-bootstrap`) when any of these hold: it will evolve across many sessions and needs a roadmap; it has more than one cooperating component or an architecture worth documenting; it involves multiple collaborators or handoffs; it is long-lived and will accrete features. It is a **deliverable** when none hold: one self-contained artifact, finished in essentially one sitting, used as-is by future-you.

If the description (`$ARGUMENTS`) or an opening exchange trips a project-signal, **surface it and offer to switch to `/cdd-bootstrap`** rather than proceeding. The human decides.

**Checkpoint:** if any project-signal is present, name it and get an explicit "stay lightweight" or "switch to `/cdd-bootstrap`" before continuing.

## 2. Lightweight discovery

A short conversation, not a questionnaire. Cover only:

- **What it is** — one or two sentences, plain terms.
- **Its goal** — the problem it solves or the output it produces; what "done" looks like.
- **Its non-goals** — what it deliberately won't do. Push briefly for these.

Probe vague answers and reflect back what you heard, briefly.

**Checkpoint:** restate the captured definition (what / goal / non-goals) and get confirmation or corrections before writing anything.

## 3. Confirm the name and target location

Propose a short `<name>` for the deliverable (a directory/repo slug, `^[a-z][a-z0-9_-]*$`), then the target location. Default: a **sibling of the CDD repo** (the parent of the current checkout):

```bash
TARGET="$(dirname "$(git rev-parse --show-toplevel)")/<name>"
```

The user may override the location freely.

Refuse a path that already exists and is non-empty:

```bash
[[ -e "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]] && echo "exists and non-empty"
```

If it exists and is non-empty, stop and ask for a different location. An absent path or an empty directory is fine; create it if absent.

**Checkpoint:** confirm the name and target path before writing.

## 4. Write the deliverable (files-first)

Write the artifact(s) and a README directly into the target — no overlay, no substitution, no template machinery. The engineering floor:

- **Clean, single-purpose code (required).** One focused artifact doing the one thing the goal describes; nothing toward the step-2 non-goals.
- **A focused README (required).** What it is, how to run it, any prerequisites. Sized to the deliverable — one screen for a one-file script.
- **Inline dependency metadata where the language supports it (offer).** For a Python `uv` script, PEP723 inline metadata (a `# /// script` block); the equivalent idiom elsewhere where one exists. Don't force a packaging story onto a language that doesn't want one.
- **A license / authorship header (offer).** A short header or `LICENSE` file if the user wants one.

## 5. Offer a smoke test

Offer — don't force — a minimal check that it works: run it once on a representative input, or a tiny happy-path invocation. Respect a "no". If it runs, note that in the summary; if it fails, fix it before moving on.

## 6. Offer git init and one local commit

Only if the user wants it — confirm first; it is not the default:

```bash
( cd "$TARGET" && git init -b main && git add -A && git commit -m "Add <name>" )  # stage-all-ok: fresh repo, every file in it is this deliverable
```

A single commit; the message a one-liner describing the deliverable.

## 7. Offer a GitHub repo (separately)

Only if the user asked for it; confirm name and visibility explicitly before running:

```bash
( cd "$TARGET" && gh repo create <name> --source . --push --private )   # or --public
```

Requires an authenticated `gh` and the step-6 commit. Skip entirely if the user wants to stay local.

## 8. Summary

Report:

- The name and target path.
- What was written: the artifact(s) and the README, plus any optional extras (inline dependency metadata, license header).
- Whether a smoke test ran and its result.
- Whether a local commit was made (step 6) and whether a GitHub repo was created (step 7).
- That this is a **deliverable**, not a project: there is no roadmap, worktree helper, or `/cdd-pre-pr` lifecycle. If it later grows into a project, `/cdd-retrofit` can install CDD onto it.
