Scope the next roadmap task and produce a handoff file for a fresh plan session.

This is the exploratory-session command. Run on the main worktree. Output is a handoff file that a later, isolated plan session (`/cdd-plan`) will consume. This session does **not** modify any file in the repo; the only artifact it produces is the handoff file under `~/.cdd/handoffs/cdd/`.

## 0. Mode: roadmap-driven, intent-driven, or issue-driven

This command has one optional argument. Dispatch on its shape, trying the rows in order:

| `$ARGUMENTS`                        | Mode                          | Branches at |
| ----------------------------------- | ----------------------------- | ----------- |
| empty                               | **roadmap-driven**            | §3          |
| `issue` or `issues`                 | **issue-driven**, browse      | §0b         |
| every whitespace-separated token matches the tracker's `ref_pattern` | **issue-driven**, direct | §0b |
| anything else                       | **intent-driven**             | §3-intent   |

`issue` / `issues` is a fixed keyword and is checked before the pattern, so browsing stays available whatever the backend calls its references.

The argument splits on whitespace, and the direct row matches only when **every** token matches — one task may be sourced from several issues (`/cdd-next-step 97 12`). A single token is the common case and behaves exactly as before; a mixed argument (one token matching, one not) is not issue-driven and falls to intent-driven, where the whole string is read as a task prompt.

**What a reference looks like is the tracker's decision, not this command's.** Resolve the tracker down the ladder — project, then machine, then built-in — and take the first executable:

```bash
for c in .cdd/tracker ~/.cdd/adapters/tracker; do [ -x "$c" ] && { echo "$c"; break; }; done
```

If one resolved, run `describe` and take `.ref_pattern` — an ERE — as the shape of a reference:

```bash
<adapter> describe    # JSON on stdout; hermetic, so it needs no network and no credentials
```

Use it only if `describe` exits 0, parses as JSON, and reports a `contract` this CDD supports (currently `1`). Otherwise — unparseable, wrong version, or a non-zero exit — say so in **one line** and fall through to the next rung; that line is unconditional, because the user installed something that is not working and silence there is indistinguishable from it working. With nothing resolved, the built-in rung serves and its `ref_pattern` is the constant `^#?[0-9]+$` — `#123` or a bare `123`, exactly as before adapters existed.

Resolution done only to classify the argument is otherwise **silent**. The line naming which rung served is printed in §0b, where a tracker call is actually made: a fallback line in every session in every repo is noise, and noise is how a load-bearing line stops being read.

Every mode first runs §0a (checkout freshness), §1 (read context) and §2 (stale-handoff sweep); the "Branches at" column is only where the mode-specific path begins after that.

- **Roadmap-driven**: pick the next item off the roadmap. Run §1–§8 as written.
- **Intent-driven**: the task is already chosen by the user, so skip candidate proposal (§3 is replaced by §3-intent below). Use this when the user wants to start something off-roadmap rather than picking the next checkbox.
- **Issue-driven**: a thin front-end onto intent-driven mode — the intent text comes from a tracker item instead of being typed. §0b resolves the item, then the flow is exactly intent-driven (§1 adaptive load, §3-intent, §4 onward).

All modes converge on the same machinery from §4 onward (stale-handoff sweep in §2 runs in all of them). Do not fork the flow beyond what §0b, §1, and §3 describe.

## 0a. Verify the checkout is current

Scoping work from a stale checkout can hand off a task that is already merged, so before reading any context, confirm this checkout is not behind its upstream. Compare the **checked-out** branch — the branch a task cut here would be based on (§4) — against its upstream, not the platform default branch:

```bash
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "origin/$BRANCH")"
git fetch --quiet origin "$BRANCH" && git rev-list --left-right --count "HEAD...$UPSTREAM"
```

The count prints two numbers, ahead then behind. The fetch updates remote-tracking refs only — it never touches the working tree, so this session still modifies no file in the repo.

