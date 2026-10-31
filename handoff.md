# Task: Make doc/architecture/adr/ the only home for decision records

## Branch
adr_single_home

## Roadmap reference
None — new ticked Phase 3 (Template refinement) item; see Notes.

## Requirements
1. Across the process doc, the template, the demo seed and the CDD repo's own CLAUDE.md and doc indexes, every pointer to decision records names `doc/architecture/adr/` only; nothing directs a decision record into `doc/knowledge_base/`.
2. The process doc and the template say ADRs are for decisions of every kind (design and tooling included), not only structural ones.
3. `knowledge_base/` descriptions keep the roadmap, overview, engineering practices, coding standards and investigation notes, and say decisions go in ADRs.
4. Existing records in downstream projects are not migrated; this changes where new ones go.

## Notes
- Sourced from GitHub issue #129 (https://github.com/drabaioli/cdd/issues/129). Reference implementation: drabaioli/ego@c0b0472.
- Roadmap edit: add a ticked Phase 3 item for this, referencing #129.
- `template/doc/index.md:14` says `architecture/` holds no "decision rationale". Reword it, since `adr/` lives there.
