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

The pre-marker (two-way) fallback had the same problem in a worse form: with no baseline, *every*
difference was presented for classification, including files the project had simply never touched
since an older bootstrap.

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
  `new`, `new (filled: …)`, `auto-merged`, `settings union`) — and **one approval writes it all.**
  Auto-merged entries are their own kind, grouped apart, so the one entry that a machine produced
  rather than copied is visible as such. Any entry's diff is available on request, and any entry can
  be pulled out into the per-file queue. Declining the batch sends every entry to the per-file
  queue — today's behaviour — never drops it.
- **The per-file queue** holds everything that needs judgement: merge conflicts, project-deleted
  files, new files still carrying residual placeholders, local hunks that swap in another backend
  (migrate into `.cdd/`), structural `CLAUDE.md` or roadmap edits, renames, legacy-sweep patches,
  capability bindings, install-mode collisions with the project's own docs, and in two-way mode any
  file that matches no past template version or that the project lacks.
- **Two guards keep a merge out of the batch even when git reports it clean:** a both-changed file
  with a backend-swap hunk always goes per file, and a merged `.claude/settings.json` that no longer
  parses goes per file.
- **Pre-marker projects get past-version matching.** The template is rendered at every CDD commit
  that touched `template/`, through the same bootstrap script, and a target file identical to the
  render of that path at any past commit counts as untouched — upgraded through the batch like a
  three-way "project untouched" file. Everything else in two-way mode stays per file.

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
- **Infer one baseline commit for a pre-marker project from the past-version matches**, then run
  the full three-way comparison. Different files can match different past commits — a project
  upgraded by hand, piecemeal — so a single inferred baseline would misclassify some of them.
  Matching per file needs no such guess.
- **Treat a pre-marker file the project lacks as "new since bootstrap".** Without a marker, a file
  the project deleted and a file it never had look the same. Guessing between them is judgement
  dressed up as mechanics; it stays per file.

## Consequences

- The common upgrade — marker present, project untouched — becomes one list and one yes, and the
  user's attention goes to the few files where there is something to decide.
- **The residual risk is a conflict-free merge that is semantically wrong**: a local hunk and a
  template hunk that never touch the same lines can still contradict each other. This is the same
  risk ADR 0004 accepted for merge-base. It is bounded by auto-merged entries being their own kind
  with their diff one request away, by the two guards above, by §4.6 still assessing the local hunks
  an auto-merge kept, and by the PR.
- Past-version matching **errs toward asking**: a match is byte-for-byte. Files from projects
  bootstrapped before the two-identifier model (#24) never match, because the old renders leave
  legacy tokens unsubstituted, so those projects see more per-file questions. Its one blind spot is
  a file the project deliberately kept at an older template version: it matches that version and is
  listed as a batch `upgrade`, where the user can pull it out. Its cost grows with the template's
  history; at the time of writing it is about fifty renders and a few seconds.
- Retrofit's summary now separates what was applied in the batch from what was approved
  individually, so the record of what the user decided stays readable after the fact.
