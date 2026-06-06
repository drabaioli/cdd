# The demo

A `demo/` subsystem that instantiates a concrete project ("Markdown Renderer") from a filled-in seed, for two uses from one source:

- A reproducible, **visual demo** of CDD's task cycle: one reviewable PR, two parallel branches that hit a guaranteed merge conflict, and a `/merge-main` that resolves the conflict *and* delivers a cross-branch dependency.
- The **dogfooding greenfield** for roadmap Phase 2.

Contents:

- `demo/seed/`: filled-in `CLAUDE.md`, a 6-phase roadmap, and architecture/features docs for the Markdown Renderer (CDD scaffolding only — the app itself is built by running CDD cycles on a created instance).
- `demo/setup.sh`: create an instance — wraps `bootstrap-cdd-project.sh --overlay demo/seed`, then always creates and pushes a GitHub repo. Auto-numbers disposable demo instances (`mdr_demo_NN`) checking both local dirs and existing repos; `mdr` is the kept dogfood instance.
- `demo/teardown.sh`: reclaim an instance — remove the local directory and delete its GitHub repo (needs the `gh` `delete_repo` scope).

Audience: anyone demoing CDD to others, and the maintainer dogfooding CDD on a real project. See `demo/README.md` for the create/teardown commands and the phases 1–3 demo script.
