Scope the next roadmap task and produce a handoff file for a fresh plan session.

The exploratory session. Run on the main worktree. It modifies **no** file in the repo; its only artifact is the handoff file under `~/.cdd/handoffs/cdd/`, consumed later by an isolated plan session (`/cdd-plan`).

## 0. Mode: roadmap-driven, intent-driven, or issue-driven

One optional argument. Dispatch on its shape, trying the rows in order:

| `$ARGUMENTS`                        | Mode                          | Branches at |
| ----------------------------------- | ----------------------------- | ----------- |
| empty                               | **roadmap-driven**            | §3          |
| `issue` or `issues`                 | **issue-driven**, browse      | §0b         |
| every whitespace-separated token matches the tracker's `ref_pattern` | **issue-driven**, direct | §0b |
| anything else                       | **intent-driven**             | §3-intent   |

The `issue` / `issues` keyword is checked before the pattern. The direct row matches only when **every** token matches (one task may be sourced from several issues: `/cdd-next-step 97 12`); a mixed argument is intent-driven, with the whole string read as the task prompt.

Every mode first runs §0a, §1 and §2; "Branches at" is where its own path starts. Issue-driven is intent-driven with the intent text taken from tracker items (§0b). All modes share §4 onward; do not fork the flow beyond §0b, §1 and §3.

**The tracker defines what a reference looks like.** Resolve it down the ladder — project, then machine — and take the first file present:

```bash
for c in .cdd/tracker ~/.cdd/adapters/tracker; do [ -e "$c" ] && { echo "$c"; break; }; done
```

If one resolved, run `describe` and take `.ref_pattern` — an ERE — as the shape of a reference:

```bash
<adapter> describe    # JSON on stdout; hermetic, so it needs no network and no credentials
```

Use it only if the file is executable and `describe` exits 0, parses as JSON, reports `capability` `tracker`, and reports a `contract` this CDD supports (currently `1`). Otherwise the adapter is **installed but broken**: say so in **one line** naming its path, and **stop the command**. Do not try a lower rung. With nothing resolved there is no `ref_pattern`: the direct row never matches, and `issue` / `issues` still dispatches to §0b, which stops with the install line.

Resolution done only to classify the argument is **silent**; the rung is announced in §0b.

## 0a. Verify the checkout is current

Before reading any context, compare the **checked-out** branch against its upstream (not the platform default branch):

```bash
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "origin/$BRANCH")"
git fetch --quiet origin "$BRANCH" && git rev-list --left-right --count "HEAD...$UPSTREAM"
```

The count prints ahead, then behind.

- **Behind** (second number non-zero): **stop**. Say how many commits behind the upstream this checkout is, and tell the user to run `git pull --ff-only` here and re-run the command. Do not pull, and do not offer to.
- **Ahead or diverged**: report it in one line and continue. Never a block.
- **Fetch failed or no upstream** (offline, no remote, or no counterpart branch on `origin`): say in one line that the freshness check was skipped, and continue.

Then continue with §0b (issue-driven mode) or §1.

## 0b. Resolve the issue (issue-driven mode)

**Preconditions.** The tracker must serve the call — `issue-read` for direct, `issue-list` for browse.

*With an adapter resolved* (§0), that verb must appear in its `describe.verbs`; if it does not, say which verb the adapter is missing and stop. A call that exits **4** (not configured / auth missing) prints an actionable line on stderr — show that line and stop, rather than reinterpreting it.

*With nothing resolved*, print exactly `No tracker adapter is installed; run /cdd-retrofit in this project to install one.` and stop.

**Announce the rung in one line** before the first call — `.cdd/tracker` or `~/.cdd/adapters/tracker`.

**Direct** (every token matched): read each item, in the order given, read-only (never assign, comment, or relabel): one `<adapter> issue-read <ref>` per token, passing each through unchanged.

Several references mean one task, not several. If the items describe unrelated work, say so and ask which to scope — do not silently fold unrelated work into one handoff.

**Browse** (`issue` / `issues`): list open issues, then exclude any already in flight:

```bash
<adapter> issue-list
jq -r '.issue_refs // [] | .[]' ~/.cdd/handoffs/cdd/*.state.json 2>/dev/null   # already-started issues, by state record
```

The state records are the only exclusion source. Compare after stripping any leading `#`. The exclusion is advisory — the records are local to this machine, absent without `jq`, and reaped once a PR merges — so when presenting the list say in one line that finding no record is not proof the issue is unstarted.

Present the filtered list (number + title) and let the user pick **one or more**; then fetch each one's detail as above.

Use the items' titles + bodies + comments as the **intent text**, and continue with §1, then §3-intent. The references are carried forward only on the task's **state record** (§7) — never in the branch name or a commit trailer.

## 1. Read context

Read `doc/knowledge_base/roadmap.md` in full. Skim `doc/architecture/index.md` and `doc/features/index.md` for current state; do not read them exhaustively.

