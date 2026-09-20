# 0007: Extend CDD through `.cdd/` capability adapters

**Status:** Accepted

## Context

CDD talks to external services — GitHub Issues for the intent inbox, `gh` for PRs and merge state,
the repo's own docs for everything else. Every one of those bindings is currently hardcoded into a
shipped prompt or a shell helper. A project whose tracker is Jira, whose forge is GitLab, or whose
reference docs live in Confluence has nowhere to put that fact except into a local edit of a file
CDD ships, which is a fork in slow motion.

The fleet was measured before deciding anything. Seven CDD projects were three-way diffed against
the template **at each project's own baseline commit**, so what remains is real customization rather
than template staleness. Colibri (56 PRs, Zephyr/C++ firmware) carries four hunks, all in
`cdd-pre-pr.md`; worklog, scribe, release-manager, cdd-dash and cde-dash carry **zero**. Of
Colibri's four, exactly one was load-bearing — build commands routed through `docker compose run` —
and the check runner (process doc §2.14) has since absorbed it. The other three are a narrowing, an
inlined indirection, and cosmetic nouns.

So there is **no observed demand for behavioural prompt hooks**. There are two counter-signals
pointing elsewhere. CDE is a workflow different enough that it became a sibling repo rather than a
customization. And cdd-dash and cde-dash are read-only consumers of `~/.cdd/handoffs/*/state.json`,
`repo.json` and `refs/cdd/*` — a de-facto public API that was never declared, with two consumers
already in production. The demand is not "change what a session does"; it is **substitute the
external service CDD talks to**.

Two failure modes bound the design. If every adaptation request has to be processed as a change to
CDD itself, the workflow becomes the bottleneck for every project that uses it. If users have
nowhere to put an adaptation, they edit the prompts locally. Both end in the same place: every
install a fork.

## Decision

**Extend CDD through capability adapters: executables a project commits under a fixed `.cdd/`
namespace, one per capability, named for the role it fills** — `.cdd/tracker`, `.cdd/forge`,
`.cdd/docs`, `.cdd/notify`. Discovery is `[ -x .cdd/<capability> ]`. There is no config format, no
parser and no registry.

**The path is fixed, not project-chosen.** `ci.sh` gets away with a project-chosen location because
only a prompt invokes it, and a prompt can read `CLAUDE.md`. A shell helper resolving an adapter has
no LLM, so the path has to be conventional — it must resolve identically from a prompt and from
`cdd-worktree`. `.cdd/` also sidesteps the `scripts/` vs `tools/` split already live across this
repo and Colibri, and mirrors `~/.cdd/`. Not `.claude/` — that directory belongs to Claude Code.

**The config is a function, not a file.** One mandatory `describe` verb makes the binding
introspectable without inventing a format, the same trick `ci.sh list` uses to make the runner the
sole source of its own gate sequence (§2.14). `describe` is what an adapter-conformance gate checks
and what an external consumer such as cdd-dash reads to show which backend a repo is bound to. The
committed file carries coordinates only — a base URL, a project key, the *name* of an environment
variable — and **never a secret**; where an adapter has a generic half, that half installs
machine-globally under §2.8's rules (newest wins, never pinned per project).

**Resolution ladder: `.cdd/<capability>` → `~/.cdd/adapters/<capability>` → built-in behaviour** —
today's `gh` path — **degrading loudly and never failing.** This is §2.14's per-gate skip rule
applied to a different artifact: an absent adapter yields a weaker binding, announced, rather than a
broken session. The machine-global tier exists because one Jira shop has many repos, and repeating
the same adapter in each of them is the thing that makes people stop updating any of them.

**CLI-first, not MCP-first.** CDD runs in two execution contexts. Prompt-time can call MCP tools and
apply judgement; shell-time — helpers, CI, hooks — can do neither, and is the only context
`cdd-worktree` runs in. A CLI contract works for both, and an adapter is free to shell out to an MCP
server internally. Going MCP-first would force `pr-merged` and `default-branch` out of the contract
entirely, because no helper can reach MCP.

**Credentials boundary: CDD never stores, reads or proxies a secret.** Authentication is whatever
the underlying tool already does — `gh auth`, `glab auth`, an MCP server's own OAuth, a keychain
helper, or an environment variable the committed shim names but never contains.

**The replace-vs-mirror rule bounds what an extension may substitute:**

> An extension may **replace** anything CDD already treats as external — issues, PRs, CI,
> notifications, review. It may only **mirror** what CDD treats as in-repo substrate — roadmap,
> architecture/feature docs, ADRs, handoff.

