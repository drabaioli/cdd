Scope the next roadmap task and produce a handoff file for a fresh implementation session.

This is the exploratory-session command. Run on the main worktree. Output is a handoff file that a later, isolated implementation session will consume. This session does **not** modify any file in the repo; the only artifact it produces is the handoff file under `~/.cdd/handoffs/<PROJECT_DIR>/`.

## 0. Mode: roadmap-driven, intent-driven, or issue-driven

This command has one optional argument. Dispatch on its shape:

| `$ARGUMENTS`                        | Mode                          | Branches at |
| ----------------------------------- | ----------------------------- | ----------- |
| empty                               | **roadmap-driven**            | §3          |
| `#123` or a bare integer `123`      | **issue-driven**, direct      | §0b         |
| `issue` or `issues`                 | **issue-driven**, browse      | §0b         |
| anything else                       | **intent-driven**             | §3-intent   |

Every mode first runs §1 (read context) and §2 (stale-handoff sweep); the "Branches at" column is only where the mode-specific path begins after that.

- **Roadmap-driven**: pick the next item off the roadmap. Run §1–§8 as written.
- **Intent-driven**: the task is already chosen by the user, so skip candidate proposal (§3 is replaced by §3-intent below). Use this when the user wants to start something off-roadmap rather than picking the next checkbox.
- **Issue-driven**: a thin front-end onto intent-driven mode — the intent text comes from a GitHub issue instead of being typed. §0b resolves the issue, then the flow is exactly intent-driven (§1 adaptive load, §3-intent, §4 onward).

All modes converge on the same machinery from §4 onward (stale-handoff sweep in §2 runs in all of them). Do not fork the flow beyond what §0b, §1, and §3 describe.

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

Use the issue's title + body + comments as the **intent text**, and continue with §1, then §3-intent. The issue number is carried forward only via the branch name in §5 (`gh_issue_NN_<slug>`) — there is no commit trailer and the implementation session does not re-read the issue.

## 1. Read context

Read `doc/knowledge_base/roadmap.md` in full. Also skim `doc/architecture/index.md` and `doc/features/index.md` for current state, but do not read them exhaustively, the implementation session will rebuild detailed context.

**Intent-driven and issue-driven modes**, load context adaptively to preserve context economy: after the roadmap and the two indexes above, selectively open only the docs the described task (or the resolved issue) actually touches — enough to scope it and detect overlap with existing work, not an exhaustive read.

## 2. Check for stale handoffs

List existing handoff files:

```bash
ls ~/.cdd/handoffs/<PROJECT_DIR>/ 2>/dev/null
```

For each file `<branch>.md`, check whether the branch still exists locally:

```bash
git branch --list <branch>
```

If the branch is gone, the handoff is stale. For each stale handoff, prompt the user inline whether to delete it (`rm ~/.cdd/handoffs/<PROJECT_DIR>/<branch>.md`). Never delete without explicit confirmation.

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

Hard, open-ended technical questions are deferred to the implementation session, which will have a clean context dedicated to one task. Examples of expensive clarification (defer):

- Detailed API design.
- Algorithm selection where there are real tradeoffs.
- Subtle concurrency or lifecycle questions.

When you defer a question, list it explicitly in the handoff's Notes section so the implementation session addresses it up front.

## 5. Draft the handoff

When the user signals they're ready, draft:

**Branch name**: short, lowercase, underscore-separated. No `fix/` / `feature/` prefix. Derive from the task (e.g. `imu_calibration_wiring`, `setpoint_timeout_handling`). **Issue-driven mode**: prefix the name with the fixed `gh_issue_NN_` token so the issue number is durable and groups cleanly — `gh_issue_NN_<descriptive_slug>` (e.g. `gh_issue_42_dark_mode`). This token is the sole mechanism threading the issue to its PR (`/cdd-pre-pr` turns it into `Closes #NN`).

**Implementation prompt**: a self-contained prompt for the new session. Critical rule, the new session will read `CLAUDE.md`, the roadmap, and the architecture/feature docs itself. Include only context that is **not** inferable from the repo:

- Decisions made during this conversation that aren't yet documented anywhere.
- Scope boundaries you agreed on.
- Non-obvious constraints the user mentioned.
- Pointers to specific files or modules if relevant.

Do **not** restate project conventions, coding style, build commands, or anything already in CLAUDE.md.

**Issue-driven mode**: open the implementation prompt by noting the source issue inline — `Sourced from GitHub issue #NN ("<title>", <url>).` — then write the scoped prompt as usual. The issue reference lives in the prose, not a separate handoff field.

End the implementation prompt with these standing instructions (verbatim):

> Before writing a plan, surface any remaining open questions and confirm scope with the user.
>
> When the work is done, commit your own changes locally (no push), following the commit conventions in CLAUDE.md. Commit only the files you changed — add them by path, never `git add -A`. If the tree holds changes you didn't make, surface them rather than committing them.

Show the draft to the user for approval. Iterate if needed.

## 6. Note any roadmap edits implied

If the discussion surfaced changes the roadmap should reflect (new tasks to add, existing tasks to split or remove, tasks that need rewording), record these in the handoff's Notes section as an instruction to the implementation session. **Do not edit the roadmap file in this session.** The implementation session will make the edits as part of its work.

## 7. Write the handoff file

On approval, write `~/.cdd/handoffs/<PROJECT_DIR>/<branch>.md` with this structure:

```markdown
# Task: <short title>

## Branch
<branch_name>

## Roadmap reference
<exact checkbox line(s) from the roadmap being addressed>

## Implementation prompt
<the self-contained prompt from step 5>

## Notes
<deferred open questions for the implementation session, proposed roadmap edits, caveats — or "None" if clean>
```

Create the per-repo handoff directory if it doesn't exist:

```bash
mkdir -p ~/.cdd/handoffs/<PROJECT_DIR>
```

## 8. Print the next command, and offer to install the helper if missing

After writing, print exactly:

```
Handoff written: ~/.cdd/handoffs/<PROJECT_DIR>/<branch>.md
Next: cdd-worktree <branch>
```

Then check whether the shared worktree helper is installed on this machine (a plain file test — `cdd-worktree` itself is a shell function, not visible to a non-interactive shell):

```bash
test -f ~/.cdd/tools/cdd-worktree.sh && echo present || echo missing
```

- **present** — nothing more to do.
- **missing** — the helper isn't installed yet. It's a one-time, machine-global install (like `git` or `gh`; it then works in every CDD project). **Offer to run it now**, and on the user's go-ahead, run:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/drabaioli/cdd/main/tools/cdd-worktree.sh \
    --create-dirs -o ~/.cdd/tools/cdd-worktree.sh \
    && bash ~/.cdd/tools/cdd-worktree.sh install
  ```

  (It must land on disk first — `curl … | bash` won't work, because the installer copies itself from its own file path. If the user has the CDD repo checked out, `./tools/cdd-worktree.sh install` from it does the same with no download.) Tell the user to open a new shell afterwards so `cdd-worktree` is available.

The user will close this session, run `cdd-worktree <branch>` from the main worktree, and a fresh Claude session will open in the new worktree with the first prompt already submitted.
