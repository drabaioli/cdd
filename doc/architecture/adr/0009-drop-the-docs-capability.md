# 0009: Drop the docs capability; an adapter needs a machine consumer

**Status:** Accepted

Partially supersedes [0007](0007-extend-cdd-through-capability-adapters.md): its docs-related
commitments only. The rest of 0007 stands.

## Context

ADR 0007 put three capabilities on the shortlist — tracker, forge and docs — and committed
Confluence as the docs backend alongside Jira. Its Consequences carried a bullet for the docs
capability ("A *docs* capability makes backend documentation read-first-class…") that deferred its
context-cost mitigations to build time, and its namespace examples listed `.cdd/docs` next to
`.cdd/tracker`, `.cdd/forge` and `.cdd/notify`.

That build happened: a docs verb contract, a Confluence adapter and wiring into every session type,
as PR #112. It was closed unmerged. Building it made plain what the tracker and forge have that docs
does not.

The tracker's output is consumed by the workflow itself. `ref_pattern` is what `/cdd-next-step`
dispatches on to tell an issue reference from a task prompt; `issue-close-token` is what
`/cdd-pre-pr` builds the PR's close lines from. The forge's `pr-merged` and `default-branch` are
read by shell helpers such as `cdd-worktree-gc`, which have no LLM at all. In each case a CDD script
or a structured workflow step does something with the answer that it could not do with prose.

A docs lookup has no such consumer. Its result is read by Claude, as prose, and used with
judgement. No CDD step branches on it, parses it, or passes it on. A contract for it would pin JSON
shapes that nothing reads.

## Decision

**A capability adapter is justified only when a CDD script or structured workflow step consumes the
backend's output.** This is now the test every proposed capability is judged by.

The tracker and the forge pass it. Docs does not, so **docs is not a capability**. Reference docs
held in an external store are served by the project's own MCP server for that store, plus a
`CLAUDE.md` line saying what lives there and when to look.

0007's CLI-first reasoning does not argue otherwise. MCP-first was rejected there because it
"amputates every shell-time verb" — `pr-merged` and `default-branch` first. Docs has no shell-time
verb to amputate: every docs read happens at prompt time, which is exactly where an MCP server is
reachable.

This withdraws, from 0007:

- **"Confluence committed"** from the shortlist verdict. Jira stays committed (and has shipped);
  GitLab stays wanted.
- **The docs-capability Consequences bullet.** Its context-cost risk is real but no longer needs an
  adapter to hold the mitigation: the recipe below has a subagent read the page and return only the
  relevant section.
- **`.cdd/docs`** from the namespace examples. `.cdd/tracker`, `.cdd/forge` and `.cdd/notify` remain
  illustrative.

**Linear and Slack**, recorded in 0007 as candidates, are judged by this rule when someone proposes
them, and get no verdict here. Linear is a tracker backend, so it would arrive as a tracker adapter —
a capability the rule already admits. Slack (notification) has to show which CDD step consumes what
it returns.

## Rejected alternatives

- **Keep a docs capability for uniformity.** A contract with no machine consumer is unvalidated
  prose: a conformance gate could check that the JSON has the right shape, but nothing in CDD would
  ever notice if it had the wrong content.
- **An MCP-backed `.cdd/docs` shim.** Adds a layer between Claude and an MCP server it can already
  call directly, and buys nothing at shell time because nothing at shell time reads docs.

## Consequences

- The recipe for serving external docs lives in `doc/architecture/capability-adapters.md` under
  "Docs: not a capability": the backend's MCP server in the project's `.mcp.json`, one `CLAUDE.md`
  paragraph, a subagent that returns only the relevant section, the page recorded under the plan's
  `## External findings`, and no copying into the repo.
- Replace-vs-mirror is unchanged. The repo stays the source of its own docs; page content is never
  copied in.
- The plan file's `## External findings` placeholder now asks for each source's version as well as
  the source, so a plan built from a doc page can be traced to the page as it read then.
- Two roadmap items (the docs contract and the Confluence adapter) are removed rather than ticked,
  and Phase 14's milestone no longer names a doc source.
- The number of capabilities CDD has to keep contracts, reference adapters and conformance gates for
  shrinks by one.
