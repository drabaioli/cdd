# 0011: Bind adapters through a machine-global library

**Status:** Accepted

## Context

CDD ships capability adapters — the GitHub tracker and code host, and a Jira tracker — under
`tools/adapters/<capability>/<backend>.sh`, and a project uses one by committing an executable
at `.cdd/<capability>` ([ADR 0007](0007-extend-cdd-through-capability-adapters.md)). Until now
nothing wrote that file: `/cdd-bootstrap` and `/cdd-retrofit`, the two installers, left every
project on the built-in `gh` rung, and binding was a hand-made exec-wrapper.

That wrapper, as documented, did not survive leaving the machine it was written on. This repo
binds itself with relative symlinks into its own `tools/adapters/`, but a downstream project has
no `tools/adapters/`. The documented Jira form was `exec /path/to/cdd/tools/adapters/tracker/jira.sh`
— an absolute path into one machine's CDD checkout, committed into the project. A clone on a
second machine either finds nothing there, or finds a different checkout at a different version.

Two constraints bound the answer. ADR 0007 says an adapter's generic half "installs
machine-globally under §2.8's rules (newest wins, never pinned per project)". And the adapters'
own documentation explains why none of them installs as the **machine rung**
`~/.cdd/adapters/<capability>`: that rung binds every repository on the machine, and the
built-in rung already *is* GitHub, so a machine-rung GitHub adapter would change nothing while
destroying the "no adapter installed" baseline behaviour-neutrality is checked against.

## Decision

1. **The adapter code installs machine-globally, as a library.** `cdd-worktree.sh install`, run
   from a CDD checkout, copies every shipped adapter to
   `~/.cdd/tools/adapters/<capability>/<backend>.sh` beside the helpers — newest wins, nothing
   deleted. The library is **not a ladder rung**: nothing consults it unless a project's binding
   points at it, so installing it binds no project.

2. **The binding is a committed shim that names the backend.** `.cdd/<capability>` is a small
   script that execs `"$HOME/.cdd/tools/adapters/<capability>/<backend>.sh"`, exporting the
   non-secret coordinates a backend needs (Jira's site and project key). It carries no path to
   a CDD checkout and never a credential.

3. **A missing library is a broken adapter.** The shim exists, so the ladder resolves to it; on a
   machine without the library it exits 4 with the install command, and
   [ADR 0010](0010-code-host-rename-and-broken-adapter-rule.md)'s rule applies — one line, no
   lower rung, never a silent fall-through to `gh`. The resolver relays the shim's first stderr
   line so the install command reaches the user.

4. **The installers write the project rung only.** `bootstrap-cdd-project.sh` gains opt-in
   binding flags and is the only writer of a shim. `/cdd-bootstrap` asks where issues and code
   review live, offering GitHub as the default; `/cdd-retrofit` detects the backends from the
   target and proposes them, never overwriting an existing binding and writing nothing without
   approval. Neither writes the machine rung, which stays hand-installed, and neither asks for a
   secret. A backend CDD ships no adapter for gets no binding.

5. **GitHub projects are bound by default when GitHub is chosen, and the built-in rung stays.**
   Whether to drop the built-in `gh` fallback and require an adapter is a separate decision, not
   made here.

**Rejected.**

- *Vendoring the adapter body into `.cdd/`.* Portable, but it pins each project to the adapter
  version it was bootstrapped with — exactly what ADR 0007 rules out — and every fix would need
  a retrofit per project to reach it.
- *Installing into the machine rung.* It binds every repository on the machine at once, which is
  the objection the adapters' own documentation already records.
- *Bindings on by default in the script (a `--no-adapters` opt-out).* It would change every
  existing render path — retrofit's staged render, the smokes — and the installers are meant to
  ask, not assume.

## Consequences

- A bound project works from a fresh clone on any machine that has run the helper install once.
  The `adapter-bindings` gate asserts that, offline, from a clone on a second scratch `HOME`.
- A machine whose helper install predates the library stops on a bound capability until
  `cdd-worktree.sh install` is re-run. That is intended — the stop names the fix — and bootstrap
  and retrofit warn about it.
- A bound GitHub project now shows the helpers' one-line "using adapter" announcement where the
  built-in rung was silent. Behaviour is otherwise unchanged.
- The conformance checker cannot probe a downstream shim, since it runs with an empty `HOME`;
  the shims are covered by the `adapter-bindings` gate instead.
- `/cdd-retrofit` upgrade mode becomes the un-forking tool: a local prompt edit that swaps in
  another backend is classified "migrate into `.cdd/`", and one for a backend CDD ships no
  adapter for becomes a candidate new shipped adapter rather than a prompt change.
