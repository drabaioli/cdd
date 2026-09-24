# CDD Repository Architecture

How this repo is structured. This index is a pointer list — the content lives in the per-topic documents.

## Documents

- [Overview](overview.md) — the two-layer model (process doc + template), top-level layout, layer relationships, the consistency guards and the check runner (`scripts/ci.sh`), open structural questions
- [Bootstrap & retrofit](bootstrap-and-retrofit.md) — the single substitution pipeline: bootstrap script, stage mode, overlay mode, `/cdd-bootstrap`, `/cdd-retrofit`, the baseline marker
- [Shell helpers](shell-helpers.md) — how `cdd-worktree` and `cdd-state` are installed and wired: install model, PATH shims, runtime derivation, atomic state writes, the `x-` extension namespace, the per-repo marker, resume discovery
- [The demo layer](demo.md) — the third artifact: filled-in seed + create/teardown automation
- [Capability adapters](capability-adapters.md) — the wire contract for `.cdd/` adapters, pinned for the tracker and docs capabilities: the verbs and their JSON shapes, the exit-code table, `describe` and its `contract` versioning rule, the docs context-cost caps and when a session calls the docs adapter, the GitHub, Jira and Confluence adapters, the announcement rule, and what the offline gates do and do not prove
- `adr/` — architecture decision records (`adr/0000-template.md` for the format)
  - [`0001-name-and-guard-founding-objectives.md`](adr/0001-name-and-guard-founding-objectives.md) — naming and guarding CDD's two under-guarded founding objectives (engineering practices, self-improvement)
  - [`0002-scope-prompt-seam-checks-deterministic-only.md`](adr/0002-scope-prompt-seam-checks-deterministic-only.md) — scoping prompt "CI" to deterministic seam checks; why LLM-as-judge evals (and a generalized prompt-lint framework) are not planned work
  - [`0003-standing-self-improvement-channel.md`](adr/0003-standing-self-improvement-channel.md) — the recurring channel behind commitment 5: a conditional `/cdd-pre-pr` step plus a `/cdd-process-pr` triage route, their trigger design, and why an upstream candidate becomes a GitHub issue rather than a local roadmap item or a standing log
  - [`0004-conditional-merge-base-approval.md`](adr/0004-conditional-merge-base-approval.md) — making human checkpoint 4 conditional: the four mechanical criteria for an automatic `/cdd-merge-base`, why no "mechanical conflict" auto-resolve tier exists, and the residual semantic-break risk
  - [`0005-roadmap-item-length-cap.md`](adr/0005-roadmap-item-length-cap.md) — one 200-character cap for every roadmap item, pending and completed alike, enforced by the `roadmap-length` gate; where detail goes instead (a GitHub issue or the handoff), and why neither a separate backlog document nor a `Status: Proposed` ADR is that place
  - [`0006-small-change-lane.md`](adr/0006-small-change-lane.md) — the second lane through the middle of the cycle: `/cdd-small-change` in place of plan + implement, the recorded lane marker and its one-directional degrade, the one-sentence eligibility heuristic and its off-ramp, and why the checkpoint count stays six
  - [`0007-extend-cdd-through-capability-adapters.md`](adr/0007-extend-cdd-through-capability-adapters.md) — extending CDD through capability adapters: the fixed `.cdd/` namespace and its mandatory `describe` verb, the project → machine → built-in resolution ladder that degrades loudly, the replace-vs-mirror rule bounding what an extension may substitute, and the shortlist verdict (GitHub reference adapter first, then Jira, Confluence and GitLab)
  - [`0008-drop-the-issue-ref-branch-token.md`](adr/0008-drop-the-issue-ref-branch-token.md) — dropping the `gh_issue_NN_` branch token so the task state record is the only carrier of a task's issue references; why a backend-agnostic token format is more mechanism rather than less, and the two costs accepted in exchange (no close lines when the record is unusable, a wider browse-mode blind spot)
