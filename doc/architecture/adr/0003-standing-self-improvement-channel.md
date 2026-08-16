# 0003: A standing self-improvement channel

**Status:** Accepted

## Context

CDD's fifth founding commitment — "the workflow improves itself" (process doc §1) — was named in
[ADR 0001](0001-name-and-guard-founding-objectives.md) but left without a recurring guardrail in
steady state. Two mechanisms covered it partially: `/cdd-retrofit` upgrade mode, which surfaces a
project's general customizations as upstream candidates when the project pulls a newer template,
and the CDD repo dogfooding itself. Neither reaches a project merely *running* CDD day to day. A
session that discovers "this constraint should have been in `CLAUDE.md`", "this convention is
enforced from inference, not from a doc", or "this manual step should be a mechanism" had nowhere
to put it, so the discovery evaporated at session end.

The obvious fix — a standing friction log — is precisely what CDD already tried and retired
(`doc/knowledge_base/friction-log.md`, killed after the first downstream dogfooding round). A
separate log accumulates entries nobody harvests and drifts from the artifacts that actually
drive the workflow. ADR 0001 recorded the deferral on exactly those grounds: name the commitment
now, design the channel separately, do not reintroduce the log.

## Decision

**Add a conditional step to `/cdd-pre-pr`** — step 7, "Workflow improvement check" — in both
command copies, sitting beside the CI-improvement check as a sibling improvement-proposal step,
**and a `workflow-gap` triage class to `/cdd-process-pr`** that routes review comments the same
way.

- **The pre-PR session, not `/cdd-next-step`, and not both.** The pre-PR session is the one point
  in the lifecycle that has just read the whole diff, the handoff, and the docs, and is already
  in the business of reconciling what landed against what is written down. A `/cdd-next-step`
  intake would ask a fresh session to recall friction it never experienced. Putting the check at
  both ends would double the prompt surface for one channel.
- **Prompt-only.** No new script, no `ci.sh` gate, no prompt seam. This matches the
  CI-improvement and test-coverage steps, neither of which has a mechanical guard. What the step
  produces (a `CLAUDE.md` edit, a roadmap item, an issue) is already covered by existing
  machinery.
- **Concrete, observable triggers rather than a quality bar.** The step enumerates six triggers
  that a pre-PR session can *observe from the material in front of it* — a manual step no artifact
  describes, a review rule written down nowhere, a handoff that missed scope, a fix-up repeated
  inside the task, a doc no pointer would have led it to, a slash command it had to work around.
  This is the load-bearing part of the design: step 6 works because its triggers are enumerable
  events. A vague trigger ("propose a workflow improvement") degrades into noise every run or
  silence forever.
- **Three routes, by scope.** An edit's worth of project-specific improvement is applied now and
  rides along in the session's reconciliation commit; anything larger becomes a proposed roadmap
  item under the normal human-approval rule; anything general enough for any CDD project is
  offered as a **GitHub issue against the CDD repo**, human-gated, with the roadmap item as the
  fallback when `gh` is unavailable or the user declines.
- **Judgement, capped at one item per run.** The triggers say what to look at; the bar says what
  clears it — it would change how a future session behaves, and it is a pattern rather than a
  one-off annoyance. Without the cap, an enumerable trigger list invites a checklist sweep that
  finds something every time.
- **Default silence, records rather than blocks, not a checkpoint.** The six human checkpoints of
  process doc §4 are unchanged; this step never gates the PR.
- **A second, review-time entry point in `/cdd-process-pr`** (added in PR #65 review). The pre-PR
  check judges only from the material in front of it and deliberately does not scan earlier PRs —
  a scan the session cannot afford and would do badly. But a gap that is invisible from inside one
  task is often exactly what a *reviewer* points at, and `/cdd-process-pr` already holds those
  comments in context. It reuses the same three routes and the same bar. It costs no new
  checkpoint: the class is declared in the triage plan, which is that command's existing single
  gate, and only the two routes that reach beyond the PR ask again.

**Upstream destination — why an issue.** Three candidates were considered. A roadmap item tagged
as an upstream candidate, kept local and harvested later by `/cdd-retrofit` upgrade mode, keeps
everything in existing artifacts but rots unharvested: a project that never upgrades never
delivers it, and the CDD repo never learns the improvement exists. A line in the PR summary
evaporates on merge — effectively no channel. An issue reaches the one place that can act on it,
at the moment the discovery is fresh, and CDD's contribution policy is issues-only, so this is
the intended inbound path. Its cost — it assumes the user is willing to interact with the CDD
repo — is bounded by the human gate and the roadmap fallback.

## Consequences

- Commitment 5 now has a recurring guardrail in steady state, so all three founding objectives
  are guarded by a mechanism rather than by intent.
- The three channels are complementary, not duplicative: the pre-PR check fires at **discovery**
  time, the `/cdd-process-pr` route at **review** time on what someone else saw, and
  `/cdd-retrofit` §4.5 at **upgrade** time on the accumulated diff. A general improvement now has
  three independent chances of reaching CDD.
- Inserting step 7 renumbered steps 7–10 to 8–11, which propagates into
  `scripts/prompt-seam-check.sh`'s pinned heading list and the corresponding mutation case in
  `scripts/prompt-seam-assert.sh`. Future insertions carry the same cost; the seam checker makes
  it a loud failure rather than a silent one.
- The step has **no mechanical guard**, so its discipline rests entirely on the trigger list
  staying concrete. If it starts firing every run, the fix is to tighten the triggers, not to
  add a gate.
- The upstream half writes to a public repo. It is human-gated for that reason: the step shows
  the issue title and body and files nothing without explicit approval.
- No new artifact was created. The channel routes into `CLAUDE.md`, the coding standard, the
  roadmap, or an issue — all machinery that already existed. The retired friction log stays
  retired.
