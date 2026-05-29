# <PROJECT_NAME> Features

This directory describes **what the system does**, from a capability / user perspective. One doc per significant feature. Updated continuously as features are added or changed.

Audience: humans (users, future-you, future-collaborators) and Claude Code sessions that need to understand the contract a feature provides.

## Index

Features land roughly in roadmap order. Add a dedicated doc per feature as it ships.

- **Live preview** (Phase 1) — paste Markdown, see it rendered to HTML as you type. Surface: web UI. Input: Markdown text. Output: rendered preview pane. User text is HTML-escaped, so source containing `<`, `>`, `&`, or raw HTML renders literally.
- **Copy rendered** (Phase 1) — copy the rendered result to the clipboard as rich text (`text/html` with a `text/plain` fallback), so it pastes formatted into documents. Surface: toolbar button.
- **Copy as rich text (email-safe)** (Phase 2) — copy with CSS inlined via `inline_styles()`, so formatting survives email clients that strip `<style>` blocks. Surface: toolbar button.
- **Download standalone .html** (Phase 3) — download a self-contained HTML file (styling in a `<style>` block) suitable for viewing in a browser. Surface: toolbar button.
- **Download email-ready .html** (Phase 3) — download an HTML file with inline styles (via `inline_styles()`) suitable for importing into an email. Surface: toolbar button.
- **Syntax-highlighted code blocks** (Phase 4) — language-aware highlighting of fenced code, kept email-safe.
- **Themes** (Phase 5) — light / dark / email preview themes; the email theme is what export/copy targets.
- **`mdr` CLI** (Phase 6) — pipe Markdown on stdin to render + copy/open from the terminal.

## What belongs here

- For each feature: what it does, who consumes it, the surface (web UI button, CLI), inputs and outputs, observable failure modes.
- Behavioural contracts (e.g. "email-safe output carries inline styles, never a `<style>` block").

## What does not belong here

- **Internal structure** (the actions pipeline, `inline_styles` internals): `doc/architecture/`.
- **Implementation history or rationale**: `doc/knowledge_base/`.

## Maintenance

When a change in code alters user-visible behaviour, update or add the relevant feature doc in the same PR. New features get a new file; modifications to existing features get edits to the existing file. `/pre-pr` will surface discrepancies.
