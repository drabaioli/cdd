Integrate the current state of the base branch into the feature branch. Two phases: a **dry-run conflict assessment** first, then the actual merge with conflict resolution. The approval between the two phases is conditional — the merge runs automatically when the dry run proves the case mechanically trivial (step 4), and stops for approval otherwise.

Run this command on the feature branch (not on the base branch). Use it when:

- The base branch has advanced under your feature branch and you want to integrate before opening or merging the PR.
- Something useful has landed on the base branch (a new utility, a refactor, an updated convention) that this branch should pick up without a separate roadmap task.

## 0. Resolve the base branch

```bash
BASE_BRANCH=$(cdd-state get base_branch 2>/dev/null)
BASE_BRANCH=${BASE_BRANCH:-$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo main)}
```

This reads the task's recorded base branch — the branch it was cut from and merges back into. When no base was recorded (every single-integration-branch project), it falls back to the hosting platform's default branch, so behaviour is unchanged there. Use `$BASE_BRANCH` everywhere `main`/`origin/main` appeared in earlier versions of this command. All git commands below use this variable.

## 1. Sanity check

Confirm the current branch is not the base branch:

```bash
git rev-parse --abbrev-ref HEAD
```

Confirm the worktree is clean:

```bash
git status --porcelain
```

If there are uncommitted changes, stop and ask the user whether to stash or commit before continuing. Do not merge over uncommitted work.

## 2. Update local base branch reference

```bash
git fetch origin "$BASE_BRANCH"
```

Determine how far the branch has diverged from `origin/$BASE_BRANCH`:

```bash
git log --oneline "HEAD..origin/$BASE_BRANCH" | head -50
git log --oneline "origin/$BASE_BRANCH..HEAD" | head -50
```

Report:

- Number of commits on `origin/$BASE_BRANCH` not in this branch.
- Number of commits on this branch not in `origin/$BASE_BRANCH`.

If there is nothing on `origin/$BASE_BRANCH` not in this branch, there is nothing to merge. Stop and report.

## 3. Dry-run conflict assessment

Perform a non-committing test merge to surface conflicts without mutating the working tree:

```bash
git merge-tree --write-tree --name-only "origin/$BASE_BRANCH" HEAD
```

Capture the list of conflicting files, and record whether the count is **zero** — step 4 reads it.

If there are conflicts, for each conflicting file:

- Read both versions and the merge base. Use:
  ```bash
  git show "origin/$BASE_BRANCH:<file>"
  git show HEAD:<file>
  git show "$(git merge-base "origin/$BASE_BRANCH" HEAD):<file>"
  ```
- Classify the conflict:
  - **Mechanical**: textual collision in a region where the intent is obvious (e.g. both sides added an import, both sides added an entry to the same list, formatting drift).
  - **Logical**: the two sides changed the same logical concern in incompatible ways (e.g. one renamed a function the other modified the body of).
  - **Structural**: file moved/renamed/deleted on one side and modified on the other.

Whether or not there were conflicts, scan the non-conflicting changes on `origin/$BASE_BRANCH` for items relevant to this branch:

- New conventions established on the base branch that this branch's code should adopt.
- New utilities or helpers that obviate code on this branch.
- Refactored interfaces that this branch consumes.

Record the outcome of this scan as an explicit count — "flagged N items" or "flagged nothing". Step 4 reads it too; "I didn't really look" is not one of the answers.

## 4. Decide the path, then report

**The merge proceeds automatically, with no approval prompt, when all of these hold:**

1. The worktree was clean (step 1).
2. Step 3's `git merge-tree` reported **zero** conflicting files.
3. Step 3's non-conflict scan flagged **nothing**.
4. The post-merge verify (step 7) passes. This one is a *safety net, not a precondition* — it is checked after the merge exists, and step 7 says what to do when it fails.

Criteria 1–3 are mechanical facts, not judgement calls. If all three hold, print a single line naming them and go straight to step 5:

```
Trivial merge: worktree clean, 0 conflicting files, nothing flagged to adopt — merging without asking. Verify follows in step 7.
```

