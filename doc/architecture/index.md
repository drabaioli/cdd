# CDD Repository Architecture

How this repo is structured. This index is a pointer list — the content lives in the per-topic documents.

## Documents

- [Overview](overview.md) — the two-layer model (process doc + template), top-level layout, layer relationships, open structural questions
- [Bootstrap & retrofit](bootstrap-and-retrofit.md) — the single substitution pipeline: bootstrap script, stage mode, overlay mode, `/cdd-bootstrap`, `/cdd-retrofit`, the baseline marker
- [The demo layer](demo.md) — the third artifact: filled-in seed + create/teardown automation
- `adr/` — architecture decision records (`adr/0000-template.md` for the format)
  - [`0001-name-and-guard-founding-objectives.md`](adr/0001-name-and-guard-founding-objectives.md) — naming and guarding CDD's two under-guarded founding objectives (engineering practices, self-improvement)
