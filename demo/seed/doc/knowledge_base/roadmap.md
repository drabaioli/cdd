# <PROJECT_NAME> Implementation Roadmap

Ordered implementation sequence for building Markdown Renderer — a local web app that renders pasted Markdown and copies the result as rich text into emails and documents. Each phase builds on the previous one. Phases are roughly sequential, but Phases 2 and 3 are deliberately designed to be built **in parallel** off `main` (see Phase 2/3 notes).

This file is the central artifact of the Claude-Driven Development workflow. It is simultaneously a plan, a progress log, and a context document for future sessions. See "Annotation conventions" below for what (and what not) to write next to a completed checkbox.

## Phase 1: Core render + preview + the actions pipeline

Stand up the Flask app, render Markdown to HTML with the `markdown` library, show a live preview, and ship the first action ("Copy rendered"). The defining architectural move of this phase is the **actions pipeline**: a single `ACTIONS = [...]` registry in Python and a matching `<div class="actions">` toolbar in the template. Every later output (email-safe copy, export, …) is added as one entry in that registry and one button in that toolbar — this is the seam the rest of the roadmap extends.

- [ ] Flask app with a paste box, a live preview pane, and a render route that calls `markdown.markdown()`.
- [ ] Define the actions pipeline: an `ACTIONS = [...]` registry where each action knows its button label and how to produce its output; render one toolbar button per action into `<div class="actions">`.
- [ ] Ship the first action, `CopyRenderedAction`: put rendered HTML on the clipboard as a `ClipboardItem` with a `text/html` part and a `text/plain` fallback.
- [ ] Escape user text so `<`, `>`, `&`, and raw HTML in the Markdown body render as literal text, not injected markup.
- [ ] Handle the obvious edge cases: empty input, nested emphasis (`***bold italic***`), and correct clipboard MIME on copy.

**Milestone:** paste Markdown, see it rendered live, click "Copy rendered", and paste formatted text into a document — with the actions pipeline in place for later outputs.

> **Review surface (intentional):** this phase carries the natural PR-review beats — HTML-escaping of `<` in text (injection), nested emphasis, empty input, and clipboard MIME handling. Expect a "comment + fix during review" pass before merge.

## Phase 2: Email-safe inline styling — *demo branch A, parallel with Phase 3*

Add an `inline_styles(html)` step that rewrites the preview's `<style>`-based formatting into inline `style="..."` attributes, because email clients strip `<style>` blocks and only inline styles survive. Expose it as a new action, "Copy as rich text (email-safe)".

- [ ] Implement `inline_styles(html)` in the app: walk the rendered HTML and push the relevant CSS onto each element as an inline `style="..."` attribute.
- [ ] Add `CopyEmailSafeAction` to the **`ACTIONS` registry**, inserted in the same region of the list the other actions live in (not appended on a fresh trailing line).
- [ ] Add its "Copy as rich text (email-safe)" button inside the **same `<div class="actions">` toolbar region**, next to the existing button.

**Milestone:** "Copy as rich text (email-safe)" produces HTML that pastes with formatting intact into Gmail.

> **Parallel-build note:** branch off `main` *after* Phase 1 merges, in its own worktree, at the same time as Phase 3. Both phases register a new action in the **same `ACTIONS` region** and add a button in the **same toolbar region** — editing the same lines, so the two branches are guaranteed to conflict on merge. Resolve it with `/cdd-merge-base` once one of them lands.

## Phase 3: Export to file — *demo branch B, parallel with Phase 2*

Add file exports: a self-contained "Download standalone .html" and an "Download email-ready .html". The email-ready export reuses Phase 2's `inline_styles()`.

- [ ] Implement `ExportStandaloneAction`: produce a standalone `.html` file (preview CSS in a `<style>` block) and offer it for download.
- [ ] Implement `ExportEmailAction`: produce an email-ready `.html` by running the rendered HTML through `inline_styles()` before download.
- [ ] Add both actions to the **`ACTIONS` registry** in the same region the other actions live in, and add their buttons in the **same `<div class="actions">` toolbar region**.

**Milestone:** both downloads work; the email-ready file opens with formatting intact when imported into an email.

> **Dependency + parallel-build note:** branch off `main` *after* Phase 1 merges, at the same time as Phase 2 (its own worktree). Because Phase 2 has not merged yet, **`inline_styles()` does not exist on this branch** — ship the standalone export and leave `ExportEmailAction` blocked on that helper. When Phase 2 merges and `main` advances, run `/cdd-merge-base` on this branch: it (a) resolves the `ACTIONS`/toolbar conflict with Phase 2 **and** (b) brings `inline_styles()` onto the branch so the email export can be finished. This is the moment `/cdd-merge-base` visibly does two jobs at once.

## Phase 4: Syntax-highlighted code blocks

- [ ] Highlight fenced code blocks (e.g. via the `markdown` library's `fenced_code` + `codehilite`, or Pygments), keeping the highlight CSS email-safe via `inline_styles()`.

**Milestone:** code blocks render with language-aware highlighting in both preview and email-safe output.

## Phase 5: Themes (light / dark / email)

- [ ] Add a theme selector (light, dark, email) that swaps the preview CSS; the "email" theme is the one `inline_styles()` targets for export/copy.

**Milestone:** the user can switch themes for the preview, and email output uses the email theme.

## Phase 6: `mdr` CLI

- [ ] A `mdr` command that reads Markdown on stdin, renders it, and copies/opens the result — so the user can pipe Claude Code's Markdown output straight through the tool.

**Milestone:** `claude ... | mdr` puts rendered, email-safe rich text on the clipboard from the terminal.

## Key principles

- **The pipeline is the extension point.** New outputs are actions in `ACTIONS` + a toolbar button, never bespoke routes.
- **Email-safe means inline styles.** Never rely on a `<style>` block for anything that leaves the browser for an email.
- **Escape first.** User-supplied Markdown is untrusted; escaping is not optional.
- **Library for parsing, effort on the product.** Keep the phases about styling, export, and CLI — not parser internals.

## Annotation conventions

The default is no annotation. Tick the box and stop.

Only add an inline annotation when a future session needs information that none of the other artifacts will carry — i.e. *not* in the commit, *not* in the PR description, *not* in the process / architecture / feature docs (which you should be updating as part of the same change). Typical cases: a deferred sub-item, a surprising caveat, a scope change.

If you do annotate, keep it to a single short clause. Do not restate what the task did or how it was implemented; that information already lives where readers will look for it.

```
- [x] <Task description> — <one short clause: deferred X / caveat Y / out-of-scope Z>
```
