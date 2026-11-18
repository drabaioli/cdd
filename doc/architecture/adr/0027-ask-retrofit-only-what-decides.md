# 0027: Ask a retrofit upgrade only what decides

**Status:** Accepted

## Context

An upgrade 18 CDD commits behind took six prompts after the batch (issue #161), most of them
asking nothing the user had to decide:

- `CLAUDE.md` went per file, as every both-changed project-owned file does (ADR 0016), though the
  template's change sat entirely in CDD's own sections (Workflow, Talking to the human, Writing
  changes), which the project had not touched.
- A hunk moved out of `cdd-pre-pr.md` left "`/cdd-pre-pr` step 2" references stale in two
  knowledge-base docs, each then asked as its own item.
- One decision-policy change landing in two `index.md` files was asked twice.
- The two titles disagreed on `<PROJECT_NAME>`, which was asked.

## Decision

1. **CDD's sections of a project's `CLAUDE.md` are compared like a CDD-managed file.** For a
   both-changed `CLAUDE.md`, the file is split at its `## ` headings; each CDD section — listed in
   `/cdd-retrofit` — takes the main comparison table on its own: untouched by the project, it is
   upgraded in the batch; a clean merge is batched; a conflict, or a section the project deleted
   or renamed, is asked. The rest of the file keeps ADR 0016's project-owned rule. ADR 0016
   rejected auto-merging project-owned files because template skeleton text would land in the
   project's prose; CDD's sections carry no skeleton text, so that reason does not reach them.
   Headings are the boundary.
2. **A move carries its repoints.** An item that moves text lists the edits elsewhere that only
   repoint references to it; its approval covers them.
3. **One question, one prompt.** Items one answer would settle are asked together; the user may
   still answer them apart.

## Rejected alternatives

- The folder name breaking a `<PROJECT_NAME>` disagreement between the two titles: the only
  disagreement seen was one project whose roadmap kept a pre-CDD title, fixed by retitling it, and
  display names rarely equal folder slugs, so the rule would almost never fire.
- Deriving the CDD-section list from the template: it would need a marker in the shipped
  `CLAUDE.md`; an explicit list in the command needs none.
- Treating all of `CLAUDE.md` as CDD-managed: the alternative ADR 0016 rejected.
- Dropping the fourth-verdict prompt here: tracked by issue #148.

## Consequences

- A run like #161's asks four questions instead of six.
- A project's edit inside a CDD section is kept by the merge and assessed for upstreaming, like an
  edit to a shipped command.
- A renamed CDD heading reads as deleted, and is asked.
- A CDD section added to the template needs its heading added to `/cdd-retrofit`'s list.
- No checkpoint changes: retrofit sits outside the six (ADR 0016).
