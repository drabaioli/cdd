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
for c in .cdd/docs ~/.cdd/adapters/docs; do [ -x "$c" ] && { echo "docs adapter: $c"; break; }; done; true
```

Read the handoff. Its `## Requirements` section is the done-test for this task: your plan must satisfy every criterion, and you check it against them in step 3. Its `## Notes` section lists open questions deferred to you — address them up front rather than mid-plan.

Then rebuild context from the repo: the roadmap and the architecture/feature doc indexes, loading only the documents the task touches.

If the plan file already exists, this task has already been planned. Say so, show the existing plan's `## Summary`, and ask whether to replan from scratch or hand off to `/cdd-implement` — do not silently overwrite.

## 2. Explore

Exploration is a named step, not an implied one. Read the source you will change, search the web, consult vendor and library documentation — whatever the task needs. Dead ends are expected and are not waste; they are findings.

**Record conclusions as you go.** After this session ends there is no transcript for the implementing session to consult, so an unrecorded finding is re-derived at full cost or simply lost.

**Docs store.** The `docs adapter:` line from step 1 names the project's docs adapter, if one is installed; if it printed nothing, skip this paragraph — no call, no line. An installed adapter is still not called by default, only on a trigger, strongest first: (1) a page reference in the handoff or the user's message — text matching the `link_pattern` its `describe` reports; (2) a line in the project's `CLAUDE.md` saying what lives in the docs store, matching this task; (3) the task depends on an external system the repo does not document. No trigger, no lookup. Here the usual reason is an integration contract the task codes against; record what you read under `## External findings`, with the page reference and version. Before the first call run `<adapter> describe` (hermetic: no network, no credentials) and use the adapter only if it exits 0, parses as JSON and reports `contract` 1 — otherwise say so in one line and carry on without it. Say once which adapter served; prefer `doc-search <query>` then `doc-read <ref> --section <heading>` to whole pages, and check `truncated` in what comes back. It is read-only, and the repo stays the source: never copy page content into the repo's docs.

## 3. Confirm scope, then check against the requirements

Surface any remaining open questions and confirm scope with the user before drafting the plan.

Then check the plan you are about to present against the handoff's `## Requirements`, criterion by criterion. If your plan does not satisfy one, or you believe a criterion is wrong, say so explicitly — do not quietly redefine done. Any deviation is a bullet in the digest below.

The handoff is immutable, so a criterion the human agrees to amend or drop is **recorded in the plan file's `## Open questions resolved`**, naming the original criterion and what replaced it. That record is the only thing that reaches `/cdd-pre-pr`, which otherwise re-checks the diff against the original wording and reports the amendment as a miss.

## 4. Print the bounded digest

Immediately before asking for approval, print a short summary of the plan in chat: what you intend to do, and the details that bear on approving it. Follow the rule in `CLAUDE.md` — short, plain, only what changes the answer. The plan file itself is written for the next session, so this summary is the whole of what the human approves against; it has to carry the plan at high altitude without becoming the plan.

What usually earns a line: the approach, roughly what it touches, the riskiest step, anything you investigated and rejected that the human might otherwise suggest, how it will be verified, and any deviation from the handoff's `## Requirements`. Say what applies and drop the rest. No granular detail and no exploration log — the human should be able to approve or push back without opening the plan file.

## 5. Checkpoint: plan approval

This is checkpoint 3, and it is the only gate in the implementation cycle. Ask the human to approve the plan or push back, and iterate until it is approved.

Nothing mechanical stops you from writing here, so **write nothing — inside the repo or out of it — until the answer is yes**.

## 6. Write the plan file

On approval, write `~/.cdd/handoffs/<repo>/<branch>.plan.md` — a flat, branch-named sibling of the handoff (`<branch>.md`) and the state record (`<branch>.state.json`). The directory already exists (`/cdd-next-step` created it when it wrote the handoff).

The plan is written **for the implementing session, not for the human** — the human read the digest above. That gives it one governing rule:

> **Cite what's in the repo, quote what isn't.** A fact from repo source is cheap for the next session to re-derive, so record a `file:line` pointer plus your one-line conclusion. A fact from outside the repo — a web search, vendor documentation, an API's semantics, a version quirk — cannot be recovered without repeating the search, so record it **verbatim with its source**. Dead ends are the same class: unwritten, they are re-explored at full cost.

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
<facts from outside the repo, quoted verbatim, each with its source — or "None">

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

## 7. Print the next command

Print exactly:

```
Plan written: ~/.cdd/handoffs/<repo>/<branch>.plan.md
Next: open a fresh `claude` in this worktree and run /cdd-implement

Read or edit the plan first if you want to — /cdd-implement builds from the file, not from this conversation.
```

Then **stop**. Do not implement, do not edit any file in the repo, and do not offer to continue in this context: the split is uniform, and this session's remaining context is exactly the exploration debris the split exists to discard.