- **Behind** (second number non-zero): **stop**. Say how many commits behind the upstream this checkout is, and tell the user to run `git pull --ff-only` here and re-run the command. Do not pull, and do not offer to.
- **Ahead or diverged**: report it in one line and continue. Never a block.
- **Fetch failed or no upstream** (offline, no remote, or no counterpart branch on `origin`): say in one line that the freshness check was skipped, and continue — the command stays usable offline, the same way roadmap and intent modes stay usable without `gh`.

Then continue with §0b (issue-driven mode) or §1.

## 0b. Resolve the issue (issue-driven mode)

**Preconditions.** This mode needs a tracker that can serve the call — the verb is `issue-read` for direct, `issue-list` for browse.

*With an adapter resolved* (§0), that verb must appear in its `describe.verbs`; if it does not, say which verb the adapter is missing and stop. A call that exits **4** (not configured / auth missing) prints an actionable line on stderr — show that line and stop, rather than reinterpreting it.

*With nothing resolved*, the built-in rung serves, and it needs the `gh` CLI authenticated and a GitHub `origin`:

```bash
gh auth status && git remote get-url origin   # origin should be a github.com URL
```

If `gh` is missing/unauthenticated or `origin` is not a GitHub remote, print a one-line explanation (e.g. "Issue mode needs the `gh` CLI and a GitHub origin; neither roadmap nor intent mode does — pass a task prompt or no argument instead.") and stop. Do not crash; roadmap- and intent-driven modes never reach this step.

**Announce the rung in one line** before the first call — `.cdd/tracker`, `~/.cdd/adapters/tracker`, or "no tracker adapter installed; using the built-in `gh` path". This is the one place the ladder is visible to the user, and where a wrong binding would otherwise stay silent.

**Direct** (every token of `$ARGUMENTS` matched the `ref_pattern`): read each item, in the order given (read-only — never assign, comment, or relabel). With an adapter, that is one `<adapter> issue-read <ref>` per token, passing each through unchanged — normalizing a reference is the adapter's job, not this command's. Otherwise strip any leading `#` and use the built-in, once per reference:

```bash
gh issue view <N> --json number,title,body,url,comments
```

Several references mean one task sourced from several issues, not several tasks. If the items turn out to describe unrelated work, say so and ask which to scope — do not fold unrelated work into one handoff silently.

**Browse** (`issue` / `issues`): list open issues, then exclude any that already have a local branch or an open PR on a `gh_issue_<n>_*` branch, so the user only sees unstarted work:

```bash
gh issue list --state open --json number,title,labels
git branch --list 'gh_issue_*'                          # already-started issues, by branch
gh pr list --state open --json number,headRefName        # already-started issues, by PR
jq -r '.issue_refs // [] | .[]' ~/.cdd/handoffs/cdd/*.state.json 2>/dev/null   # ...by state record
```

With an adapter, `<adapter> issue-list` replaces the first line; the other three stay as they are, since a local branch, an open PR and a task's own state record are facts about this checkout, not about the tracker.

The first two exclusion lines find already-started issues by the `gh_issue_NN_` branch token, which a multi-ref or non-GitHub task does not carry (§5) — the fourth line covers those, since their references live on the state record instead. Compare after stripping any leading `#`, as a reference is recorded exactly as the tracker reports it. The records are local to this machine and advisory (absent without `jq`, reaped once a PR merges), so this narrows the blind spot rather than closing it: a reference found there means "already in flight", while finding none is not proof the issue is unstarted.

Present the filtered list (number + title) and let the user pick **one or more**; then fetch each one's detail as above.

Use the items' titles + bodies + comments as the **intent text**, and continue with §1, then §3-intent. The references are carried forward on the task's **state record** (§7), which is what `/cdd-pre-pr` reads to emit one close line per reference; the `gh_issue_NN_` branch token (§5) survives for a single GitHub-backed numeric reference as a fallback, not as the mechanism. There is no commit trailer, and no downstream session is required to re-read the issue.

## 1. Read context

