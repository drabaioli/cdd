Run a pre-PR checklist for the current branch. Compare against the base branch to identify all changes. This is a verification session: it runs CI gates, code-reviews the diff, and reconciles documentation against the changes.

This session is **fresh and separate** from the implementation session by design, so that the verification work is not biased by the context that produced the change. Any "propose to the user" step in this command is a proposal to the user running this session.

## 0. Resolve the base branch

```bash
BASE_BRANCH=$(cdd-state get base_branch 2>/dev/null)
BASE_BRANCH=${BASE_BRANCH:-$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo main)}
```

This reads the task's recorded base branch — the branch it was cut from and merges back into — and falls back to the hosting platform's default branch when none was recorded (unchanged behaviour for single-integration-branch projects). Use `$BASE_BRANCH` wherever `main`/`origin/main` appears in git commands below.

## 1. Identify changes

```bash
git diff "$BASE_BRANCH"...HEAD --name-only
git status --porcelain
```

Capture the list of changed files. Use it as the scope for steps 3 and 4.

Also record the `git status --porcelain` output as the **entry snapshot**. The tree should be clean here (the implementation session commits its own work). If it is already dirty, those are changes this session did not create — note them now; step 10 must not sweep them into the auto-commit.

## 2. Build & QA

Run the project's **check runner** — the single command that runs every gate, the same one CI invokes. Because it is the same command, a green run here means CI will be green too. **Capture only the last 40 lines + exit code, do not read the full output.**

```bash
<check runner command>   2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
```

Report each gate as pass ✓ / fail ✗ / skipped ⊘ from the runner's summary. On failure, include the captured tail. A **skipped** gate is not a pass: say which gate was skipped and why (usually a tool missing on this host), so the reader knows the local verdict is weaker than CI's.

If the project has no single runner yet, run each gate command in sequence instead — and note the gap for step 6, because a split gate list drifts and a pre-PR session that runs only some of the gates gives a green verdict that guarantees little:

```bash
<build command>          2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<format check command>   2>&1 | tail -20; echo "EXIT:${PIPESTATUS[0]}"
<lint command>           2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<unit test command>      2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<integration test cmd>   2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
```
<!-- cdd-only-begin -->

**In this repo the runner is `./scripts/ci.sh`** — 16 gates: shell syntax and shellcheck, the command-set drift and prompt-seam checks plus the seam checker's own contract, the helper install / worktree-resume / ref-sync / GC / base-branch assertions, the four bootstrap-and-render smokes, the demo seed overlay, and the runner's own contract. `./scripts/ci.sh list` names them; `./scripts/ci.sh <gate>` reruns one while iterating on a failure. It is not fail-fast — every gate runs, so one invocation surfaces every problem. Two of its gates need interpretation rather than a rerun; see the sections below.
<!-- cdd-only-end -->

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

## 7. Workflow improvement check (conditional)

If, and only if, this task surfaced something about *how the project works* that no artifact captures, route it. This is the recurring channel behind the "the workflow improves itself" commitment. Concrete triggers:

- A step in this task had to be done by hand that no artifact describes: a command not in `CLAUDE.md`'s build/test section, a file hand-edited that the docs imply is generated, a setup detail rediscovered from scratch.
- The code review in step 3 enforced a rule that is written down nowhere — a convention applied from inference rather than from `CLAUDE.md` or the coding standard.
- The handoff was materially wrong or incomplete: the diff contains work the handoff did not scope, or a constraint it missed cost rework.
- The same correction appears here that a recent PR also made — a repeated fix-up is a missing rule.
- Step 4 had to update a doc that no pointer in `doc/index.md` or `CLAUDE.md` would have led you to.
- A slash command's own instructions were ambiguous or wrong for this task and had to be worked around.

Route each one by scope; never leave it as a remark that dies with the session:

- **Project-specific, and an edit's worth** → apply it now: a `CLAUDE.md` constraint, a coding-standard rule, a doc pointer. It rides along in step 10's commit.
- **Project-specific, and bigger than an edit** → propose a roadmap item. That is a structural roadmap edit, so it needs the user's approval before it is written.
- **General enough that any CDD project would want it** → offer to file an issue on the CDD repo: `gh issue create --repo drabaioli/cdd`. **Human-gated** — show the title and body, ask once, and never file without explicit approval. If `gh` is unauthenticated or the user declines, fall back to the roadmap item above and say which fallback was taken. If this project *is* the CDD repo, there is no upstream: it is a normal roadmap item plus a process-doc and template change.

Do **not** manufacture an improvement every run. The default is silence, and "nothing surfaced" is the common, correct outcome. This step records; it never blocks the PR, and it is not a checkpoint.

## 8. Upstream drift check

```bash
git fetch origin "$BASE_BRANCH"
git log --oneline "HEAD..origin/$BASE_BRANCH"
```

If `origin/$BASE_BRANCH` has advanced beyond the branch point, mention it and recommend running `/cdd-merge-base` before opening the PR. Do not merge from this session.

<!-- cdd-only-begin -->
## Triaging the `drift` and `seams` gates (CDD repo only)

Two of the runner's gates are specific to the CDD repo (the meta-project) and, unlike the rest, a failure is a **judgement call, not a bug to fix blindly**. Step 2 already ran both; these notes are for reading a failure.

