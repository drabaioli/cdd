# Task: Drop the helper-install reminder from /cdd-next-step's output

## Branch
trim_next_step_install_reminder

## Roadmap reference
None — off-roadmap cleanup, intent-driven.

## Requirements
1. §8 of `.claude/commands/cdd-next-step.md` no longer prints the "If `cdd-worktree` or `cdd-state` is \"command not found\"…" block: the fenced output ends after the two `Next: cdd-worktree <branch>` lines.
2. The §8 lead-in parenthetical ("the install line is a static reminder — do **not** probe for the helper on every run; it's a once-per-machine setup the user ignores once done") goes too, since it describes only the removed block.
3. The identical edit lands in `template/.claude/commands/cdd-next-step.md`, symmetrically — the template copy differs only in the handoff path placeholder.
4. `./scripts/ci.sh` is green, `drift` and `seams` in particular.
5. No other file changes.

## Notes
- `/cdd-next-step` is the only command carrying this block (checked: the other
  "command not found" hits are `doc/architecture/shell-helpers.md`, `demo/lib.sh`, and
  `tools/cdd-worktree.sh`, all of which legitimately keep theirs). Nothing else to sweep.
- Removing it strands no one: the one-time install command is documented in `README.md`,
  `template/BOOTSTRAP.md`, and `doc/architecture/shell-helpers.md`. The loss is the inline
  recovery path, not the instructions.
- No seam check pins the block. The `Print the next command` heading it sits under *is*
  pinned by title in `scripts/prompt-seam-check.sh` and must stay.
- `cdd-next-step.md` is not in `scripts/command-drift-whitelist.txt`, so a one-sided edit
  fails the `drift` gate. Both copies, same change.
- Roadmap verdict: **no item**. This is a prompt-output trim, not evolving work that a
  future session would need to find. Do not add one.
