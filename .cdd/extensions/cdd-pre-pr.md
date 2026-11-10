This repo's additions to `/cdd-pre-pr` — CDD dogfooding its own command extensions.

## Build & QA

**In this repo the runner is `./scripts/ci.sh`** — 30 gates, listed with what each checks in the registry at the top of the script; `./scripts/ci.sh list` names them and `./scripts/ci.sh <gate>` reruns one. Not fail-fast. CI runs it on Ubuntu and macOS, so a gate leaning on one host's sed/grep/awk can pass here and fail there.

A failure of the `drift` or `seams` gate is a **judgement call, not a bug to fix blindly** — read it with the notes below rather than rerunning it.

**`drift` — `scripts/command-drift-check.sh`.** Diffs this repo's `.claude/commands/` and `.claude/agents/` against the `template/.claude/` copies, rendered with this repo's identifiers so substitution drift cancels out. Intentionally one-sided files are listed in `scripts/command-drift-whitelist.txt`. CDD-only sections of shared files may still be fenced with `cdd-only` markers, stripped before comparison, but no repo command uses one today: this repo's additions live in `.cdd/extensions/`, like any project's. It also asserts that the handoff and plan-file schema blocks are identical between the process doc (Sections 2.6 and 2.15) and `cdd-next-step.md` / `cdd-plan.md`, that no `cdd-only` markers leak into the template, and that no template file hardcodes this repo's handoff directory (`handoffs/cdd`).

On divergence, present each diff to the user; for each, the user decides: reconcile the repo copy, reconcile the template copy, or record a justified exception (a whitelist entry, a `cdd-only` fence, or an extension here).

**`seams` — `scripts/prompt-seam-check.sh`.** Verifies 13 seams between the repo's prompts with grep only; `./scripts/prompt-seam-check.sh list` names them and each failure line names its seam. Known non-commands are whitelisted in `scripts/prompt-seam-whitelist.txt`. This prose lives outside the checked commands, so the tokens it quotes cannot satisfy a seam's needles.

On a broken seam, present each one to the user; for each, the user decides: fix the reference/heading/path, or record a justified exception (a whitelist entry).

For both: apply fixes only on user approval, and do not auto-edit either tree from this step.

## Workflow improvement check (conditional)

This repo *is* CDD, so the "general enough that any CDD project would want it" route has no upstream to reach: a general improvement discovered here is a normal roadmap item (or an issue on this repo) plus the matching process-doc and template change.
