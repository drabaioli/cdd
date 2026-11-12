# Task: Turn a multi-PR issue into a roadmap phase whose tasks point back to it

## Branch
multi_pr_issue_roadmap_phase

## Roadmap reference
None — off-roadmap, sourced from issue #146.

## Requirements
1. In issue-driven mode, the process doc (§3.1) and `/cdd-next-step` say that the session judges whether the issue is multi-PR as a one-line recommendation naming its signal (the issue lays out several separately shippable steps, or asks for a phase), and the human decides.
2. For a multi-PR issue, the session proposes a roadmap phase — one task line per PR, each ending with the issue ref and within the 200-character cap — and records it as roadmap edits in the handoff; it still never edits the roadmap file.
3. The first task adds the phase; the human chooses at handoff whether it also does the phase's first line.
4. When the issue asks for a convergence step first, that step is the phase's first line, and the implementation lines are added or confirmed only after the human approves the final shape.
5. The process doc states the roles: the tracker is the inbox, the roadmap is the plan. A multi-PR issue is closed by the PR that puts its phase on the roadmap; the phase's later tasks are picked roadmap-driven and record no issue ref on their state record.
6. In roadmap-driven mode, when the chosen task's line references an issue, the session reads it read-only, whether open or closed.
7. This repo's and the template's `/cdd-next-step` carry the same behaviour, and `./scripts/ci.sh` passes (the `drift` gate included).

## Implementation prompt
Sourced from GitHub issue #146 ("/cdd-next-step: turn a multi-PR issue into a roadmap phase whose tasks point back to it", https://github.com/drabaioli/cdd/issues/146).

Teach `/cdd-next-step` to handle an issue that spans several PRs (an epic). The issue body is the spec — read it with `.cdd/tracker issue-read 146`. Its five proposed behaviours and its two "Decided" points stand, refined by what the handoff session settled:

- **The framing: tracker = inbox, roadmap = plan.** An issue is either done straight off the tracker (one PR, which closes it) or promoted onto the roadmap. Promotion is what closes a multi-PR issue: "closed" means "planned", not "done". From then on the roadmap owns order and progress, and the issue is reference material read through the ref on each line. This was chosen over keeping the issue open until its last line is ticked, because an open epic would keep coming back as an entry point (`/cdd-next-step #NN`, the `issues` browse list) when the next step should come from plain `/cdd-next-step`. State the framing in the process doc, briefly.
- **Multi-PR judgement** (the issue's open question) works like the lane: state the signal in one line, recommend, the human decides. The signal is what the issue shows up front: it lays out several separately shippable steps whose order is worth planning, or asks for a phase. An issue merely likely to take 2–3 PRs is not an epic.
- **Out of scope: an issue that grows mid-implementation** (a single task whose PR turns out to do only part of it). The human leaves the issue open with a progress comment, and a later `/cdd-next-step #NN` resumes it from the issue's comments. That is not an epic and gets no roadmap phase. Supporting it in the tooling is a separate follow-up: today the state record makes `/cdd-pre-pr` emit a close line and `cdd-worktree-done`/gc close the issue after merge regardless.
- **The first task adds the phase**, and the human chooses whether it also does the phase's first line. A task that only adds the phase is a small-change-lane candidate under the existing heuristic ("adding a roadmap phase").
- **Later tasks record no issue ref** on their state record: the issue is already closed, and a close line on a PR that closes nothing is noise.
- **Convergence first:** the convergence task's own implementing session is where the implementation lines are added or confirmed, after the human approves the final shape.

Scope: process doc §3.1 (issue-driven and roadmap-driven bullets), then `/cdd-next-step` in this repo and in `template/` — process-first. No change to `/cdd-pre-pr`, `cdd-state` or the tracker adapters is expected; if the plan finds one necessary, say so at plan approval.

Issue #145 is the first issue that will use this behaviour. Do not scope or start #145 here.

## Research
none — the repo answers everything.

## Notes
- Roadmap-belonging verdict: no roadmap item for this task (issue-driven default; #146 tracks it).
- Deferred to /cdd-plan:
  - Does the decision need its own ADR (it names the tracker/roadmap roles and when a promoted issue closes), or is it the process-doc rule plus a pointer to an existing one (ADR 0005, ADR 0008)? Apply ADR 0018 either way.
  - How a roadmap line's issue ref is recognised for any tracker: `ref_pattern` is anchored (`^#?[0-9]+$` for GitHub) and other trackers' refs differ (e.g. Jira keys). And what roadmap-driven mode does when no tracker is installed or the read fails — presumably one line and carry on, never a stop, since the issue is context, not the invocation's point.
  - What the first task's handoff `## Roadmap reference` holds, in both variants (phase only; phase plus first line), since its lines are not on the roadmap yet.
  - Confirm the existing overlap check routes `/cdd-next-step #NN` on an already-promoted (closed, cited) issue to the phase's next line; tighten the wording if it does not.
  - Whether §2.2 rule 3 or the roadmap's "Annotation conventions" (here and in `template/`) need a matching line.