Read `doc/knowledge_base/roadmap.md` in full. Also skim `doc/architecture/index.md` and `doc/features/index.md` for current state, but do not read them exhaustively, the plan session will rebuild detailed context.

**Intent-driven and issue-driven modes**, load context adaptively to preserve context economy: after the roadmap and the two indexes above, selectively open only the docs the described task (or the resolved issue) actually touches — enough to scope it and detect overlap with existing work, not an exhaustive read.

## 2. Check for stale handoffs

List existing handoff files:

```bash
ls ~/.cdd/handoffs/cdd/ 2>/dev/null
```

The handoffs are the `<branch>.md` files. Their branch-named siblings are **not** handoffs — skip `<branch>.plan.md` (the plan file) and `<branch>.state.json`, and skip the per-repo `repo.json`; treating `<branch>.plan.md` as a handoff would invent a task named `<branch>.plan`.

For each handoff `<branch>.md`, check whether the branch still exists locally:

```bash
git branch --list <branch>
```

If the branch is gone, the handoff is stale. For each stale handoff, prompt the user inline whether to delete it together with its branch-named siblings (`rm -f ~/.cdd/handoffs/cdd/<branch>.md ~/.cdd/handoffs/cdd/<branch>.plan.md ~/.cdd/handoffs/cdd/<branch>.state.json`). Never delete without explicit confirmation.

For a richer view that also reports worktree / PR status, suggest `cdd-worktree-list`.

## 3. Propose the next task (roadmap-driven mode)

Identify the next unchecked item(s) in the roadmap. Summarize:

- What the task is, in one sentence.
- Its dependencies: what must already be done, and what this unblocks.
- Ambiguity or open design questions you can see from the roadmap alone.

If multiple items could reasonably be "next" (including items that could be done in parallel in separate worktrees), present them and let the user pick. Be explicit about which items overlap in the modules they would touch; parallel work assumes minimal overlap.

## 3-intent. Scope the given task (intent-driven and issue-driven modes)

The task is already chosen — do **not** propose candidates. In issue-driven mode, the issue's title/body/comments (from §0b) are the intent text; everything below applies unchanged. Instead:

- **Overlap check**: if the prompt substantially matches an existing roadmap item (especially an unchecked one), surface it and ask whether to proceed as that item (roadmap-driven) rather than silently creating a duplicate.
- **Roadmap-belonging decision**: judge whether this new task belongs on the roadmap — substantive, evolving, or likely to be referenced later → yes; a trivial throwaway → maybe not. If it's unclear, ask the user. Record the verdict in §6 as an instruction to the implementation session (the implementation session makes the actual roadmap edit; this session never edits the roadmap).

Then continue with §4.

## 4. Iterate (cheap clarification only)

Discuss with the user. Ask clarifying questions, but keep them to the requirements that are **cheap to resolve here**: questions where the right answer follows from the roadmap, from architecture docs, or from a brief discussion. Examples of cheap clarification:

- Exact scope boundaries (what is in, what is deferred).
- Which existing module owns the new code.
- Whether the work needs a new test category.
- The task's **base branch** — the branch it is cut from and merges back into. It defaults to the branch checked out here (ordinary work, and gitflow where you sit on `develop`); confirm an override only when the task stacks on another feature branch.

Hard, open-ended technical questions are deferred to the **plan session** (`/cdd-plan`), which will have a clean context dedicated to one task, in the real worktree. Examples of expensive clarification (defer):

- Detailed API design.
- Algorithm selection where there are real tradeoffs.
- Subtle concurrency or lifecycle questions.

When you defer a question, list it explicitly in the handoff's Notes section so `/cdd-plan` addresses it up front.

## 4b. Assess the lane

Smallness is only answerable once the task is known, which is why there is no flag for it and why this step sits here rather than at §0. Judge it now, against the eligibility heuristic:

> If you can state the finished diff in one sentence, before any exploration, it's small. If in doubt, take the standard lane.

