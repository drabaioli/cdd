# 0010: Rename "forge" to "code host", and stop on a broken adapter

**Status:** Accepted; partially superseded by [0012](0012-drop-the-builtin-gh-rung.md) (a missing adapter no longer falls through to a built-in `gh` rung, and the helpers no longer have a silent built-in rung to be silent on)

## Context

[ADR 0007](0007-extend-cdd-through-capability-adapters.md) named the capability that hosts PRs
and merge state the **forge**, and set one rule for the whole resolution ladder: it "degrades
loudly and never fails". With the second capability about to ship — its contract, a GitHub
reference adapter, and the shell helpers' PR lookups routed through it — two things in that
record no longer hold up.

**The name.** "Forge" is open-source jargon (from SourceForge). It reads naturally to people
who already use it and not at all to anyone else, and CDD's audience is not limited to the
first group. Nothing has shipped under the name — no path, no adapter, no caller — so renaming
it now costs a docs sweep, and renaming it later would cost a migration.

**The fall-through.** "Never fails" was written for the absent adapter, and there it is right:
no project has an adapter, so each must behave as before. But the ladder applied the same rule
to an adapter that is *present and broken* — a `describe` that exits non-zero or does not parse,
an unsupported `contract` — and fell through to the next rung with a line saying so. That is the
wrong answer for a different reason than noise. An installed adapter is a **declaration of the
backend**: a project that commits `.cdd/code-host` for GitLab has said its PRs are not on GitHub.
Falling through to the built-in `gh` rung then asks the wrong system, and for the shell helpers
that answer is acted on: `cdd-worktree-gc` reaps by it and `cdd-worktree-done` force-deletes by
it. A loud line followed by a confident wrong action is not degradation.

A narrower hole sat next to it. Discovery tested `-x`, so a file present but not executable was
treated as *absent* — the one way a misconfigured adapter could produce the built-in behaviour
with no line at all.

## Decision

1. **Rename the capability to `code-host`.** The namespace is `.cdd/code-host`,
   `~/.cdd/adapters/code-host`, and `tools/adapters/code-host/<backend>.sh`. Docs, commands and
   the roadmap say "code host"; ADR bodies are records and keep the word they were written with.

2. **Three cases at every rung, for every capability.**
   - **Missing** — no file at the rung — goes to the next rung, as before.
   - **Installed but broken** — not executable; `describe` exits non-zero, does not parse,
     reports another `capability`, or an unsupported `contract`; or `jq` is absent, so the
     caller cannot read `describe` at all — is **one line naming the adapter and why, and no
     lower rung**. What "stop" reaches is decided per call site: a command about to act on the
     answer stops outright (`/cdd-next-step`; `cdd-worktree`, `-done`, `-gc`, `-resume`; the
     default-branch lookup in `/cdd-pre-pr` and `/cdd-merge-base`); a read-only listing
     (`cdd-worktree-list`) prints the line and shows no PR data rather than guessing.
   - **Verb unsupported** — absent from `describe.verbs`, or exit 3 — is not an error: the
     caller skips that feature, as it would when the backend has no answer.

3. **Present means present.** Discovery tests that the file exists; executability is then a
   validity check. A non-executable file at a rung is broken, not missing.

4. **The shell helpers are silent on the built-in rung** and print one line only when an
   adapter serves. The prompts keep announcing every rung at the point of use (the tracker
   rule in `capability-adapters.md`), because a prompt's line is read by the user in the
   session doing the work; a helper's line would be printed on every `cdd-worktree-list` in
   every repo, none of which has an adapter. Decision 3 removes the one failure the helper
   line would have been guarding against.

5. **The contract.** Six code-host verbs are pinned — `pr-create`, `pr-for-branch`,
   `pr-comments`, `pr-reply`, `pr-merged`, `default-branch` — and the GitHub adapter implements
   all six. Only `pr-merged`, `pr-for-branch` and `default-branch` get callers in this change.
   `pr-merged` takes a **branch**, not a PR number, because both of its callers start from one.

Rejected: keeping the fall-through for broken adapters (the wrong-system action above);
announcing the built-in rung in the helpers (noise in every repo, and decision 3 closes the hole
it would have covered); `pr-merged <pr>` (both callers would need a `pr-for-branch` round trip
first).

## Consequences

- A project that binds a code host other than GitHub gets correct `done`, `gc`, `list`, `resume`
  and default-branch behaviour — but **still cannot open or process a PR through CDD**:
  `/cdd-pre-pr`'s `gh pr create` and `/cdd-process-pr`'s `gh` calls are not routed yet. The
  verbs they need are pinned; moving the callers is a separate roadmap item.
- A broken adapter now blocks the commands listed above until it is fixed or removed. That is
  the intended cost: the alternative was the same commands acting on another system's answer.
- The tracker path changes too: `/cdd-next-step` stops on a broken tracker adapter where it
  used to fall through. Nothing shipped depended on the fall-through.
- `cdd-worktree-gc` now reads merge state through `pr-merged` when an adapter serves, which is
  the prerequisite the post-merge `issue-transition` roadmap item was waiting for.
- `/cdd-pre-pr` and `/cdd-merge-base` now resolve the fallback base branch to a bare name
  (`main`); before, `git symbolic-ref --short` handed them `origin/main`, which
  `/cdd-merge-base` then fetched as `origin origin/main`.
