# <PROJECT_NAME> Architecture Overview

## The shape: render → actions pipeline → outputs

Markdown Renderer is a single small Flask app with one core data flow:

```
raw Markdown
   │  markdown.markdown()  (HTML escaping on)
   ▼
rendered HTML
   │  ACTIONS = [action_1, action_2, …]   (ordered post-processors)
   ▼
one output per action
   ├─ CopyRenderedAction      → text/html on the clipboard
   ├─ CopyEmailSafeAction     → inline_styles(html) → clipboard   (Phase 2)
   ├─ ExportStandaloneAction  → downloadable .html (<style> block) (Phase 3)
   └─ ExportEmailAction       → inline_styles(html) → downloadable .html (Phase 3)
```

The **actions pipeline** is the central structural idea. `ACTIONS` is a single ordered registry; each action declares a button label and a function that turns the rendered HTML into one user-facing output. The UI iterates the registry to render the toolbar, so adding an output means adding one registry entry and one button — never a new bespoke route. This is the seam every roadmap phase past Phase 1 extends, and the reason Phases 2 and 3 (built in parallel) edit the same registry region and the same toolbar region.

## Key interfaces

- **`ACTIONS` registry** (`app/`): the ordered list of actions. New actions are inserted into the existing region of this list.
- **`inline_styles(html)`** (`app/`, lands in Phase 2): rewrites the preview's `<style>`-based formatting into inline `style="..."` attributes. Email clients strip `<style>` blocks, so any output bound for email must pass through this. Phase 3's `ExportEmailAction` depends on it.
- **`<div class="actions">` toolbar** (`app/templates/`): one button per registered action; the shared UI region both Phase 2 and Phase 3 add buttons to.
- **Clipboard write** (`app/static/`, client-side JS): writes a `ClipboardItem` with a `text/html` part and a `text/plain` fallback. The server produces HTML; the browser owns the clipboard.

## External boundaries

- **Browser clipboard** — the only way to get real rich text onto the system clipboard; server-side code never touches it.
- **Filesystem (downloads)** — export actions stream a generated `.html` file to the browser.
- No database, no network calls out, no auth. State is per-request.

## What belongs here

- Module boundaries and responsibilities; the pipeline contract.
- Data flow and key interfaces (`ACTIONS`, `inline_styles`, the toolbar, the clipboard write).
- External boundaries (clipboard, filesystem).

## What does not belong here

- **User-visible behaviour**: that goes in `doc/features/`.
- **Decision rationale** (e.g. why a library parser): `doc/knowledge_base/` as a decision record.
- **Coding style**: the coding standard under `doc/knowledge_base/`.

## Maintenance

When a change in code alters anything described here, update the relevant doc in the same PR. `/pre-pr` will surface discrepancies, but the implementation session should keep this in mind during the change itself.
