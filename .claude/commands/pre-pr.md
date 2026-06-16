Run a pre-PR checklist for the current branch. Compare against `main` to identify all changes. This is a verification session: it runs CI gates, code-reviews the diff, and reconciles documentation against the changes.

This session is **fresh and separate** from the implementation session by design, so that the verification work is not biased by the context that produced the change. Any "propose to the user" step in this command is a proposal to the user running this session.

## 1. Identify changes

```bash
git diff main...HEAD --name-only
```

Capture the list of changed files. Use it as the scope for steps 3 and 4.

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

## 5. CI improvement check (conditional)

If, and only if, the change introduces a category of work that the existing CI does not cover, propose specific improvements to the user. Examples that should trigger a proposal:

- A new file type or language is being committed that no existing job builds, lints, or formats.
- A new test category is introduced (e.g. first integration test in a project that only had unit tests until now) and there is no CI job that runs it.
- A new external tool is invoked in build/test scripts but is not pinned or version-checked.
- A new convention was established during the code review in step 3 that could be enforced mechanically.

Do **not** propose generic CI improvements every run. The default is silence. If you do propose, the user has two options: apply now in this PR, or defer as a new roadmap task. Apply only on approval.

## 6. Upstream drift check

```bash
git fetch origin main
git log --oneline HEAD..origin/main
```

If `origin/main` has advanced beyond the branch point, mention it and recommend running `/merge-main` before opening the PR. Do not merge from this session.

<!-- cdd-only-begin -->
## Command-set drift (CDD repo only)

This check is specific to the CDD repo (the meta-project): it surfaces unintended divergence between the repo's own `.claude/commands/` and the `template/.claude/commands/` it ships to downstream projects.

```bash
./scripts/command-drift-check.sh
```

The script renders the template through `bootstrap-cdd-project.sh --stage` with this repo's own identifiers, so expected substitution drift cancels out mechanically. Intentionally one-sided files are listed in `scripts/command-drift-whitelist.txt`; CDD-meta-only sections of shared files (such as this one) are fenced with `cdd-only` markers and stripped before comparison. The same script asserts that the handoff schema headings match between the process doc (Section 2.6) and `next-step.md`, that the worktree helpers (`tools/cdd-worktree.sh` vs the rendered template helper) match from the first function definition onward, and that no `cdd-only` markers leak into the template itself. CI runs it on every PR via `template-smoke.yml`.

If the script exits 0, report "no drift" and continue. If it reports divergence, present each diff to the user; for each, the user decides whether to reconcile the repo copy, reconcile the template copy, or record a justified exception (a whitelist entry or a `cdd-only` fence). Apply fixes only on user approval. Do not auto-edit either tree from this step.

When presenting the step 7 checklist, append a `- [ ] Command-set drift clean` line to it.
<!-- cdd-only-end -->
## 7. Summary

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
- [ ] CI gaps surfaced: none / proposed (list them)
- [ ] No upstream drift (or: /merge-main recommended)
```

Mark each item as pass ✓ or needs attention ✗ with details.

## 8. Open PR (optional)

After the checklist, offer to open the PR. This is human-gated — never open a PR without explicit confirmation.

**Preconditions.** Needs the `gh` CLI authenticated and a GitHub `origin`:

```bash
gh auth status && git remote get-url origin   # origin should be a github.com URL
```

If either is missing, say so in one line and skip this step (the checklist above still stands).

If §6 found upstream drift, restate the recommendation to run `/merge-main` before opening the PR, and let the user decide whether to proceed anyway.

Ask: **"Open a PR now?"**

- **Title/body**: derive a title from the branch/commits and confirm it with the user; build the body from the change summary. If the branch name matches `gh_issue_NN` (e.g. `gh_issue_42_dark_mode`), parse `NN` and append a `Closes #NN` line to the body so the issue auto-closes on merge.
- **On yes**: run `gh pr create --title "<title>" --body "<body>"` and print the resulting PR URL.
- **On no**: print the ready-to-run command (including `Closes #NN` when applicable) so the user can open it later:

  ```bash
  gh pr create --title "<title>" --body "<body>"
  ```
