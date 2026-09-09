Scope the next roadmap task and produce a handoff file for a fresh plan session.

This is the exploratory-session command. Run on the main worktree. Output is a handoff file that a later, isolated plan session (`/cdd-plan`) will consume. This session does **not** modify any file in the repo; the only artifact it produces is the handoff file under `~/.cdd/handoffs/<PROJECT_DIR>/`.

## 0. Mode: roadmap-driven, intent-driven, or issue-driven

This command has one optional argument. Dispatch on its shape:

| `$ARGUMENTS`                        | Mode                          | Branches at |
| ----------------------------------- | ----------------------------- | ----------- |
| empty                               | **roadmap-driven**            | §3          |
| `#123` or a bare integer `123`      | **issue-driven**, direct      | §0b         |
| `issue` or `issues`                 | **issue-driven**, browse      | §0b         |
| anything else                       | **intent-driven**             | §3-intent   |

Every mode first runs §0a (checkout freshness), §1 (read context) and §2 (stale-handoff sweep); the "Branches at" column is only where the mode-specific path begins after that.

- **Roadmap-driven**: pick the next item off the roadmap. Run §1–§8 as written.
- **Intent-driven**: the task is already chosen by the user, so skip candidate proposal (§3 is replaced by §3-intent below). Use this when the user wants to start something off-roadmap rather than picking the next checkbox.
- **Issue-driven**: a thin front-end onto intent-driven mode — the intent text comes from a GitHub issue instead of being typed. §0b resolves the issue, then the flow is exactly intent-driven (§1 adaptive load, §3-intent, §4 onward).

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

**Preconditions.** This mode needs the `gh` CLI authenticated and a GitHub `origin`:

```bash
gh auth status && git remote get-url origin   # origin should be a github.com URL
```

If `gh` is missing/unauthenticated or `origin` is not a GitHub remote, print a one-line explanation (e.g. "Issue mode needs the `gh` CLI and a GitHub origin; neither roadmap nor intent mode does — pass a task prompt or no argument instead.") and stop. Do not crash; roadmap- and intent-driven modes never reach this step.

**Direct** (`#N` or bare `N`): strip any leading `#`, then read the issue (read-only — never assign, comment, or relabel):

```bash
gh issue view <N> --json number,title,body,url,comments
```

**Browse** (`issue` / `issues`): list open issues, then exclude any that already have a local branch or an open PR on a `gh_issue_<n>_*` branch, so the user only sees unstarted work:

```bash
gh issue list --state open --json number,title,labels
git branch --list 'gh_issue_*'                          # already-started issues, by branch
gh pr list --state open --json number,headRefName        # already-started issues, by PR
```

Present the filtered list (number + title) and let the user pick one; then fetch its detail with `gh issue view` as above.

Use the issue's title + body + comments as the **intent text**, and continue with §1, then §3-intent. The issue number is carried forward only via the branch name in §5 (`gh_issue_NN_<slug>`) — there is no commit trailer, and no downstream session is required to re-read the issue.

## 1. Read context

Read `doc/knowledge_base/roadmap.md` in full. Also skim `doc/architecture/index.md` and `doc/features/index.md` for current state, but do not read them exhaustively, the plan session will rebuild detailed context.

**Intent-driven and issue-driven modes**, load context adaptively to preserve context economy: after the roadmap and the two indexes above, selectively open only the docs the described task (or the resolved issue) actually touches — enough to scope it and detect overlap with existing work, not an exhaustive read.

## 2. Check for stale handoffs

List existing handoff files:

```bash
ls ~/.cdd/handoffs/<PROJECT_DIR>/ 2>/dev/null
```

The handoffs are the `<branch>.md` files. Their branch-named siblings are **not** handoffs — skip `<branch>.plan.md` (the plan file) and `<branch>.state.json`, and skip the per-repo `repo.json`; treating `<branch>.plan.md` as a handoff would invent a task named `<branch>.plan`.

For each handoff `<branch>.md`, check whether the branch still exists locally:

```bash
git branch --list <branch>
```

If the branch is gone, the handoff is stale. For each stale handoff, prompt the user inline whether to delete it together with its branch-named siblings (`rm -f ~/.cdd/handoffs/<PROJECT_DIR>/<branch>.md ~/.cdd/handoffs/<PROJECT_DIR>/<branch>.plan.md ~/.cdd/handoffs/<PROJECT_DIR>/<branch>.state.json`). Never delete without explicit confirmation.

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

## 5. Draft the handoff

When the user signals they're ready, draft:

**Branch name**: short, lowercase, underscore-separated. No `fix/` / `feature/` prefix. Derive from the task (e.g. `imu_calibration_wiring`, `setpoint_timeout_handling`). **Issue-driven mode**: prefix the name with the fixed `gh_issue_NN_` token so the issue number is durable and groups cleanly — `gh_issue_NN_<descriptive_slug>` (e.g. `gh_issue_42_dark_mode`). This token is the sole mechanism threading the issue to its PR (`/cdd-pre-pr` turns it into `Closes #NN`).

