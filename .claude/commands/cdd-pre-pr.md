Run a pre-PR checklist for the current branch. Compare against the base branch to identify all changes. This is a verification session: it runs CI gates, code-reviews the diff, and reconciles documentation against the changes.

This session is fresh and separate from the implementation session. Any "propose to the user" step in this command is a proposal to the user running this session.

## 0. Resolve the base branch

```bash
BASE_BRANCH=$(cdd-state get base_branch 2>/dev/null)
# The code-host adapter: project, then machine; the first file present wins.
for c in .cdd/code-host ~/.cdd/adapters/code-host; do [ -e "$c" ] && { CODE_HOST="$c"; break; }; done
```

**The code-host adapter is resolved once, here, and checked once, at its first use** — below when no base is recorded, else in §11. The check: the file is executable, and `"$CODE_HOST" describe` exits 0, parses as JSON, and reports `capability` `code-host` and `contract` `1`. If it passes, say in one line which adapter serves and its `backend`; it is not announced again. If it fails, the adapter is installed but broken: say so in **one line** naming its path. Here that **stops the session**; in §11 it only blocks the PR. Never fall back to git or route around it.

If `$BASE_BRANCH` is empty and `$CODE_HOST` is set, check the adapter now, then take its answer:

```bash
BASE_BRANCH=$("$CODE_HOST" default-branch | jq -r '.branch // empty')   # exit 3 (unsupported) or a failure leaves it empty
```

Whatever is still empty falls back to git, as a bare branch name:

```bash
BASE_BRANCH=${BASE_BRANCH:-$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}
BASE_BRANCH=${BASE_BRANCH:-main}
```

`$BASE_BRANCH` is the branch the task was cut from and merges back into. Use it wherever `main`/`origin/main` appears in git commands below.

## 1. Identify changes

```bash
git diff "$BASE_BRANCH"...HEAD --name-only
git status --porcelain
```

Capture the list of changed files. Use it as the scope for steps 3 and 4.

Also record the `git status --porcelain` output as the **entry snapshot**. The tree should be clean here. If it is already dirty, those are changes this session did not create — note them now; step 10 must not sweep them into the auto-commit.

## 2. Build & QA

Run the project's **check runner** — the single command that runs every gate, the same gate list CI runs. **Capture only the last 40 lines + exit code, do not read the full output.**

```bash
<check runner command>   2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
```

Report each gate as pass ✓ / fail ✗ from the runner's summary. On failure, include the captured tail. **A missing tool is a failure, never a skip** — say which tool to install; an older runner's *skipped* counts as failed too.

If the project has no single runner yet, run each gate command in sequence instead, and note the gap for step 6:

```bash
<build command>          2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<format check command>   2>&1 | tail -20; echo "EXIT:${PIPESTATUS[0]}"
<lint command>           2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<unit test command>      2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
<integration test cmd>   2>&1 | tail -40; echo "EXIT:${PIPESTATUS[0]}"
```
<!-- cdd-only-begin -->

**In this repo the runner is `./scripts/ci.sh`** — 29 gates, listed with what each checks in the registry at the top of the script; `./scripts/ci.sh list` names them and `./scripts/ci.sh <gate>` reruns one. Not fail-fast. CI runs it on Ubuntu and macOS, so a gate leaning on one host's sed/grep/awk can pass here and fail there. The `drift` and `seams` gates need interpretation rather than a rerun; see their triage section after step 8.
<!-- cdd-only-end -->

## 3. Code review

Read all changed source files from the step 1 diff.

Review for:

- Correctness and logic bugs.
- Design issues (coupling, responsibility boundaries, API shape).
- Compliance with the project coding standard linked from CLAUDE.md.

Flag any issues found. If the change establishes a convention that should become the project norm, update the coding standard accordingly.

**Then check the diff against the handoff's acceptance criteria** — its `## Requirements` section.

```bash
repo="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
branch="$(git rev-parse --abbrev-ref HEAD)"
echo "handoff: ~/.cdd/handoffs/$repo/$branch.md"
echo "plan:    ~/.cdd/handoffs/$repo/$branch.plan.md"
```

Read it and check the diff criterion by criterion. Report any criterion the diff does not satisfy, and any it satisfies differently than stated — name the deviation even if it looks right.

**Read the plan file's `## Open questions resolved` before judging a miss.** A criterion the plan records as amended or dropped is not a miss — report it as an approved amendment, with what replaced it. A criterion the diff does not satisfy, with no such record, still is.

This is a check, not a gate: if the handoff is absent, or carries no `## Requirements` (an older task), or there is no plan file, say so in one line and move on.

