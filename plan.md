# Plan: Turn a multi-PR issue into a roadmap phase whose tasks point back to it

## Summary
- **Approach:** process doc §3.1 first, then the same edit to both copies of `/cdd-next-step`. A new ADR 0021 holds the reasoning, including the rejected option of keeping the issue open until its last line is done. The adapter doc gets one new row saying what `/cdd-next-step` does with a broken tracker when it has no argument.
- **Issue-driven mode:** the session recommends whether the issue is multi-PR, in one line naming the signal, and the human decides. If it is, the session proposes a phase: one line per PR, each ending with the issue ref and within 200 characters. The first task adds the phase, and the human chooses whether it also does line 1. If the issue asks for a convergence step, that step is line 1.
- **Roadmap reference for that first task:** the phase's first line marked "added by this task", or "None — adds the phase" when it only adds the phase.
- **Gap found:** today `/cdd-next-step #NN` on an issue that is already a phase doesn't lead to that phase. Tightened: a closed issue cited on roadmap lines leads to the phase's next unchecked line, picked as a roadmap task, with no issue ref recorded.
- **Roadmap-driven mode:** once a task is chosen, it reads any issue cited on that line, open or closed. A cited issue is a token on the line that matches the tracker's ref pattern, which also covers Jira keys. A missing or broken tracker, or a failed read, gets one line and the session carries on.
- **Behaviour change:** run with no argument, `/cdd-next-step` no longer stops on a broken tracker adapter.
- **Unchanged:** `cdd-state`, `/cdd-pre-pr`, the adapters, process doc §2.2 and the roadmap conventions. The first task records the issue ref as it does today, so its PR closes the issue.
- **Research:** none, as the handoff set. Checked in the repo that all three trackers' `issue-read` returns closed issues.
- **Riskiest part:** keeping the two command copies identical and the command lean.
- **Verification:** `./scripts/ci.sh`, with `drift` and `seams` the gates that matter.
- **Out of scope:** an issue that grows during implementation. The ADR records it as a follow-up; no issue gets filed.

Every handoff requirement is met; none was changed. Approved by the human as printed.

## Approach
Process-first: state the rule in process doc §3.1 with a pointer to a new ADR 0021 that carries the reasoning (ADR 0018: the argument lives once, in the ADR; the process doc gets the rule plus one sentence of why). Then make the identical edit to `.claude/commands/cdd-next-step.md` and `template/.claude/commands/cdd-next-step.md`. The two files are byte-identical today except `~/.cdd/handoffs/cdd` ↔ `~/.cdd/handoffs/<PROJECT_DIR>` (verified: `diff <(sed 's#handoffs/cdd#handoffs/<PROJECT_DIR>#g' .claude/commands/cdd-next-step.md) template/.claude/commands/cdd-next-step.md` is empty) — keep it that way. Commands carry instructions only (CLAUDE.md "Critical constraints"): no argument in the command, nothing said twice in it.

Ordered steps:

1. **ADR 0021** — new `doc/architecture/adr/0021-promote-a-multi-pr-issue-to-a-roadmap-phase.md` (Nygard, format of `doc/architecture/adr/0000-template.md`), and its line in `doc/architecture/index.md` after line 32 (the 0020 entry), in the same style as the entries above it.
2. **Process doc §3.1** — `doc/knowledge_base/claude-driven-development.md:437` (roadmap-driven bullet) and `:439` (issue-driven bullet). Wording below.
3. **`/cdd-next-step`, both copies** — §0 (line 22), §3 (after line 117), §3-intent (lines 123–124 plus a new bullet), §5 (after line 195; the digest list at 197), §7 (line 235). Wording below.
4. **Adapter doc** — `doc/architecture/capability-adapters.md:385` (per-call-site table) and `:72` (verb table Notes column).
5. Run `./scripts/ci.sh`; fix anything it reports; commit.

### Drafted wording (adapt only to fit; keep both command copies identical)