Two bounds, and both must hold. **Discovery**: there is nothing to find out — that is the one-sentence test. **Durability**: there is no reasoning worth carrying into the next window, because the small-change lane writes no plan file and only the requirements plus the diff reach `/cdd-pre-pr` and the reviewer. The bar is **not** line count.

Qualifies: ticking a roadmap box; a typo; adding a roadmap phase; adding a small utility script whose behaviour you can state in full; a mechanical rename across a few files. Does not: a three-line change whose consequence you would want reasoned about; a multi-file change you can specify in a sentence but could not justify without explanation.

**Recommend one lane in a single line**, naming which bound decided it — then do as the user says, in either direction, unconditionally. This is checkpoint 2, and the posture is the same as every other structural choice in CDD: surface the signals, recommend, and let the human decide. Do not refuse or re-argue a task the user declares small, and do not quietly take the small lane for a task they kept on the standard one. The override is safe both ways: a task wrongly declared small is recovered by `/cdd-small-change`'s off-ramp into `/cdd-plan`, at the cost of one session start, and a task wrongly kept standard just costs a window.

The lane changes three things downstream, and nothing else: the handoff is thinner (§5), the state record carries a marker (§7), and `cdd-worktree` opens the worktree on `/cdd-small-change` instead of `/cdd-plan` (§8).

## 5. Draft the handoff

When the user signals they're ready, draft:

**Branch name**: short, lowercase, underscore-separated. No `fix/` / `feature/` prefix. Derive from the task (e.g. `imu_calibration_wiring`, `setpoint_timeout_handling`). **Issue-driven mode**: with a **single** reference on the built-in `gh` rung — a numeric ref, `#NN` or `NN` — prefix the name with the fixed `gh_issue_NN_` token, so the issue number is durable and groups cleanly: `gh_issue_NN_<descriptive_slug>` (e.g. `gh_issue_42_dark_mode`). With several references, or with a backend whose references are not GitHub issue numbers, use a plain descriptive slug and **no token**: the references ride the state record (§7), and no ref-encoding scheme is introduced into branch names. Where the token is present it is a fallback `/cdd-pre-pr` parses when the record is unusable — not the mechanism.

**Requirements**: the observable acceptance criteria — what "done" means for this task, checkable against the finished diff. **As few as possible: minimum 1, typically 3–6, hard cap 10.** Each is an observation, not a design decision ("the command prints its digest before the approval checkpoint", not "add a `print_digest()` helper").

This section exists because the plan and the implementation run in separate windows: it is the one artifact that survives both and can be checked against each — `/cdd-plan` checks its plan against it, `/cdd-implement` treats it as the done-test, and `/cdd-pre-pr` reconciles the diff against it instead of inferring intent.

The cap is what keeps this from turning the session into a requirements interview, which the cheap/expensive split in step 4 exists to prevent. A criterion you cannot state cheaply here is a **deferred question for `/cdd-plan`**, recorded in Notes — not grounds for an interview.

The floor of 1 is load-bearing too, and it is why "tick one box" still gets a criterion: `/cdd-pre-pr` reconciles the diff *against* this section, so an empty one leaves it inferring intent — the exact thing the section prevents. A small-change handoff normally carries one or two ("the Phase 9 item is ticked, and nothing else in the roadmap changes" is a real check, not a restatement).

**Implementation prompt**: a self-contained prompt for the new session. Critical rule, the new session will read `CLAUDE.md`, the roadmap, and the architecture/feature docs itself. Include only context that is **not** inferable from the repo:

- Decisions made during this conversation that aren't yet documented anywhere.
- Scope boundaries you agreed on.
- Non-obvious constraints the user mentioned.
- Pointers to specific files or modules if relevant.

Do **not** restate project conventions, coding style, build commands, or anything already in CLAUDE.md.

**Issue-driven mode**: open the implementation prompt by noting the source issue inline — `Sourced from GitHub issue #NN ("<title>", <url>).` — then write the scoped prompt as usual. The issue reference lives in the prose, not a separate handoff field.

