# 0030: Code-level rules aimed at agent failure modes

**Status:** Accepted

## Context

ADR 0001 instils engineering practice by "mechanism and floor, not prescription", so CDD shipped
no code-level rules. Issue #153 asked whether it should ship a catalogue of code-quality
practices, and researched it:

- Context files "does not generally improve task success rates, while increasing inference cost
  by over 20% on average", yet "context files are useful for specifying non-standard coding
  practices" (Gloaguen et al., arXiv 2602.11988 v3, September 2026; v1 said they "tend to reduce"
  success).
- A persona of a developer following best practices "has a small positive effect on the code
  quality, but at the expense of slightly lower correctness" (Khojah et al., arXiv 2412.20545 v2).
- Tool output beats prose: Bandit and Pylint output fed back to GPT-4o cut "security issues …
  from >40% to 13%, readability violations from >80% to 11%" (Blyth et al., arXiv 2508.14419).

Coding agents fail in documented ways:

- **Duplicated helpers.** Copy/paste "climbed from 9.4% (in 2022) to 15.7% in the first half of
  2026" (GitClear, vendor data).
- **Hidden failures.** "Error handling and exception-path gaps were nearly 2× more common" in AI
  pull requests (CodeRabbit, vendor data, 470 PRs).
- **Gamed or bug-locking tests.** Claude models "cheat primarily (>79%) through modifying test
  cases", and an option to flag the task for a human cut GPT-5's cheating "from 54% to 9%"
  (ImpossibleBench, arXiv 2510.20270). Generated suites "validate bugs by treating incorrect
  behaviour as expected" — up to 68.1% for one tool on GPT-4o (arXiv 2412.14137).
- **Made-up dependencies.** Hallucinated packages run "at least 5.2% for commercial models and
  21.7% for open-source models" (arXiv 2406.10279, USENIX Security 2025).

Rules over-apply. One ownership sentence moved duplicate consolidation from "under 10 percent" to
"about 75 percent of runs", but "output tokens rose by about 70 to 80 percent and the model made
changes nobody had asked for"; "A rule that limits scope doesn't cancel it", and "The model
treats an instruction that contains 'never' as absolute" (Anthropic, Prompting Claude Fable 5.2).
"piling on emphasis mostly makes Claude over-apply the rule" (Claude Code best practices).

Claude Code's own coding guidance is not always present: "A custom output style leaves the
`claude_code` preset's software engineering instructions out", and "Those instructions are only
in Claude Code's full system prompt" (Agent SDK docs, modifying system prompts). `CLAUDE.md`
reaches every setup.

## Decision

1. **ADR 0001's stance is revised at code level**: CDD prescribes a few generic rules in "Writing
   changes", beside ADR 0026's rule. Process-level practices stay mechanism and floor.
2. **What earns a rule**: it targets a failure mode documented for coding agents, rests on a
   verified finding, carries a limit against over-application, and is not something every Claude
   Code setup already gives. A rule a later check holds may be dropped then. No catalogue of
   general principles.
3. **The rules**, each labelled by its failure mode and carrying its limit: duplicated helpers,
   hidden failures, gamed or bug-locking tests, made-up dependencies. Their text lives in
   `CLAUDE.md` (ADR 0018).
4. **Plainly worded**, each rule scoped: no emphasis, no "never".
5. **Language-specific rules** live in the project's linter config and coding standard, never in
   the generic set.

## Rejected alternatives

- A catalogue of principles (SOLID, DRY, patterns): the agent already knows them, persona and
  principle prompts trade correctness for little quality, and context files cost.
- "Make only the changes asked for": ADR 0026 already holds its over-engineering half
  ("abstractions nothing needs yet"), and its scope half would contradict ADR 0026's "fixing an
  unrelated bug or improving quality along the way stays welcome".
- "A new test must fail without the change it covers": it misses the bug-locking tests it was
  aimed at (a test written against buggy new code also fails without that code), costs a
  revert-and-run per test, and means nothing for a refactor; mutation testing measures what it is
  after. The tests rule's expected-values clause targets bug-locking directly.
- "Don't make claims about code you haven't read": no finding documents it as a failure; per
  OpenAI's guidance ("add new rules only after you notice repeated mistakes") it waits for one.
- Dropping a rule because Claude Code's built-in prompt gives it: that guidance is absent under
  output styles, the shorter system prompt and the SDK default.
- Emphatic or absolute wording: over-applied (Context).
- A line per command: `CLAUDE.md` already reaches every session (ADR 0026).

## Consequences

- Both `CLAUDE.md` files carry the rules; downstream projects get them through `/cdd-retrofit`,
  which upgrades "Writing changes" as one of CDD's own sections.
- About ten more lines of context per session.
- The rules are held by review, not a gate; the roadmap's code-level phase adds the checks
  (static analysis fed back, a duplicate-block check, test protection, mutation testing).
- No checkpoint changes.
