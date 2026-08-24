# 0005: One length cap for every roadmap item, with a named home for the detail

**Status:** Accepted

## Context

The roadmap is a plan, a progress log, and a context document every CDD session loads (process
doc §2.2). That triple role makes item length a running cost: an over-long completed item is paid
for on every future session, in exchange for detail the PR and the docs already carry.

The bar had been stated for a long time — "a completed item reads like a PR title or barely more",
in the roadmap's own "Annotation conventions" section — and it did not hold: **46 of 94 items
exceeded 200 characters**, averaging 343, with the worst at 3,872. Two causes. The section shipped
its own escape clause ("Items above this line predating the convention are over-long; they are left
as-is"), and a convention that exempts every existing violation gives each new session a reason to
add one more. And it addressed only *completed* items, so a pending task whose scope did not fit on
a line had nowhere to go but the line.

## Decision

**One cap, mechanically enforced, applying to pending and completed items alike; detail that does
not fit is routed to a named artifact rather than trimmed away.**

- The cap is **200 characters of the whole line**, checkbox prefix included. Raw and whole-line,
  because a cap is only useful if a session can apply it without running the checker.
- Enforced by `scripts/roadmap-length-check.sh` (the `roadmap-length` gate) over **every roadmap the
  repo ships**: its own, `template/`'s skeleton, and `demo/seed/`'s filled-in one. A file stating
  this convention has to obey it, and the template's items are inherited verbatim by every
  bootstrapped project. Detail trimmed out of an instructional item goes to the phase intro, which
  is prose and uncapped.
- The escape clause is deleted; every pre-existing item was rewritten rather than grandfathered.
- Detail that no longer fits goes to a **GitHub issue** cited by number on the line, or to the
  **handoff file** for detail only the implementation session needs. Issues were already the inbox
  feeding the roadmap (process doc §3.1), so this introduces nothing new.
- **An ADR is not a detail store.** Routing pending scope into an ADR with `Status: Proposed` was
  rejected: nothing defines what `Proposed` means or who flips it, no ADR has used it, and §2.3
  frames an ADR as the record of a decision *taken*.
- **A separate backlog document was rejected.** New artifact, new update rule, and a standing sync
  obligation between two lists of pending work — the failure mode the roadmap exists to prevent.
  Precedent: `friction-log.md` was a side-list of this shape and was retired into the roadmap.

## Consequences

- The roadmap becomes cheap to load and skimmable as an arc: 37 KB down to 21 KB, no item lost.
- The cap disciplines links. A full relative ADR link can eat a third of the budget, so items cite
  an ADR by number (`ADR 0002`) and `doc/architecture/index.md` carries the links.
- Some provenance genuinely leaves the roadmap. That trade is only safe because the same change
  updates the PR, the ADRs, and the architecture docs; the salvage pass is a precondition for
  cutting a line, not politeness.
- The rule now lives in three places that must agree — process doc §2.2 rule 3, the roadmap's
  conventions section, and `template/doc/knowledge_base/roadmap.md` — with nothing tying them
  together. A future divergence is a candidate for a seam check.
- The gate carries an inline self-check rather than a sibling mutation harness: a length rule has a
  narrow silent-failure surface (the item pattern stops matching, or character counting regresses to
  bytes), and three fixtures pin both.