**Intent-driven and issue-driven modes**: after those, open only the docs the described task (or resolved issue) actually touches — enough to scope it and detect overlap with existing work.

## 2. Check for stale handoffs

List existing handoff files:

```bash
ls ~/.cdd/handoffs/cdd/ 2>/dev/null
```

The handoffs are the `<branch>.md` files. Skip their siblings — `<branch>.plan.md`, `<branch>.state.json` — and the per-repo `repo.json`.

For each handoff `<branch>.md`, check whether the branch still exists locally:

```bash
git branch --list <branch>
```

If the branch is gone, the handoff is stale. For each stale handoff, ask the user inline whether to delete it with its siblings (`rm -f ~/.cdd/handoffs/cdd/<branch>.md ~/.cdd/handoffs/cdd/<branch>.plan.md ~/.cdd/handoffs/cdd/<branch>.state.json`). Never delete without explicit confirmation.

For a richer view that also reports worktree / PR status, suggest `cdd-worktree-list`.

## 3. Propose the next task (roadmap-driven mode)

Identify the next unchecked item(s) in the roadmap. Summarize:

- What the task is, in one sentence.
- Its dependencies: what must already be done, and what this unblocks.
- Ambiguity or open design questions you can see from the roadmap alone.

If several items could reasonably be "next" (including ones that could run in parallel in separate worktrees), present them and let the user pick. Say explicitly which items overlap in the modules they would touch.

## 3-intent. Scope the given task (intent-driven and issue-driven modes)

The task is already chosen — do **not** propose candidates. In issue-driven mode the intent text comes from §0b; everything below applies unchanged.

- **Overlap check**: if the prompt substantially matches an existing roadmap item (especially an unchecked one), surface it and ask whether to proceed as that item (roadmap-driven) rather than create a duplicate.
- **Roadmap-belonging decision**: substantive, evolving, or likely to be referenced later → belongs on the roadmap; a trivial throwaway → maybe not. If unclear, ask the user. Record the verdict in the handoff's Notes (§5).

Then continue with §4.

## 4. Iterate (cheap clarification only)

Discuss with the user. Ask clarifying questions only where the answer is **cheap to resolve here** — it follows from the roadmap, the architecture docs, or a brief discussion. Examples:

- Exact scope boundaries (what is in, what is deferred).
- Which existing module owns the new code.
- Whether the work needs a new test category.
- The task's **base branch** — the branch it is cut from and merges back into. It defaults to the branch checked out here (ordinary work, and gitflow where you sit on `develop`); confirm an override only when the task stacks on another feature branch.

Defer hard, open-ended technical questions to the **plan session** (`/cdd-plan`). Examples:

- Detailed API design.
- Algorithm selection where there are real tradeoffs.
- Subtle concurrency or lifecycle questions.

List each deferred question explicitly in the handoff's Notes so `/cdd-plan` addresses it up front.

## 4b. Assess the lane

Judge smallness now, against the eligibility heuristic:

> If you can state the finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard lane.

Both bounds must hold. **Discovery**: there is nothing to find out — the one-sentence test. **Durability**: there is no reasoning worth carrying into the next window (the small-change lane writes no plan file). The bar is **not** line count.

Qualifies: ticking a roadmap box; a typo; adding a roadmap phase; adding a small utility script whose behaviour you can state in full; a mechanical rename across a few files. Does not: a three-line change whose consequence you would want reasoned about; a multi-file change you can specify in a sentence but could not justify without explanation.

**Recommend one lane in a single line**, naming which bound decided it — then do as the user says, in either direction, unconditionally (checkpoint 2). Do not refuse or re-argue a task the user declares small, and do not quietly take the small lane for a task they kept on the standard one.

The lane changes three things downstream, and nothing else: the handoff is thinner (§5), the state record carries a marker (§7), and `cdd-worktree` opens the worktree on `/cdd-small-change` instead of `/cdd-plan` (§8).

## 4c. Scope the research

Standard lane only. The plan session researches what lies outside the repo — the web, vendor and library documentation, the state of the art on the task's topic — at the depth the human sets here. The tiers:

- **none** — the repo answers everything; research is skipped.
- **light** — one focused lookup: a version quirk, an API's semantics.
- **standard** — a few independent questions, each worth its own look.
- **deep** — a wide question where the state of the art should shape the design.

The budgets behind each tier live in `/cdd-plan`, not here. **Recommend a depth and the questions research must answer, in a line or two.** Ask only what the repo cannot answer: what nobody here knows how to do, and — where the task holds a real design choice — how others solve it. Then do as the user says. "Leave it to the planner" is a valid answer: the handoff then carries no `## Research` section and the planner decides.

Never scope research on the small-change lane. A task that needs anything looked up outside the repo fails the discovery bound — recommend the standard lane instead.

