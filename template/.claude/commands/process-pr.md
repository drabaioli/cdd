Address the open PR's review feedback: read the review comments for the current branch, triage them, implement the change-requests (pushing back where warranted), then auto-post in-thread replies and auto-commit + push the result.

Run this command on the feature branch (not on main), after a PR has been opened and someone has reviewed it. It is a post-review side-loop, analogous in position to `/merge-main`.

**Note on automation:** this command has a single checkpoint, placed up front: the triage plan in step 4. Once the user approves that plan, the rest of the run — edits, in-thread replies, commit, push — executes without further confirmation gates (see the process doc, "The `/process-pr` exception"). Do not add per-action gates after the plan is approved. Review threads are never resolved by this command; the user resolves them.

## 1. Discover the open PR

Confirm the current branch is not `main`:

```bash
git rev-parse --abbrev-ref HEAD
```

Resolve the open PR for the current branch:

```bash
gh pr view --json number,url,state,headRefName
gh repo view --json owner,name -q '.owner.login + "/" + .name'
```

- If there is no open PR, stop and report clearly: "No open PR for this branch; nothing to process."
- If `gh` reports more than one candidate PR, stop and ask the user which PR number to process.

Hold the owner, repo, and PR number; the steps below refer to them as OWNER, REPO, and NUMBER.

## 2. Read all three comment surfaces

Read every place a reviewer can leave feedback. `gh pr view` alone is insufficient for inline review threads and their resolution state, so use `gh api`.

**Inline review threads (with resolution state), via GraphQL:**

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes {
          isResolved
          isOutdated
          comments(first:100) {
            nodes { databaseId body path line author { login } }
          }
        }
      }
    }
  }
}' -F owner=OWNER -F repo=REPO -F pr=NUMBER
```

Each thread is a list of comments; the first comment's `databaseId` is the REST id used to reply in-thread.

**Review summary bodies (the text a reviewer writes when approving / requesting changes):**

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/reviews
```

Use entries whose `body` is non-empty.

**General PR conversation comments (not attached to a diff line):**

```bash
gh api repos/OWNER/REPO/issues/NUMBER/comments
```

## 3. Scope: only unresolved / open feedback

Process **only** what still needs action:

- Skip any review thread where `isResolved` is `true`.
- Skip any thread whose latest comment is your own reply (compare `author.login` against `gh api user -q .login`) — it was addressed in a previous run and is waiting on the reviewer.
- Skip comments that are already addressed (e.g. a later commit or reply already handled them).

This keeps re-runs idempotent: since the command never resolves threads itself, a re-run after a review round only picks up items with new reviewer activity.

If nothing is unresolved, report "no open review feedback to process" and stop.

## 4. Triage (the retained checkpoint)

Classify each open item and present a short plan to the user **before editing any files**:

- **change-request** — reviewer wants a code change.
- **question** — reviewer is asking something; answer it (and change code only if the answer implies a change).
- **nit** — minor/style; address unless trivially wrong.
- **discussion** — opinion or context; reply, usually no code change.

Present the plan compactly, e.g.:

```
## /process-pr triage (PR #NUMBER)

1. [change-request] src/foo.ts:42 — "rename to X" → will rename.
2. [question]        review summary — "why no retry?" → will answer, no code change.
3. [change-request] src/bar.ts:10 — "drop the lock here" → DISAGREE (introduces a race); will explain in reply.
4. [nit]             general comment — "typo in log" → will fix.
```

This is the one human checkpoint in this command. Wait for the user to confirm the triage before proceeding to edit. That approval covers the rest of the run, including the GitHub actions in steps 6–7.

## 5. Address the feedback

Implement the change-requests and nits. Apply project conventions from CLAUDE.md.

**Push back, do not blindly execute.** When a change-request is wrong, risky, or conflicts with a project constraint, do **not** implement it. Decide to decline it, and prepare a short reasoned explanation for the reply in step 6. Human-in-the-loop reasoning lives at the code level even though posting and pushing are automated.

For questions, prepare the answer text. For discussion comments, prepare a brief reply.

## 6. Post replies

Reply **in-thread** to each processed review thread — reply to the specific comment, not just a top-level PR comment — using the first comment's `databaseId`:

```bash
gh api -X POST repos/OWNER/REPO/pulls/NUMBER/comments/COMMENT_ID/replies -f body='...'
```

Keep every reply short — a sentence or two. Content by triage class:

- **change-request (implemented):** a short "Addressed in `<sha>`." (reference the commit from step 7; if you commit first, you will have the sha; otherwise post the reply after committing).
- **question:** the answer, briefly.
- **declined change-request:** the reason for declining in a few plain sentences — direct, not dismissive, no essays.
- **nit / discussion:** a one-line acknowledgement or reply.

Do **not** resolve threads — leave all of them, including addressed ones, for the user to resolve during re-review.

For review-summary bodies and general conversation comments that have no inline thread to reply into, respond with a single top-level comment that references them:

```bash
gh pr comment NUMBER --body '...'
```

## 7. Commit and push

Commit the code changes in logical groups, with messages referencing what each addressed. Follow the repo's commit conventions from CLAUDE.md.

```bash
git add -A
git commit -m '...'
git push
```

Push to the PR branch. Sequencing note: if you want the reply in step 6 to cite the commit sha, commit first, then post replies; otherwise post replies and follow with the commit. Either order is fine as long as both happen.

## 8. Follow-up

Summarize what was processed:

```
## /process-pr summary (PR #NUMBER)
- Threads addressed: <count>
- Questions answered: <count>
- Change-requests declined: <count> (replies explain why)
- Commits pushed: <count>
```
