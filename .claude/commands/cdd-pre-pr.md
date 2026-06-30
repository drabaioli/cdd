Run a pre-PR checklist for the current branch. Compare against the base branch to identify all changes. This is a verification session: it runs CI gates, code-reviews the diff, and reconciles documentation against the changes.

This session is **fresh and separate** from the implementation session by design, so that the verification work is not biased by the context that produced the change. Any "propose to the user" step in this command is a proposal to the user running this session.

## 0. Resolve the default branch

```bash
DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo main)
```

Use `$DEFAULT_BRANCH` wherever `main`/`origin/main` appears in git commands below.

## 1. Identify changes

```bash
git diff "$DEFAULT_BRANCH"...HEAD --name-only
git status --porcelain
```

Capture the list of changed files. Use it as the scope for steps 3 and 4.

Also record the `git status --porcelain` output as the **entry snapshot**. The tree should be clean here (the implementation session commits its own work). If it is already dirty, those are changes this session did not create — note them now; step 8 must not sweep them into the auto-commit.

## 2. Build & QA

Run each CI job sequentially. **Capture only the last 40 lines + exit code, do not read the full output.** Stop on first failure.

```bash
<build command>          2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<format check command>   2>&1 | tail -20; echo "EXIT:${PIPESTATUS[0]}"
<lint command>           2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<unit test command>      2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<integration test cmd>   2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
```

Report pass ✓ / fail ✗ for each job. On failure, include the captured tail in the report.

## 3. Code review

Read all changed source files from the step 1 diff.

Review for:

- Correctness and logic bugs.
- Design issues (coupling, responsibility boundaries, API shape).
- Compliance with the project coding standard linked from CLAUDE.md.

Flag any issues found. If new conventions are established during this review (something the change does that should become the project norm), update the coding standard accordingly.

## 4. Documentation reconciliation

Check and **update** documentation based on the changes:

- **Architecture docs** (`doc/architecture/`): if module structure, data flow, key interfaces, threading model, or external boundaries changed, update the relevant doc to reflect it. Edit directly.
- **Feature docs** (`doc/features/`): if user-visible behaviour changed or a new feature landed, update or add the relevant feature doc. Edit directly.
- **CLAUDE.md**: if module layout, build commands, or top-level constraints changed, update it. Edit directly.
- **README.md**: if anything it states — quick start, layout, status, links — went stale relative to the change, update it. Edit directly.
- **Roadmap** (`doc/knowledge_base/roadmap.md`):
  1. Tick any newly completed checkboxes directly.
  2. Identify items that should be **added, modified, or removed** based on what was implemented. Present these suggestions explicitly to the user **before** making any edits. Apply only on approval.

Read each relevant doc and compare against the actual code changes. Fix discrepancies directly when they are reconciliation (the doc is out of date relative to what landed). Ask before applying structural changes (adding new doc files, restructuring an existing doc).

## 5. Test coverage reconciliation

For each behavioural change in the diff (a new function, a new branch, changed output, a fixed bug), check whether it is covered by a test. This is the recurring guardrail behind the "tested behaviour" row of `doc/knowledge_base/engineering-practices.md`.

- **If the project has a test command** ("tested behaviour" marked *enforced*): confirm a test exercises the new behaviour. If a behavioural change landed with no accompanying test, flag it — the default expectation is that new behaviour ships with a test.
- **If a change is deliberately untested** (a throwaway script, generated code, a spike): that is allowed, but it must be *intentional and recorded*, not silent. State the reason in the PR summary.
- **If the project has no test command yet** ("tested behaviour" still *expected*): do not invent a framework. Note that the change shipped untested because there is no test harness, and confirm that standing one up is tracked as a roadmap task. If this change is exactly the kind of behaviour that motivates a first test, say so and let the user decide whether to pull that task forward.

This step asks a question and records the answer; it does not mandate a specific framework, a coverage threshold, or that every change be tested. "Not tested, and here is why" is a valid, recorded outcome. Surface it — do not block on it.

## 6. CI improvement check (conditional)

If, and only if, the change introduces a category of work that the existing CI does not cover, propose specific improvements to the user. Examples that should trigger a proposal:

- A new file type or language is being committed that no existing job builds, lints, or formats.
- A new test category is introduced (e.g. first integration test in a project that only had unit tests until now) and there is no CI job that runs it.
- A new external tool is invoked in build/test scripts but is not pinned or version-checked.
- A new convention was established during the code review in step 3 that could be enforced mechanically.

Do **not** propose generic CI improvements every run. The default is silence. If you do propose, the user has two options: apply now in this PR, or defer as a new roadmap task. Apply only on approval.

## 7. Upstream drift check

```bash
git fetch origin "$DEFAULT_BRANCH"
git log --oneline "HEAD..origin/$DEFAULT_BRANCH"
```

If `origin/$DEFAULT_BRANCH` has advanced beyond the branch point, mention it and recommend running `/cdd-merge-base` before opening the PR. Do not merge from this session.

<!-- cdd-only-begin -->
## Command-set drift (CDD repo only)

