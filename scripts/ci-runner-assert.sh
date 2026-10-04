#!/usr/bin/env bash
# Contract checks for scripts/ci.sh, the check runner (issue #36).
#
# It tests the runner's own behaviour, not the gates it runs — the real gates are
# exercised by running the runner itself. It asserts:
#   1. `ci.sh list` is non-empty and every slug resolves to a gate_<slug> function,
#      so the registry and the functions cannot drift apart.
#   2. An unknown gate name is rejected (non-zero) and the known slugs are listed.
#   3. A gate whose tool is missing FAILs, naming the tool, while the other gates
#      still run — a missing tool is a failure, never a skip, so a host without one
#      cannot report green over checks that never ran. And no gate script carries a
#      self-skip of its own (an `echo "skip: ..."` path), which would be the same
#      silent pass one level down.
#   4. The workflow delegates: exactly one `run:` line in template-smoke.yml
#      invokes scripts/ci.sh, and every other is an install-only setup step (a
#      package install naming no repo script), so a gate cannot be re-added to YAML
#      behind the runner's back. Its matrix names an Ubuntu and a macOS runner —
#      the two tool families (issue #107) — and the runner's bash >= 4 guard
#      precedes its first bash-4 construct.
#   5. The syntax gate checks *every* script in scope, not just the first. This is
#      not hypothetical: `bash -n a.sh b.sh` parses only a.sh and turns the rest
#      into positional parameters, so the pre-runner CI's `bash -n scripts/*.sh`
#      was checking a single file and passing regardless of the others. Pinned by
#      dropping a deliberately broken script into the lint scope and requiring the
#      gate to fail.
#   6. `-h` prints the header block and stops there, from any working directory.
#      The runner documents its own usage by echoing its header, so the extraction
#      must not run on into the section comments further down the file — nor break
#      when invoked by a relative path from elsewhere, since it cd's to the repo
#      root before reading itself back.
#   7. Gates are isolated: a gate cannot leak a shell variable or a cd into a
#      later gate. They are declared independent, and the runner enforces that by
#      running each in a subshell — asserted so the enforcement is a property of
#      the contract rather than an accident of how the per-gate logs are teed.
#
# Sets CDD_CI_SELFTEST so the runner's own `runner` gate does not re-enter this
# script when the full suite runs.
#
# Usage: scripts/ci-runner-assert.sh   (no arguments; no side effects outside $TMPDIR)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

RUNNER="scripts/ci.sh"
WORKFLOW=".github/workflows/template-smoke.yml"

export CDD_CI_SELFTEST=1

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[[ -x "$RUNNER" ]] || fail "runner not found or not executable: $RUNNER"
[[ -f "$WORKFLOW" ]] || fail "workflow not found: $WORKFLOW"

