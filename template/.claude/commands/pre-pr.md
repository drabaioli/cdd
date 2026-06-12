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