**Process doc §3.1, roadmap-driven bullet (`:437`)** — append after "…converges on one with the human.":

> Once a task is chosen, an issue its line cites is read for context — read-only, open or closed; a missing or broken tracker, or a failed read, costs one line and never stops the session, since the issue is context, not the point of the run.

**Process doc §3.1, issue-driven bullet (`:439`)** — insert after "…an issue matching an existing roadmap item is that item, found by the overlap check.":

> The exception is an issue that spans several PRs. The session judges it multi-PR in a one-line recommendation naming its signal — the issue lays out several separately shippable steps whose order is worth planning, or asks for a phase — and the human decides. A multi-PR issue is promoted to a **roadmap phase**: one task line per PR, each ending with the issue's reference and within the 200-character cap, recorded as roadmap edits in the handoff (§2.2). The first task adds the phase and, if the human chooses, also does its first line; when the issue asks for a convergence step first, that step is the first line, and the implementation lines are added or confirmed only once the human approves the final shape. The roles: the tracker is the inbox and the roadmap is the plan, so the PR that puts the phase on the roadmap closes the issue — closed means planned, not done — and the phase's later tasks are picked roadmap-driven and record no issue reference (ADR 0021). A closed issue that roadmap lines cite leads the overlap check to its phase's next unchecked line.

**Command §0 (line 22)** — replace "**The tracker defines what a reference looks like.** Resolve it down the ladder — project, then machine — and take the first file present:" with:

> **The tracker defines what a reference looks like.** With an empty argument there is nothing to classify: skip to §0a (roadmap-driven mode resolves the tracker in §3, only to read a cited issue). Otherwise resolve it down the ladder — project, then machine — and take the first file present:

(This is what removes the broken-adapter stop from no-argument runs; everything else in §0 stays.)

**Command §3** — new paragraph after line 117 ("…Say explicitly which items overlap in the modules they would touch."):

> Once the user has picked one task, read any issue its line cites, as context for scoping it — read-only, open or closed. Resolve the tracker down §0's ladder with §0's checks, and announce the rung in one line. A cited issue is a token on the line that matches `ref_pattern` once surrounding punctuation is stripped and reads as a reference — not a number in the prose (an ADR, a phase, a count). Read each with `<adapter> issue-read <ref>`. The issue is context, never the point of the run: a broken adapter, no `issue-read` verb, or a failed call gets one line saying the issue was not read and why (the stderr line, for exit 4), and the session carries on without it. With nothing resolved, print §0b's install line only if the line visibly cites an issue, and carry on. The task stays roadmap-driven: no issue ref is recorded (§7).

**Command §3-intent, overlap check bullet (line 123)** — append:

> In issue-driven mode, a closed issue that roadmap lines cite was promoted to a phase: propose the phase's first unchecked line citing it (none left: say the phase is done) and, if the user agrees, proceed as that item, roadmap-driven, recording no issue ref (§7).

**Command §3-intent, roadmap-belonging bullet (line 124)** — "issue-driven → no roadmap item by default, since the issue already tracks the task; add one only if the user asks." becomes "issue-driven → no roadmap item by default, since the issue already tracks the task, unless it is multi-PR (below); add one only if the user asks."

**Command §3-intent, new bullet** after the roadmap-belonging bullet (before "Then continue with §4."):

> - **Multi-PR judgement** (issue-driven): the issue is multi-PR when it shows, up front, several separately shippable steps whose order is worth planning, or asks for a phase — not merely when it looks likely to take two or three PRs. Recommend in one line naming the signal; the user decides. For a multi-PR issue the verdict is a new **roadmap phase**, recorded in Notes (§5):
>   - an intro, one task line per PR — each ending with the issue's ref, in the form `ref_pattern` matches (e.g. `#NN`), and within the 200-character cap — and a milestone; the issue keeps the detail;
>   - this task adds the phase; ask whether it also does the phase's first line (adding the phase alone usually qualifies for the small-change lane, §4b);
>   - if the issue asks for a convergence step first (decisions to confirm, research to finish), that step is the first line, worded so its task adds or confirms the implementation lines once the user approves the final shape; until then propose those lines only as the issue sketches them, or not at all;
>   - the issue's ref is still recorded (§7), so this task's PR closes it; the phase's later tasks are picked roadmap-driven and record none.