It falls out of existing invariants rather than out of taste. Issues are already an external inbox
feeding the roadmap, so swapping GitHub Issues for Jira changes nothing structural. The roadmap is
in-repo because the implementation session ticks it in the same commit (§5), `/cdd-pre-pr`
reconciles it against the diff, and a structural edit to it takes its human gate *as a PR* —
relocating it breaks all three, plus offline reads and `git blame` attribution. This is the standing
answer to "can the roadmap live in Confluence / Notion / Backstage?": as a mirror, yes; as the
source, no.

**Four shape constraints the verb contract must honour**, decided now because each is expensive to
revisit later:

- `ref` is the human handle and `id` the backend's internal key where the two differ. Splitting them
  later touches every adapter, so they are split from the start.
- `state` is normalized to `open` / `closed`, with `state_raw` keeping the backend's native value.
  CDD only ever branches on open-versus-closed; everything richer is the backend's business.
- A `raw` passthrough carries the backend's own payload, and nothing in CDD reads it — so an adapter
  never has to lie about its backend to fit the contract.
- **Absent means unsupported; never emit `null` to mean unsupported.** `[]` and `""` mean supported
  and empty.

**One exit code is reserved for "this backend does not support that verb"**, distinct from "the
operation failed". That is what lets a prompt tell "GitHub has no transitions, carry on" from "Jira
is down, stop". Without a distinct code every caller has to guess, and they will guess differently.
The numeric value, the verb lists and the JSON examples are **not** pinned here — that is the later
roadmap item that pins the tracker contract, and issue #86 carries them meanwhile.

**Gates are already solved; do not build a second mechanism for them.** A check that is
deterministic, pass/fail, and runs anywhere is a gate in the project's check runner (§2.14). A thing
that needs judgement, talks to an external service, or is a *step* rather than a check is an
adapter. The two do not overlap and neither grows into the other.

**Shortlist verdict.** **GitHub is the reference tracker adapter and ships first**, because it is
the only backend whose correct behaviour is already known: it validates the contract by producing
*no behaviour change at all*. **Jira and Confluence are committed**, and **GitLab is wanted**.
**Linear and Slack are recorded as candidates, not committed** — no roadmap items. The same
reasoning merges the roadmap's separate "pin the tracker verb contract" and "GitHub reference
tracker adapter" items into one: a verb contract with no implementation is unvalidated prose, and
the conformance gate the first item asks for has nothing to run against without the second. The
forge item already bundles exactly that shape, so the merge removes an inconsistency rather than
introducing one.

## Rejected alternatives

- **Session hooks (`.cdd/hooks/<gate>.md`) now.** Zero observed demand across the whole fleet; the
  one load-bearing customization anyone had was a gate, and the check runner already took it.
  Deferred, not refused — if the demand appears, the namespace has room.
- **A config file (YAML/TOML/JSON) instead of a `describe` verb.** Needs a format, a parser and a
  registry, and still cannot express a bespoke project setup whose binding has to run logic inline.
- **MCP-first.** See CLI-first above: it amputates every shell-time verb, `pr-merged` and
  `default-branch` first.
- **A project-chosen adapter path declared in `CLAUDE.md`.** Works from a prompt, fails from a shell
  helper, which has no LLM to read `CLAUDE.md` with.
- **Letting the roadmap or the architecture docs live in a doc backend as the source.** Barred by
  replace-vs-mirror. A mirror is fine and is the intended shape.
- **Teaching the prompts to recognize each backend's reference syntax.** Today §0 of
  `/cdd-next-step` pattern-matches `#123` or a bare integer, which does not scale past one backend.
  The inversion — the adapter declaring its own `ref_pattern` — is the right shape, and it lands
  with the later roadmap item rather than here.

## Consequences

- `.cdd/` becomes a reserved project directory and `~/.cdd/adapters/` a reserved machine one.
- Adaptation stops being either a change to CDD or a local fork of its prompts. The fleet's real
  failure mode is closed before it has produced any forks.
- A *docs* capability makes backend documentation read-first-class while the repo stays the source.
  **Context cost, not correctness, is the design risk there**: a session that pulls three long
  Confluence pages into context has spent its budget before it starts, which is the opposite of the
  context economy the doc philosophy exists to protect. The mitigations — excerpt-returning search,
  section anchors, an adapter-side size cap that says when it truncates — are settled when that
  capability is built, not here.
- The `~/.cdd` consumer surface that cdd-dash and cde-dash already read still has **no declared,
  versioned schema**. This ADR names the gap; it does not close it. That is separate deferred work.
- Every adapter is optional and absence degrades to today's behaviour, so the whole mechanism is
  inert on a project that installs none — the same additive shape as §2.8's machine-global rule.
- GitHub issue #86 stays the living detail record for the deferred surfaces (session hooks, helper
  lifecycle hooks, publish/mirror, multi-backend routing, the `x-` schema convention, declaring
  `~/.cdd` a public API). The repo deliberately carries no copy of that list, so there is one place
  for it to be wrong.
