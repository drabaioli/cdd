# 0024: Leave a partially done issue open

**Status:** Accepted

## Context

[ADR 0021](0021-promote-a-multi-pr-issue-to-a-roadmap-phase.md) left out of scope a single-task
issue whose PR turns out to do only part of it: the human leaves it open and a later
`/cdd-next-step <ref>` resumes it. The tooling closed it anyway — the recorded reference made
`/cdd-pre-pr` emit a close line, and `cdd-worktree-done` / `-gc` closed it after the merge (#151).

## Decision

1. **The mark is CDD's own field.** `partial_refs`, an optional subset of `issue_refs` on the
   state record, written by its own verb `cdd-state partial-refs`. `set-field` cannot write it:
   that verb is `x-` only, and CDD never reads `x-` keys. Absent means every reference closes,
   so old records stay valid.
2. **`/cdd-pre-pr` judges, at PR open, per recorded issue.** It reads the issue and compares
   what it asks with what the branch delivers. Complete → its close line, nothing said.
   Incomplete, or it cannot tell → partial, marked without asking: an issue wrongly left open
   costs a manual close, while one wrongly closed loses the remaining work silently. The mark is
   said in one line at the existing open-the-PR confirmation, where the human can reverse it. No
   new question, so the checkpoint count is unchanged.
3. **The PR body references a partial issue without closing it:** `Part of <url> — left for
   later: <what>`, with the URL `issue-read` already returned, so no new tracker verb. A plain
   URL links without closing on GitHub and GitLab. The body never puts a closing word before a
   partial reference, nor a `#` word on its line: GitLab's default pattern also closes on
   "implement" and "-ing" forms and on a full URL after a closing word; Jira runs a `#command`
   on the keys of its own line; and a squash merge can copy the body into the commit message.
4. **After the merge, `done` / `gc` skip `issue-transition` for a partial ref** and reuse
   `issue-comment` to link the merged PR — only on a run where no other close failed, the run
   that lets the record be reaped, and only when `issue-read` does not already show that link,
   since an open issue has no `changed: false` to stop a rerun from commenting twice.

Rejected:

- `cdd-state set-field partial_refs …` — refused by the `x-` guard, by design.
- Objects inside `issue_refs` (`{ref, partial}`) — older helpers read `.issue_refs[] | strings`
  and would silently drop the ref.
- A new tracker verb for a non-closing token — the issue URL already does it.
- Storing "what is left" on the record for the post-merge comment — the PR body carries it, one
  click from the comment.
- Marking at handoff or implement time — only at PR open is it known what the branch delivers.

## Consequences

- A machine whose helper predates the field ignores the mark and closes the issue (helpers sync
  on pull, [ADR 0014](0014-keep-the-install-current-by-syncing-on-pull.md)).
- A partial-only task with no tracker is kept by gc like any task with refs, so the link is
  posted once a tracker is installed.
- Resuming stays `/cdd-next-step <ref>`. Reopening an already-closed issue stays out of scope.
