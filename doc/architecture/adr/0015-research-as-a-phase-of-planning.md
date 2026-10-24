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

**It runs in a shipped, web-only subagent.** `.claude/agents/cdd-researcher.md` ships in the
template. Its `tools` line lists `WebSearch` and `WebFetch` only — no file reads, no edit, no shell,
no `Agent`, so it can neither read the repo, write, nor spawn subagents of its own. The allowlist is
the enforcement. The planner puts the repo facts a question needs into the brief.

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

**Research asks only what the repo cannot answer**, in two kinds of question, each only where it
applies: unknowns — what nobody here knows how to do — and, when the task holds a real design
choice, how others solve the problem, with the options, tradeoffs and known pitfalls. The second is
there because a wrong approach sinks more plans than a wrong fact: a manual study of 150 failed
SWE-bench Verified issues puts about 65% of root causes in flawed reasoning and about 25% in
knowledge deficiency ([arXiv 2509.13941](https://arxiv.org/html/2509.13941v1)). It is asked
**blind** — the brief does not say which option the planner leans toward, and does not ask the
researcher to find faults with it. A model shown an answer drifts toward it: feedback is "more
positive when the user states they like or wrote the passage", and a user suggesting a wrong
answer cut accuracy by up to 27% for one model (Sharma et al.,
[arXiv 2310.13548](https://arxiv.org/html/2310.13548v4)). A model asked for faults reports them
anyway: "A reviewer prompted to find gaps will usually report some, even when the work is sound"
([Claude Code best practices](https://code.claude.com/docs/en/best-practices), checked
2026-10-24), and model critics produce "nitpicks and hallucinated bugs" at a much higher rate than
humans ([arXiv 2407.00215](https://arxiv.org/html/2407.00215v1)). The researcher reports the
options its sources describe; the planner compares them with its own.

**Verify after drafting, then disposition.** Once the approach is drafted, one fresh researcher
checks it, so the agent that drafted the plan is not the one grading it; the planner does not
fetch. It re-fetches each finding the draft rests on and confirms the quote, and it answers the
draft's **fragile assumptions** — outside facts the draft relies on without a source that are new,
rarely used or version-specific — sent as neutral questions, not as claims to confirm. This is
Chain-of-Verification's shape — draft, plan verification questions, answer them "independently so
the answers are not biased by other responses", revise
([arXiv 2309.11495](https://arxiv.org/abs/2309.11495)) — applied to a plan. It is selective
because blanket checking costs accuracy as well as time: retrieving documentation for every API
call cost GPT-4o 39 points on common APIs with a weak retriever, while retrieving only for rare
ones gained 8.2 points overall ([arXiv 2407.09726](https://arxiv.org/html/2407.09726v1)). An
assumption the check cannot settle becomes a *to verify* finding; at depth `none` every fragile
assumption does, and the digest names it. Each kept finding lands in `## External findings` with
a disposition: adopted (which step), rejected (why — and a Dead ends line if it was an approach),
to verify (with a Verification line), or context only. A finding that settles a structural decision
puts an ADR into the plan's doc edits, under the existing ADR rule; no new task type is needed.

**Raw digests are not persisted.** What matters lands in the plan.

**The small-change lane never researches.** A task that needs anything looked up fails the
discovery bound, so it takes the off-ramp to `/cdd-plan`.

**Only the researcher fetches without a prompt.** Research fetches constantly, and a prompt per
page turns the research phase into a stream of approvals nobody reads. But an agent that holds
private data, reads untrusted pages and can send requests unprompted can be steered by a malicious
page into fetching a URL with that data embedded in it — the "lethal trifecta", and the shape of
CVE-2026-54316, where a pre-approved domain became the way out. The fix is to remove one leg: the
researcher holds no private data. It has no file tools, and its brief carries no secrets. A
`PreToolUse` hook in `.claude/settings.json` approves `WebFetch` when the hook input's `agent_type`
is `cdd-researcher` — the one thing a permission rule cannot do, since rules apply to the whole
session — and stays silent otherwise, so every other fetch keeps its prompt (or its auto-mode
review). `WebSearch` stays allowed outright: its query goes to the search provider, not to a server
a page chose. As a second line, `Read` deny rules block the files most worth stealing — `.env`,
`.env.*`, `*.pem` and `*.key` anywhere on disk, and the usual credential stores under `~`. They
also block Claude's own edits to those paths, `.env.example` included.

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
- **Asking a researcher to review the planner's approach**, or to look for evidence against it.
  The first anchors the researcher on the planner's answer; the second invites invented faults.
  The blind question gets an independent answer without either bias.
- **A best-practices question for every dependency**, as Spec Kit's plan phase does ("For each
  dependency → best practices task"). Thorough, but it spends research where nothing is uncertain;
  CDD asks about the approach only when the task holds a real design choice.
- **Checking every outside fact the plan uses.** Common, stable facts rarely go wrong, and checking
  them adds noise; the check targets what is new, rarely used or version-specific.
- **Spec Kit's Decision / Rationale / Alternatives as the finding format.** In this split the
  decision and its rationale belong to the plan's Approach, not to a researcher's output; the
  disposition plays the "what was chosen" role and rejected alternatives go to Dead ends.
- **Leaving `WebFetch` to prompt per page**, so the human sees every domain. Safest, but the
  approvals come too often to be read, which makes them a rubber stamp rather than a check.
- **Allowing `WebFetch` for every session**, paired with the secret-file deny rules. Shipped
  briefly; the deny rules narrow what a steered fetch could carry but leave the planner — which
  holds the repo and reads digests distilled from untrusted pages — with an unprompted way out.
- **Allowing `WebFetch` only for listed domains.** A generic template cannot know which
  documentation sites a project needs, and CVE-2026-54316 shows an allowed domain whose content an
  attacker controls is itself a channel.
- **Filtering fetch URLs** (no query strings, length or entropy caps). Defeated by sending data a
  character per request, as the CamoLeak attack on GitHub Copilot did; no credible source
  recommends it.
- **Allowing only URLs already seen in the conversation**, as the Anthropic API's own fetch tool
  does. Little gain once the fetching agent holds no secrets.
- **Blocking reads outside the working directories** (`permissions.blockReadsOutsideWorkingDirectories`).
  Breaks CDD, whose handoff and plan files live under `~/.cdd`.

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
- **What an unprompted fetch can leak is the brief.** The residual path is two-step: a page
  steers a researcher's digest, the digest steers the planner into writing private data into a
  later brief, and that researcher fetches it out. Briefs carry no secrets, and the planner treats
  digests as data. The deny rules do not cover a shell command that reads files without naming them
  (`grep -r` over a directory); only the sandbox does.
- **The researcher cannot read the repo.** A question that needs repo context gets it in the brief,
  which the planner must write well.
- **The hook needs `jq`.** Without it the hook exits quietly and researcher fetches prompt like any
  other — degraded, never unsafe. It matches the agent's frontmatter `name`, which is what the hook
  input reports for a custom subagent; renaming the agent means editing the hook.
- **The post-draft check is CDD's own.** None of the workflows surveyed (Claude Code's best
  practices, HumanLayer's research / plan / implement, Spec Kit) checks a plan's outside
  assumptions after drafting; the step rests on Chain-of-Verification and claim-level fact-checking
  results from question answering, not from code plans. Which assumptions count as fragile is the
  planner's judgement.
- **The budgets are judgement, not measurement.** They come from published multi-agent research
  practice, not from CDD's own usage; real tasks may show them to be wrong, and they live in one
  place (`/cdd-plan`) so that changing them is one edit.
