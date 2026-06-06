# <PROJECT_NAME> Architecture

System design documents: **what the system is, structurally**. This index is a pointer list — the content lives in the per-topic documents. Read this index, then load only the documents relevant to the task. Updated continuously as the system changes; the `/pre-pr` command reconciles it against each change.

## Documents

- `overview.md` — high-level system shape, main modules, data flow (created by the Phase 1 bootstrap survey)
- <add documents as the architecture takes shape — one link per doc, with a one-line summary>

## What belongs here

- Module boundaries and responsibilities.
- Data flow and key interfaces between modules.
- Threading / concurrency model.
- External boundaries (network, hardware, filesystem, other processes).
- Cross-cutting conventions that have structural implications (e.g. error-handling strategy, message bus topics, units and coordinate frames).

What does **not**: user-visible behaviour (`doc/features/`), decision rationale (`doc/knowledge_base/` decision records), coding style (`doc/knowledge_base/` coding standard).

## Maintenance

When a change in code alters anything described in these documents, update the relevant doc — and this index, if a doc was added or removed — in the same PR. `/pre-pr` will surface discrepancies, but the implementation session should keep this in mind during the change itself.
