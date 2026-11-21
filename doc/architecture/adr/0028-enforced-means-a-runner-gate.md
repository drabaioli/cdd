# 0028: Enforced means a runner gate

**Status:** Accepted; amended by [0029](0029-ship-the-practices-checker.md)

## Context

The engineering-practices contract (process doc §2.12) marked each practice Enforced or Expected,
with no mechanical meaning for Enforced, so nothing kept the claim honest (issue #89). A survey of
the downstream CDD projects found it drifting:

- Every project, this repo included, marked Documentation Enforced, though `/cdd-pre-pr`'s
  reconciliation holds it, not a gate.
- One project improvised a "Partially enforced" heading.
- One filed a practice "no linter can judge" as Expected — a promise that can never be kept.
- One listed hardware-in-the-loop tests under an Enforced heading while noting by hand that no
  workflow runs them.

## Decision

1. **Three markers.** *Enforced*: named gate(s) of the project's check runner hold it on every
   change. *Upheld*: a named mechanism other than a runner gate holds it on every change — a CDD
   command's step, a Claude Code hook or deny rule, the code host's branch protection — the
   soft-mandatory analogue of Sentinel's enforcement levels: held, but bypassable. *Expected*:
   unchanged.
2. **A `Gates:` line.** An Enforced section carries a visible line, `- Gates: \`a\`, \`b\``,
   naming its gates by the name the runner registers them under; only an Enforced section carries
   one. Headings keep the `## Practice — Marker` form. Visible labelled fields follow Sphinx-Needs'
   link fields, and an unknown name is a hard failure, as an unresolved reference is in Doorstop.
3. **Split markers, not "partial".** A section whose practices differ splits its marker into parts
   (`Enforced (lint); Expected (format)`), its one `Gates:` line backing the Enforced part(s). No
   primary framework defines a partial status (SLSA has levels, not partial ones), and "partial"
   hides which part is held.
4. **Hooks are Upheld.** A Claude Code hook or deny rule runs only inside a Claude session, on the
   machines that carry it, never in CI or on a plain commit.
5. **This repo is checked.** The `practices` gate fails when an Enforced section names no gate, a
   `Gates:` line names a gate `./scripts/ci.sh list` does not register, or a non-Enforced section
   carries a `Gates:` line. Mechanics: `doc/architecture/overview.md`.

## Rejected alternatives

- HTML-comment tags (`<!-- gates: … -->`): hidden from the human reader, and OpenFastTrace shows
  the failure mode — a malformed tag is silently ignored.
- YAML front matter: one block per file, while the contract has several sections each needing its
  own gates.
- Gate names in the heading: the tested-behaviour heading would carry some 25 names.
- A "partially enforced" marker: see decision 3.
- Counting a hook as Enforced: see decision 4.
- A downstream checker now: of eight downstream projects only two have a runner with a `list`
  mode, which is required only when CI fans out. It needs `list` made mandatory first — done,
  and the checker shipped, by ADR 0029.
- The reverse check (every registered gate named by some row): #89 does not ask for it, and it
  would force guard and meta gates into rows for no reader benefit.
- Per-bullet markers instead of heading markers: they break the seam check's heading parse,
  `/cdd-bootstrap`'s discovery and every downstream contract's shape, for no gain over split
  markers.

## Consequences

- This repo's contract cannot claim Enforced without a registered gate behind it.
- Downstream contracts were honest by convention, plus `/cdd-retrofit` proposing a re-marking
  against the project's runner, until ADR 0029 shipped the checker downstream.
- The contract stays project-owned: the new preamble reaches existing projects through retrofit's
  three-way merge, and re-marking rows is proposed per file, never batched.
- An Upheld practice is weaker than an Enforced one by design; moving it to Enforced means landing
  a gate.
