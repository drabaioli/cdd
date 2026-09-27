Address the open PR's review feedback: read the review comments for the current branch, triage them, implement the change-requests (pushing back where warranted), then auto-post in-thread replies and auto-commit + push the result.

Run this command on the feature branch (not on main), after a PR has been opened and someone has reviewed it. It is a post-review side-loop, analogous in position to `/cdd-merge-base`.

**Note on automation:** this command has a single checkpoint, placed up front: the triage plan in step 4. Once the user approves that plan, the rest of the run — edits, in-thread replies, commit, push — executes without further confirmation gates. Do not add per-action gates after the plan is approved — the one exception is where step 5 routes a workflow gap (folded into this PR, a roadmap item, or an issue on another repo), which the triage plan does not settle and which is asked once, with a recommendation. Review threads are never resolved by this command; the user resolves them.

## 1. Discover the open PR

Confirm the current branch is not `main`:

```bash
git rev-parse --abbrev-ref HEAD
```

Resolve the code host down the ladder — project, then machine, then built-in; the first file present wins:

```bash
for c in .cdd/code-host ~/.cdd/adapters/code-host; do [ -e "$c" ] && { CODE_HOST="$c"; break; }; done
```

If `$CODE_HOST` is set, check it before using it: the file is executable, and `"$CODE_HOST" describe` exits 0, parses as JSON, and reports `capability` `code-host` and `contract` `1`. If any of that fails, the adapter is installed but broken — say so in **one line** naming its path, and **stop**; do not fall back to `gh`, because an installed adapter declares which code host this project uses. If it is usable, say in one line which adapter serves and its `backend`. With nothing resolved, say in one line that no code-host adapter is installed and the built-in `gh` path serves. Steps 2, 3 and 6 each have one form per path; use the one that matches.

Resolve the open PR for the current branch.

**Through the adapter:**

```bash
"$CODE_HOST" pr-for-branch "$(git rev-parse --abbrev-ref HEAD)"   # JSON array, newest first
```

Keep only the entries whose `state` is `open`. If `pr-for-branch` is not in the adapter's `describe.verbs` (or it exits 3), say so in one line and ask the user for the PR reference instead. Any other failure → say so in one line, quoting the adapter's error line, and stop.

**On the built-in `gh` path:**

```bash
gh pr view --json number,url,state,headRefName
gh repo view --json owner,name -q '.owner.login + "/" + .name'
```

On either path:

- If there is no open PR, stop and report clearly: "No open PR for this branch; nothing to process."
- If there is more than one open candidate PR, stop and ask the user which PR number to process.

Hold the PR number — the open entry's `.ref` through the adapter — and, on the built-in path, the owner and repo; the steps below refer to them as NUMBER, OWNER, and REPO.

## 2. Read all three comment surfaces

Read every place a reviewer can leave feedback: inline review threads (with their resolution state), review summary bodies, and general conversation comments.

**Through the adapter**, one call returns all three:

```bash
"$CODE_HOST" pr-comments NUMBER
```

Its `threads[]` carry `id` (the reply target for step 6), `resolved`, `outdated`, `path`, `line` (absent when outdated) and `comments[]` with each `author`; `reviews[]` are the summary bodies, already limited to non-empty ones; `comments[]` are the general conversation comments; `viewer` is who the adapter acts as, when it can tell. If `pr-comments` is not in the adapter's `describe.verbs` (or it exits 3), say in one line that this code host's adapter cannot read review feedback, and stop — there is nothing to triage. Any other failure → say so in one line, quoting the adapter's error line, and stop.

**On the built-in `gh` path**, `gh pr view` alone is insufficient for inline review threads and their resolution state, so use `gh api`.

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

- Skip any review thread that is resolved (`isResolved` on the built-in path, `resolved` through the adapter).
- Skip any thread whose latest comment is your own reply — it was addressed in a previous run and is waiting on the reviewer. On the built-in path, compare `author.login` against `gh api user -q .login`; through the adapter, compare the thread's last `comments[].author` against `viewer`. If the adapter omits `viewer`, say so in one line, skip nothing on authorship, and mark those threads in the triage plan as possibly already answered, so the step 4 checkpoint can drop them. Never ask `gh api user` on the adapter path: it would ask the wrong system.
- Skip comments that are already addressed (e.g. a later commit or reply already handled them).

This keeps re-runs idempotent: since the command never resolves threads itself, a re-run after a review round only picks up items with new reviewer activity.

If nothing is unresolved, report "no open review feedback to process" and stop.

## 4. Triage (the retained checkpoint)

Classify each open item and present a short plan to the user **before editing any files**:

- **change-request** — reviewer wants a code change.
- **question** — reviewer is asking something; answer it (and change code only if the answer implies a change).
- **nit** — minor/style; address unless trivially wrong.
- **discussion** — opinion or context; reply, usually no code change.
- **workflow-gap** — the comment is not really about this diff: it points at something the project's own substrate should have prevented or described (a `CLAUDE.md` constraint, a convention, a doc pointer, a slash command that reads wrong). Route it per step 5 rather than patching only the symptom. A comment can be both this and a change-request.

