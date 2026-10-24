Plan a task from its handoff and write the plan file a later `/cdd-implement` session builds from: `/cdd-plan` (takes no argument).

This is the first half of the implementation cycle. It runs in the task's feature worktree, and its **only** artifact is the plan file — it writes no file inside the repo. The second half is a separate, fresh session running `/cdd-implement`.

Everything you learn here and do not write down is destroyed when this session ends. That is the whole reason the plan file has a schema; follow it.

## 1. Read the handoff and rebuild context

Derive the task's paths from git — no argument is passed:

```bash
repo="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")"
branch="$(git rev-parse --abbrev-ref HEAD)"
echo "handoff: ~/.cdd/handoffs/$repo/$branch.md"
echo "plan:    ~/.cdd/handoffs/$repo/$branch.plan.md"
```

Read the handoff. Its `## Requirements` section is the done-test for this task: your plan must satisfy every criterion, and you check it against them in step 4. Its `## Notes` section lists open questions deferred to you — address them up front rather than mid-plan. Its `## Research` section, if present, sets how much research step 3 does and which questions it answers.

Then rebuild context from the repo: the roadmap and the architecture/feature doc indexes, loading only the documents the task touches.

If the plan file already exists, this task has already been planned. Say so, show the existing plan's `## Summary`, and ask whether to replan from scratch or hand off to `/cdd-implement` — do not silently overwrite.

## 2. Explore

Exploration is a named step, not an implied one. Read the source you will change — whatever the task needs inside the repo. What lies outside it (the web, vendor and library documentation) is the next step's job. Dead ends are expected and are not waste; they are findings.

**Record conclusions as you go.** After this session ends there is no transcript for the implementing session to consult, so an unrecorded finding is re-derived at full cost or simply lost.

## 3. Research

**Depth.** Take it from the handoff's `## Research` section. If the handoff has none, choose one yourself and say which in the digest. `none` skips this step — say that in the digest too.

**Budget.** Every figure is a cap, not a quota. Never fan out a question one researcher can answer.

| Depth    | Researchers | Tool calls each |
| -------- | ----------- | --------------- |
| none     | 0           | —               |
| light    | 1           | about 5         |
| standard | 2–4         | about 10        |
| deep     | 5–6         | up to 15        |

Hard ceiling, whatever the depth: 10 researchers, 20 tool calls each.

**What to ask.** Only what the repo cannot answer, and only where it applies:

- **Unknowns** — what the plan needs and nobody here knows how to do.
- **The approach** — when the task holds a real design choice: how others solve this problem, with the options, their tradeoffs and their known pitfalls. A wrong approach sinks more plans than a wrong fact. Ask it blind: do not tell the researcher which option you lean toward, and do not ask it to find faults with yours. A model drifts toward an answer it is shown, and one asked for faults reports some whether or not they are there. Compare what comes back with your own option yourself.

**Spawn.** One `cdd-researcher` subagent (`.claude/agents/cdd-researcher.md`) per independent question, all launched together in one message. Its tools are web only: it cannot read the repo or edit anything, so it holds nothing worth leaking but its brief. That is why its fetches are approved without a prompt (a hook in `.claude/settings.json`) and yours are not. Brief each one with exactly these fields, and nothing else of your context — the brief is a firewall. Put in the repo facts it needs, and never a secret:

- **Objective** — what to find out.
- **Decision** — the plan decision the answer serves.
- **Questions** — the ones this researcher owns.
- **Out of scope** — the other researchers' questions.
- **Sources** — where to look first, if you know.
- **Budget** — its tool-call cap from the table above.
- **Return format** — as in its definition.

If that agent file is missing (a project not yet upgraded), say so in one line and research inline, keeping the same rules: a source fetched in this run for every claim, verbatim quotes, the same caps. Each fetch then asks for approval.

**Verify.** Once you have a draft approach, and before you present it, have it checked by one fresh `cdd-researcher`, so the agent that drafted the plan is not the one grading it. It is not counted in the tier's researchers, but stays under the hard ceiling. It takes two lists:

- **The findings the draft rests on** — adopted, or the reason something was rejected — each as a URL and a quote. It re-fetches each page with a narrow question ("does this page contain this text? quote it") and reports which match. Research agents cite pages that do not say what they claim, or do not exist.
- **The fragile assumptions** — facts about something outside the repo that the draft relies on, that no finding sources, and that are new, rarely used or version-specific: an API's behaviour, a tool's flag, a field a payload carries. Send each as a neutral question, not as your claim ("which fields does X's input carry?", not "confirm X carries Y"). Leave out what is common and stable: checking everything adds noise, not accuracy.

Do not fetch any of it yourself — you hold the repo, so your fetches are not pre-approved. Revise the draft by what comes back. Drop a finding that does not verify, or keep it marked as unverified. An assumption the check refutes changes the draft; one it cannot settle is recorded as a finding with the disposition **to verify**. At depth `none` no researcher runs, so record each fragile assumption as **to verify** and name it in the digest.

