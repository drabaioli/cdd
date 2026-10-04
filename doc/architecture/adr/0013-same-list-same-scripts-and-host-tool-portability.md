# 0013: Same list, same scripts — and host-tool portability

**Status:** Accepted

## Context

The check runner (process doc §2.14) promised that a green local run meant a green CI run,
"because it is the same command". Two things made that untrue.

- **Host tools differ.** The gate scripts — and `tools/`, which runs on users' machines — call
  sed, grep and awk, and the implementations disagree. #106 was the instance that surfaced it
  (issue #107): a backslash in an `awk -v` value, kept literal by mawk on a contributor's host,
  stripped by gawk on the GitHub runner, so a gate passed locally and failed CI. A sweep of the
  tree found five more: an in-place `sed -i` in the bootstrap script (broken on macOS, where BSD
  sed reads the next argument as a backup suffix) and four GNU-only BRE escapes, one of which
  made a drift-check guard silently match nothing under BSD grep.
- **Slow gates want fanning out.** A project whose gates are container builds cannot sensibly run
  them in one CI job, and "the same command" forbids anything else (issue #75, part 1). The
  runner already has a list mode and per-gate invocation, so a fanned-out CI can still take its
  list from the runner.

## Decision

1. **The guarantee is "same list, same scripts", not "same command".** CI never holds a gate
   list: it calls the runner whole, or fans out — one job reads the runner's list mode, one job
   per gate runs that gate — which needs the runner to have both modes. A green local run means
   CI runs the same gates through the same scripts, not that the verdict is identical: host
   tools can differ. The template ships the fan-out shape
   as prose, not as a CI config. This repo still calls the runner whole; its full run is about
   half a minute.

2. **Narrow the host-tool gap two ways.** A `portability` gate bans, over the lint scope, the
   constructs the families are known to disagree on — `sed -i`, a backslash in a literal
   `awk -v` value, the GNU BRE escapes `\?` `\+` `\|`, `grep -P` — proving its rules with an
   inline self-check before every scan rather than a separate mutation-harness gate (the
   `roadmap-length` precedent; a separate contract gate with a data file and whitelist was
   designed and rejected as too many parts). And CI runs on two pinned OSes, `ubuntu-24.04` and
   `macos-15`, both blocking: macOS brings BSD sed/grep and BWK awk, the real user environment,
   rather than a second awk planted on `PATH` by a runner knob (also designed, and dropped).

3. **CDD requires bash >= 4.** The runner and `tools/` already use bash-4 constructs (`mapfile`,
   `${var,,}`) and macOS ships 3.2; rewriting them for 3.2 buys nothing a Homebrew bash does not.
   The runner stops with a one-line message on an older bash, and so does the worktree helper
   (sourced, before defining any function; run as `install`, before writing anything) — it
   otherwise fails mid-command, after side effects. zsh, which also sources the helper, is not
   a bash and is left as it was. The macOS CI job installs
   Homebrew bash in an install-only setup step — the one kind of extra step the runner's
   contract lets the workflow carry.

4. **A missing tool is a failure, never a skip — locally and in CI.** This reverses the
   skip-and-continue default the runner was built with (issue #36, process doc §2.14 before
   this change), under which a gate whose tool was absent reported SKIP and the run stayed
   green. That was argued as a weaker verdict rather than a wrong one, but a skip is read as a
   pass, and CI is where it costs most: the first runs of the new macOS job passed with
   `shellcheck` skipped, and a runner image that dropped `jq` would have skipped ten gates and
   kept merging. Now a gate whose `needs` tool is absent fails, naming it; detection stays per
   gate and the run stays non-fail-fast, so one run lists everything to install. Gate scripts
   run standalone follow the same rule instead of exiting 0 on a "skip:" line, which
   `ci-runner-assert.sh` rejects. The template's runner guidance changes with it, so a project
   bootstrapped from here gets the same rule. A per-project opt-out (skip where tools are
   independent and optional) was the old escape hatch and is dropped rather than kept: the
   case it served — a contributor without `shellcheck` — is better served by being told to
   install it.

## Consequences

- A gate that leans on one tool family fails the PR rather than a contributor's run — on the
  sweep's rules mechanically, on everything else through the macOS job.
- The sweep is line-based: a flag on a continuation line, or a value built from variables, is
  invisible to it. A justified use carries `# portability-ok: <reason>`.
- macOS users of CDD need Homebrew bash; the engineering-practices contract says so, along with
  the host tools the scripts may assume.
- The workflow may now carry install-only steps besides the runner step; `ci-runner-assert.sh`
  holds every other `run:` line to a package install that names no repo script, so no gate can
  hide in one. CI's job id changed (`bootstrap` → `checks`); the repo has no required status
  checks that named it.
- A project with slow gates has a sanctioned way to parallelise CI without a second gate list.
- Running this repo's gates now needs `shellcheck`, `jq` and `tar` on the host; a contributor
  without one gets a red run that names it. CI installs whatever its image lacks in an
  install-only step (`shellcheck` on macOS). Downstream runners built under the old guidance
  may still print skips; `/cdd-pre-pr` counts those as failures.