**Requirements**: the observable acceptance criteria — what "done" means for this task, checkable against the finished diff. **As few as possible: typically 3–6, hard cap 10.** Each is an observation, not a design decision ("the command prints its digest before the approval checkpoint", not "add a `print_digest()` helper").

This section exists because the plan and the implementation run in separate windows: it is the one artifact that survives both and can be checked against each — `/cdd-plan` checks its plan against it, `/cdd-implement` treats it as the done-test, and `/cdd-pre-pr` reconciles the diff against it instead of inferring intent.

The cap is what keeps this from turning the session into a requirements interview, which the cheap/expensive split in step 4 exists to prevent. A criterion you cannot state cheaply here is a **deferred question for `/cdd-plan`**, recorded in Notes — not grounds for an interview.

**Implementation prompt**: a self-contained prompt for the new session. Critical rule, the new session will read `CLAUDE.md`, the roadmap, and the architecture/feature docs itself. Include only context that is **not** inferable from the repo:

- Decisions made during this conversation that aren't yet documented anywhere.
- Scope boundaries you agreed on.
- Non-obvious constraints the user mentioned.
- Pointers to specific files or modules if relevant.

Do **not** restate project conventions, coding style, build commands, or anything already in CLAUDE.md.

**Issue-driven mode**: open the implementation prompt by noting the source issue inline — `Sourced from GitHub issue #NN ("<title>", <url>).` — then write the scoped prompt as usual. The issue reference lives in the prose, not a separate handoff field.

The prompt is a plain task spec. It carries no standing instructions about planning, committing, or advancing the state record: those live in `/cdd-plan` and `/cdd-implement`, where they are improved once instead of regenerated into every handoff.

Show the draft to the user for approval, after the digest below. Iterate if needed.

## 5b. Print the bounded digest

Immediately before asking for approval, print a plainly-worded digest of the handoff in chat: **at most 7 bullets, one line each**. The cap is the feature — an uncapped digest is the wall of text the checkpoint gets skimmed for, and the human should be able to approve or push back without reading the artifact.

Cover, in this order, skipping any that do not apply:

1. The task, in one line.
2. Why now — the problem it addresses.
3. What "done" means (the `## Requirements`, condensed).
4. What rides along, or what this is coupled to.
5. The mechanical surface — roughly what gets touched.
6. What is explicitly out of scope.
7. Questions deferred to `/cdd-plan`.

(The cap is a starting point; tuning it, and generalizing this convention to the other commands, is tracked separately.)

## 6. Note any roadmap edits implied

If the discussion surfaced changes the roadmap should reflect (new tasks to add, existing tasks to split or remove, tasks that need rewording), record these in the handoff's Notes section as an instruction to the implementation session. **Do not edit the roadmap file in this session.** `/cdd-implement` will make the edits as part of its work.

## 7. Write the handoff file

On approval, write `~/.cdd/handoffs/<PROJECT_DIR>/<branch>.md` with this structure:

```markdown
# Task: <short title>

## Branch
<branch_name>

## Roadmap reference
<exact checkbox line(s) from the roadmap being addressed>

## Requirements
<observable acceptance criteria, as few as possible — typically 3-6, hard cap 10; no design>

## Implementation prompt
<the self-contained prompt from step 5>

## Notes
<deferred open questions for /cdd-plan, proposed roadmap edits, caveats — or "None" if clean>
```

Create the per-repo handoff directory if it doesn't exist:

```bash
mkdir -p ~/.cdd/handoffs/<PROJECT_DIR>
```

Then seed the task **state record** beside the handoff — the slash commands advance this file as the task moves through its stages, and external tools read it. Record the task's **base branch** (agreed in §4 above) with it, defaulting to the branch checked out here; substitute the agreed base for the `$(…)` default when the task stacks on a branch not checked out here:

```bash
cdd-state seed <branch> --base "$(git rev-parse --abbrev-ref HEAD)"
```

## 8. Print the next command

After writing, print exactly (the install line is a static reminder — do **not** probe for the helper on every run; it's a once-per-machine setup the user ignores once done):

```
Handoff written: ~/.cdd/handoffs/<PROJECT_DIR>/<branch>.md
Next: cdd-worktree <branch>   (opens a plan session on /cdd-plan; /cdd-implement follows in a fresh session)

If `cdd-worktree` or `cdd-state` is "command not found", install the shared helpers once (machine-global, like git/gh), then open a new shell:
  curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/cdd-worktree.sh --create-dirs -o ~/.cdd/tools/cdd-worktree.sh && bash ~/.cdd/tools/cdd-worktree.sh install
  curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/cdd-state.sh --create-dirs -o ~/.cdd/tools/cdd-state.sh && bash ~/.cdd/tools/cdd-state.sh install
  (Or, from a CDD repo checkout: ./tools/cdd-worktree.sh install && ./tools/cdd-state.sh install)
```

The user will close this session, run `cdd-worktree <branch>` from the main worktree, and a fresh Claude session will open in the new worktree in plan mode with `/cdd-plan` already submitted. That session plans and stops; the user then opens another fresh session in the same worktree and runs `/cdd-implement`.
