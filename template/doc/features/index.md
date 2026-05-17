# <PROJECT_NAME> Features

This directory describes **what the system does**, from a capability / user perspective. One doc per significant feature. Updated continuously as features are added or changed.

Audience: humans (users, future-you, future-collaborators) and Claude Code sessions that need to understand the contract a feature provides.

## Index

- `<add features as they land>`

## What belongs here

- For each feature: what it does, who consumes it, the surface (CLI, API, UI, protocol), the inputs and outputs, the failure modes the user can observe.
- Behavioural contracts the feature promises (e.g. timing guarantees, ordering, idempotence).

## What does not belong here

- **Internal structure**: that goes in `doc/architecture/`.
- **Implementation history or rationale**: that goes in `doc/knowledge_base/`.

## Maintenance

When a change in code alters user-visible behaviour, update or add the relevant feature doc in the same PR. New features get a new file; modifications to existing features get edits to the existing file. `/pre-pr` will surface discrepancies.
