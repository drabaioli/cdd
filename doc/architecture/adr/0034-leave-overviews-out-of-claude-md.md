# 0034: Leave overviews out of `CLAUDE.md`

**Status:** Accepted

## Context

The template's `CLAUDE.md` shipped a `## Module layout` table and a `## Architecture` paragraph,
although process doc §2.1 never listed either among its contents. Issue #153 asked whether they
earn their cost:

- "repository overviews, although popular and recommended by model providers, are not helpful",
  and "context files are not effective at providing a repository overview" (Gloaguen et al.,
  arXiv 2602.11988 v3, September 2026; ADR 0030 cites it for the general cost). The result spans
  developer-written files: "Across the 12 developer-provided context files in CTXbench, 8 include
  a dedicated codebase overview."
- Developer-provided files "improve agent performance by 2.4% on average (p=21%)", not
  significant, while raising cost by up to 19%. They "should only include instructions required
  for coding agents that are not already present in the README".
- The limit: generated files help "where context files are the only source of documentation
  available". Every CDD project has `doc/architecture/`.
- Anthropic's best practices list "Describe your architecture and file layout in `CLAUDE.md`"
  under what to stop doing ("Claude reads the repo itself"), keep "a directory that looks unused
  but isn't", and test each line: "Could it find this by reading the code? … Would it actually go
  and look? If both are yes, leave it out." `/doctor` cuts "directory layouts, dependency lists,
  and architecture overviews" from a checked-in `CLAUDE.md`.

## Decision

1. `CLAUDE.md` carries no module layout or architecture overview. The Key references row to
   `doc/architecture/index.md` is the pointer.
2. Layout and shape live in `doc/architecture/overview.md`.
3. A structural fact the code makes misleading (a directory that looks unused but isn't) goes in
   Critical constraints.
4. This applies to the template, the demo seed and this repo.

## Rejected alternatives

- A one-line `## Architecture` pointer section: it duplicates the Key references row.
- Cut the layout table, keep the architecture paragraph: the finding covers overviews generally,
  and the guidance names "architecture and file layout" together.
- Keep both for human readers: humans reach the same content one hop away; the agent pays every
  session.
- `/cdd-retrofit` offering to cut the sections on upgrade: they are project-owned, and its
  existing `no-op` rule covers the template change.
- Keeping them on the memory page's "Use for … project architecture" row: the same page's
  `/doctor` text and the best-practices page say to cut them.

## Consequences

- About 10–35 fewer lines of context per session.
- Humans take one hop to `doc/architecture/overview.md`.
- Downstream projects keep their sections until they choose otherwise (retrofit reports `no-op`).
- `/cdd-pre-pr` keeps the layout current through its architecture-docs bullet.
- No checkpoint changes.
