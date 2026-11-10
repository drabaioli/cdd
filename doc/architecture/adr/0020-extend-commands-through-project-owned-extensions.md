# 0020: Extend commands through project-owned extensions

**Status:** Accepted

## Context

Projects wrote their specifics *into* the shipped command files, so every upgrade through
`/cdd-retrofit` became a "both changed" three-way hand-merge. Colibri's upgrade (70d6e4b →
929cf0f, issue #127) had to re-merge `cdd-pre-pr.md` by hand: §2 replaced with its own gate list
plus a "scale gates to the diff" rule, §3 narrowed to `.cpp`/`.hpp` and pointed at its C++ coding
guide, §4 given extra architecture triggers, the checklist line rewritten. The template invited
it: `cdd-pre-pr.md` §2 carried a `<check runner command>` placeholder and a per-gate fallback block
of five more, and `BOOTSTRAP.md` told projects to fill them in place.

ADR 0007 deferred exactly this as "session hooks (`.cdd/hooks/<gate>.md`)", for want of demand:
"Deferred, not refused — if the demand appears, the namespace has room." #127 is that demand, and
it is wider than one gate: plausible extensions include a security or licence audit in
`/cdd-pre-pr`, a required threat-model section in `/cdd-plan`, regenerating generated code in
`/cdd-implement`, regenerating lockfiles after `/cdd-merge-base`, team reply conventions in
`/cdd-process-pr`, required ticket fields in `/cdd-next-step`.

## Decision

Project specifics live in two project-owned places, and no project edits a shipped command.

1. **Declarations in `CLAUDE.md`.** Facts a command needs from the project are declared in
   `CLAUDE.md`, which every session loads. Two exist: the **check runner**, whose only declaration
   is the Build & test block (`/cdd-pre-pr`, `/cdd-merge-base`, `/cdd-implement` and
   `/cdd-small-change` all read it there; no command carries a runner placeholder), and the **code
   review scope**, an optional line narrowing which changed files `/cdd-pre-pr` reviews. A
   placeholder left unfilled declares nothing, and the command falls back to its default.
2. **Extensions in `.cdd/extensions/<command>.md`.** Steps a project adds to one command go in a
   file at a fixed path matched by the command's name — the systemd drop-in shape (a separate
   file found by name beside the unit), without its precedence. Each of the seven shipped
   lifecycle commands first checks for its own file and, if present, follows it alongside itself.
   The file is read by an ordinary tool call, not included at load time.
3. **An extension only adds, and the command outranks it.** Additions sit under `##` headings
   naming, by title rather than number, the step they attach to, so renumbering never strands
   one (the headings seam check already treats titles as the stable anchor). An extension cannot
   remove, skip, reorder or weaken anything — a checkpoint least of all. The command says, in its
   own text, that it wins a conflict and that the conflict is said in one line, never resolved
   silently; a heading naming a step the command lacks is said and asked about. The explicit
   instruction is there because models rarely acknowledge conflicting instructions unprompted,
   and because nothing in a prompt's position establishes precedence on its own.
4. **Gates stay gates.** A deterministic pass/fail check belongs in the check runner (ADR 0007:
   "gates are already solved"); an extension is for steps and judgement.
5. **Not a capability.** `.cdd/extensions/` holds Markdown a session reads, not an executable a
   script resolves: no `describe`, no machine tier, no ladder, and nothing substituted, so ADR
   0007's replace-vs-mirror rule does not bear on it.
6. **Retrofit migrates the old edits — transitionally.** `/cdd-retrofit` upgrade mode gains a
   fourth verdict: a local hunk left in a shipped command is proposed, per file, to move onto a
   declaration or an extension. It exists only to migrate edits made before this mechanism; it
   is deleted once every project has migrated, and the removal issue is filed then.
7. **The CDD repo dogfoods it.** The repo's own additions to `/cdd-pre-pr` and `/cdd-process-pr`
   moved out of `cdd-only` fences into `.cdd/extensions/`, so its command copies equal the
   rendered template. The fence stays supported.

## Rejected alternatives

- **A project-owned fenced region inside shipped commands** (carrying `cdd-only`-style fences
  downstream). Still a file the project edits, so still a hand-merge on upgrade — the problem
  itself.
- **`.claude/commands/local/<command>.md`.** Claude Code registers a file in a subdirectory of
  `.claude/commands/` as a command of its own (`/local:<command>`).
- **A load-time `!` or `@` include.** A failed shell command in a command aborts the whole
  invocation, so a missing extension would kill the command it extends; and policy can disable
  shell execution outright.
- **A `UserPromptExpansion` hook injecting the extension.** Needs a shipped hook in settings plus a
  script, and its behaviour for prompts started by `cdd-worktree` rather than typed is unverified.
- **Named insertion slots** (`<!-- extension: after-review -->`). Every new slot is a template
  change; the commands' step titles are already stable anchors.
- **A `.cdd/check-runner` executable.** ADR 0007 fixed `.cdd/` paths because shell helpers must
  resolve them without an LLM. Only prompts and the project's own CI run the runner, and the
  runner was already named in `CLAUDE.md`; a second declaration would be one too many.
- **A machine tier (`~/.cdd/extensions/`).** No demand, and it would let one machine change a
  project's workflow without a commit anyone reviews.
- **An extension narrowing the review.** Narrowing is not an addition, so it cannot be an
  extension; it is a declaration, kept in `CLAUDE.md`.
- **Extension points in `/cdd-retrofit`, `/cdd-bootstrap` and `/cdd-quick-create`.** They live in
  the CDD repo only and run from a CDD session on another target; no downstream project owns them.

## Consequences

- No shipped command carries a project fact, so an upgrade replaces command files cleanly; a
  project's specifics survive in `CLAUDE.md` and `.cdd/extensions/`, which the upgrade never
  overwrites.
- "Only adds" is a prompt rule, not enforcement — the same residual risk the checkpoints already
  carry, and the same safeguard: the file is committed and reviewed. Every extension line rides
  into the command's context, so extensions should stay short.
- That Claude Code does not discover Markdown under `.cdd/` as commands is inferred from its
  documented discovery locations, not stated by them.
- `/cdd-retrofit` carries a transitional fourth verdict until the fleet has migrated.
- One more seam check (`extension-points`) pins that every shipped command still reads its
  extension file, that the four gate-running commands read the runner `CLAUDE.md` declares, and
  that this repo's own extension headings name real command steps.
- ADR 0007's deferred session hooks are taken up here, as command extensions, outside its
  capability namespace.
