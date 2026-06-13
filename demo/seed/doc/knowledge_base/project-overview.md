# <PROJECT_NAME> — Project Overview

The project's charter: what it is, why it exists, and where its boundaries sit. A fresh session
reads this first, before descending into the architecture and feature docs. Keep it **current** —
unlike decision records and investigation notes, this document is not append-only; update it as the
project's scope and constraints evolve.

## What it is

Markdown Renderer is a small local web app: paste Markdown into a box, see it rendered live, and
copy the rendered result as **rich text** so it pastes formatted — sized headings, bold/italic,
lists — into Gmail, Google Docs, or Word, rather than as raw `# Heading` source. It renders and
hands off; nothing more.

## Goals

- Get Markdown out of Claude Code (and other Markdown sources) and into emails and documents with
  its formatting intact, in two clicks.
- Make email-safe output a first-class result, not an afterthought — formatting that survives the
  `<style>`-stripping that email clients apply.
- Stay small and obvious: a single Flask app whose only interesting seam is the actions pipeline.
- Success looks like pasting Claude's Markdown answer in, clicking "Copy as rich text (email-safe)",
  and pasting formatted text straight into Gmail.

## What it does

- Renders pasted Markdown to HTML and shows a live preview.
- Copies the rendered HTML to the clipboard as rich text (`text/html` with a `text/plain` fallback).
- Produces email-safe output by rewriting `<style>`-based formatting into inline `style="..."`
  attributes.
- Exports standalone and email-ready `.html` files.
- Highlights fenced code blocks and offers light / dark / email themes.
- Ships an `mdr` CLI so terminal output can be piped straight through the tool.

## What it explicitly does not do

- It is **not** a general CMS, a static-site generator, or a Markdown *editor* — there is no
  document store, no authoring workflow, no persistence.
- It does not hand-roll a Markdown parser; parsing is delegated to the `markdown` library and the
  product value lives in the post-render actions.
- It does not run as a hosted multi-user service. It is a local, single-user tool.
- The server never touches the clipboard — rich-text copy is a browser Clipboard API concern.

## Constraints

- Python 3.11+; backend is Flask, kept to a single small app — no blueprints, no ORM.
- Markdown→HTML parsing uses the `markdown` library; no custom parser.
- **Always escape user text.** Markdown bodies can contain `<`, `>`, `&`, and raw HTML, and must
  render as literal text — never injected markup.
- **Email-safe means inline CSS.** A `<style>` block is fine for the on-screen preview, never for
  any output that leaves the browser for an email.
- New output formats are added as **actions** in the pipeline, not as ad-hoc routes.

## Architecture intentions

A render request flows: raw Markdown → `markdown.markdown()` → an ordered **actions pipeline**
(`ACTIONS = [...]`) of post-processors, each producing one user-facing output (preview HTML,
email-safe HTML, downloadable files). The single-page UI renders one toolbar button per registered
action inside `<div class="actions">`. The pipeline is the extension point: every later output is
one registry entry plus one button, never a bespoke route. The email-safety transform
`inline_styles()` is the shared helper that export and email-copy actions reuse. See
`doc/architecture/` for the living structural description as it grows.

## Audience

A single developer using the tool locally — primarily to move Claude Code's Markdown output into
emails and documents. "Done" and "good" are judged by whether formatted text lands correctly in
Gmail, Docs, and Word, not by breadth of Markdown features.
