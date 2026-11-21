# 0033: Guard existing tests with a hook

**Status:** Accepted

## Context

ADR 0030 ships a "gamed or bug-locking tests" rule in prose. Issue #153 asks for a mechanism
behind it: what must happen every time belongs in a hook or a deny rule, not in `CLAUDE.md`.

- "Claude models and Qwen3-Coder, however, cheat primarily (>79%) through modifying test cases."
  "Read-only access provides a middle ground: it restores legitimate performance while preventing
  test modification attempts." An abort option lowered "the cheating rate of GPT-5 from 54% to 9%"
  (Zhong, Raghunathan, Carlini, ImpossibleBench, arXiv 2510.20270, §4.2, §5.2, §5.3).
- Agents get around filesystem locks: with tests locked, circumvention ran at 40% (Opus 4.6), 66%
  (Sonnet 4.6) and 94% (GPT-5.4), and "only the two prompts telling the agent to stop and report
  when it cannot edit a file drive circumvention to zero" (Agrawal, Scheurer, Ariel_, "Door's
  locked? Try the window", LessWrong, 24 Jun 2026).
- A Claude Code `PreToolUse` hook can return `ask`; its reason is "shown to the user in the
  permission prompt", whereas a `deny` reason is "shown to Claude". Precedence is
  `deny` > `defer` > `ask` > `allow`, and a silent hook does not approve the call (Claude Code
  hooks reference, accessed 2026-11-21).
- Auto mode "still shows you those prompts" forced by an `ask` rule or a hook (Claude Code
  permission modes, accessed 2026-11-21).
- Test layouts are declared per tool (Jest `testMatch`, pytest `python_files`, Cargo's `tests/`
  directory); no cross-language convention exists.

## Decision

1. **A hook CDD ships**, `.claude/hooks/cdd-test-guard.sh`, wired in `.claude/settings.json` on
   the edit tools (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`). CDD-managed, identical in
   this repo.
2. **It asks, never blocks or allows.** It forces a permission prompt when the edited file
   matches the project's test paths, is tracked at `HEAD`, and is not named in the approved
   plan's `## File map`. Otherwise it says nothing and normal permissions apply.
3. **The project declares its test paths** in a new contract row, "Test protection", as a
   `- Test paths:` line of backticked shell patterns matched against the repo-relative path
   (`*` also matches `/`). Plain text, filled by `/cdd-bootstrap` or `/cdd-retrofit`; left
   unfilled, the hook holds nothing.
4. **The plan's file map is the approval.** `/cdd-plan` names every existing test file the plan
   changes there, by its repo-relative path in backticks (a `file:line` pointer counts), and in
   its digest.
5. **The row is Upheld once paths are declared, Expected until then**, never Enforced: CI cannot
   see the plan file (ADR 0028).

## Rejected alternatives

- Deny instead of ask: the small-change lane, `/cdd-process-pr` fixes and `/cdd-merge-base`
  conflict resolution make approved test edits with no plan file, and a deny leaves no way
  through but editing the plan or disabling the hook; a silent block invites workarounds.
- Settings `permissions.ask` or `deny` rules on test globs: they cannot tell a new file from an
  existing one or read the plan, and per-project globs in the CDD-managed `settings.json` would
  need a third placeholder (process doc §2.9).
- Sandbox `denyWrite` for shell edits: the sandbox is off by default, and on Linux it skips glob
  patterns.
- Parsing Bash commands in the hook: a command-text rule covers the invocation Claude usually
  produces and is not a boundary around the program; other forms slip past, and reads trip it.
- A `PostToolUse` `git diff` check after each Bash call: the edit has already happened, and it
  would re-fire on every later call once an approved test edit sits in the diff.
- A separate `.cdd/test-paths` file: a new artifact, where the contract row already carries the
  project's placeholders and reaches downstream through retrofit's merge.
- A dedicated plan section listing allowed tests: it changes the plan schema (process doc §2.15)
  for what `## File map` already says.
- "Existing" relative to the base branch: the base-branch resolution lives in
  `cdd-worktree.sh`, out of a project-local hook's reach.
- A runner gate: CI cannot see `~/.cdd`.
- `onFailure: "block"` on the hook: any hook error would block every edit, and it is
  version-gated.

## Consequences

- No checkpoint changes: the prompt is about one edit the approved plan did not name.
- Edits made through the shell are not held; `/cdd-pre-pr`'s code review of the diff, which
  applies the "gamed or bug-locking tests" rule, is the backstop.
- The small-change lane has no plan file, so every edit to an existing test there prompts once.
- "Existing" means tracked at `HEAD`: a test this task already committed prompts unless the file
  map names it.
- A human's rejection gives the agent only a generic refusal; the "Writing changes" rule already
  tells it to stop and say so.
- Path matching cannot see tests that live inside source files (Rust unit tests).
- A missing `jq` makes the hook exit non-zero, which Claude Code treats as a non-blocking error:
  the edit proceeds unguarded. `jq` is a CDD required tool (process doc §2.18).
- Unknown, not documented: how a hook-forced `ask` behaves under `bypassPermissions` and
  `dontAsk`, and exactly what the model receives when the human rejects the prompt.
- Downstream projects get the row through `/cdd-retrofit`'s three-way merge and the hook as a
  CDD-managed file; the non-interactive bootstrap script leaves the paths unfilled, so the guard
  is inert there until they are declared.
