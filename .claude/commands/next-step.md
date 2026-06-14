Scope the next roadmap task and produce a handoff file for a fresh implementation session.

This is the exploratory-session command. Run on the main worktree. Output is a handoff file that a later, isolated implementation session will consume. This session does **not** modify any file in the repo; the only artifact it produces is the handoff file under `~/.claude-handoffs/cdd/`.

## 0. Mode: roadmap-driven or intent-driven

This command has one optional argument: a prompt describing a task the user wants to start.

- **No argument** → **roadmap-driven** mode: pick the next item off the roadmap. Run §1–§8 as written.
- **Argument present** (`$ARGUMENTS`) → **intent-driven** mode: the task is already chosen by the user, so skip candidate proposal (§3 is replaced by §3-intent below). Use this when the user wants to start something off-roadmap rather than picking the next checkbox.

Both modes converge on the same machinery from §4 onward (stale-handoff sweep in §2 runs in both). Do not fork the flow beyond what §1 and §3 describe.

## 1. Read context

Read `doc/knowledge_base/roadmap.md` in full. Also skim `doc/architecture/index.md` and `doc/features/index.md` for current state, but do not read them exhaustively, the implementation session will rebuild detailed context.

**Intent-driven mode**, load context adaptively to preserve context economy: after the roadmap and the two indexes above, selectively open only the docs the described task actually touches — enough to scope it and detect overlap with existing work, not an exhaustive read.

## 2. Check for stale handoffs

List existing handoff files:

```bash
ls ~/.claude-handoffs/cdd/ 2>/dev/null
```

For each file `<branch>.md`, check whether the branch still exists locally:

```bash
git branch --list <branch>
```

If the branch is gone, the handoff is stale. For each stale handoff, prompt the user inline whether to delete it (`rm ~/.claude-handoffs/cdd/<branch>.md`). Never delete without explicit confirmation.

For a richer view that also reports worktree / PR status, suggest `cdd-worktree-list`.

## 3. Propose the next task (roadmap-driven mode)

Identify the next unchecked item(s) in the roadmap. Summarize:

- What the task is, in one sentence.
- Its dependencies: what must already be done, and what this unblocks.
- Ambiguity or open design questions you can see from the roadmap alone.

If multiple items could reasonably be "next" (including items that could be done in parallel in separate worktrees), present them and let the user pick. Be explicit about which items overlap in the modules they would touch; parallel work assumes minimal overlap.

## 3-intent. Scope the given task (intent-driven mode)

The task is already chosen — do **not** propose candidates. Instead:

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

**Branch name**: short, lowercase, underscore-separated. No `fix/` / `feature/` prefix. Derive from the task (e.g. `imu_calibration_wiring`, `setpoint_timeout_handling`).

**Implementation prompt**: a self-contained prompt for the new session. Critical rule, the new session will read `CLAUDE.md`, the roadmap, and the architecture/feature docs itself. Include only context that is **not** inferable from the repo:

- Decisions made during this conversation that aren't yet documented anywhere.
- Scope boundaries you agreed on.
- Non-obvious constraints the user mentioned.
- Pointers to specific files or modules if relevant.

Do **not** restate project conventions, coding style, build commands, or anything already in CLAUDE.md.

End the implementation prompt with this standing instruction (verbatim):

> Before writing a plan, surface any remaining open questions and confirm scope with the user.

Show the draft to the user for approval. Iterate if needed.

## 6. Note any roadmap edits implied

If the discussion surfaced changes the roadmap should reflect (new tasks to add, existing tasks to split or remove, tasks that need rewording), record these in the handoff's Notes section as an instruction to the implementation session. **Do not edit the roadmap file in this session.** The implementation session will make the edits as part of its work.

## 7. Write the handoff file

On approval, write `~/.claude-handoffs/cdd/<branch>.md` with this structure:

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
mkdir -p ~/.claude-handoffs/cdd
```

## 8. Print the next command

After writing, print exactly:

```
Handoff written: ~/.claude-handoffs/cdd/<branch>.md
Next: cdd-worktree <branch>

If `cdd-worktree` reports "command not found", the worktree helper isn't sourced. Add this to ~/.bashrc (or ~/.zshrc) and open a new shell:
  [[ -f "$HOME/Code/cdd/tools/cdd-worktree.sh" ]] && source "$HOME/Code/cdd/tools/cdd-worktree.sh"
```

The user will close this session, run `cdd-worktree <branch>` from the main worktree, and a fresh Claude session will open in the new worktree with the first prompt already submitted.
