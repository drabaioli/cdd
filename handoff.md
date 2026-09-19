# Task: Record the extensibility phase on the roadmap

## Branch
gh_issue_86_extensibility_roadmap_phase

## Roadmap reference
None — this task creates the phase. Sourced from GitHub issue #86
("Extensibility: `.cdd/` capability adapters, and the rules that bound them",
https://github.com/drabaioli/cdd/issues/86), whose stated first task is to turn its
"Proposed roadmap phase" block into a real roadmap phase.

## Requirements
1. `doc/knowledge_base/roadmap.md` gains `## Phase 14: Extensibility — capability adapters`, placed after Phase 13 and before the "Annotation conventions" section, carrying the 13 unchecked items from issue #86 and a `**Milestone:**` line, in the same shape as every other phase.
2. The phase intro names GitHub issue #86 as where the design detail lives.
3. `./scripts/ci.sh` is green — the `roadmap-length` gate in particular.
4. No other file changes: no process-doc, `template/`, `demo/seed/`, or ADR edits.

## Notes
- Copy the 13 items verbatim from the issue's "Proposed roadmap phase" block. They
  measure 131–144 characters, already inside the 200-char cap, so they need no rewording.
- Drop the issue's meta-line "Each item ≤200 chars per ADR 0005; detail lives in this
  issue" — that is guidance to the reader of the issue, not roadmap content. The pointer
  to #86 belongs in the phase intro prose, which is uncapped.
- The ADR named in item 2 of the phase ("ADR + process-doc section: the `.cdd/`
  namespace…") is a *later* task in the phase, not this one. This task ships no ADR, no
  process-doc section, and no adapter.
- Nothing in the repo pins the roadmap's phase count, so adding Phase 14 strands no prose
  (checked across `*.md` and `scripts/`).
- The PR will auto-close #86 via the `gh_issue_86` branch token. That is intended: the
  issue's stated job is this roadmap phase, and its design detail stays readable after
  closing, reachable from the phase intro pointer.
- No further roadmap edits implied — this task *is* the roadmap edit.