Do **not** present the assessment block below as a prompt on this path and do not wait for a reply; step 8's summary reports the assessment afterwards.

**If any of criteria 1–3 fails**, present the assessment to the user:

```
## Merge-base assessment

Commits to integrate from origin/<BASE_BRANCH>: <N>
Commits unique to this branch:                     <M>

### Conflicts
- <file>: <mechanical | logical | structural>, <one-line description>
- <file>: ...

### Non-conflict items worth attention
- <file>: <new convention / new utility / refactored interface> — <one-line implication>
- ...

### Recommendation
<one of:>
  - No conflicts, but <N> items flagged to adopt; recommend proceeding, then deciding each in step 6.
  - Mostly mechanical conflicts, recommend proceeding; manual review needed on <N> files.
  - Logical/structural conflicts present; recommend discussing approach before merging.
```

Then **stop and wait for explicit user approval**. Do not begin the merge. This is the point where the human sees the conflict complexity, so the wait is the whole purpose of reaching this branch.

## 5. Perform the merge

On user approval, or automatically via step 4's trivial path:

```bash
git merge --no-edit "origin/$BASE_BRANCH"
```

`--no-edit` takes the default merge message: on the trivial path nobody is watching, and a merge that drops into an editor would hang the session.

On the trivial path there is nothing to resolve — step 4's criterion 2 established zero conflicting files — so the merge command is the whole step. Otherwise resolve conflicts file by file:

- For mechanical conflicts, resolve directly and explain each resolution in one line.
- For logical conflicts, propose a resolution and ask the user before applying. Do not silently pick a side.
- For structural conflicts (renames, deletes), always ask before applying.

After resolving each file, stage it:

```bash
git add <file>
```

When all conflicts are resolved, complete the merge:

```bash
git merge --continue
```

## 6. Adopt non-conflict improvements (optional)

**On the trivial path this step is a no-op, by construction** — step 4's criterion 3 requires that the scan flagged nothing, so there is nothing here to adopt. That is intended, not an oversight: an automatic merge never adopts improvements, and anything worth adopting sends the run down the approval path instead. Skip to step 7.

Otherwise, for each non-conflict item flagged in step 3 (new conventions, helpers, refactored interfaces), ask the user whether to apply now in a follow-up commit on this branch. Default to asking, not assuming.

If applied, commit separately from the merge commit with a message like:

```
adopt: <one-line description of what was adopted from the base branch>
```

## 7. Verify

Run the project build and tests to confirm the merged state is healthy. Use the same commands as `/cdd-pre-pr` step 2, with the same "tail 40 lines + exit code" capture pattern. This is step 4's criterion 4, and it runs on both paths.

If anything fails, report the failure — naming the failing gate and including the captured tail — and stop. Do not push.

**If the merge was automatic**, say so explicitly in the same breath: the tree now holds a merge nobody approved and the verify is red. Offer the undo, and let the user choose:

```bash
git reset --hard ORIG_HEAD   # discards the merge commit; safe because step 1 proved the tree clean
```

Do not run it unasked, and do not go quiet — never leave a broken tree without saying it is broken and how to get out.

## 8. Summary

Present a final summary:

```
## Merge-base summary
- [ ] Merge path: automatic (trivial) | approved by user
- [ ] Merge completed
- [ ] Commits integrated from origin/<BASE_BRANCH>: <N>
- [ ] Conflicts resolved: <count> (mechanical: M, logical: L, structural: S)
- [ ] Improvements adopted: <count or "none">
- [ ] Build passes
- [ ] Tests pass

Next: re-run /cdd-pre-pr before opening or updating the PR.
```

On the automatic path this summary is where the assessment lands, since step 4 skipped its report: state the commit counts and that zero files conflicted and nothing was flagged to adopt, so the run is legible after the fact without re-deriving it.

Then advance the task **state record** (advisory): run `cdd-state set merged`. It skips silently if the record is absent.

The user should re-run `/cdd-pre-pr` in a fresh session after `/cdd-merge-base` to ensure the merged state passes all gates.
