Address the open PR's review feedback: read the review comments for the current branch, triage them, implement the change-requests (pushing back where warranted), then auto-commit + push the result and auto-post in-thread replies.

Run on the feature branch (not on main), after a PR has been opened and reviewed.

**Automation:** one checkpoint, up front — the triage plan in step 4. Once it is approved, edits, commit, push and in-thread replies run without further confirmation; add no per-action gates. The one exception: routing a workflow gap (step 5), which the triage plan does not settle and which is asked once, with a recommendation. Never resolve review threads; the user does.

## 1. Discover the open PR

Confirm the current branch is not `main`:

```bash
git rev-parse --abbrev-ref HEAD
```

Resolve the code host down the ladder — project, then machine; the first file present wins:

```bash
for c in .cdd/code-host ~/.cdd/adapters/code-host; do [ -e "$c" ] && { CODE_HOST="$c"; break; }; done
```

If `$CODE_HOST` is set, check it: the file is executable, and `"$CODE_HOST" describe` exits 0, parses as JSON, and reports `capability` `code-host` and `contract` `1`. If any of that fails, say in **one line** that the adapter at its path is installed but broken, and **stop** — do not route around it. If usable, say in one line which adapter serves and its `backend`. With nothing resolved, print `No code-host adapter is installed; run /cdd-retrofit in this project to install one.` and **stop**.

Resolve the open PR for the current branch:

```bash
"$CODE_HOST" pr-for-branch "$(git rev-parse --abbrev-ref HEAD)"   # JSON array, newest first
```

Keep only entries whose `state` is `open`. If `pr-for-branch` is not in the adapter's `describe.verbs` (or it exits 3), say so in one line and ask the user for the PR reference. Any other failure → say so in one line, quoting the adapter's error line, and stop.

- No open PR → stop and report: "No open PR for this branch; nothing to process."
- More than one open PR → stop and ask the user which PR number to process.

Hold the open entry's `.ref` as NUMBER.

## 2. Read all three comment surfaces

Read inline review threads (with resolution state), review summary bodies, and general conversation comments. One call returns all three:

```bash
"$CODE_HOST" pr-comments NUMBER
```

`threads[]` carry `id` (the reply target for step 7), `resolved`, `outdated`, `path`, `line` (absent when outdated) and `comments[]` with each `author`; `reviews[]` are the non-empty summary bodies; `comments[]` are the general conversation comments; `viewer` is who the adapter acts as, when it can tell. If `pr-comments` is not in `describe.verbs` (or it exits 3), say in one line that this code host's adapter cannot read review feedback, and stop. Any other failure → say so in one line, quoting the adapter's error line, and stop.

## 3. Scope: only unresolved / open feedback

Process **only** what still needs action:

- Skip resolved threads (`resolved`).
- Skip threads whose last comment is your own reply (last `comments[].author` equals `viewer`). If the adapter omits `viewer`, say so in one line, skip nothing on authorship, and mark those threads in the triage plan as possibly already answered, so the step 4 checkpoint can drop them.
- Skip comments already addressed (e.g. by a later commit or reply).

If nothing is unresolved, report "no open review feedback to process" and stop.

## 4. Triage (the retained checkpoint)

Classify each open item and present a short plan **before editing any files**:

- **change-request** — reviewer wants a code change.
- **question** — answer it (change code only if the answer implies a change).
- **nit** — minor/style; address unless trivially wrong.
- **discussion** — opinion or context; reply, usually no code change.
- **workflow-gap** — not really about this diff: it points at something the project's own substrate should have prevented or described (a `CLAUDE.md` constraint, a convention, a doc pointer, a slash command that reads wrong). Route it per step 5 rather than patching only the symptom. A comment can be both this and a change-request.

Present the plan compactly, e.g.:

```
## /cdd-process-pr triage (PR #NUMBER)

1. [change-request] src/foo.ts:42 — "rename to X" → will rename.
2. [question]        review summary — "why no retry?" → will answer, no code change.
3. [change-request] src/bar.ts:10 — "drop the lock here" → DISAGREE (introduces a race); will explain in reply.
4. [nit]             general comment — "typo in log" → will fix.
5. [workflow-gap]   src/baz.ts:8 — third PR asked for the same import order → will add the rule to the coding standard.
```

Wait for the user to confirm the triage before editing. That approval covers the rest of the run, including the push and replies in steps 6–7.

## 5. Address the feedback

Implement the change-requests and nits, applying project conventions from CLAUDE.md.

**Push back, do not blindly execute.** When a change-request is wrong, risky, or conflicts with a project constraint, do **not** implement it; decline it and prepare a short reasoned explanation for the reply in step 7.

For questions, prepare the answer text. For discussion comments, prepare a brief reply.

**Route the workflow-gaps** by scope, with the same bar as `/cdd-pre-pr` step 7: it would change how a future session behaves, and it is a pattern rather than a one-off.

- **Project-specific** → the user chooses where it lands, and you recommend: folded into this PR as an edit in this run's commit (a `CLAUDE.md` constraint, a coding-standard rule, a doc pointer), or a roadmap item for later. A line or two argues for folding it in, anything larger for the roadmap — say which you'd pick and why, ask once, apply the answer. Never pick silently.
- **General enough that any CDD project would want it** → offer to file an issue on the CDD repo: `gh issue create --repo drabaioli/cdd`. **Human-gated** — show the title and body, ask once, and never file without explicit approval. If `gh` is unauthenticated or the user declines, fall back to the roadmap item above and say which fallback was taken.
<!-- cdd-only-begin -->

  This repo *is* CDD, so the third route has no upstream to reach: a general improvement discovered here is a normal roadmap item (or an issue on this repo) plus the matching process-doc and template change.
<!-- cdd-only-end -->

Say in the reply (step 7) where the gap was routed. The default is still silence: most review comments are about the diff and nothing else.

## 6. Commit and push

Commit the code changes in logical groups, with messages referencing what each addressed, following the repo's commit conventions from CLAUDE.md. Commit only the files you changed, adding them by path; never `git add -A`. If the tree holds changes you did not make, surface them rather than committing them.

```bash
git add <file>...   # only the files this session changed
git commit -m '...'
git push
```

Push **before** posting any reply (step 7 cites the pushed sha). If nothing changed (only answers or declines), there is no commit; go to step 7. If the push fails, say so in one line and do not post replies that cite a commit — print them for the user instead, as step 7 does when `pr-reply` is unavailable.

## 7. Post replies

Reply **in-thread** to each processed review thread (to the specific comment, not a top-level PR comment), using the thread's `id` from step 2:

```bash
"$CODE_HOST" pr-reply NUMBER --to THREAD_ID --body '...'
```

If `pr-reply` is not in `describe.verbs` (or it exits 3), say so in one line and print each prepared reply instead — with its thread's `path:line`, or "top-level" — for the user to post. If a single reply fails, say which in one line and carry on.

Keep every reply to a sentence or two. Content by triage class:

- **change-request (implemented):** "Addressed in `<sha>`.", citing the commit pushed in step 6.
- **question:** the answer, briefly.
- **declined change-request:** the reason in a few plain sentences — direct, not dismissive.
- **nit / discussion:** a one-line acknowledgement or reply.
- **workflow-gap:** where it was routed — the edit applied, the roadmap item proposed, or the CDD issue filed.

Do **not** resolve threads, including addressed ones.

For review-summary bodies and general conversation comments with no inline thread, post a single top-level comment that references them:

```bash
"$CODE_HOST" pr-reply NUMBER --body '...'
```

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

Then advance the task **state record** (advisory): run `cdd-state set addressed --pr NUMBER`. It skips silently if the record is absent.
