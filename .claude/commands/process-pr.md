Address the open PR's review feedback: read the review comments for the current branch, triage them, implement the change-requests (pushing back where warranted), then auto-post in-thread replies and auto-commit + push the result.

Run this command on the feature branch (not on main), after a PR has been opened and someone has reviewed it. It is a post-review side-loop, analogous in position to `/merge-main`.

**Note on automation:** unlike the other CDD commands, this one does **not** gate its GitHub-side actions. It auto-posts replies and auto-commits + pushes without asking. This is a deliberate exception (see the process doc, "The `/process-pr` exception"), justified by the single-user, fast review-iteration loop where the PR is open and every change is visible and revertable in git. The one checkpoint it keeps is the triage plan in step 4. Do not add confirmation gates around the GitHub actions.

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
          id
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

Each thread node has a GraphQL `id` (used to reply/resolve) and a list of comments; the first comment's `databaseId` is the REST id used to reply in-thread.

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
- Skip comments that are already addressed (e.g. a later commit or reply already handled them).

This keeps re-runs idempotent: running `/process-pr` again after a review round only picks up the newly-unresolved items.

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

This is the one human checkpoint in this command. Wait for the user to confirm the triage before proceeding to edit. (The GitHub actions in steps 6–7 are not gated.)

## 5. Address the feedback

Implement the change-requests and nits. Apply project conventions from CLAUDE.md.

**Push back, do not blindly execute.** When a change-request is wrong, risky, or conflicts with a project constraint, do **not** implement it. Decide to decline it, and prepare a short reasoned explanation for the reply in step 6. Human-in-the-loop reasoning lives at the code level even though posting and pushing are automated.

For questions, prepare the answer text. For discussion comments, prepare a brief reply.

## 6. Post replies (no confirmation gate)

Reply **in-thread** to each processed review thread — reply to the specific comment, not just a top-level PR comment — using the first comment's `databaseId`:

```bash
gh api -X POST repos/OWNER/REPO/pulls/NUMBER/comments/COMMENT_ID/replies -f body='...'
```

Reply content by triage class:

- **change-request (implemented):** a short "Addressed in `<sha>`." (reference the commit from step 7; if you commit first, you will have the sha; otherwise post the reply after committing).
- **question:** the answer.
- **declined change-request:** the reasoning for declining — clearly, not dismissively.
- **nit / discussion:** a brief acknowledgement or reply.

After a thread is genuinely addressed (change-request implemented or question answered), resolve it so re-runs skip it:

```bash
gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread { isResolved } } }' -F id=THREAD_ID
```

Leave **declined** threads unresolved, so the human sees the open disagreement.

For review-summary bodies and general conversation comments that have no inline thread to reply into, respond with a single top-level comment that references them:

```bash
gh pr comment NUMBER --body '...'
```

## 7. Commit and push (no confirmation gate)

Commit the code changes in logical groups, with messages referencing what each addressed. Follow the repo's commit conventions from CLAUDE.md, including the `Co-Authored-By` trailer.

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

Next: re-run /pre-pr in a fresh session before the PR goes back for re-review.
```

The user should re-run `/pre-pr` before re-requesting review, so the updated branch passes all gates.
