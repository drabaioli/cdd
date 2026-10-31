# <PROJECT_NAME> Documentation

Project documentation map. Each directory keeps an `index.md` pointer list: read the index, then load only the documents you need.

## Structure

- [`knowledge_base/project-overview.md`](knowledge_base/project-overview.md) — the project charter: what it is, why it exists, what it does and does not do. **Read this first.**
- [`architecture/`](architecture/index.md) — system design documents: what the system is, structurally
- [`features/`](features/index.md) — feature documentation: what the system does, per capability
- [`knowledge_base/`](knowledge_base/index.md) — the roadmap, the engineering-practices contract, coding guidelines, investigation notes

## What goes where

- `architecture/` — module boundaries and responsibilities, data flow and key interfaces, threading / concurrency model, external boundaries, cross-cutting conventions with structural implications, and `adr/` — the decision records for every kind of decision (structural, design, tooling; append-only: why a choice was made, alternatives considered). Not user-visible behaviour or coding style.
- `features/` — per feature: what it does, who consumes it, the surface (CLI, API, UI, protocol), inputs and outputs, observable failure modes, behavioural contracts. Not internal structure or implementation history.
- `knowledge_base/` — the roadmap, the project overview, the engineering-practices contract, coding standards, investigation notes. Not decisions: those go in `architecture/adr/`.

When a change in code alters anything described in these documents, update the relevant doc — and its index, if a doc was added or removed — in the same PR. `/cdd-pre-pr` surfaces discrepancies.
