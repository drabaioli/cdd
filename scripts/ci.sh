#!/usr/bin/env bash
# The check runner: the single source of this repo's gate sequence (issue #36).
#
# One script, two callers. `.github/workflows/template-smoke.yml` delegates to it
# (the workflow holds no gate list at all), and `/cdd-pre-pr` invokes the same
# command, so "it passed locally" means "it will pass CI". Adding a gate here is
# the only way to add one — there is no second list to keep in sync.
#
# Usage:
#   scripts/ci.sh                  run every gate, then print a summary
#   scripts/ci.sh <gate> [<gate>]  run only the named gates (the iteration path)
#   scripts/ci.sh list             print the gate slugs, one per line
#   scripts/ci.sh -h               this header
#
# Mechanics:
#   - Gate registry: GATES holds "slug|needs|description" in run order; each slug
#     has a matching gate_<slug> function (kebab slug -> snake function name).
#     scripts/ci-runner-assert.sh pins the two together so the list and the
#     functions cannot drift apart.
#   - Missing tools degrade gracefully. A gate whose `needs` tool is absent is
#     reported SKIP — loudly, in the summary *and* in the closing line — and never
#     fails the run. Host-direct by design: no container, no pinned toolchain.
#     The motivating case is `shellcheck` (GitHub's runners preinstall it, a
#     contributor's host may not); `jq` is the same story for the state-record
#     gates, which already self-skip internally but do so with exit 0 — invisibly.
#     (Note the deliberate backticks: an unquoted "shellcheck" opening a comment
#     line would be parsed as a shellcheck directive.)
#   - Not fail-fast: every gate runs, and the exit status is non-zero if any
#     FAILed. One run surfaces every problem. The gates are independent, so
#     nothing cascades.
#   - The lint gates glob tools/, scripts/, and demo/, so every script — including
#     this one — is inside its own syntax and shellcheck scope, and a newly added
#     script is covered without touching this file.
#   - Output folds into named groups under GitHub Actions (::group::) and into
#     plain banners elsewhere; a failure also emits an ::error:: annotation.
#   - Scratch space: one mktemp -d per run, removed on exit. Replaces the
#     /tmp/smoke paths the workflow used to hardcode. CDD_CI_TMPDIR overrides the
#     location and, deliberately, keeps it: that is the knob for inspecting what a
#     gate produced.
#   - git is made hermetic (GIT_CONFIG_SYSTEM/GIT_CONFIG_GLOBAL pointed at a
#     throwaway config, as ref-sync-assert.sh and gc-assert.sh already do), so the
#     bootstrap gates' scaffold commits need neither a preconfigured identity —
#     the workflow no longer sets one — nor the caller's signing config.
#   - The gates that bootstrap a real tree also get a throwaway HOME, so the
#     per-repo marker a bootstrap writes (~/.cdd/handoffs/<repo>/repo.json) lands
#     in the scratch dir instead of the caller's home.
#
# Architecture notes: doc/architecture/overview.md. Workflow altitude: process doc
# §2.14.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# --- Gate registry -----------------------------------------------------------
# "slug|needs|description", in run order. `needs` is a single command name that
# must be on PATH, or empty when the gate needs nothing beyond bash and git.
GATES=(
  "syntax||bash -n over every shell script"
  "shellcheck|shellcheck|shellcheck over every shell script"
  "drift||command-set drift: repo commands vs the rendered template"
  "seams||prompt-seam contracts between the repo's own prompts"
  "seams-contract||the prompt-seam checker's own contract (mutation-tested)"
  "roadmap-length||roadmap item length: the 200-char cap"
  "install-smoke||worktree/state helper install, against a throwaway HOME"
  "worktree-resume||worktree resume on an existing remote branch"
  "ref-sync|jq|refs/cdd/<branch> handoff + state round-trip"
  "gc|jq|worktree GC: reap merged tasks, keep scoped ones"
  "base-branch|jq|per-task base branch: seed, get, cut-from-base"
  "bootstrap||end-to-end bootstrap into a tmpdir"
  "bootstrap-camelcase||bootstrap with a CamelCase directory slug"
  "stage-render||render-only staging (--stage), no git tree"
  "snapshot-render|tar|render from an extracted template snapshot (--template-dir)"
  "demo-seed||demo instance via the seed overlay, no GitHub side effects"
  "runner||the check runner's own contract"
)

