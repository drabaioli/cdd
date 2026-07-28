#!/usr/bin/env bash
# Contract checks for scripts/ci.sh, the check runner (issue #36).
#
# It tests the runner's own behaviour, not the gates it runs — the real gates are
# exercised by running the runner itself. It asserts:
#   1. `ci.sh list` is non-empty and every slug resolves to a gate_<slug> function,
#      so the registry and the functions cannot drift apart.
#   2. An unknown gate name is rejected (non-zero) and the known slugs are listed.
#   3. A gate whose tool is missing reports SKIP and still exits 0 — the
#      degrade-gracefully decision behind #36, which must never regress into a
#      silent pass or a hard failure.
#   4. The workflow delegates: every `run:` line in template-smoke.yml invokes
#      scripts/ci.sh, so a gate cannot be re-added to YAML behind the runner's back.
#   5. The syntax gate checks *every* script in scope, not just the first. This is
#      not hypothetical: `bash -n a.sh b.sh` parses only a.sh and turns the rest
#      into positional parameters, so the pre-runner CI's `bash -n scripts/*.sh`
#      was checking a single file and passing regardless of the others. Pinned by
#      dropping a deliberately broken script into the lint scope and requiring the
#      gate to fail.
#   6. `-h` prints the header block and stops there. The runner documents its own
#      usage by echoing its header, so the extraction must not run on into the
#      section comments further down the file.
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

# --- 3. Missing tool -> loud SKIP, exit 0 ------------------------------------
# Stand in an empty bin dir as the whole PATH except the interpreters the runner
# needs, so the `needs` tool genuinely cannot be found. `shellcheck` is the gate
# whose tool is most often absent on a contributor's host, and the reason the
# skip path exists at all.
STUB_HOME="$(mktemp -d)"
trap 'rm -rf "$STUB_HOME"' EXIT
mkdir -p "$STUB_HOME/bin"
for tool in bash env sed grep mktemp rm cat git mkdir printf; do
  src="$(command -v "$tool" 2>/dev/null)" || continue
  ln -sf "$src" "$STUB_HOME/bin/$tool"
done

skip_out="$(PATH="$STUB_HOME/bin" "$(command -v bash)" "./$RUNNER" shellcheck 2>&1)"
skip_status=$?
[[ $skip_status -eq 0 ]] \
  || fail "a gate with a missing tool exited $skip_status; the skip must be non-fatal"
grep -q 'SKIP shellcheck' <<<"$skip_out" \
  || fail "missing-tool run did not report 'SKIP shellcheck': $skip_out"
grep -q 'SKIPPED: shellcheck' <<<"$skip_out" \
  || fail "missing-tool run did not repeat the skip in the closing line: $skip_out"
pass "missing tool reports a loud SKIP and exits 0"

# --- 4. The workflow delegates, holding no gate list of its own --------------
mapfile -t run_lines < <(grep -nE '^[[:space:]]*run:' "$WORKFLOW")
[[ ${#run_lines[@]} -gt 0 ]] || fail "$WORKFLOW has no run: step"
for line in "${run_lines[@]}"; do
  grep -qF 'scripts/ci.sh' <<<"$line" \
    || fail "$WORKFLOW runs something other than the check runner: $line"
done
[[ ${#run_lines[@]} -eq 1 ]] \
  || fail "$WORKFLOW has ${#run_lines[@]} run: steps; the runner should be the only one"
pass "workflow delegates to $RUNNER and holds no gate list"

# --- 5. The syntax gate covers every script in scope --------------------------
# The probe lives in the lint scope (scripts/*.sh) on purpose — that is the only
# way to prove the gate looks past the first file. Named so a stray copy is
# obvious, refused if it already exists, and removed by the trap either way.
PROBE="scripts/zz-ci-runner-assert-probe.sh"
[[ -e "$PROBE" ]] && fail "probe path already exists, refusing to overwrite: $PROBE"
trap 'rm -rf "$STUB_HOME"; rm -f "$PROBE"' EXIT

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
pass "-h prints the header block and stops there"

echo "ci runner contract: clean"
