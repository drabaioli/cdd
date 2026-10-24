# 0015: Research as a phase of planning

**Status:** Accepted

## Context

Research in CDD was ad hoc. `/cdd-plan`'s Explore step said "search the web, consult vendor and
library documentation", and a human who wanted more asked for it in prose in the handoff. Nothing
sized it, nothing bounded it, and nothing said what a finding had to carry to be usable by the
implementing session — beyond the plan schema's rule that external facts are quoted verbatim with
a source.

Three pressures made that worth fixing:

- **Context rot.** Research reads far more than it keeps. Done inline, every page the planner
  fetched sits in the same window it then plans in, and even a single irrelevant passage measurably
  degrades a model's performance on the task in front of it.
- **Hallucinated citations.** Research agents cite URLs that do not resolve or never existed, and
  deep-research agents do so at higher rates than plain search-augmented models. A plan that
  adopts such a finding carries the error into code with nobody re-checking it, because
  `/cdd-implement` is told to trust `## External findings` rather than re-run the searches.
- **Unsized effort.** With no notion of depth, a question one lookup answers and a question
  whose answer should reshape the design got the same treatment — whatever the planner felt like.
  Over-investing in a simple question is itself a known failure mode of multi-agent research.

## Decision

**Research is a phase inside `/cdd-plan`, the step after Explore.** It is not a new session type.

**Its depth is scoped at handoff.** The handoff gains an optional `## Research` section: a tier —
`none`, `light`, `standard`, `deep` — and the questions to answer. `/cdd-next-step` recommends it
and the human decides at checkpoint 2, next to the lane. An absent section means the planner
decides, which is what happened before, so an old handoff plans exactly as it did.

**It runs in a shipped, read-only subagent.** `.claude/agents/cdd-researcher.md` ships in the
template. Its `tools` line lists read and web tools only — no edit, no shell, no `Agent`, so it can
neither write nor spawn subagents of its own. The allowlist is the enforcement.

**Each tier has hard caps, and they are limits, not targets.** Light is one researcher with about
five tool calls; standard two to four with about ten each; deep five or six with up to fifteen; and
whatever the tier, never more than ten researchers or twenty calls each. A question one researcher
can answer is never fanned out.

**Each researcher gets a firewalled brief** — objective, the decision it serves, the questions it
owns, what is out of scope, where to look, its budget, the return format — and nothing else of the
planner's context. It returns a short digest: per finding a claim, a verbatim quote, the URL fetched
this run, publisher, date or version, access date, confidence and which question it bears on; then
what it looked for and did not find, and any conflicts or version caveats. It may not conclude from
training data.

**Verify, then disposition.** Before a finding shapes the plan, the planner re-fetches its source
with a narrow prompt and confirms the quote. Each kept finding lands in `## External findings` with
a disposition: adopted (which step), rejected (why — and a Dead ends line if it was an approach),
to verify (with a Verification line), or context only. A finding that settles a structural decision
puts an ADR into the plan's doc edits, under the existing ADR rule; no new task type is needed.

**Raw digests are not persisted.** What matters lands in the plan.

**The small-change lane never researches.** A task that needs anything looked up fails the
discovery bound, so it takes the off-ramp to `/cdd-plan`.

**`WebSearch` is pre-allowed; `WebFetch` is not.** Searching is low-risk and constant; a fetch
names a domain the human should see, and a fully-allowed fetch would let a malicious page steer the
agent into sending data out through a URL of its choosing.

## Alternatives considered

- **A separate research session** (the research / plan / implement split some workflows use). It
  costs a window and introduces a new artifact with its own lifecycle, sync and reaping — and plan
  approval already gates everything research produces, so a separate session adds no checkpoint.
- **An inline brief in `/cdd-plan`, with no agent file.** Simpler, but a general-purpose subagent
  inherits every tool; only a definition with a `tools` line can make the researcher read-only.
- **`permissionMode: plan` in the agent definition** as the read-only mechanism. The subagent docs
  say a parent in `bypassPermissions`, `acceptEdits` or auto mode overrides it, so it guarantees
  nothing in exactly the sessions where it matters.
- **Persisting the raw digests** beside the plan, for re-derivation. A second artifact means a
  second lifecycle, and the plan already holds everything a later session needs.
- **Research in the handoff session.** That session runs on main with its context spent on
  cross-phase reasoning; research there pollutes the wrong window and happens before the task is
  scoped.
- **Always-on research.** Over-invests in simple tasks — the failure mode the tier caps exist for.
- **Spec Kit's Decision / Rationale / Alternatives as the finding format.** In this split the
  decision and its rationale belong to the plan's Approach, not to a researcher's output; the
  disposition plays the "what was chosen" role and rejected alternatives go to Dead ends.
- **Fully allowing `WebFetch`.** See the last decision paragraph.

## Consequences

- **The checkpoint count stays six.** Research runs before checkpoint 3, whose digest now says what
  research changed — the place a wrong research line, which can mislead every step built on it,
  becomes visible. Checkpoint 2 now also sets the research depth.
- **`.claude/agents/` is a new CDD-managed category.** The drift check diffs it between the repo and
  the template, its self-test mutates it, the bootstrapped-tree check asserts that every shipped
  agent names its tools and none that can write, and `/cdd-retrofit` installs and upgrades it. A
  future write-capable agent has to change that assertion deliberately.
- **Older projects degrade, they do not break.** Without the agent file, `/cdd-plan` says so and
  researches inline under the same rules.
- **A project may extend the researcher's tools** — most usefully with its docs MCP server — and a
  retrofit upgrade keeps that as a local customization.
- **The budgets are judgement, not measurement.** They come from published multi-agent research
  practice, not from CDD's own usage; real tasks may show them to be wrong, and they live in one
  place (`/cdd-plan`) so that changing them is one edit.