# The lint scope, one path per line. Globs, so it stays self-including: a newly
# added script is covered without editing this file.
lint_targets() {
  printf '%s\n' tools/*.sh scripts/*.sh demo/*.sh
}

# --- Gates -------------------------------------------------------------------
# Each gate is a function returning non-zero on failure. They may assume $TMP
# exists and that git is hermetic (see set_up_scratch).

gate_syntax() {
  # One invocation per file, deliberately: `bash -n a.sh b.sh` parses only a.sh
  # and passes the rest as positional parameters, so a multi-file invocation
  # silently checks just the first name. The pre-runner CI did exactly that
  # (`bash -n scripts/*.sh`) and was checking one file per line.
  local f status=0
  while IFS= read -r f; do
    bash -n "$f" || status=1
  done < <(lint_targets)
  return "$status"
}

gate_shellcheck() {
  # Unlike `bash -n`, this one does take a file list.
  local -a files
  mapfile -t files < <(lint_targets)
  shellcheck "${files[@]}"
}

gate_drift() {
  ./scripts/command-drift-check.sh
}

gate_seams() {
  ./scripts/prompt-seam-check.sh
}

gate_seams_contract() {
  ./scripts/prompt-seam-assert.sh
}

gate_roadmap_length() {
  ./scripts/roadmap-length-check.sh
}

gate_install_smoke() {
  ./scripts/install-smoke-assert.sh
}

gate_worktree_resume() {
  ./scripts/worktree-resume-assert.sh
}

gate_ref_sync() {
  ./scripts/ref-sync-assert.sh
}

gate_gc() {
  ./scripts/gc-assert.sh
}

gate_base_branch() {
  ./scripts/base-branch-assert.sh
}

# The three gates that bootstrap a real tree (both of these plus demo-seed) run with a
# throwaway HOME: a non-staged bootstrap writes the per-repo marker
# ~/.cdd/handoffs/<repo>/repo.json, and the runner must not leave markers for its own
# temp projects behind in the caller's home. The --stage gates write no marker.

# Assert that a non-staged bootstrap wrote the per-repo marker for $repo under the
# throwaway $home, pointing at $want. The bootstrap's writer is advisory end-to-end
# (it sources tools/cdd-state.sh and warns rather than failing), so without this the
# sourcing seam has no test: a rename fails the gate under `set -e`, but a silent
# no-op would pass. jq-gated exactly like the writer — no jq means no marker was
# written at all, which is the documented degradation, not a failure.
assert_repo_marker() {
  local home="$1" repo="$2" want="$3"
  local marker="$home/.cdd/handoffs/$repo/repo.json" got_ver got_name got_path
  if ! command -v jq >/dev/null 2>&1; then
    echo "skip: jq absent, so the bootstrap wrote no marker; assertion skipped (advisory)"
    return 0
  fi
  [[ -f "$marker" ]] || { echo "FAIL: bootstrap wrote no per-repo marker at $marker" >&2; return 1; }
  got_ver="$(jq -r '.schema_version' "$marker")"
  got_name="$(jq -r '.name' "$marker")"
  got_path="$(jq -r '.path' "$marker")"
  [[ "$got_ver|$got_name" == "1|$repo" ]] || {
    echo "FAIL: $marker {schema_version, name} = '$got_ver|$got_name', expected '1|$repo'" >&2
    return 1; }
  # Compare physical paths: git can hand back a symlink-resolved path while $TMP still
  # names the symlink, so a plain string compare would fail spuriously on such a host.
  [[ -d "$got_path" && "$(cd "$got_path" && pwd -P)" == "$(cd "$want" && pwd -P)" ]] || {
    echo "FAIL: $marker .path = '$got_path', expected '$want'" >&2
    return 1; }
  echo "per-repo marker: $marker -> $got_path"
}

gate_bootstrap() {
  HOME="$TMP/home" ./tools/bootstrap-cdd-project.sh \
    --name "Demo Project" \
    --path "$TMP/demo-project" \
    && ./scripts/template-smoke-assert.sh "$TMP/demo-project" \
    && assert_repo_marker "$TMP/home" demo-project "$TMP/demo-project" \
    && git -C "$TMP/demo-project" log --oneline
}

gate_bootstrap_camelcase() {
  HOME="$TMP/home" ./tools/bootstrap-cdd-project.sh \
    --name "My CamelCase Project" \
    --path "$TMP/MyProject" \
    && ./scripts/template-smoke-assert.sh "$TMP/MyProject"
}

gate_stage_render() {
  ./tools/bootstrap-cdd-project.sh --stage \
    --name "Stage Test" \
    --dir stage-test \
    --path "$TMP/stage-render" || return 1
  if [[ -d "$TMP/stage-render/.git" ]]; then
    echo "FAIL: --stage created a git tree" >&2
    return 1
  fi
  ./scripts/template-smoke-assert.sh "$TMP/stage-render"
}

gate_snapshot_render() {
  mkdir -p "$TMP/snapshot" || return 1
  git archive HEAD template | tar -x -C "$TMP/snapshot" || return 1
  ./tools/bootstrap-cdd-project.sh --stage \
    --name "Snapshot Test" \
    --dir snap-test \
    --template-dir "$TMP/snapshot/template" \
    --path "$TMP/snapshot-render" \
    && ./scripts/template-smoke-assert.sh "$TMP/snapshot-render"
}

gate_demo_seed() {
  local instance="mdr_demo_99" target
  target="$TMP/$instance"
  HOME="$TMP/home" ./demo/setup.sh "$instance" --base "$TMP" --local-only || return 1
  if grep -rnE '<PROJECT_(NAME|DIR)>' "$target"; then
    echo "FAIL: leftover placeholder tokens in the seeded instance" >&2
    return 1
  fi
  # The seeded roadmap carries the deliberate conflict seam the demo relies on.
  grep -q 'ACTIONS' "$target/doc/knowledge_base/roadmap.md" || return 1
  grep -q 'inline_styles' "$target/doc/knowledge_base/roadmap.md" || return 1
  echo "demo seed overlay is clean"
}

gate_runner() {
  # ci-runner-assert.sh invokes this script (for `list` and a single gate), so it
  # must not re-enter this gate. It sets CDD_CI_SELFTEST to mark the nested run.
  if [[ -n "${CDD_CI_SELFTEST:-}" ]]; then
    echo "skipping the runner gate inside the runner's own self-test"
    return 0
  fi
  ./scripts/ci-runner-assert.sh
}

# --- Runner ------------------------------------------------------------------

usage() {
  # The header block only: skip the shebang, stop at the first non-comment line.
  # A bare `grep '^#'` would also print every section comment further down as if
  # it were help text.
  #
  # Read via the repo-relative path, not $BASH_SOURCE: we have already cd'd to
  # $REPO_ROOT, so a relative invocation path (../cdd/scripts/ci.sh) would no
  # longer resolve from here.
  sed -n '2,/^[^#]/{ /^[^#]/q; s/^# \?//; p; }' scripts/ci.sh
}

# A slug is kebab-case; its gate function is snake_case.
fn_for_slug() { echo "gate_${1//-/_}"; }

registry_slugs() {
  local entry
  for entry in "${GATES[@]}"; do
    echo "${entry%%|*}"
  done
}

registry_has() {  # registry_has <slug>
  registry_slugs | grep -qxF -- "$1"
}

registry_needs() {  # registry_needs <slug> -> the required command, or empty
  local entry rest
  for entry in "${GATES[@]}"; do
    if [[ "${entry%%|*}" == "$1" ]]; then
      rest="${entry#*|}"
      echo "${rest%%|*}"
      return 0
    fi
  done
}

registry_desc() {  # registry_desc <slug>
  local entry
  for entry in "${GATES[@]}"; do
    [[ "${entry%%|*}" == "$1" ]] && { echo "${entry##*|}"; return 0; }
  done
}

set_up_scratch() {
  if [[ -n "${CDD_CI_TMPDIR:-}" ]]; then
    TMP="$CDD_CI_TMPDIR"
    mkdir -p "$TMP"
  else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
  fi

  # Hermetic git: the bootstrap gates commit, and must neither depend on nor be
  # perturbed by the caller's identity, signing, or default-branch settings.
  export GIT_CONFIG_SYSTEM=/dev/null
  export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
  cat > "$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	name = CDD Check Runner
	email = ci@example.com
[init]
	defaultBranch = main
[commit]
	gpgsign = false
[tag]
	gpgsign = false
EOF
}

group_begin() {  # group_begin <slug> <description>
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::group::$1 — $2"
  else
    echo
    echo "=== $1 — $2"
  fi
}

group_end() {
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::endgroup::"
  return 0
}

run_gates() {  # run_gates <slug>...
  local total=$#
  local slug needs desc started elapsed status log
  local -a summary=()
  local -a skipped=()
  local -a failed_logs=()
  local passed=0 failed=0

  for slug in "$@"; do
    needs="$(registry_needs "$slug")"
    desc="$(registry_desc "$slug")"

    if [[ -n "$needs" ]] && ! command -v "$needs" >/dev/null 2>&1; then
      echo "SKIP $slug — $needs is not installed (gate not run)"
      summary+=("$(printf '  %-4s  %-20s  %s' SKIP "$slug" "$needs not installed")")
      skipped+=("$slug ($needs)")
      continue
    fi

    group_begin "$slug" "$desc"
    started="$SECONDS"
    # Tee each gate to its own log as well as to the terminal. Live output alone is not
    # enough: a gate that fails once and then passes leaves nothing behind to read, and
    # a caller who piped this run through `tail` has already discarded the only copy —
    # which is exactly how one intermittent failure here had to be reverse-engineered
    # from a duration. PIPESTATUS[0] keeps the gate's own status; tee's is irrelevant.
    log="$TMP/gate-$slug.log"
    "$(fn_for_slug "$slug")" 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    elapsed=$((SECONDS - started))
    group_end

    if [[ $status -eq 0 ]]; then
      echo "PASS $slug (${elapsed}s)"
      summary+=("$(printf '  %-4s  %-20s  %s' PASS "$slug" "${elapsed}s")")
      passed=$((passed + 1))
    else
      echo "FAIL $slug (${elapsed}s, exit $status)"
      [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::error title=$slug failed::$desc (exit $status)"
      summary+=("$(printf '  %-4s  %-20s  %s' FAIL "$slug" "exit $status, ${elapsed}s")")
      failed_logs+=("$slug")
      failed=$((failed + 1))
    fi
  done

  echo
  echo "=== summary"
  printf '%s\n' "${summary[@]}"
  echo

  local line="$total gate(s): $passed passed, $failed failed, ${#skipped[@]} skipped"
  [[ ${#skipped[@]} -gt 0 ]] && line+=" — SKIPPED: ${skipped[*]}"
  echo "$line"

  # Repeat each failure's tail after the summary, so a failed run is legible without
  # scrolling back past every passing gate — and so a caller that keeps only the last
  # lines of this run still keeps the evidence. Set CDD_CI_TMPDIR to retain the full logs.
  if [[ ${#failed_logs[@]} -gt 0 ]]; then
    for slug in "${failed_logs[@]}"; do
      echo
      echo "--- $slug: last 20 lines (full log: $TMP/gate-$slug.log)"
      tail -n 20 "$TMP/gate-$slug.log" | sed 's/^/  /'
    done
    [[ -z "${CDD_CI_TMPDIR:-}" ]] && echo && \
      echo "note: gate logs live in a temp dir removed on exit; set CDD_CI_TMPDIR to keep them."
  fi

  [[ $failed -eq 0 ]]
}

main() {
  case "${1:-}" in
    -h|--help) usage; return 0 ;;
    list)      registry_slugs; return 0 ;;
  esac

  local -a selected=()
  if [[ $# -eq 0 ]]; then
    mapfile -t selected < <(registry_slugs)
  else
    local arg
    for arg in "$@"; do
      if ! registry_has "$arg"; then
        echo "error: unknown gate: $arg" >&2
        echo "known gates:" >&2
        registry_slugs | sed 's/^/  /' >&2
        return 2
      fi
      selected+=("$arg")
    done
  fi

  set_up_scratch
  echo "check runner: ${#selected[@]} gate(s), scratch dir $TMP"
  run_gates "${selected[@]}"
}

main "$@"
