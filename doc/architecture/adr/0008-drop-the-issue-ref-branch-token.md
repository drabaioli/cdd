# 0008: Drop the issue-ref branch token; the state record is the only carrier

**Status:** Accepted

## Context

When `/cdd-next-step` grew a GitHub-issue front-end, the issue number was carried in the branch
name: `gh_issue_42_dark_mode`. `/cdd-pre-pr` parsed it back out to append `Closes #42`, and
`/cdd-next-step`'s browse mode matched it to hide issues already in flight. That worked because
one backend was assumed.

Capability adapters (ADR 0007) removed the assumption. A reference is now whatever the resolved
tracker says it is — `42`, `PROJ-114`, a URL — and one task may close several. The change that
introduced this ADR's subject moved the references onto the task state record (`issue_refs`,
process doc §2.13) and kept the branch token for the single-GitHub-numeric-ref case as a fallback
for an unusable record.

That left the workflow with **two carriers and one special case**: GitHub single-ref tasks got a
token, everything else got a plain slug. Two mechanisms for one fact, with the special case
belonging to the one backend adapters exist to stop privileging.

## Decision

**Branch names are plain descriptive slugs in every mode. The state record's `issue_refs` is the
only thing carrying a task's issue references forward.**

The reviewed alternative — a backend-agnostic token format, so the rule is at least uniform — was
rejected as more mechanism, not less:

- A reference would have to be sanitized to git's branch-name rules per backend. Sanitizing is
  lossy, so parsing it back stops being reliable, which is the only thing a token is for.
- A multi-reference task has no non-arbitrary way to spell itself: it needs a delimiter, a cap,
  and a rule for what happens past the cap.
- It would re-introduce, generically, exactly the ref-encoding scheme the state record replaced.

Consequently the `branch-token` half of the `seams` gate's issue-ref check is deleted (the check
itself remains, now pinned solely to the record), along with `/cdd-pre-pr`'s branch-name fallback
and the branch/PR arms of browse-mode exclusion.

## Consequences

- **One mechanism, no special case.** Nothing in the workflow treats GitHub references differently
  from any other tracker's, which is the posture ADR 0007 set.
- **A task whose record is unusable gets no close lines.** The record is machine-local and advisory
  — absent without `jq`, not yet synced on a second machine — and there is no longer a second place
  to look. This is stated at `/cdd-pre-pr`'s PR-open confirmation rather than discovered afterwards:
  the PR opens fine and the issues stay open for someone to close by hand. Losing the fallback is
  acceptable only because the failure is now *announced*; a silent omission would not be.
- **Browse mode's blind spot widens.** Excluding already-started issues previously also matched
  local branches and open PRs, which caught work started on another machine. Only the local state
  records remain, so browse now says in one line that it cannot see other machines' tasks. Closing
  this properly needs a forge capability that can ask which references an open PR already claims —
  which is Phase 14 work, not this change.
- **Branch names lose their at-a-glance issue grouping.** `git branch --list 'gh_issue_*'` no longer
  answers "what am I working on for the tracker". The descriptive slug still says what the work is.
- **Net removal.** The change deletes more prose and check surface than it adds: a producer/consumer
  grep pair and its mutation case, a fallback bullet, two exclusion command lines and the paragraph
  explaining them, a branch-naming special case, and the trailing "…falling back to" clause in eight
  doc sentences.
