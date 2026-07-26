Integrate the current state of the base branch into the feature branch. Two phases: a **dry-run conflict assessment** first, then on user approval the actual merge with conflict resolution.

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

Capture the list of conflicting files.

If there are no conflicts:

- Report "no conflicts; merge will be clean."
- Skip to step 5 and ask the user whether to proceed with the merge.

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

Also scan the non-conflicting changes on `origin/$BASE_BRANCH` for items relevant to this branch:

- New conventions established on the base branch that this branch's code should adopt.
- New utilities or helpers that obviate code on this branch.
- Refactored interfaces that this branch consumes.

## 4. Report

Present to the user:

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
  - Clean merge, recommend proceeding.
  - Mostly mechanical conflicts, recommend proceeding; manual review needed on <N> files.
  - Logical/structural conflicts present; recommend discussing approach before merging.
```

If conflicts are non-trivial, **stop and wait for explicit user approval**. Do not begin the merge.

## 5. Perform the merge

On user approval:

```bash
git merge "origin/$BASE_BRANCH"
```

Resolve conflicts file by file:

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

For each non-conflict item flagged in step 3 (new conventions, helpers, refactored interfaces), ask the user whether to apply now in a follow-up commit on this branch. Default to asking, not assuming.

If applied, commit separately from the merge commit with a message like:

```
adopt: <one-line description of what was adopted from the base branch>
```

## 7. Verify

Run the project build and tests to confirm the merged state is healthy. Use the same commands as `/cdd-pre-pr` step 2, with the same "tail 40 lines + exit code" capture pattern.

If anything fails, report the failure and stop. Do not push.

## 8. Summary

Present a final summary:

```
## Merge-base summary
- [ ] Merge completed
- [ ] Conflicts resolved: <count> (mechanical: M, logical: L, structural: S)
- [ ] Improvements adopted: <count or "none">
- [ ] Build passes
- [ ] Tests pass

Next: re-run /cdd-pre-pr before opening or updating the PR.
```

Then advance the task **state record** (advisory; see the process doc §2.13): run `cdd-state set merged`. It skips silently if the record is absent.

The user should re-run `/cdd-pre-pr` in a fresh session after `/cdd-merge-base` to ensure the merged state passes all gates.