## 4. Documentation reconciliation

Check and **update** documentation based on the changes:

- **Architecture docs** (`doc/architecture/`): if module structure, data flow, key interfaces, threading model, or external boundaries changed, update the relevant doc. Edit directly.
- **Feature docs** (`doc/features/`): if user-visible behaviour changed or a new feature landed, update or add the relevant feature doc. Edit directly.
- **CLAUDE.md**: if module layout, build commands, or top-level constraints changed, update it. Edit directly. Keep it an index: do not add detail a slash command already injects into the sessions that need it.
- **README.md**: if anything it states — quick start, layout, status, links — went stale relative to the change, update it. Edit directly.
- **Roadmap** (`doc/knowledge_base/roadmap.md`):
  1. Tick any newly completed checkboxes directly.
  2. Identify items that should be **added, modified, or removed** based on what was implemented. Present these suggestions explicitly to the user **before** making any edits. Apply only on approval.
  3. Keep every annotation at the bar set by "Annotation conventions" in the roadmap itself: a ticked item reads like a PR title or barely more; the default is no annotation, at most one short clause for what no other artifact carries (a deferred sub-item, a caveat, a scope change). Implementation detail, rejected alternatives and reasoning go in the PR description, an ADR, or the docs.

Read each relevant doc and compare against the actual code changes. Fix reconciliation discrepancies (the doc is out of date relative to what landed) directly. Ask before structural changes (adding doc files, restructuring a doc).

Rationale lives once: where the change touches a rule whose argument already has a home, shrink any other restatement of it to the rule plus a pointer there, rather than rewriting it at full length.

## 5. Test coverage reconciliation

For each behavioural change in the diff (a new function, a new branch, changed output, a fixed bug), check whether a test covers it (the "tested behaviour" row of `doc/knowledge_base/engineering-practices.md`).

- **If the project has a test command** ("tested behaviour" marked *enforced*): confirm a test exercises the new behaviour. Flag a behavioural change that landed with no test.
- **If a change is deliberately untested** (a throwaway script, generated code, a spike): allowed, but state the reason in the PR summary.
- **If the project has no test command yet** ("tested behaviour" still *expected*): do not invent a framework. Note that the change shipped untested for lack of a harness, and confirm that standing one up is tracked as a roadmap task. If this change is exactly the kind of behaviour that motivates a first test, say so and let the user decide whether to pull that task forward.

Do not mandate a framework, a coverage threshold, or that every change be tested; "not tested, and here is why" is a valid recorded outcome. Surface it — do not block on it.

## 6. CI improvement check (conditional)

If, and only if, the change introduces a category of work the existing CI does not cover, propose specific improvements to the user. Examples that should trigger a proposal:

- A new file type or language is committed that no existing job builds, lints, or formats.
- A new test category is introduced (e.g. the first integration test) and no CI job runs it.
- A new external tool is invoked in build/test scripts but is not pinned or version-checked.
- A convention established in the step 3 review could be enforced mechanically.

Do **not** propose generic CI improvements every run. The default is silence. If you propose, the user chooses: apply now in this PR, or defer as a new roadmap task. Apply only on approval.

## 7. Workflow improvement check (conditional)

If, and only if, this task surfaced something about *how the project works* that no artifact captures, route it. Concrete triggers:

- A step had to be done by hand that no artifact describes: a command not in `CLAUDE.md`'s build/test section, a file hand-edited that the docs imply is generated, a setup detail rediscovered from scratch.
- The step 3 review enforced a rule written down nowhere — inferred rather than taken from `CLAUDE.md` or the coding standard.
- The handoff was materially wrong or incomplete: the diff contains work it did not scope, or a constraint it missed cost rework.
- Step 4 had to update a doc that no pointer in `doc/index.md` or `CLAUDE.md` would have led you to.
- A slash command's own instructions were ambiguous or wrong for this task and had to be worked around.

Route each one by scope; never leave it as a remark that dies with the session:

- **Project-specific** → the user chooses where it lands, and you recommend: applied now as an edit (a `CLAUDE.md` constraint, a coding-standard rule, a doc pointer), riding along in step 10's commit, or proposed as a roadmap item for later. A line or two argues for the edit, anything larger for the roadmap — say which you'd pick and why, ask once, apply the answer. Never pick silently. Step 9's summary names whichever landed.
- **General enough that any CDD project would want it** → offer to file an issue on the CDD repo: `gh issue create --repo drabaioli/cdd`. **Human-gated** — show the title and body, ask once, and never file without explicit approval. If `gh` is unauthenticated or the user declines, fall back to the roadmap item above and say which fallback was taken.
<!-- cdd-only-begin -->

  This repo *is* CDD, so the third route has no upstream to reach: a general improvement discovered here is a normal roadmap item (or an issue on this repo) plus the matching process-doc and template change.
