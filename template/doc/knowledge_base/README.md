# <PROJECT_NAME> Knowledge Base

Project metadata and history. Mostly append-only.

## Contents

- `project-overview.md`: the project charter — what it is, why it exists, what it does and explicitly does not do, its constraints and architecture intentions. Kept current (see Conventions).
- `roadmap.md`: implementation roadmap (the central workflow artifact).
- `<coding-standard>.md`: language-specific style and convention rules.
- `<decision-record>.md`: design and tooling decisions (why we chose X over Y).
- `<investigation-notes>.md`: deep dives done in the course of the project that don't fit into architecture or feature docs.

## Conventions

- **The project overview is kept current.** It is the exception to the append-only rule: `project-overview.md` describes what the project is *today*, so update it as scope and constraints evolve rather than appending. (A separate founding document, if you keep one, follows the append-only rule.)
- **Decision records are append-only.** When a decision is superseded, add a new record describing the new choice and reference the old one. Do not edit historical records to rewrite the reasoning. This preserves the trail.
- **The coding standard evolves with the project.** When `/pre-pr` flags a new convention established during a change, update the standard in the same PR.
- **Investigation notes are durable.** They document research that informed a decision. Even if the conclusion later changes, the notes themselves should remain.

## What does not belong here

- **Current system structure**: goes in `doc/architecture/`.
- **Current system capabilities**: goes in `doc/features/`.
