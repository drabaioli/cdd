# <PROJECT_NAME> Architecture

This directory describes **what the system is, structurally**. It is updated continuously as the system changes; the `/pre-pr` command reconciles it against each change.

Audience: humans reading to understand the system, and Claude Code sessions rebuilding context for a new task. Optimise for both.

## Index

- `overview.md`: high-level system shape, main modules, data flow.
- `<add docs as the architecture takes shape>`

## What belongs here

- Module boundaries and responsibilities.
- Data flow and key interfaces between modules.
- Threading / concurrency model.
- External boundaries (network, hardware, filesystem, other processes).
- Cross-cutting conventions that have structural implications (e.g. error-handling strategy, message bus topics, units and coordinate frames).

## What does not belong here

- **User-visible behaviour**: that goes in `doc/features/`.
- **Decision rationale**: why a choice was made, alternatives considered, that goes in `doc/knowledge_base/` as a decision record.
- **Coding style and conventions**: that goes in the coding standard under `doc/knowledge_base/`.

## Maintenance

When a change in code alters anything described here, update the relevant doc in the same PR. `/pre-pr` will surface discrepancies, but the implementation session should keep this in mind during the change itself.