**Command §5** — new paragraph after the Notes paragraph (line 195):

> **Multi-PR issue** (§3-intent): Notes carry the whole phase, exact lines included. `## Roadmap reference` holds the phase's first line marked `(added by this task)` when this task also does it, else `None — adds the phase in Notes`.

And in the digest paragraph (line 197), add to the "What usually earns a line" list: "for a multi-PR issue, the proposed phase and whether this task also does its first line,".

**Command §7 (line 235)** — "The third runs **in issue-driven mode only**, with the references…" becomes "The third runs **in issue-driven mode only** — not for a promoted issue routed to its phase (§3-intent) — with the references…".

**`capability-adapters.md:385`** — replace the row `| \`/cdd-next-step\` (tracker) | stops the command |` with two rows (keep the table's column padding):

> | `/cdd-next-step` with an argument (tracker) | stops the command |
> | `/cdd-next-step` with no argument (tracker) | prints the line and scopes the task without the cited issue |

**`capability-adapters.md:72`** — the `issue-read` row's Notes column: "comments inline" → "comments inline; also a roadmap line's cited issue (`/cdd-next-step` §3)".

### ADR 0021 content (the reasoning's one home)

Title: `# 0021: Promote a multi-PR issue to a roadmap phase; promotion closes it`. Status: Accepted.

- **Context:** issue-driven `/cdd-next-step` treated an issue as one task and added no roadmap item (process doc §3.1). For an issue spanning several PRs (an epic, e.g. #145), the first PR closed it through the `/cdd-pre-pr` close line and the remaining work had no place on the roadmap. Epics had been handled by hand; issue #146 asked for it in the command.
- **Decision:**
  - Roles: the tracker is the inbox, the roadmap is the plan. An issue is done straight off the tracker (one PR, which closes it) or promoted onto the roadmap. Promotion is what closes a multi-PR issue: "closed" means planned, not done. From then on the roadmap owns order and progress; the issue is reference material read through the ref on each line.
  - Multi-PR judgement works like the lane (ADR 0006): a one-line recommendation naming the signal — the issue lays out several separately shippable steps whose order is worth planning, or asks for a phase — and the human decides. An issue merely likely to take 2–3 PRs is not an epic.
  - Promotion: one roadmap line per PR, each ending with the issue ref, within the 200-character cap (ADR 0005); the issue keeps the detail. The first task adds the phase; the human chooses whether it also does the first line. Convergence first when the issue asks for it; implementation lines added or confirmed once the human approves the final shape.
  - Later tasks are picked roadmap-driven and record no issue ref: the issue is already closed, and a close line on a PR that closes nothing is noise (closing again would be a harmless no-op — `issue-transition` returns `changed: false`, `doc/architecture/capability-adapters.md:119` — so this is about noise, not safety).
  - Roadmap-driven mode reads a line's cited issue, open or closed, as context. Its failure never stops the session: the read is a read-only consumer, the case ADR 0010 already lets print a line instead of stopping ("a read-only listing … prints the line"). So a no-argument run no longer resolves the tracker up front and no longer stops on a broken adapter.
  - A closed issue cited by roadmap lines routes `/cdd-next-step <ref>` to its phase's next unchecked line, roadmap-driven.
- **Rejected:** keeping the issue open until its last line is ticked — an open epic keeps coming back as an entry point (`/cdd-next-step <ref>`, the `issues` browse list) when the next step should come from plain `/cdd-next-step`, and every task recording its ref would emit a close line that closes it early. Recording the ref on later tasks — harmless but noise (above).
- **Out of scope / consequences:** an issue that grows mid-implementation (a single task whose PR does only part of it) is not an epic and gets no phase: the human leaves it open with a progress comment and a later `/cdd-next-step <ref>` resumes it from the comments. Supporting it in the tooling is a follow-up — today the state record makes `/cdd-pre-pr` emit a close line and `cdd-worktree-done`/`-gc` close the issue after merge regardless. No change to `cdd-state`, `/cdd-pre-pr` or the adapters: the first task is issue-driven and records the ref as before, so its PR closes the issue. A reader seeing a closed issue cited by pending lines must read "closed" as planned. #145 is the first issue to use this.

## File map
- `doc/architecture/adr/0021-promote-a-multi-pr-issue-to-a-roadmap-phase.md` → new. Next free number: `doc/architecture/adr/` ends at `0020-extend-commands-through-project-owned-extensions.md`.
- `doc/architecture/index.md:32` → add the 0021 entry after the 0020 line (one line: link + summary with "why not" clause, like its neighbours).
- `doc/knowledge_base/claude-driven-development.md:437` → roadmap-driven bullet: read a cited issue. `:439` → issue-driven bullet: multi-PR exception, roles, routing of a promoted issue; cites ADR 0021 in the "(ADR 0008)" style already used there.
- `.claude/commands/cdd-next-step.md` and `template/.claude/commands/cdd-next-step.md` (identical edits):
  - `:22` §0 — today's resolution reads as unconditional, so a broken tracker would stop even a no-argument run; scoped to non-empty arguments.
  - `:117` §3 — new paragraph reading the chosen line's cited issue.
  - `:123` §3-intent overlap check — today it only asks "proceed as that item"; it neither looks for the issue's ref on roadmap lines nor picks the phase's next unchecked line nor says the ref is not recorded. Tightened.
  - `:124` roadmap-belonging — "unless it is multi-PR (below)".
  - new §3-intent bullet "Multi-PR judgement".
  - `:195`/`:197` §5 — the Roadmap reference rule for a phase-adding task; digest list item.
  - `:235` §7 — the `issue-refs` call excludes a promoted issue routed to its phase.
  - Headings are unchanged — `scripts/prompt-seam-check.sh:151-156` pins five of them by title.
  - `:153` §4b already lists "adding a roadmap phase" as small-change-eligible — the new bullet points at it, no edit there.
- `doc/architecture/capability-adapters.md:385` → split the `/cdd-next-step` row by argument. `:72` → `issue-read` Notes column. `:375` ("Nothing installed … except where the feature is the whole point … (issue-driven `/cdd-next-step` …)") already covers the roadmap-driven skip — no edit.
- Not touched, deliberately: `tools/cdd-state.sh`, `.claude/commands/cdd-pre-pr.md`, `tools/adapters/tracker/*.sh`, process doc §2.2 rule 3 (`:43`, "scope belongs in a GitHub issue referenced by number on the line" already covers a phase line's ref), the "Annotation conventions" in `doc/knowledge_base/roadmap.md`, `template/doc/knowledge_base/roadmap.md` and `demo/seed/doc/knowledge_base/roadmap.md` (adding a clause there would put the three sites ADR 0005 says must agree out of step with §2.2), process doc §4 checkpoint 2 (the phase is part of the Notes approved there), `CLAUDE.md`/`template/CLAUDE.md` workflow bullet (invocation-level, unchanged), `doc/features/*` (no feature doc describes `/cdd-next-step`'s modes).
- Repo facts relied on:
  - `tools/adapters/tracker/{github,gitlab,jira}.sh` `issue-read` sections apply no state filter, so closed issues read fine.
  - `tools/adapters/tracker/github.sh:69` strips a leading `#` (`REF="${ref#\#}"`), so `#NN` from a roadmap line passes straight to `issue-read`.
  - Jira `ref_pattern` `^[A-Z][A-Z0-9_]+-[0-9]+$` (`doc/architecture/capability-adapters.md:293`); GitHub/GitLab `^#?[0-9]+$` (`:179`, `:321`). The optional `#` means bare numbers also match, hence the "reads as a reference" clause.

## External findings
None — research depth `none` (handoff). The spec is issue #146 (read with `.cdd/tracker issue-read 146`); its "Decided" points are restated in the ADR content above and are verifiable in the repo (`capability-adapters.md:119` for the `changed: false` no-op; the adapters' `issue-read` for closed-issue reads).

## Dead ends
- Recognising a line's ref by "last token only": rejected — older lines may cite an issue mid-line, and a trailing count ("…at 200") would still match `^#?[0-9]+$`. Token-match plus "reads as a reference" is used instead.
- Keying the promoted-issue routing on "cited by any roadmap line": rejected — an open issue cited by one line is that line's scope store (§2.2 rule 3) and must keep today's behaviour (ref recorded, PR closes it). Keyed on closed + cited.
- A seam/gate pinning the new behaviour: rejected — it is a judgement call by the session, not a producer/consumer string pair (ADR 0002, deterministic checks only); existing heading pins still apply.

## Open questions resolved
- **Own ADR, or rule plus a pointer to ADR 0005/0008?** Own ADR (0021). It is a decision with a rejected alternative and an argument (closed = planned; why not keep it open), which neither 0005 (length cap) nor 0008 (branch token) records; ADR 0018 makes the ADR its one home, with the process doc carrying rule + pointer.
- **How a line's ref is recognised for any tracker; no tracker or a failed read in roadmap-driven mode.** A token on the chosen line matching the resolved tracker's `ref_pattern` once surrounding punctuation is stripped, judged to read as a reference (not an ADR/phase number or count). Nothing installed → §0b's install line only if the line visibly cites an issue; broken adapter, missing verb or failed call → one line, carry on. Never a stop: §0 resolution is now skipped for an empty argument.
- **First task's `## Roadmap reference`.** Phase plus first line: that line, verbatim, marked `(added by this task)`. Phase only: `None — adds the phase in Notes`. The phase itself lives in Notes as roadmap edits.
- **Does the overlap check route `/cdd-next-step <ref>` on a promoted issue to the phase's next line?** Not today; tightened (§3-intent overlap bullet + §7 exclusion + process doc sentence).
- **§2.2 rule 3 / "Annotation conventions" need a matching line?** No (see File map, "Not touched").
- No `## Requirements` criterion amended or dropped.

## Doc and roadmap edits
- New ADR 0021 + its `doc/architecture/index.md` entry.
- Process doc §3.1 (both bullets) as drafted.
- `doc/architecture/capability-adapters.md:72` and `:385` as drafted.
- No roadmap edit: off-roadmap task sourced from #146, issue-driven default (no roadmap item); nothing to tick.
- No `CLAUDE.md` edit.

## Verification
- `./scripts/ci.sh` — all gates PASS. The ones this change can trip:
  - `drift` — the two command copies must stay equal after rendering. Spot-check first with `diff <(sed 's#handoffs/cdd#handoffs/<PROJECT_DIR>#g' .claude/commands/cdd-next-step.md) template/.claude/commands/cdd-next-step.md`, which must print nothing.
  - `seams` — headings unchanged; `cdd-state issue-refs` and `cdd-state lane` still present in the command; the small-change heuristic sentence untouched.
  - `roadmap-length` — no roadmap edit, but rerun anyway.
- No new gate or assertion (judgement behaviour; ADR 0002).
- Requirement walk before committing:
  1. §3.1 + §3-intent bullet state the one-line recommendation with its signal.
  2. Phase lines end with the ref, stay within the cap, and are recorded in Notes; the handoff session still never edits the roadmap.
  3. The first task adds the phase; the human chooses about its first line.
  4. Convergence comes first, with the implementation lines added or confirmed after the human approves the final shape.
  5. The roles, the close-by-promoting-PR rule, and "later tasks record no ref" are in §3.1.
  6. The §3 read happens open or closed, read-only.
  7. Both copies match and CI is green.
