# 0019: Declare a dependency posture

**Status:** Accepted

## Context

CDD's scripts lean on external tools — `git`, bash >= 4, `jq`, `claude`, `gh`, `curl`,
`shellcheck`, `rsync`, `timeout` — and treated a missing one in four different ways without ever
saying which tool got which. The adapters stopped (exit 4). The gates failed (ADR 0013). `rsync`
fell back to `cp -a`, which is identical. And `jq` was *advisory*: without it `cdd-state` printed
one line and wrote nothing, and `cdd-worktree` quietly skipped every read of the state record.

That last bucket was the expensive one. A jq-less machine ran a reduced workflow with nothing
saying so: no record meant no recorded base branch (tasks cut from the default branch), no lane
(the small-change lane never routed), no resume-to-`/cdd-implement`, no issue close lines, no gc
closes. ADR 0006 ("every miss — … no `jq` …") and ADR 0008 ("absent without `jq`") wrote that
degrade into the design. `claude` was never checked at all: `cdd-worktree` found it missing only
at the launch, after the branch and the worktree already existed. And no project had a way to
install what it needed: the prerequisites were scattered across a README sentence, a
`BOOTSTRAP.md` list and the macOS CI step.

## Decision

1. **Four postures, each tool exactly one.** *Required*: absence stops, with a message naming the
   tool and how to install it, exit 4 — at install and at runtime. *Per-adapter required*: only
   the adapter that needs it stops, exit 4 — already the adapter contract. *CDD-repo development
   only*: the gates' tools; a missing one fails its gate (ADR 0013). *Silent equivalent*: the
   fallback behaves identically, so silence is correct. There is no "silently does less" posture.
   The per-tool assignment for this repo lives in `doc/knowledge_base/engineering-practices.md`.
2. **The required set is `git`, bash >= 4, `claude` and `jq`.** `claude` and `jq` are required,
   not loud-skip: both are fundamental to the workflow's mechanics, and a loud skip on every
   command is a nag the user learns to ignore while the workflow still runs reduced. This
   supersedes, on this point only, the jq-absent misses in process doc §2.13, ADR 0006 and ADR
   0008. The state record itself stays advisory *in content*: an absent or stale record is still a
   quiet fallback, and writers still never fabricate one.
3. **Install fails, it does not warn.** `cdd-state install`, `cdd-worktree install` and the
   bootstrap script refuse before writing anything: install is the one moment a human is
   watching, and the fix is cheap then. At runtime each helper command checks the tools it uses
   before any side effect — `cdd-worktree` checks `claude` before it creates the worktree. The
   check is one block of shell, duplicated byte-for-byte in both helpers (they install and run
   independently, so neither may source the other) and held identical by a gate.
4. **Every project carries an install-dependencies script.** The template ships
   `scripts/install-deps.sh`: check first, install only what is missing (apt-get on Ubuntu,
   Homebrew on macOS, `claude` through Anthropic's native installer, never under sudo; never
   installing Homebrew or a third-party apt repository). It is split into a CDD-owned part and a
   project block that `/cdd-bootstrap` and `/cdd-retrofit` fill with the bound adapters' tools and
   the project's toolchain, so `/cdd-retrofit`'s three-way merge carries a change to CDD's
   required set to existing projects. Rejected: generating the script per project from a spec (a
   change to CDD's part would never reach a project already bootstrapped); a Brewfile (on Ubuntu
   it needs Linuxbrew and a C toolchain first, where apt is already there); mise (one more tool to
   install before anything else, and it cannot install the host's bash or `claude`); a
   devcontainer (needs a container runtime, while CDD's helpers live in the host's shell and
   `~/.cdd`).
5. **The installer is tested by its own workflow, not a runner gate.** A path-filtered workflow
   runs it on fresh Ubuntu and macOS runners, twice (the second run must install nothing), when it
   or the workflow changes. This is a deliberate exception to "the runner is the sole gate list"
   (§2.14, ADR 0013): the test installs packages on the host, so it cannot run in a local
   `./scripts/ci.sh`, and the script rarely changes. The runner stubs `claude` on PATH for every
   gate, so no gate needs — or ever runs — the real CLI.
6. **A `posture` gate keeps the declaration honest.** Every `command -v` under `tools/` carries a
   `# posture:` tag naming its posture, so a new probe's posture is a decision, not an accident;
   the gate also holds the two helpers' required-tools blocks identical and this repo's
   install-deps script equal to the template's outside its project block.

## Consequences

- A machine missing `jq` or `claude` gets a stop with the fix, instead of a workflow that quietly
  does less. The cost: a user who never needed the record's features now has to install `jq`.
- Every gate that runs `install` or the bootstrap script needs `jq` (and finds the runner's
  `claude` stub); the jq-absent fallbacks and their tests are gone.
- A plain non-interactive bootstrap (and the demo instance) gets an unfilled project block in
  `scripts/install-deps.sh`; `template/BOOTSTRAP.md` tells the user to fill it. The commands fill
  it; the bootstrap script does not, to keep the substitution pipeline free of per-binding logic.
- `gh` on Ubuntu is not installed by the script: Ubuntu's own package is too old to work, and
  adding GitHub's apt repository means trusting a third-party key automatically. The script
  prints GitHub's install steps and fails instead.
- The installer workflow runs only when the script changes, so a runner-image change that breaks
  it surfaces at the next change to the script, not before.