## 5. Draft the handoff

When the user signals they're ready, draft:

**Branch name**: short, lowercase, underscore-separated. No `fix/` / `feature/` prefix. Derive from the task (e.g. `imu_calibration_wiring`, `setpoint_timeout_handling`). This holds in every mode, issue-driven included: never encode issue references in the branch name.

**Requirements**: the observable acceptance criteria — what "done" means for this task, checkable against the finished diff. **As few as possible: minimum 1, typically 3–6, hard cap 10.** Each is an observation, not a design decision ("the command prints its digest before the approval checkpoint", not "add a `print_digest()` helper"). A criterion you cannot state cheaply here is a **deferred question for `/cdd-plan`**, recorded in Notes — not grounds for a requirements interview. Even "tick one box" gets a criterion: a small-change handoff normally carries one or two ("the Phase 9 item is ticked, and nothing else in the roadmap changes" is a real check, not a restatement).

**Implementation prompt**: a self-contained prompt for the new session. The new session reads `CLAUDE.md`, the roadmap, and the architecture/feature docs itself, so include only context **not** inferable from the repo:

- Decisions made during this conversation that aren't yet documented anywhere.
- Scope boundaries you agreed on.
- Non-obvious constraints the user mentioned.
- Pointers to specific files or modules if relevant.

Do **not** restate project conventions, coding style, build commands, or anything already in CLAUDE.md.

**Issue-driven mode**: open the implementation prompt by noting the source issue inline — `Sourced from GitHub issue #NN ("<title>", <url>).` — then write the scoped prompt as usual. The issue reference lives in the prose, not a separate handoff field.

The prompt is a plain task spec: no standing instructions about planning, committing, or advancing the state record.

**On the small-change lane, omit the `## Implementation prompt` and `## Research` sections entirely** (the headings stay frozen: never renamed, but not always present).

**Notes**: deferred questions (§4), the roadmap-belonging verdict (§3-intent), and any roadmap changes the discussion surfaced (tasks to add, split, remove, or reword), as instructions to the implementation session. **Do not edit the roadmap file in this session.** The implementing session makes the edits: `/cdd-implement`, or `/cdd-small-change` on the small-change lane.

Then, immediately before asking for approval, print a short digest of the handoff in chat, following the `CLAUDE.md` rule — short, plain, only what changes the answer — so the human can approve or push back without opening the handoff. What usually earns a line: what the task is and which lane it takes, how much research the plan session should do (or that it is left to the planner), why it is worth doing now, what "done" means, anything deliberately out of scope, and any question deferred to `/cdd-plan`. Say what applies and drop the rest.

Show the draft for approval. Iterate if needed.

## 7. Write the handoff file

On approval, write `~/.cdd/handoffs/cdd/<branch>.md` with this structure:

```markdown
# Task: <short title>

## Branch
<branch_name>

## Roadmap reference
<exact checkbox line(s) from the roadmap being addressed>

## Requirements
<observable acceptance criteria, as few as possible — minimum 1, typically 3-6, hard cap 10; no design>

## Implementation prompt
<self-contained prompt for the plan session>

## Research
<depth: none | light | standard | deep, and the questions research must answer — or omit the section to leave it to /cdd-plan>

## Notes
<deferred open questions for /cdd-plan, proposed roadmap edits, caveats — or "None" if clean>
```

`## Research` is optional: write it only when the user set a depth in §4c, and omit it on the small-change lane. An absent section means the planner decides.

Create the per-repo handoff directory if it doesn't exist:

```bash
mkdir -p ~/.cdd/handoffs/cdd
```

Then seed the task **state record** beside the handoff, with the **base branch** agreed in §4 (substitute it for the `$(…)` default when the task stacks on a branch not checked out here). The second call runs **on the small-change lane only** (it is what `cdd-worktree` routes on; on the standard lane do not call it — an absent marker *is* the standard lane). The third runs **in issue-driven mode only**, with the references in the order given, each exactly as the tracker reports it (the adapter's `.ref`):

```bash
cdd-state seed <branch> --base "$(git rev-parse --abbrev-ref HEAD)"
cdd-state lane <branch> small
cdd-state issue-refs <branch> <ref> [<ref>...]
```

Run each as its own call, not chained, so a `cdd-state` too old for `lane` or `issue-refs` fails only that call and keeps the seeded record. If `lane` fails, the task runs the standard lane. If `issue-refs` fails, say so in one line: the task still runs, but `/cdd-pre-pr` will open the PR with no close lines and the issues stay open.

## 8. Print the next command

After writing, print exactly:

```
Handoff written: ~/.cdd/handoffs/cdd/<branch>.md
Next: cdd-worktree <branch>   (opens a plan session on /cdd-plan; /cdd-implement follows in a fresh session)
                              (small-change lane: opens on /cdd-small-change, which does the whole build)
```