**Disposition.** Give each kept finding exactly one:

- **adopted** — name the Approach step it shapes;
- **rejected** — say why; if it represents an approach, it also gets a `## Dead ends` line;
- **to verify** — the implementing session checks it; it also gets a `## Verification` line;
- **context only** — background the plan does not rest on.

A finding that settles a structural decision puts an ADR into `## Doc and roadmap edits`, as any structural decision does.

The researchers' digests are not written anywhere. What matters lands in the plan's `## External findings`, with its disposition; the rest is discarded with this session.

## 4. Confirm scope, then check against the requirements

Surface any remaining open questions and confirm scope with the user before drafting the plan.

Then check the plan you are about to present against the handoff's `## Requirements`, criterion by criterion. If your plan does not satisfy one, or you believe a criterion is wrong, say so explicitly — do not quietly redefine done. Any deviation is a bullet in the digest below.

The handoff is immutable, so a criterion the human agrees to amend or drop is **recorded in the plan file's `## Open questions resolved`**, naming the original criterion and what replaced it. That record is the only thing that reaches `/cdd-pre-pr`, which otherwise re-checks the diff against the original wording and reports the amendment as a miss.

## 5. Print the bounded digest

Immediately before asking for approval, print a short summary of the plan in chat: what you intend to do, and the details that bear on approving it. Follow the rule in `CLAUDE.md` — short, plain, only what changes the answer. The plan file itself is written for the next session, so this summary is the whole of what the human approves against; it has to carry the plan at high altitude without becoming the plan.

What usually earns a line: the approach, roughly what it touches, the riskiest step, what research changed (which findings moved the plan, that research found nothing that changed it, or that it was skipped and why), any outside assumption the plan rests on that could not be checked, anything you investigated and rejected that the human might otherwise suggest, how it will be verified, and any deviation from the handoff's `## Requirements`. Say what applies and drop the rest. No granular detail and no exploration log — the human should be able to approve or push back without opening the plan file.

## 6. Checkpoint: plan approval

This is checkpoint 3, and it is the only gate in the implementation cycle. Ask the human to approve the plan or push back, and iterate until it is approved.

Nothing mechanical stops you from writing here, so **write nothing — inside the repo or out of it — until the answer is yes**.

## 7. Write the plan file

On approval, write `~/.cdd/handoffs/<repo>/<branch>.plan.md` — a flat, branch-named sibling of the handoff (`<branch>.md`) and the state record (`<branch>.state.json`). The directory already exists (`/cdd-next-step` created it when it wrote the handoff).

The plan is written **for the implementing session, not for the human** — the human read the digest above. That gives it one governing rule:

> **Cite what's in the repo, quote what isn't.** A fact from repo source is cheap for the next session to re-derive, so record a `file:line` pointer plus your one-line conclusion. A fact from outside the repo — a web search, vendor documentation, an API's semantics, a version quirk — cannot be recovered without repeating the search, so record it **verbatim with its source**. Dead ends are the same class: unwritten, they are re-explored at full cost. And a finding without a disposition (step 3) is not done — the implementing session cannot tell what it is for.

Structure (the section names are a contract `/cdd-implement` reads — do not rename them):

```markdown
# Plan: <short title>

## Summary
<the same bounded digest printed above>

## Approach
<one paragraph, then the ordered steps; each step names the files it touches>

## File map
<path → what changes, plus the distilled fact: `file:line` + your one-line conclusion>

## External findings
<facts from outside the repo, quoted verbatim, each with its source, its date or version, and its disposition — adopted (step), rejected (reason), to verify, or context only — or "None">

## Dead ends
<what was tried and why it failed, so it is not re-explored — or "None">

## Open questions resolved
<the handoff's deferred questions and the answers agreed here, plus any `## Requirements` criterion amended or dropped with the human's agreement — or "None">

## Doc and roadmap edits
<architecture/feature/CLAUDE.md edits and roadmap ticks the implementation must apply>

## Verification
<which check-runner gates to run, which assertions or tests to add or extend>
```

Then advance the task **state record** — this write is also what pushes the plan onto the task's sync ref, so it reaches other machines. It is advisory and skips silently if the record is absent (only `/cdd-next-step` seeds one; a mid-lifecycle writer never fabricates one):

```bash
cdd-state set plan_written
```

## 8. Print the next command

Print exactly:

```
Plan written: ~/.cdd/handoffs/<repo>/<branch>.plan.md
Next: open a fresh `claude` in this worktree and run /cdd-implement

Read or edit the plan first if you want to — /cdd-implement builds from the file, not from this conversation.
```

Then **stop**. Do not implement, do not edit any file in the repo, and do not offer to continue in this context: the split is uniform, and this session's remaining context is exactly the exploration debris the split exists to discard.
