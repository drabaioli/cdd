# 0026: Economy of change

**Status:** Accepted

## Context

Agents tend to write more than a change needs, and every extra line costs review now and upkeep
later (issue #157); PR #156 showed the alternative, a diff doing exactly what its task needed.
Outside evidence points the same way:

- In a 2006 SmartBear study at Cisco, "the rate of defect discovery starts to fall above 300
  lines, with a significant tailing off above 500 LOC" (Tekin Süleyman's 2020 summary; one team's
  codebase).
- GitClear and GitKraken report code duplication "up 81%" and "Move (refactor)" down 70%,
  "indicating declining code reuse", over 2023–2026 — vendor data, as LeadDev reported it (July 2026).
- "over-editing is widespread even among strong models", and "A preservation instruction
  substantially reduces this behavior" (Zhu, Lim and Kan, arXiv 2609.04061, 2026).
- Telling an agent to leave correct code alone helps "substantially", "But prompting is brittle
  across edge cases" (ETH Zurich SRI Lab, "Coding Agents Are 'Fixing' Correct Code", 2026).

Projects get their `CLAUDE.md` from the template, but nothing kept this repo's and the template's
in step: the drift gate compares commands, agents and settings only, and `/cdd-pre-pr` reconciles
this repo's own file. So the `cdd-worktree-gc` bullet (#53) never reached the template, and
`/cdd-bootstrap`'s named list of sections to keep missed "Talking to the human" (#95).

## Decision

1. **The rule** — every change in the least code, prose and structure that still delivers the
   best solution — and what counts as bloat live once, in "Writing changes" in `CLAUDE.md` and the
   template's. It governs how a change is written, not how much a task touches. ADR 0018 keeps an
   argument in one place; this rule covers everything else a change writes.
2. **`/cdd-plan`** drafts, among equally good designs, the one that needs the least code.
3. **`/cdd-pre-pr`'s code review** looks for bloat as that section defines it, under ADR 0025:
   one obvious fix is made, anything else flagged.
4. **`/cdd-implement` and `/cdd-small-change` are unchanged**: `CLAUDE.md` already reaches them.
5. **The template's `CLAUDE.md` carries every part of this repo's that is not CDD-specific**,
   kept equal by this repo's pre-PR extension; `/cdd-bootstrap` keeps every section it does not
   fill as the template ships it.

## Rejected alternatives

- A "be minimal" line in every command: the rule repeated per command, when `CLAUDE.md` already
  reaches every session.
- A gate on diff size: size is not bloat, and the best solution is sometimes large.
- A row in the engineering-practices contract: its rows are practices a gate enforces or a
  roadmap item will; this one is held by review.
- A gate comparing the two `CLAUDE.md` files: their Workflow sections differ on purpose, so
  telling a shared part from a CDD-specific one is a judgement.

## Consequences

- No checkpoint changes.
- A project that has not yet taken the template's new section reviews for bloat without its
  definition until `/cdd-retrofit` upgrades it.
