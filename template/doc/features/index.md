# <PROJECT_NAME> Features

Feature documentation: **what the system does**, from a capability / user perspective. This index is a pointer list — one doc per significant feature, the content lives in the feature docs. Read this index, then load only the documents relevant to the task. Updated continuously as features are added or changed.

## Documents

- <add features as they land — one link per doc, with a one-line summary>

## What belongs here

- For each feature: what it does, who consumes it, the surface (CLI, API, UI, protocol), the inputs and outputs, the failure modes the user can observe.
- Behavioural contracts the feature promises (e.g. timing guarantees, ordering, idempotence).

What does **not**: internal structure (`doc/architecture/`), implementation history or rationale (`doc/knowledge_base/`).

## Maintenance

When a change in code alters user-visible behaviour, update or add the relevant feature doc — and this index, if a doc was added or removed — in the same PR. New features get a new file; modifications to existing features get edits to the existing file. `/pre-pr` will surface discrepancies.
