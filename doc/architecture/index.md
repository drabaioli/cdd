# CDD Repository Architecture

How this repo is structured. This index is a pointer list — the content lives in the per-topic documents.

## Documents

- [Overview](overview.md) — the two-layer model (process doc + template), top-level layout, layer relationships, the consistency guards and the check runner (`scripts/ci.sh`), open structural questions
- [Bootstrap & retrofit](bootstrap-and-retrofit.md) — the single substitution pipeline: bootstrap script, stage mode, overlay mode, `/cdd-bootstrap`, `/cdd-retrofit`, the baseline marker
- [Shell helpers](shell-helpers.md) — how `cdd-worktree` and `cdd-state` are installed and wired: install model, PATH shims, runtime derivation, atomic state writes, the per-repo marker, resume discovery
- [The demo layer](demo.md) — the third artifact: filled-in seed + create/teardown automation
- `adr/` — architecture decision records (`adr/0000-template.md` for the format)
  - [`0001-name-and-guard-founding-objectives.md`](adr/0001-name-and-guard-founding-objectives.md) — naming and guarding CDD's two under-guarded founding objectives (engineering practices, self-improvement)
  - [`0002-scope-prompt-seam-checks-deterministic-only.md`](adr/0002-scope-prompt-seam-checks-deterministic-only.md) — scoping prompt "CI" to deterministic seam checks; why LLM-as-judge evals (and a generalized prompt-lint framework) are not planned work
  - [`0003-standing-self-improvement-channel.md`](adr/0003-standing-self-improvement-channel.md) — the recurring channel behind commitment 5: a conditional `/cdd-pre-pr` step plus a `/cdd-process-pr` triage route, their trigger design, and why an upstream candidate becomes a GitHub issue rather than a local roadmap item or a standing log
  - [`0004-conditional-merge-base-approval.md`](adr/0004-conditional-merge-base-approval.md) — making human checkpoint 4 conditional: the four mechanical criteria for an automatic `/cdd-merge-base`, why no "mechanical conflict" auto-resolve tier exists, and the residual semantic-break risk
  - [`0005-roadmap-item-length-cap.md`](adr/0005-roadmap-item-length-cap.md) — one 200-character cap for every roadmap item, pending and completed alike, enforced by the `roadmap-length` gate; where detail goes instead (a GitHub issue or the handoff), and why neither a separate backlog document nor a `Status: Proposed` ADR is that place