<!-- cdd-only-end -->

Do **not** manufacture an improvement every run; "nothing surfaced" is the common, correct outcome. Raise it only if it would change how a future session behaves and is a pattern, not a one-off — a friction hit twice, or one that would cost the next session the same rework. At most one item per run; if two qualify, take the stronger. This step records; it never blocks the PR, and it is not a checkpoint.

## 8. Upstream drift check

Fetch the remote base first (step 1 diffed against the local one):

```bash
git fetch origin "$BASE_BRANCH"
git rev-list --count "HEAD..origin/$BASE_BRANCH"
git log --oneline "HEAD..origin/$BASE_BRANCH"
```

Report the count. If it is non-zero, say by how many commits `origin/$BASE_BRANCH` has advanced, summarize what landed, and recommend running `/cdd-merge-base` in a fresh session before opening the PR. Advisory only — it never blocks the checklist, and this session neither merges nor invokes `/cdd-merge-base` itself.

<!-- cdd-only-begin -->
## Triaging the `drift` and `seams` gates (CDD repo only)

A failure of either gate is a **judgement call, not a bug to fix blindly**. Step 2 already ran both; these notes are for reading a failure.

**`drift` — `scripts/command-drift-check.sh`.** Diffs this repo's `.claude/commands/` and `.claude/agents/` against the `template/.claude/` copies, rendered with this repo's identifiers so substitution drift cancels out. Intentionally one-sided files are listed in `scripts/command-drift-whitelist.txt`; CDD-only sections of shared files (such as this one) are fenced with `cdd-only` markers and stripped before comparison. It also asserts that the handoff schema headings match between the process doc (Section 2.6) and `cdd-next-step.md`, and that no `cdd-only` markers leak into the template.

On divergence, present each diff to the user; for each, the user decides: reconcile the repo copy, reconcile the template copy, or record a justified exception (a whitelist entry or a `cdd-only` fence).

**`seams` — `scripts/prompt-seam-check.sh`.** Verifies 12 seams between the repo's prompts with grep only; `./scripts/prompt-seam-check.sh list` names them and each failure line names its seam. Known non-commands are whitelisted in `scripts/prompt-seam-whitelist.txt`. The issue-ref and code-host-caller checks strip this file's `cdd-only` regions first: a needle of theirs satisfied only inside this section does not count.

On a broken seam, present each one to the user; for each, the user decides: fix the reference/heading/path, or record a justified exception (a whitelist entry).

For both: apply fixes only on user approval, and do not auto-edit either tree from this step.
<!-- cdd-only-end -->
## 9. Summary

Present a checklist summary:

```
## Pre-PR Checklist
- [ ] Check runner passed (<N> gates: <N> passed, <N> failed)
- [ ] Code review: no issues / issues flagged (list them)
- [ ] Handoff requirements met (or unmet/deviating criteria listed)
- [ ] Architecture docs up to date
- [ ] Feature docs up to date
- [ ] CLAUDE.md up to date
- [ ] README up to date
- [ ] Roadmap up to date
- [ ] New behaviour tested (or untested-with-reason recorded)
- [ ] CI gaps surfaced: none / proposed (list them)
- [ ] Workflow improvements: none / routed (list them)
- [ ] Upstream drift: none (or: <N> commits behind origin/<BASE_BRANCH>, /cdd-merge-base recommended)
- [ ] Reconciliation edits committed
```

Mark each item as pass ✓ or needs attention ✗ with details.

## 10. Commit reconciliation edits

Commit the documentation reconciliation edits this session made in steps 3–8 (architecture/feature docs, CLAUDE.md, README, the coding standard, and the roadmap). Local commit only — **no push**; pushing happens, if at all, in step 11.

First check the entry snapshot from step 1:

- **If the tree was already dirty on entry**, **stop and surface** it: list those paths, state that the auto-commit is skipped, and let the user resolve it. The checklist above still stands.
- **Otherwise**, commit only the files this session edited. Add them by path — do not `git add -A`:

```bash
git add <files reconciled in steps 3–8>
git commit -m '<message>'
```

Follow the repo's commit conventions from CLAUDE.md. Print a one-line summary of the commit (subject + files included). If nothing was reconciled, say so and skip the commit.

Then advance the task **state record** (advisory): run `cdd-state set checks_passed`. It skips silently if the record is absent.

