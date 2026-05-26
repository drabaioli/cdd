# CDD friction log

Append-only log of friction encountered while using CDD on real downstream projects, plus what (if anything) was changed in CDD as a result. Each entry names the downstream project, summarises the friction, and links to the CDD-side fix.

The log lives in the CDD repo (not in any downstream project) because its audience is the maintainer of CDD itself. Downstream projects are free to keep their own internal notes; what surfaces here is whatever should drive CDD-side change.

## 2026-05 — sprint-planning-automation-poc bootstrap

**Downstream project:** `sprint-planning-automation-poc` (first greenfield consumer of `template/`).

**What happened:** Bootstrapped by hand following `template/README.md`'s sed recipe. Seven concrete defects surfaced in the template and its substitution recipe.

**Defects (raw friction):**

1. `template/README.md` is meta-doc for bootstrapping, but the recipe copies it into the new project's root where it then reads as if it were the project's own README.
2. The placeholder model was two-tier (`<PROJECT_NAME>`, bare `PROJECT`), but a project actually needs three identifiers: display name, shell-command slug, directory slug. References like `<PROJECT_NAME>-worktree <branch>` expanded to `Sprint Planning Automation POC-worktree <branch>` — a broken command. Hand-fixed in four places.
3. `template/tools/PROJECT-worktree.sh` carries a "Before using: rename + substitute" comment block in its header. After bootstrap, that rename has already happened; the instructions are stale inside the user's repo. Trimmed by hand.
4. The roadmap stub's example Phase 1 implicitly suggested "initialise git repo" as a first task — but bootstrap already does that, and once `bootstrap.sh` exists the suggestion is actively wrong.
5. `template/CLAUDE.md`'s Key references table pointed at `doc/knowledge_base/<coding-standard-filename>.md` — a dangling link in any freshly bootstrapped project.
6. No sanity check that the worktree helper is sourced. `/next-step` could happily print `Next: <slug>-worktree <branch>` and the user would hit "command not found".
7. The sed substitution recipe was fragile: a `grep -rl | xargs sed -i` that should just be `sed -i`, and order-of-operations safety (`<PROJECT_NAME>` before bare `PROJECT`) was implicit.

**CDD-side response:** PR landing on branch `template-bootstrap-hardening`. Fixes all seven defects, ships `bootstrap-cdd-project.sh` at the CDD repo root, adds a `template-smoke` CI workflow so the defects can't silently regress, and updates the process doc with the three-identifier model.

**Not retro-fixed:** `sprint-planning-automation-poc` keeps its hand-fixed copies — this PR does not back-port substitutions into existing downstream projects. Future readers comparing its `tools/spa-poc-worktree.sh` to a freshly-bootstrapped project's will see a small delta.

**Still open after this entry:**

- Three or more downstream task cycles before drawing conclusions (Phase 2 milestone).
- `/merge-main` refinement once a real merge has been performed (separate Phase 3 task).
- `/pre-pr` drift check for the two command sets (separate Phase 3 task).