The prompt is a plain task spec. It carries no standing instructions about planning, committing, or advancing the state record: those live in `/cdd-plan` and `/cdd-implement`, where they are improved once instead of regenerated into every handoff.

**On the small-change lane, omit the `## Implementation prompt` section entirely.** The requirements already say everything there is to say about a change whose diff fits in a sentence, and a section restating them is the drift risk this lane exists to avoid. The heading itself stays frozen — frozen means never renamed, not always present.

Show the draft to the user for approval, after the digest below. Iterate if needed.

## 5b. Print the bounded digest

Immediately before asking for approval, print a short summary of the handoff in chat: what the task is about, and the details that bear on approving it. Follow the rule in `CLAUDE.md` — short, plain, only what changes the answer. The human should be able to approve or push back on this alone, without opening the handoff.

What usually earns a line: what the task is and which lane it takes, why it is worth doing now, what "done" means, anything deliberately out of scope, and any question being deferred to `/cdd-plan`. Say what applies and drop the rest — this is a summary, not a form to fill in.

## 6. Note any roadmap edits implied

If the discussion surfaced changes the roadmap should reflect (new tasks to add, existing tasks to split or remove, tasks that need rewording), record these in the handoff's Notes section as an instruction to the implementation session. **Do not edit the roadmap file in this session.** `/cdd-implement` will make the edits as part of its work.

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
<the self-contained prompt from step 5>

## Notes
<deferred open questions for /cdd-plan, proposed roadmap edits, caveats — or "None" if clean>
```

Create the per-repo handoff directory if it doesn't exist:

```bash
mkdir -p ~/.cdd/handoffs/cdd
```

Then seed the task **state record** beside the handoff — the slash commands advance this file as the task moves through its stages, and external tools read it. Record the task's **base branch** (agreed in §4 above) with it, defaulting to the branch checked out here; substitute the agreed base for the `$(…)` default when the task stacks on a branch not checked out here:

```bash
cdd-state seed <branch> --base "$(git rev-parse --abbrev-ref HEAD)"
```

**On the small-change lane only**, mark the lane on the record — this is what `cdd-worktree` routes on:

```bash
cdd-state lane <branch> small
```

It is a separate call rather than a flag on `seed` so that a machine whose `cdd-state` predates the lane fails this one command and keeps the seeded record (base branch included); the task then simply runs the standard lane. On the standard lane, do not call it at all — an absent marker *is* the standard lane.

**Issue-driven mode only**, record the reference(s) the task was sourced from, in the order they were given:

```bash
cdd-state issue-refs <branch> <ref> [<ref>...]
```

Pass each reference exactly as the tracker reports it — the adapter's `.ref`, or the argument as typed on the built-in `gh` rung. `/cdd-pre-pr` reads this list back and emits one close line per entry. It is its own subcommand for the same reason `lane` is: a machine whose `cdd-state` predates it fails this one call and keeps the seeded record. If it fails, say so in one line — the task still runs, but only the `gh_issue_NN_` branch token carries an issue forward, so a multi-reference task would close its first issue alone.

## 8. Print the next command

After writing, print exactly:

```
Handoff written: ~/.cdd/handoffs/cdd/<branch>.md
Next: cdd-worktree <branch>   (opens a plan session on /cdd-plan; /cdd-implement follows in a fresh session)
                              (small-change lane: opens on /cdd-small-change, which does the whole build)
```

The user will close this session, run `cdd-worktree <branch>` from the main worktree, and a fresh Claude session will open in the new worktree with `/cdd-plan` already submitted. That session plans and stops; the user then opens another fresh session in the same worktree and runs `/cdd-implement`.

On the small-change lane the helper reads the marker and opens that session on `/cdd-small-change` instead, which explores nothing, takes its own approval of the concrete change, builds it, and commits — one session in place of two. If the helper is older than the lane, or the project ships no `/cdd-small-change`, it opens `/cdd-plan` as usual and nothing is lost but a window.