This check is specific to the CDD repo (the meta-project): it surfaces unintended divergence between the repo's own `.claude/commands/` and the `template/.claude/commands/` it ships to downstream projects.

```bash
./scripts/command-drift-check.sh
```

The script renders the template through `bootstrap-cdd-project.sh --stage` with this repo's own identifiers, so expected substitution drift cancels out mechanically. Intentionally one-sided files are listed in `scripts/command-drift-whitelist.txt`; CDD-meta-only sections of shared files (such as this one) are fenced with `cdd-only` markers and stripped before comparison. The same script asserts that the handoff schema headings match between the process doc (Section 2.6) and `cdd-next-step.md`, and that no `cdd-only` markers leak into the template itself. CI runs it on every PR via `template-smoke.yml`.

If the script exits 0, report "no drift" and continue. If it reports divergence, present each diff to the user; for each, the user decides whether to reconcile the repo copy, reconcile the template copy, or record a justified exception (a whitelist entry or a `cdd-only` fence). Apply fixes only on user approval. Do not auto-edit either tree from this step.

When presenting the step 8 checklist, append a `- [ ] Command-set drift clean` line to it.

## Prompt-seam checks (CDD repo only)

Also specific to the CDD repo: deterministic seam-contract checks over the repo's own prompts (the slash-commands and the docs around them), guarding against a one-sided edit silently stranding a downstream prompt-driven step.

```bash
./scripts/prompt-seam-check.sh
```

It verifies four seams with grep only (no LLM, no API key): every `/cdd-*` reference across the repo's markdown resolves to an existing command file (known non-commands are whitelisted in `scripts/prompt-seam-whitelist.txt`); the `gh_issue_NN` branch token produced in `cdd-next-step.md` is still consumed (turned into a `Closes #NN` line) in `cdd-pre-pr.md`; backticked file paths in the command files, `CLAUDE.md`, and `README.md` resolve to real files; and each `cdd-*.md` still carries its load-bearing headings. CI runs it on every PR via `template-smoke.yml`.

If the script exits 0, report "prompt seams clean" and continue. If it reports a broken seam, present each one to the user; for each, the user decides whether to fix the reference/heading/path or record a justified exception (a whitelist entry). Apply fixes only on user approval.

When presenting the step 8 checklist, append a `- [ ] Prompt seams clean` line to it.
<!-- cdd-only-end -->
## 8. Summary

Present a checklist summary:

```
## Pre-PR Checklist
- [ ] Build passes
- [ ] Formatting passes
- [ ] Lint passes
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Code review: no issues / issues flagged (list them)
- [ ] Architecture docs up to date
- [ ] Feature docs up to date
- [ ] CLAUDE.md up to date
- [ ] README up to date
- [ ] Roadmap up to date
- [ ] New behaviour tested (or untested-with-reason recorded)
- [ ] CI gaps surfaced: none / proposed (list them)
- [ ] No upstream drift (or: /cdd-merge-base recommended)
- [ ] Reconciliation edits committed
```

Mark each item as pass ✓ or needs attention ✗ with details.

## 9. Commit reconciliation edits

Commit the documentation reconciliation edits this session made in steps 3–7 (architecture/feature docs, CLAUDE.md, README, the coding standard, and the roadmap). This is a local commit only — **no push**. Pushing happens, if at all, in step 10.

First check the entry snapshot from step 1:

- **If the tree was already dirty on entry** (changes this session did not create), **stop and surface** them: list those paths, state that the auto-commit is skipped so unrelated work isn't swept in, and let the user resolve it. The checklist above still stands on its own.
- **Otherwise**, commit only the files this session edited. Add them by path — do not `git add -A`:

```bash
git add <files reconciled in steps 3–7>
git commit -m '<message>'
```

Follow the repo's commit conventions from CLAUDE.md. Print a one-line summary of the commit (subject + files included). If nothing was reconciled (no edits this session), say so and skip the commit.

Then advance the task **state record** (advisory; see the process doc §2.13): run `cdd-state set checks_passed`. It skips silently if the record is absent.

## 10. Open PR (optional)

After the checklist, offer to open the PR. This is human-gated — never open a PR without explicit confirmation.

**Preconditions.** Needs the `gh` CLI authenticated and a GitHub `origin`:

```bash
gh auth status && git remote get-url origin   # origin should be a github.com URL
```

If either is missing, say so in one line and skip this step (the checklist above still stands).

If §7 found upstream drift, restate the recommendation to run `/cdd-merge-base` before opening the PR, and let the user decide whether to proceed anyway.

Ask: **"Open a PR now?"** Do not pre-show a title or body, and do not print manual `gh` instructions — just ask whether to proceed.

- **On yes**: derive a title from the branch/commits and a body from the change summary, then run `gh pr create --title "<title>" --body "<body>"` and print the resulting PR URL. If the branch name matches `gh_issue_NN` (e.g. `gh_issue_42_dark_mode`), parse `NN` and append a `Closes #NN` line to the body so the issue auto-closes on merge. Then advance the task **state record** (§2.13), passing the new PR's number: run `cdd-state set pr_open --pr NN` with the new PR's number.
- **On no**: stop. The checklist above already stands on its own.
