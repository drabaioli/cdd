# 0035: Mark transitional changes; retire them through upgrade stops

**Status:** Accepted

## Context

Issue #80 asks for versioning, deprecation and fleet-migration mechanics. Its first sub-problem is
deprecation: some CDD-repo text exists only to carry existing projects or machines across a change,
and must go once nothing needs it. Four removals were pending (#90, #93, #148, #166), and the
pattern had no rule:

- Markers were inconsistent: `TRANSITIONAL:` pointing at the *source* issue, `DEPRECATION SEAM`,
  and a bare lowercase "transitional".
- Each piece's sites were listed by hand, in `/cdd-retrofit` ("delete this paragraph, its section
  2.7 queue line, …") and in the removal issue's body.
- The removal signal was always "every project, on every machine, upgraded past X". Nothing records
  which projects exist, so the signal could only be checked by asking around.
- Some sites are only partly transitional: the legacy-token step is permanent while its rows are not
  (#93); the `list`-mode proposal is permanent on install, transitional on upgrade (ADR 0029).

The human framed it as a database-migration problem: a CDD change that reaches downstream projects
is a migration, and frameworks that ship migrations to fleets they do not control have solved
pieces of this.

## Decision

1. **One marker.** A transitional piece is marked `TRANSITIONAL(#<issue>)`, naming its removal
   issue, on the transitional part only — never on the permanent block around it. Every doc
   sentence describing the piece carries the same marker. The shape follows Google's C++ style
   guide for `TODO`s ("`TODO` in all caps, followed by the bug ID"). `DEPRECATION SEAM` merges into
   it. `git grep` on one marker lists every site one removal touches, so hand-kept site lists go.
   ADRs are record and carry none.
2. **Upgrade stops retire `/cdd-retrofit` pieces.** The PR that removes a piece adds a stop to the
   table in `/cdd-retrofit` section 4.1: a CDD commit that still carries the piece.
   `/cdd-retrofit` refuses a baseline that is not past every stop, before anything is created, and
   routes the project through the stop: retrofit from a CDD checkout at the stop, land that PR,
   rerun. GitLab does this for its fleet ("required upgrade stops, which are versions of GitLab that
   you must upgrade to before upgrading to later versions"; "Ensure migrations are only removed
   after they've been a part of a planned required stop"). Removal then needs no fleet knowledge.
   The check is `git merge-base --is-ancestor <stop> <baseline>`. Removals are batched into few
   stops, since each costs an old project one extra run (Terraform's one-major-at-a-time advice
   shows the cost of dense stops).
3. **Helper pieces keep the fleet check.** A compatibility branch in a machine-global helper
   (`cdd-worktree`'s pre-split fallback, #90) serves projects that are never upgraded, so no stop
   reaches them. It is removed once every project on every machine is past the change, checked by
   the human. An issue covering both kinds waits on the stricter signal.
4. **A format gate, an open-issue check at pre-PR.** The `transitional` gate checks, offline, that
   each marker is well-formed, that no `DEPRECATION SEAM` remains, that `template/` holds no
   marker, and that a "transitional" line in `.claude/commands/` or `tools/` carries one — Ruff's
   TD003 ("Missing issue link for this TODO") is the model. Whether the issue is open needs the
   network, so this repo's `/cdd-pre-pr` extension checks it for markers a branch adds.
5. **The template carries none.** Shipped files are replaced on upgrade, and a downstream project
   would read `#<issue>` against its own tracker. Transitional pieces live only in CDD-repo-only
   files, so a transitional change leaves the template unchanged.

The ideas weighed from database migrations:

- **Upgrade stops** (GitLab; Django's squash advice to "ensure your users upgrade releases in order
  without skipping any") — adopted (2). With no registry, an in-order policy is the only signal
  that works, and a stop enforces it.
- **Expand/contract** — adopted as framing. §2.8's additive, global-first rule is the expand step; a
  transitional piece is the pending contract step.
- **Ordered, named migration files** for content moves, applied in sequence and deleted whole — not
  now. Four small pieces do not justify restructuring `/cdd-retrofit`; the first real content
  migration (a docs restructuring, #145) is the time to decide. Kept in process doc §6.
- **Load current state for new instances** (Rails: the schema file "makes it possible to delete or
  prune old migration files") — adopted, already true: install and bootstrap render the current
  template and replay nothing, so stops are upgrade-only.
- **Per-instance applied record** (Django's migration table, Flyway's schema history) — rejected.
  `.claude/cdd-baseline` is a high-water mark, and a declined retrofit hunk means "past X" does not
  prove X was applied. But a decline is a human decision already listed in the retrofit commit's
  "behind the template" list; a prose applied-record has nothing like Flyway's checksum to keep it
  honest.
- **Declared dependencies between migrations** — out of scope (#80's ordering sub-problem). Stops
  are ordered by commit ancestry, so they do not preclude it.

## Rejected alternatives

- **Alembic's "remove old migration files that are no longer represented on any existing
  environments"** as the signal for retrofit pieces: it needs the fleet knowledge CDD lacks. It
  survives only for helper pieces (3), as a human check.
- **A per-machine fleet report** from `~/.cdd/handoffs/<repo>/repo.json` and each project's
  baseline: feasible, but stops leave one helper piece needing it. Deferred.
- **Issue-state or date checks in the gate** (todocheck: "Only `TODO`s with valid, open issues are
  allowed"; eslint-plugin-unicorn's expiring TODOs): the first needs the network (ADR 0002), the
  second breaks an unchanged build. The issue check moved to `/cdd-pre-pr` instead.
- **Begin/end region markers:** pairs must balance, and the transitional parts are sentence-sized
  inside prose.
- **A removal-issue label:** `git grep -ho 'TRANSITIONAL(#[0-9]*)' | sort -u` already lists every
  pending removal, offline.
- **A lowercase "transitional" check repo-wide:** the process doc and the guard docs use the word as
  a term. Scoped to where pieces are added.

## Consequences

- An old project pays one extra retrofit run per stop it has not passed.
- Removing a retrofit piece needs no knowledge of the fleet; removing a helper piece still does.
- Adding a transitional piece means opening its removal issue first.
- #80 stays open for the version handshake and ordering; ADRs 0020 and 0029 are left as written.
- No checkpoint changes.