# --- 1. Registry and gate functions agree ------------------------------------
mapfile -t slugs < <("./$RUNNER" list)
[[ ${#slugs[@]} -gt 0 ]] || fail "$RUNNER list printed no gates"

for slug in "${slugs[@]}"; do
  fn="gate_${slug//-/_}"
  grep -qE "^${fn}\(\) \{" "$RUNNER" \
    || fail "gate '$slug' has no ${fn}() function in $RUNNER"
done
pass "${#slugs[@]} gates listed, each with a matching gate function"

# Every gate_* function in the script is also in the registry (no orphans).
while IFS= read -r fn; do
  slug="${fn#gate_}"
  slug="${slug//_/-}"
  printf '%s\n' "${slugs[@]}" | grep -qxF -- "$slug" \
    || fail "orphan function ${fn}() in $RUNNER: '$slug' is not in the gate registry"
done < <(grep -oE '^gate_[a-z_]+\(\)' "$RUNNER" | sed 's/()$//')
pass "no orphan gate functions"

# --- 2. Unknown gate is rejected ---------------------------------------------
if out="$("./$RUNNER" definitely-not-a-gate 2>&1)"; then
  fail "$RUNNER accepted an unknown gate name"
fi
grep -q 'unknown gate' <<<"$out" || fail "unknown-gate error message missing: $out"
grep -q 'known gates' <<<"$out" || fail "unknown-gate error did not list the known gates"
pass "unknown gate name rejected, known gates listed"

# --- 3. Missing tool -> FAIL, the rest still run --------------------------------
# Stand in a bin dir holding only the tools the runner itself needs as the whole PATH,
# so the `needs` tool genuinely cannot be found. `shellcheck` is the gate whose tool is
# most often absent on a contributor's host. `syntax` rides along to prove the run is
# not cut short: a missing tool fails its own gate and nothing else.
STUB_HOME="$(mktemp -d)"
trap 'rm -rf "$STUB_HOME"' EXIT
mkdir -p "$STUB_HOME/bin"
for tool in bash env sed grep mktemp rm cat git mkdir printf tee sort tr tail dirname basename; do
  src="$(command -v "$tool" 2>/dev/null)" || continue
  ln -sf "$src" "$STUB_HOME/bin/$tool"
done

miss_out="$(PATH="$STUB_HOME/bin" "$(command -v bash)" "./$RUNNER" shellcheck syntax 2>&1)"
miss_status=$?
[[ $miss_status -ne 0 ]] \
  || fail "a gate with a missing tool let the run exit 0; a missing tool must fail it: $miss_out"
grep -q 'FAIL shellcheck — shellcheck is not installed' <<<"$miss_out" \
  || fail "missing-tool run did not report 'FAIL shellcheck — shellcheck is not installed': $miss_out"
grep -q 'PASS syntax' <<<"$miss_out" \
  || fail "a missing tool cut the run short: the syntax gate did not run and pass: $miss_out"
grep -q '2 gate(s): 1 passed, 1 failed — missing tools: shellcheck' <<<"$miss_out" \
  || fail "the closing line did not name the missing tool: $miss_out"
pass "missing tool fails its gate, is named in the closing line, and the other gates still run"

# A gate script that tests for its own tool and exits 0 on "skip:" is the same silent pass
# one level down, and reachable whenever the script runs standalone.
self_skips="$(grep -nE '(echo|printf)[^#]*["'"'"']skip:' scripts/*.sh | grep -v '^scripts/ci-runner-assert\.sh:' || true)"
[[ -z "$self_skips" ]] \
  || fail "gate scripts must fail on a missing tool, not skip:"$'\n'"$self_skips"
pass "no gate script carries a self-skip"

# --- 4. The workflow delegates, holding no gate list of its own --------------
# Exactly one run: step invokes the runner; any other must be an install-only setup
# step (a package install, naming no repo script), so no gate can hide in one.
mapfile -t run_lines < <(grep -nE '^[[:space:]]*run:' "$WORKFLOW")
[[ ${#run_lines[@]} -gt 0 ]] || fail "$WORKFLOW has no run: step"
runner_steps=0
for line in "${run_lines[@]}"; do
  if grep -qF 'scripts/ci.sh' <<<"$line"; then
    runner_steps=$((runner_steps + 1))
    continue
  fi
  grep -qE '^[0-9]+:[[:space:]]*run:[[:space:]]+(brew install|sudo apt-get install)[[:space:]]' <<<"$line" \
    || fail "$WORKFLOW runs something other than the check runner or a package install: $line"
  grep -qE 'scripts/|tools/|demo/' <<<"$line" \
    && fail "$WORKFLOW setup step names a repo script: $line"
done
[[ $runner_steps -eq 1 ]] \
  || fail "$WORKFLOW invokes $RUNNER from $runner_steps run: steps; it should be exactly one"
pass "workflow delegates to $RUNNER and holds no gate list"

# Both tool families stay in CI: an Ubuntu (GNU, gawk) and a macOS (BSD, BWK awk)
# runner, so a host-tool difference fails the PR (issue #107).
os_line="$(grep -E '^[[:space:]]*os:' "$WORKFLOW")"
[[ "$os_line" == *ubuntu-* && "$os_line" == *macos-* ]] \
  || fail "$WORKFLOW matrix must name an ubuntu- and a macos- runner; got: ${os_line:-<no os: line>}"
pass "workflow matrix runs on Ubuntu and macOS"

# The bash >= 4 guard sits before the runner's first bash-4 construct, or on bash 3.2
# (stock macOS) it would never get the chance to explain itself.
# awk, not `grep | head -n 1`: head exiting early can SIGPIPE grep, fatal under pipefail.
guard_at="$(awk '/BASH_VERSINFO/ { print NR; exit }' "$RUNNER")"
mapfile_at="$(awk '/^[^#]*mapfile/ { print NR; exit }' "$RUNNER")"
[[ -n "$guard_at" && -n "$mapfile_at" && "$guard_at" -lt "$mapfile_at" ]] \
  || fail "$RUNNER's bash >= 4 guard (line ${guard_at:-none}) must precede its first mapfile (line ${mapfile_at:-none})"
pass "bash >= 4 guard precedes the first bash-4 construct"

# --- 5. The syntax gate covers every script in scope --------------------------
# The probe lives in the lint scope (scripts/*.sh) on purpose — that is the only
# way to prove the gate looks past the first file. Named so a stray copy is
# obvious, refused if it already exists, and removed by the trap either way.
PROBE="scripts/zz-ci-runner-assert-probe.sh"
[[ -e "$PROBE" ]] && fail "probe path already exists, refusing to overwrite: $PROBE"
ISO_PROBE="scripts/zz-ci-runner-assert-iso.sh"
trap 'rm -rf "$STUB_HOME"; rm -f "$PROBE" "$ISO_PROBE"' EXIT

# Sorts last in scripts/*.sh, so only a gate that checks every file will see it.
printf '#!/usr/bin/env bash\nif true; then\n' > "$PROBE"
if "./$RUNNER" syntax >/dev/null 2>&1; then
  fail "the syntax gate passed with a broken script in scope ($PROBE) — it is checking only some files"
fi
rm -f "$PROBE"
"./$RUNNER" syntax >/dev/null 2>&1 \
  || fail "the syntax gate fails on a clean tree once the probe is removed"
pass "syntax gate covers every script in scope"

# --- 6. -h prints the header block, and only that ------------------------------
help_out="$("./$RUNNER" -h 2>&1)"
help_status=$?
[[ $help_status -eq 0 ]] || fail "$RUNNER -h exited $help_status"
grep -q '^Usage:' <<<"$help_out" || fail "$RUNNER -h printed no Usage: section"
grep -q '^!' <<<"$help_out" && fail "$RUNNER -h leaked the shebang line"
grep -q '^--- ' <<<"$help_out" \
  && fail "$RUNNER -h ran past the header into the script's section comments"

# ...and from any working directory. The runner cd's to the repo root before it
# extracts its own header, so reading it back through $BASH_SOURCE would break on
# a relative invocation path from elsewhere (sed: can't read ./…/scripts/ci.sh).
rel_out="$(cd "$(dirname "$REPO_ROOT")" && "./$(basename "$REPO_ROOT")/$RUNNER" -h 2>&1)"
grep -q '^Usage:' <<<"$rel_out" \
  || fail "$RUNNER -h via a relative path from another cwd printed no header: $rel_out"
pass "-h prints the header block and stops there, from any cwd"

# --- 7. A gate cannot leak shell state into the runner or a later gate --------
# Gates are declared independent ("nothing cascades"), and the runner enforces that by
# running each one in a pipeline subshell -- a side effect of teeing to a per-gate log,
# which would be a silent trap if it were only a side effect: a gate that set a variable
# for a later gate, or cd'd somewhere the runner then depended on, would fail in a way no
# test would catch. So the isolation is asserted here, which turns an accident of the
# implementation into a property of the contract. If someone later replaces the pipeline
# with a form that runs gates in the current shell, this fails and says why.
#
# Behavioural, not a grep for `| tee`: what matters is the isolation, not how it is
# achieved. A copy of the runner carries two injected gates -- the first dirties the shell
# (sets a variable, changes directory), the second reports what it can see. The copy lives
# in scripts/ because the runner resolves REPO_ROOT from its own path and cd's there.
[[ -e "$ISO_PROBE" ]] && fail "probe path already exists, refusing to overwrite: $ISO_PROBE"
awk -f - "$RUNNER" > "$ISO_PROBE" <<'INJECT'
/^main "\$@"$/ {
  print "gate_iso_a() { ISO_LEAK=leaked; cd / || return 1; }"
  print "gate_iso_b() { echo \"ISO_VAR:${ISO_LEAK:-unset}\"; echo \"ISO_CWD:$PWD\"; }"
  print ""
}
{ print }
/^GATES=\($/ {
  print "  \"iso-a||probe: dirty the shell\""
  print "  \"iso-b||probe: report what leaked\""
}
INJECT
chmod +x "$ISO_PROBE"
iso_out="$("./$ISO_PROBE" iso-a iso-b 2>&1)"
grep -qF "ISO_VAR:unset" <<<"$iso_out" \
  || fail "a gate's shell variable leaked into the next gate (gates must be isolated); got: $iso_out"
grep -qF "ISO_CWD:$REPO_ROOT" <<<"$iso_out" \
  || fail "a gate's cd leaked into the next gate, which must start at the repo root; got: $iso_out"
rm -f "$ISO_PROBE"
pass "a gate cannot leak a variable or a cd into a later gate"

echo "ci runner contract: clean"