## 11. Open PR (optional)

After the checklist, offer to open the PR. This is human-gated — never open a PR without explicit confirmation.

**Code host.** Use the adapter §0 resolved. If §0 did not check it (a base was recorded), check it now as §0 describes (announcing it once if usable); broken → say so in one line naming its path and **do not open the PR** (the checklist still stands). With none resolved, print `No code-host adapter is installed; run /cdd-retrofit in this project to install one.` and **skip this step** (the checklist still stands). An adapter carries its own authentication: when that is missing, the adapter's own error line is what the user sees.

**If the branch already has an open PR, stop here.** If the adapter's `describe.verbs` has `pr-for-branch`, run `"$CODE_HOST" pr-for-branch "$(git rev-parse --abbrev-ref HEAD)"` (a JSON array, newest first) and keep the entries whose `state` is `open`. If the verb is undeclared, it exits 3, or it fails, fall back to `cdd-state get pr` (empty when there is no record or no PR). If either finds a PR, print `PR #<ref> is already open — push to update it.` and skip the rest of this step: no offer to open a PR, no close lines. The checklist still stands.

If §8 found upstream drift, restate the recommendation to run `/cdd-merge-base` before opening the PR, and let the user decide whether to proceed anyway.

Ask: **"Open a PR now?"** Do not pre-show a title or body, and do not print manual PR instructions — just ask whether to proceed.

- **On yes**: derive a title from the branch/commits and a body from the change summary. **Target the PR at the task's base branch:** if `$BASE_BRANCH` differs from the platform default (`git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's#^origin/##'`, a bare name like `$BASE_BRANCH`), the PR must set `--base "$BASE_BRANCH"` — but first confirm the base exists on the remote (`git ls-remote --exit-code --heads origin "$BASE_BRANCH"`). If it does not (e.g. the task stacks on a never-pushed local base branch), **stop and ask** the user: push the base branch first, retarget the PR at the default branch, or abort. Derive the body's close lines as described under **Close lines** below. Then open it, adding `--base "$BASE_BRANCH"` when the base differs from the default:
  If the adapter's `describe.verbs` lacks `pr-create`, say in one line that this code host's adapter cannot open PRs, and do not open one. Otherwise run `"$CODE_HOST" pr-create --title "<title>" --body "<body>"` and print the returned `.url`; the new PR's number is its `.ref`. An exit 3 reads as the undeclared case; any other failure → say in one line that the PR was not opened, quoting the adapter's error line, and never retry another way.

  Once a PR is open, advance the task **state record**: run `cdd-state set pr_open --pr NN` with the new PR's number.
- **On no**: stop. The checklist already stands on its own.

**Close lines.** The body carries one close line per reference the task was sourced from. Read the recorded references first:

```bash
cdd-state get issue_refs    # one reference per line; empty when none were recorded
```

- **Non-empty**: resolve the tracker down the ladder — project, then machine — and take the first file present:

  ```bash
  for c in .cdd/tracker ~/.cdd/adapters/tracker; do [ -e "$c" ] && { echo "$c"; break; }; done
  ```

  If one resolved but is broken — not executable, or its `describe` exits non-zero, does not parse, or reports another `capability` or an unsupported `contract` — say so in one line naming it and emit **no close lines**; do not guess a `Closes #` syntax. The PR itself can still be opened.

  **Announce the rung in one line, once**, before the first call — not once per reference. Then, per reference, run `<adapter> issue-close-token <ref>` and append its `.token` to the body — one line each, in recorded order. With nothing resolved, emit **no close lines** and say in one line `No tracker adapter is installed; run /cdd-retrofit in this project to install one.` — the PR still opens, and the issues stay open to close by hand. An adapter that does not declare `issue-close-token` in its `describe.verbs` yields **no close lines at all** — say so in one line rather than guessing a syntax.

  **Then say what those lines will actually do**, once, before asking to open the PR. When the tracker's and the code host's `describe.backend` are the same (`github`, `gitlab`), the code host closes the issue on merge — say that plainly, adding GitLab's caveat when it is `gitlab`: it closes only on a merge into the default branch, and only while the project's "Auto-close referenced issues on default branch" setting is on (the default). Otherwise the line fires only if the tracker's own code-host integration is installed and watching this repo (Jira's DVCS connector, say); name that condition rather than implying the issue will close.
- **Empty** (no record, an unsynced or reaped one, or no `jq`): **no close lines.** Do not derive references from the branch name. Say so in one line at the confirmation step; the PR still opens, and the issues stay open to close by hand.