Present the plan compactly, e.g.:

```
## /cdd-process-pr triage (PR #NUMBER)

1. [change-request] src/foo.ts:42 — "rename to X" → will rename.
2. [question]        review summary — "why no retry?" → will answer, no code change.
3. [change-request] src/bar.ts:10 — "drop the lock here" → DISAGREE (introduces a race); will explain in reply.
4. [nit]             general comment — "typo in log" → will fix.
5. [workflow-gap]   src/baz.ts:8 — third PR asked for the same import order → will add the rule to the coding standard.
```

This is the one human checkpoint in this command. Wait for the user to confirm the triage before proceeding to edit. That approval covers the rest of the run, including the replies and push in steps 6–7.

## 5. Address the feedback

Implement the change-requests and nits. Apply project conventions from CLAUDE.md.

**Push back, do not blindly execute.** When a change-request is wrong, risky, or conflicts with a project constraint, do **not** implement it. Decide to decline it, and prepare a short reasoned explanation for the reply in step 6. Human-in-the-loop reasoning lives at the code level even though posting and pushing are automated.

For questions, prepare the answer text. For discussion comments, prepare a brief reply.

**Route the workflow-gaps.** A review comment is the one place a gap in how the project works becomes visible from outside the session that caused it, so this is where it gets captured — the review-time arm of the "the workflow improves itself" commitment, alongside `/cdd-pre-pr`'s discovery-time check. Route by scope, using the same bar that step's check uses (it would change how a future session behaves, and it is a pattern rather than a one-off):

- **Project-specific** → the user chooses where it lands, and you recommend: folded into this PR as an edit in this run's commit (a `CLAUDE.md` constraint, a coding-standard rule, a doc pointer), or a roadmap item for later. A line or two argues for folding it in, anything larger for the roadmap — say which you'd pick and why, ask once, apply the answer. Never pick silently; the approved triage plan settles which comments get addressed, not where a gap that outlives this diff should land.
- **General enough that any CDD project would want it** → offer to file an issue on the CDD repo: `gh issue create --repo drabaioli/cdd`. **Human-gated** — show the title and body, ask once, and never file without explicit approval. If `gh` is unauthenticated or the user declines, fall back to the roadmap item above and say which fallback was taken.
<!-- cdd-only-begin -->

  This repo *is* CDD, so the third route has no upstream to reach: a general improvement discovered here is a normal roadmap item (or an issue on this repo) plus the matching process-doc and template change.
<!-- cdd-only-end -->

Say in the reply (step 6) where the gap was routed, so the reviewer sees the comment produced a rule and not just a patch. The default here is still silence: most review comments are about the diff and nothing else.

## 6. Post replies

Reply **in-thread** to each processed review thread — reply to the specific comment, not just a top-level PR comment.

**Through the adapter**, using the thread's `id` from step 2:

```bash
"$CODE_HOST" pr-reply NUMBER --to THREAD_ID --body '...'
```

If `pr-reply` is not in the adapter's `describe.verbs` (or it exits 3), say so in one line and print each prepared reply instead — with its thread's `path:line`, or "top-level" — for the user to post; step 7 still runs. If a single reply fails, say which in one line and carry on with the rest.

**On the built-in `gh` path**, using the first comment's `databaseId`:

```bash
gh api -X POST repos/OWNER/REPO/pulls/NUMBER/comments/COMMENT_ID/replies -f body='...'
```

Keep every reply short — a sentence or two. Content by triage class:

- **change-request (implemented):** a short "Addressed in `<sha>`." (reference the commit from step 7; if you commit first, you will have the sha; otherwise post the reply after committing).
- **question:** the answer, briefly.
- **declined change-request:** the reason for declining in a few plain sentences — direct, not dismissive, no essays.
- **nit / discussion:** a one-line acknowledgement or reply.
- **workflow-gap:** name where it was routed — the edit applied, the roadmap item proposed, or the CDD issue filed.

Do **not** resolve threads — leave all of them, including addressed ones, for the user to resolve during re-review.

For review-summary bodies and general conversation comments that have no inline thread to reply into, respond with a single top-level comment that references them:

```bash
"$CODE_HOST" pr-reply NUMBER --body '...'   # through the adapter
gh pr comment NUMBER --body '...'           # on the built-in gh path
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
## /cdd-process-pr summary (PR #NUMBER)
- Threads addressed: <count>
- Questions answered: <count>
- Change-requests declined: <count> (replies explain why)
- Workflow gaps routed: <count> (edit / roadmap item / CDD issue)
- Commits pushed: <count>
- Replies not posted: <count> (only when some were printed instead or failed)
```

Then advance the task **state record** (advisory), passing the PR number: run `cdd-state set addressed --pr NUMBER`. It skips silently if the record is absent.
