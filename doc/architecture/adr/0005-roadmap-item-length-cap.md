# 0005: One length cap for every roadmap item, with a named home for the detail

**Status:** Accepted

## Context

The roadmap is simultaneously a plan, a progress log, and a context document that every CDD session
loads (process doc §2.2). That triple role is what makes it the workflow's anchor, and it is also
what makes item length a running cost: an over-long completed item is paid for on every future
session, forever, in exchange for detail the PR description and the docs already carry.

The bar had been stated for a long time — "a completed item reads like a PR title or barely more",
with an example, in the roadmap's own "Annotation conventions" section. It did not hold. By the time
this was measured, **46 of 94 items exceeded 200 characters**, averaging 343, with the worst at
3,872 — a single checkbox line carrying a full implementation narrative.

Two things caused that, and only one of them is the obvious one.

The obvious one: the conventions section shipped its own escape clause. Its closing sentence read
"Items above this line predating the convention are over-long; they are left as-is rather than
rewritten, and are not a precedent." A convention that exempts every existing violation gives each
new session a defensible reason to add one more, and "not a precedent" is not a mechanism.

The less obvious one: the convention only ever addressed *completed* items — it was titled "Inline
annotations stay terse". Pending items had no bar at all, so a task whose scope did not fit on a
line had nowhere to go but the line, and the roadmap absorbed scoping detail that belonged
elsewhere. Every over-long item measured was in fact a completed one, but only because the pending
list happened to be short at the time; the loophole was open either way.

## Decision

**One cap, mechanically enforced, applying to pending and completed items alike; detail that does
not fit is routed to a named artifact rather than trimmed away.**

- The cap is **200 characters of the whole line**, checkbox prefix included. Raw and whole-line was
  chosen over rendered width, backtick-excluding, or link-target-collapsing measures because a cap
  is only useful if a session can apply it without running the checker.
- It is enforced by `scripts/roadmap-length-check.sh`, registered as the `roadmap-length` gate in
  `scripts/ci.sh`, and it covers **every roadmap the repo ships**: its own, the skeleton in
  `template/`, and the filled-in one in `demo/seed/`. The rule is that a file stating this
  convention has to obey it. The template's pre-filled items are inherited verbatim by every
  bootstrapped project, so bloat there ships the problem downstream and starts each new project from
  items violating the convention it just read; the demo seed is the worked example a reader copies
  from, which is the same argument. Detail trimmed out of an instructional item goes to the phase
  intro, which is prose and uncapped.
- The escape clause is deleted. Every pre-existing item was rewritten to the cap rather than
  grandfathered.
- Detail that no longer fits goes to one of two places: a **GitHub issue** referenced by number on
  the roadmap line, or the **handoff file** for detail only the implementation session needs. Issues
  were already framed as the inbox feeding the roadmap (process doc §3.1) and `/cdd-next-step #NN`
  already consumes one, so this makes them the detail store too rather than introducing anything.
- **An ADR is not a detail store.** Routing pending scope into an ADR with `Status: Proposed` was
  drafted and rejected. `Proposed` appears in exactly one place in this workflow — the status line of
  `adr/0000-template.md` — and nothing defines what it means, when it applies, or who flips it to
  `Accepted`; no ADR has ever used it. Leaning a routing rule on an undefined status would have made
  the rule depend on a convention that does not exist, and it cuts against §2.3's framing of an ADR
  as the record of a decision *taken*. So: where a task hinges on a design decision, the ADR is
  written when the decision is taken, and the issue carries the thinking until then.
- Before any line was cut, the rationale carried only by an over-long item was relocated. Most was
  already documented elsewhere; two items were not, and their reasoning moved into
  `doc/architecture/shell-helpers.md` and `doc/architecture/overview.md` first.

**A separate backlog or notes document was considered and rejected.** It is the obvious answer —
"the roadmap stays short, the backlog holds the detail" — and it is wrong here for three reasons. It
is a new artifact, with a new owner and a new update rule to specify. It creates a standing sync
obligation between two lists of pending work, which is exactly the failure mode the roadmap exists
to prevent ("if it drifts from reality, the workflow loses its anchor"). And there is direct
precedent: `doc/knowledge_base/friction-log.md` was a standing side-list of exactly this shape and
was retired, its content folded into the roadmap and the template. GitHub issues already provide the
durable, addressable, per-item store a backlog doc would provide, without being a file anyone has to
reconcile.

## Consequences

- The roadmap becomes cheap to load and skimmable as an arc, which is what a context document owes
  its reader. The recompaction took the file from 37 KB to 21 KB — a 44% cut with no item lost.
- The cap disciplines links: a full relative ADR link can eat a third of the budget, so the
  convention is now to cite an ADR by number (`ADR 0002`) and let `doc/architecture/index.md` carry
  the links. Slightly less convenient to click, materially cheaper to read.
- Some provenance genuinely leaves the roadmap. That is the trade being made, and it is only safe
  because the same change updates the PR, the ADRs, and the architecture docs — so the salvage pass
  is not optional politeness, it is the precondition for cutting a line.
- The trailing clause is introduced by a **semicolon**, not an em dash. Nothing mechanical depends on
  the choice; it is a house-style preference, and the gate measures length only.
- All three conventions sections now say the same thing, and `demo/seed/`'s is a byte-for-byte copy
  of the template's. It had drifted — missing the ADR clause and the PR-title bar — which is the
  ordinary fate of a rule stated in three places with nothing tying them together. Worth a seam
  check if it drifts again; the gate only pins item length, not the prose stating the rule.
- The rule now lives in three places that must agree: process doc §2.2 rule 3, the roadmap's own
  conventions section, and `template/doc/knowledge_base/roadmap.md`. No mechanical check ties them
  together — `command-drift-check.sh` only covers `.claude/commands/` — so that consistency is
  convention-enforced, and a future divergence is a candidate for a seam check.
- The gate carries an inline self-check rather than a sibling `*-assert.sh` mutation harness. A
  length rule has a narrow silent-failure surface (the item pattern stops matching, or character
  counting regresses to byte counting), and three fixtures pin both; a full sandbox-and-mutate harness
  would have been a second script and an eighteenth gate for no additional coverage.
- Counting characters portably turned out to be the one real subtlety: `awk`'s `length()` is
  byte-based in mawk and character-based in gawk under a UTF-8 locale, so the naive check would have
  given different verdicts on different contributors' machines, and the items are full of
  multibyte punctuation (`§` in process-doc references, `→` and `≠` in the Phase 10 entries) that
  would silently have cost 3 of the 200 on one of them. The gate runs under `LC_ALL=C` and strips
  UTF-8 continuation bytes before measuring.
