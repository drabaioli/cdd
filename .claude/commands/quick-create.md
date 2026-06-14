Produce a small, self-contained deliverable — a script plus a README, not a full CDD project: `/quick-create` (takes an optional one-line description of what to build).

Run this command from a CDD-repo session. It is the third sibling of `/bootstrap` and `/retrofit`: `/bootstrap` creates a new CDD *project*, `/retrofit` adapts an *existing* one, and `/quick-create` creates a lightweight *deliverable* — a one-off artifact with none of the project substrate (no roadmap, no `doc/` tree, no `.claude/commands/`, no worktree helper, no baseline marker, no `/pre-pr` lifecycle). Like its siblings it exists only in the CDD repo and has no counterpart in `template/.claude/commands/`; unlike them it needs neither `template/` nor the bootstrap script, because a one-off has no template — it writes plain files directly (see the process doc, Section 6).

This is a **guided** command, but deliberately lighter than `/bootstrap`: a few natural questions, not the seven discovery headings. What it keeps from CDD is the part that pays off even for a one-off — a little guided discovery, clean single-purpose code, and a README so future-you can use it. What it drops is everything a single artifact doesn't need.

**Checkpoint discipline:** confirm the scope (step 1), then the captured definition (step 2), then the name and target (step 3) — each before moving on. The deliverable is written **files-first** (step 4), before any version control. The two outward-facing actions — a local commit (step 6) and a GitHub repo (step 7) — are offered separately, confirmed individually, and never done silently or by default.

## 1. Scope check (the gate)

Before discovery, confirm this is actually a deliverable and not a project. Apply the shared scope-triage heuristic (process doc, Section 6): a task is a **project** (→ `/bootstrap`) when any of these hold — it is expected to evolve across many sessions and needs a roadmap; it has more than one cooperating component or an architecture worth documenting; it involves multiple collaborators or handoffs; it is long-lived and will accrete features. It is a **deliverable** (→ `/quick-create`) when none hold: a single self-contained artifact, finished in essentially one sitting, used as-is by future-you.

If, from the description (`$ARGUMENTS`) or an opening exchange, project-signals trip, **surface them and offer to switch to `/bootstrap`** rather than proceeding. The human decides.

**Checkpoint:** if any project-signal is present, name it and get an explicit "stay lightweight" or "switch to `/bootstrap`" before continuing.

## 2. Lightweight discovery

Have a short conversation — not a questionnaire. Cover only:

- **What it is** — one or two sentences, plain terms.
- **Its goal** — the problem it solves or the output it produces; what "done" looks like.
- **Its non-goals** — what it deliberately won't do, so the artifact stays single-purpose. Push briefly for this; it keeps the deliverable small.

Probe vague answers and reflect back what you heard, but keep it brief — this is a one-off, not a project charter.

**Checkpoint:** restate the captured definition (what / goal / non-goals) and get confirmation or corrections before writing anything.

## 3. Confirm the name and target location

Propose a short `<name>` for the deliverable (a directory/repo slug, `^[a-z][a-z0-9_-]*$`), then propose the target location. The default is a **sibling of the CDD repo** — the parent of the current CDD checkout:

```bash
TARGET="$(dirname "$(git rev-parse --show-toplevel)")/<name>"
```

(From the canonical `$HOME/Code/cdd` checkout or any of its worktrees, this resolves to `$HOME/Code/<name>`.) Let the user override the location freely.

Refuse a path that already exists and is non-empty:

```bash
[[ -e "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]] && echo "exists and non-empty"
```

If it exists and is non-empty, stop and ask for a different location. An absent path or an empty directory is fine; create it if absent.

**Checkpoint:** confirm the name and target path before writing.

## 4. Write the deliverable (files-first)

Write the artifact(s) and a README directly into the target — no overlay, no substitution, no template machinery. The engineering floor:

- **Clean, single-purpose code (required).** One focused artifact that does the one thing the goal describes. Resist scope creep toward the non-goals from step 2.
- **A focused README (required).** Short and usable: what it is, how to run it, and any prerequisites. Match the deliverable's size — a one-screen README for a one-file script, not a project's worth of docs.
- **Inline dependency metadata where the language supports it (offer).** For a Python `uv` script, PEP723 inline metadata (a `# /// script` block) keeps dependencies self-contained and the script runnable with no separate install. Use the equivalent idiom for other languages where one exists; don't force a packaging story onto a language that doesn't want one.
- **A license / authorship header (offer).** A short header or `LICENSE` file if the user wants one. Skip if they don't.

Don't over-prescribe by language: required items are the README and clean code; the rest are offered and applied only if they fit.

## 5. Offer a smoke test

Offer — don't force — a minimal check that the deliverable works: run the script once on a representative input, or a tiny invocation that exercises the happy path. This is skippable; respect a "no". If it runs, note that in the summary; if it fails, fix it before moving on.

## 6. Offer git init and one local commit

Only if the user wants it — confirm first; it is not the default:

```bash
( cd "$TARGET" && git init -b main && git add -A && git commit -m "Add <name>" )
```

A single, clean commit. Keep the message a one-liner describing the deliverable.

## 7. Offer a GitHub repo (separately)

A separate decision from step 6 and outward-facing, so confirm explicitly (name, visibility) before running, and only if the user asked for it:

```bash
( cd "$TARGET" && gh repo create <name> --source . --push --private )   # or --public
```

Requires an authenticated `gh` and a local commit from step 6. Skip entirely if the user wants to stay local — local-only is a perfectly good end state for a one-off.

## 8. Summary

Report:

- The name and target path.
- What was written: the artifact(s) and the README, plus any optional extras (inline dependency metadata, license header).
- Whether a smoke test ran and its result.
- Whether a local commit was made (step 6) and whether a GitHub repo was created (step 7).
- That this is a **deliverable**, not a project: there is no roadmap, worktree helper, or `/pre-pr` lifecycle. If it later grows into a project, `/retrofit` can install CDD onto it.
