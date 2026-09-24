# Task: Docs capability contract + Confluence reference adapter

## Branch
docs_capability_confluence_adapter

## Roadmap reference
- [ ] Docs capability: verbs, shapes, and context-cost caps for read-only backend docs, callable from every session type.
- [ ] Confluence docs adapter, validated on a real project.

## Requirements
1. `doc/architecture/capability-adapters.md` pins a read-only docs contract: `describe`, `doc-search`, `doc-read`, `doc-stat`, their JSON shapes, exit codes, and a size cap that flags truncated output.
2. `tools/adapters/docs/confluence.sh` implements that contract with its own credential settings, falling back to the Jira adapter's (`JIRA_EMAIL`, `JIRA_API_TOKEN`) when unset.
3. `doc-read` on the test page (see Notes) succeeds live, end to end.
4. The offline adapter-conformance gate covers the docs adapter, and `./scripts/ci.sh` passes.
5. The four session commands (`/cdd-next-step`, `/cdd-implement`, `/cdd-pre-pr`, `/cdd-process-pr`), repo and template copies, use the docs adapter only when one is installed and the task gives a reason; with none installed they make no extra call and print nothing.
6. Process doc and template stay consistent; roadmap items "Docs capability…" and "Confluence docs adapter…" are merged into one line and ticked; no `doc-sync` item is added.

## Implementation prompt
Build the docs capability (Phase 14) and its first backend in one task. The design sketch is in GitHub issue #86, section "Documentation backends: read-first-class, repo stays the source" — read that section only.

Decisions taken during scoping:
- The Confluence adapter is the docs capability's reference implementation (the role the GitHub adapter plays for the tracker). No stand-in / local-folder adapter.
- Read-only. Verbs: `describe`, `doc-search <query>` (excerpts, not whole pages), `doc-read <ref>` (optional section anchor, size-capped, says when it truncates), `doc-stat <ref>` (version / updated_at only).
- `doc-sync` is dropped entirely — not built, not deferred to the roadmap. `doc-publish` (repo → backend) is out of scope.
- Credentials: Jira and Confluence may need separate credential sets in practice (they can live on different Atlassian sites), so the Confluence adapter has its own settings (site URL, email, token). When the Confluence ones are unset and the Jira ones are set, fall back to the Jira ones so a shared Atlassian account needs configuring once. Follow the Jira adapter's shape (curl + jq, env-configured, not self-installing; `tools/adapters/tracker/jira.sh`).
- Session wiring must be near-zero cost for projects with no external doc store: each of the four commands gains only a short conditional paragraph; the existence check (`[ -x .cdd/docs ]` / `~/.cdd/adapters/docs`) should ride on a shell call the session already makes where possible; with no adapter, no call, no output, no "not installed" line. Detail (shapes, caps, exit codes) lives in `capability-adapters.md`, not in the prompts.
- When an adapter is installed it is still not called every session. Triggers, strongest first: (1) an explicit page reference in the handoff / issue / review comment / user message, recognized via a pattern the adapter reports in `describe`; (2) a project-authored one-liner in its CLAUDE.md saying what lives in the doc store (e.g. "platform integration specs live in Confluence space TT"), matched against the task; (3) session judgment that the task depends on an external system the repo does not document. No trigger → no lookup.

## Notes
Live test page: https://avy-wiki.atlassian.net/wiki/spaces/TT/pages/2808119297/Avy+GCS+software+setup+clients+instructions
For the live test, use the same Atlassian credentials the user used for the Jira tracker adapter's live validation — ask the user to provide/export them at test time; never write them to the repo.

Deferred to /cdd-plan:
- Content format returned by `doc-read` (Confluence storage/XHTML vs Markdown vs plain text), given a curl + jq-only adapter.
- How `describe` advertises the reference shape (URL and/or page-ID pattern), mirroring the tracker's `ref_pattern`.
- Concrete size-cap numbers for search excerpts and reads, and the truncation signal.
- Credential variable naming and exact fallback rule (site URL especially, since the sites may differ).
- Where the existence check piggybacks in each of the four commands.
- Whether the conformance gate generalizes across capabilities or gains a docs-specific branch.
- Whether this warrants an ADR or fits under ADR 0007.

Roadmap edit for /cdd-implement: merge the two referenced Phase 14 items into one line (≤200 chars) and tick it.
