# 0016: Apply clean retrofit changes as one approved batch

**Status:** Accepted

## Context

A user ran `/cdd-retrofit` upgrade mode on a downstream project with a valid `.claude/cdd-baseline`
marker and no project-specific edits to its CDD commands, and was still asked, file by file, whether
to upgrade each command. Nothing was wrong with the run; the command was doing what it said. Its
checkpoint-discipline rule required every write touching a pre-existing file to be approved per
file, the §4.4 comparison table said "apply on approval" even for the trivial "template evolved,
project untouched" and "new since the baseline" rows, a line under the table said "Every application
is per-file interactive", and the process doc's retrofit entry said "Every change to a project file
is approved per file."

For those rows the question carries no decision. The three-way comparison has already established
that the project never touched the file, or that the file did not exist at the baseline; the only
sensible answer is yes, and asking it twenty times teaches the user to stop reading. That is the
shape process doc §1 names as a gap rather than a gate: "automate everything except decisions."

Reviewing the change surfaced the opposite failure too: files that silently stay at an older
template version. The comparison covered only part of what the template ships — the commands, the
agent definition, `settings.json` and the four `index.md` files. Once a project had
`engineering-practices.md`, `project-overview.md` or the ADR template, later template changes to
them were never compared or reported, and `CLAUDE.md` and the roadmap were looked at only when the
agent judged a change "structural". A declined upgrade disappeared too: it was listed once, and the
next upgrade, anchored on the advanced marker, read it as a local customization. The stated policy
is that every project tracks the template: most upgrades are automatic, a doubt is asked, and
nothing stays behind unseen.

The counter-pressure is `CLAUDE.md`'s standing constraint that the six checkpoints are load-bearing
and are not to be weakened without explicit discussion. This ADR is that discussion, in the shape
ADR 0004 set for `/cdd-merge-base`.

## Decision

**Retrofit sorts every proposed write before writing anything, into a batch and a per-file queue.**

- **The batch** holds clean, mechanical changes: an upgrade to a file the project never touched
  since its baseline; a file new since the baseline, including one whose placeholders the
  best-effort fill cleared entirely (listed with the fields it filled); a both-changed file whose
  three-way text merge is conflict-free; and, in install mode, files the project lacks plus the
  union merge into an existing `.claude/settings.json`.
- **The batch is shown once, before any write** — one line per path with its kind (`upgrade`,
  `new`, `new (filled: …)`, `auto-merged`, `no-op: …`, `settings union`) — and **one approval
  writes it all.** Auto-merged entries are their own kind, grouped apart, so the one entry that a
  machine produced rather than copied is visible as such. Any entry's diff is available on request,
  and any entry can be pulled out into the per-file queue. Declining the batch sends every entry to
  the per-file queue, never drops it.
- **The per-file queue** holds everything that needs judgement: merge conflicts, project-deleted
  files, new files still carrying residual placeholders, local hunks that swap in another backend
  (migrate into `.cdd/`), template changes to a project-owned file the project has also changed,
  renames, legacy-sweep patches, capability bindings, and install-mode collisions with the project's
  own docs.
- **Two guards keep a merge out of the batch even when git reports it clean:** a both-changed file
  with a backend-swap hunk always goes per file, and a merged `.claude/settings.json` that no longer
  parses goes per file.
- **Every file the template ships is compared**, in one of two sets. *Project-owned* files are the
  ones bootstrap fills with the project's own content (`CLAUDE.md`, the roadmap,
  `engineering-practices.md`, `project-overview.md`). A both-changed one never auto-merges: the
  template's change is shown and its adaptation proposed per file. The exception is a change that
  touches only skeleton text the project has since replaced: it is listed in the batch as `no-op`
  with its reason, so it is seen rather than asked. *CDD-managed* is every other file, including any
  the template adds later — the default is to compare, so a new template file cannot fall outside.
- **Nothing stays behind unseen.** Whatever a run leaves un-upgraded — a declined question, a
  deleted file left deleted, a project-owned change not carried over — is listed as *behind the
  template* in the summary, with its reason, and copied into the retrofit commit's body. The commit
  body is the durable record, because the next upgrade reads the same file as a local customization.
- **Upgrade mode requires the baseline marker.** A missing marker, `unknown`, or a hash the CDD
  checkout lacks stops the run, before the worktree is created, with how to fix it. Every existing
  CDD project carries a marker, so a marker-less fallback would be machinery with no user.

**Why this weakens none of the six §4 checkpoints.** Retrofit is not one of the six; it runs from a
CDD-repo session on someone else's project, outside the task lifecycle the checkpoints gate. Its
writes land on a dedicated branch in a separate worktree and reach the project only through
`/cdd-pre-pr` and a normal PR — checkpoint 6. The per-file rule was retrofit's own discipline, "the
checkpoints of Section 4 in spirit", and the batch keeps that spirit: nothing is written before the
user has seen the full list and said yes, and every judgement still gets its own question. The batch
summary plus the PR is retrofit's review.

## Rejected alternatives

- **Keep per-file approval everywhere.** The status quo, and the source of the report: approvals
  that carry no decision are rubber stamps, and a long run of them trains the user to approve the
  one that does carry a decision without reading it.
- **Report-only, no approval.** Apply the clean changes and list them in the summary. The user
  explicitly chose one up-front approval over this: the list is short to read, and seeing it before
  anything is written costs one answer.
- **Batch conflicting merges too, with an agent-proposed resolution.** "Git found no conflict" is a
  mechanical fact; "this conflict is easy" is the agent's own judgement — the same line ADR 0004
  draws for merge-base. A conflict stays per file.
- **Auto-merge project-owned files like the rest.** A clean text merge into a `CLAUDE.md` or a
  roadmap the project has rewritten can land template skeleton text in the middle of the project's
  prose. Adapting a template change to a project's own words is judgement.
- **Keep a marker-less fallback, matching each file against renders of every past template
  version.** It was built during this change, and it worked: about fifty renders in a few seconds,
  and a file identical to some past render counted as untouched. It was dropped because every
  existing project carries a marker, and because a file that matches an *older* version would be
  upgraded with no way to tell a deliberate pin from staleness.

## Consequences

- The common upgrade — marker present, project untouched — becomes one list and one yes, and the
  user's attention goes to the few files where there is something to decide.
- **The residual risk is a conflict-free merge that is semantically wrong**: a local hunk and a
  template hunk that never touch the same lines can still contradict each other. This is the same
  risk ADR 0004 accepted for merge-base. It is bounded by auto-merged entries being their own kind
  with their diff one request away, by the two guards above, by §4.6 still assessing the local hunks
  an auto-merge kept, and by the PR.
- A `no-op` entry is the agent's judgement that a template change carries nothing. It is listed in
  the batch rather than asked, so a wrong call is visible and can be pulled out before anything is
  written. "When in doubt, ask" is the rule.
- A project with no usable marker cannot be upgraded until someone writes one by hand: the CDD
  commit it was bootstrapped or last upgraded from. That is a one-line fix, and it beats a guess.
- Retrofit's summary now separates what was applied in the batch, what was approved individually,
  what was preserved, and what is behind the template, so the record of what the user decided stays
  readable after the fact.