**`drift` — `scripts/command-drift-check.sh`.** Surfaces unintended divergence between the repo's own `.claude/commands/` and the `template/.claude/commands/` it ships downstream. It renders the template through `bootstrap-cdd-project.sh --stage` with this repo's own identifiers, so expected substitution drift cancels out mechanically. Intentionally one-sided files are listed in `scripts/command-drift-whitelist.txt`; CDD-meta-only sections of shared files (such as this one) are fenced with `cdd-only` markers and stripped before comparison. The same gate asserts that the handoff schema headings match between the process doc (Section 2.6) and `cdd-next-step.md`, and that no `cdd-only` markers leak into the template itself.

On divergence, present each diff to the user; for each, the user decides whether to reconcile the repo copy, reconcile the template copy, or record a justified exception (a whitelist entry or a `cdd-only` fence).

**`seams` — `scripts/prompt-seam-check.sh`.** Deterministic seam-contract checks over the repo's own prompts, guarding against a one-sided edit silently stranding a downstream prompt-driven step. It verifies five seams with grep only (no LLM, no API key): every `/cdd-*` reference across the repo's markdown resolves to an existing command file (known non-commands are whitelisted in `scripts/prompt-seam-whitelist.txt`); the `gh_issue_NN` branch token produced in `cdd-next-step.md` is still consumed (turned into a `Closes #NN` line) in `cdd-pre-pr.md`; backticked file paths in the command files, `CLAUDE.md`, and `README.md` resolve to real files; each `cdd-*.md` still carries its load-bearing headings; and the gate count stated in prose here and in `CLAUDE.md` matches what `./scripts/ci.sh list` registers.

On a broken seam, present each one to the user; for each, the user decides whether to fix the reference/heading/path or record a justified exception (a whitelist entry).

For both: apply fixes only on user approval, and do not auto-edit either tree from this step.
<!-- cdd-only-end -->
## 9. Summary

Present a checklist summary:

```
## Pre-PR Checklist
- [ ] Check runner passed (<N> gates: <N> passed, <N> skipped)
- [ ] Code review: no issues / issues flagged (list them)
- [ ] Architecture docs up to date
- [ ] Feature docs up to date
- [ ] CLAUDE.md up to date
- [ ] README up to date
- [ ] Roadmap up to date
- [ ] New behaviour tested (or untested-with-reason recorded)
- [ ] CI gaps surfaced: none / proposed (list them)
- [ ] Workflow improvements: none / routed (list them)
- [ ] No upstream drift (or: /cdd-merge-base recommended)
- [ ] Reconciliation edits committed
```

Mark each item as pass ✓ or needs attention ✗ with details.

## 10. Commit reconciliation edits

Commit the documentation reconciliation edits this session made in steps 3–8 (architecture/feature docs, CLAUDE.md, README, the coding standard, and the roadmap). This is a local commit only — **no push**. Pushing happens, if at all, in step 11.

First check the entry snapshot from step 1:

- **If the tree was already dirty on entry** (changes this session did not create), **stop and surface** them: list those paths, state that the auto-commit is skipped so unrelated work isn't swept in, and let the user resolve it. The checklist above still stands on its own.
- **Otherwise**, commit only the files this session edited. Add them by path — do not `git add -A`:

```bash
git add <files reconciled in steps 3–8>
git commit -m '<message>'
```

Follow the repo's commit conventions from CLAUDE.md. Print a one-line summary of the commit (subject + files included). If nothing was reconciled (no edits this session), say so and skip the commit.

Then advance the task **state record** (advisory): run `cdd-state set checks_passed`. It skips silently if the record is absent.

## 11. Open PR (optional)

After the checklist, offer to open the PR. This is human-gated — never open a PR without explicit confirmation.

**Preconditions.** Needs the `gh` CLI authenticated and a GitHub `origin`:

```bash
gh auth status && git remote get-url origin   # origin should be a github.com URL
```

If either is missing, say so in one line and skip this step (the checklist above still stands).

If §8 found upstream drift, restate the recommendation to run `/cdd-merge-base` before opening the PR, and let the user decide whether to proceed anyway.

Ask: **"Open a PR now?"** Do not pre-show a title or body, and do not print manual `gh` instructions — just ask whether to proceed.

- **On yes**: derive a title from the branch/commits and a body from the change summary. **Target the PR at the task's base branch:** if `$BASE_BRANCH` differs from the platform default (`git symbolic-ref --quiet --short refs/remotes/origin/HEAD`), the PR must set `--base "$BASE_BRANCH"` — but first confirm the base exists on the remote (`git ls-remote --exit-code --heads origin "$BASE_BRANCH"`). If it does not (e.g. the task stacks on a local base branch that was never pushed), **stop and ask** the user how to proceed: push the base branch first, retarget the PR at the default branch, or abort. Then run `gh pr create --title "<title>" --body "<body>"`, adding `--base "$BASE_BRANCH"` when the base differs from the default, and print the resulting PR URL. If the branch name matches `gh_issue_NN` (e.g. `gh_issue_42_dark_mode`), parse `NN` and append a `Closes #NN` line to the body so the issue auto-closes on merge. Then advance the task **state record**, passing the new PR's number: run `cdd-state set pr_open --pr NN` with the new PR's number.
- **On no**: stop. The checklist above already stands on its own.
