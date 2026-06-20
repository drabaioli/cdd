# <PROJECT_NAME> — Claude Code Context

Markdown Renderer is a small local web app: paste Markdown into a box, see it rendered live, and **copy the rendered result as rich text** so it pastes formatted (sized headings, bold/italic, lists) into Gmail, Google Docs, or Word — not as raw `# Heading` source. The motivating use case is getting Markdown out of Claude Code and wanting formatted text in documents and emails. It is explicitly **not** a general CMS, a static-site generator, or a Markdown editor; it renders and hands off, nothing more.

## Key references

| Topic                            | Location                                          |
| -------------------------------- | ------------------------------------------------- |
| System architecture & design     | `doc/architecture/` (start with `index.md`)       |
| Feature documentation            | `doc/features/` (start with `index.md`)           |
| Implementation roadmap           | `doc/knowledge_base/roadmap.md`                   |
| Engineering practices            | `doc/knowledge_base/engineering-practices.md`     |
| Design decisions                 | `doc/knowledge_base/` (decision records)          |

**Read `doc/architecture/` before planning any feature or structural change.**
**Read `doc/features/` before changing user-visible behaviour.**
Keep architecture and feature docs current as part of every change.

## Critical constraints (quick reference)

- Python 3.11+. Backend is Flask; keep it to a single small app — no blueprints or ORM.
- Markdown→HTML parsing uses the `markdown` library. Do **not** hand-roll a parser; the product value is in the post-render actions, not parser internals.
- **Always escape user text.** Markdown bodies can contain `<`, `>`, `&`, and raw HTML. Render with HTML escaping on so pasted source cannot inject markup. This is the most common review catch.
- **Email-safe means inline CSS.** Email clients strip `<style>` blocks, so any "email" output must carry styling as inline `style="..."` attributes (see `inline_styles()` from Phase 2). A `<style>` block is fine for the on-screen preview, never for email output.
- Rich-text copy uses the browser Clipboard API: write a `ClipboardItem` with a `text/html` part (and a `text/plain` fallback). Server never touches the clipboard.
- New output formats are added as **actions** in the pipeline, not as ad-hoc routes. See the architecture doc.

## Build & test

```bash
pip install -r requirements.txt        # build / install deps
flask --app app run --debug            # run the app locally
pytest                                 # unit + render tests
pytest tests/integration               # integration tests (render → action output)
python -m pyflakes app                 # lint
black --check app tests                # format check
```

## Module layout

| Directory        | Purpose                                                            |
| ---------------- | ------------------------------------------------------------------ |
| `app/`           | Flask app: routes, render entry point, the actions pipeline        |
| `app/actions/`   | One module per action (copy-rendered, email-safe copy, export, …)  |
| `app/templates/` | The single-page UI (paste box, live preview, actions toolbar)      |
| `app/static/`    | Preview CSS and client-side clipboard/copy JavaScript              |
| `tests/`         | Unit tests (render, escaping, each action) + `tests/integration/`  |

## Architecture

A render request flows: raw Markdown → `markdown.markdown()` → an ordered **actions pipeline** (`ACTIONS = [...]`) of post-processors that each produce one user-facing output (rendered HTML for preview, email-safe HTML, downloadable files). The single-page UI renders one toolbar button per registered action inside `<div class="actions">`. The email-safety transform `inline_styles()` rewrites `<style>`-based formatting into inline `style="..."` attributes so output survives email clients.

See `doc/architecture/index.md` for the full picture.

## Workflow

This project uses the Claude-Driven Development workflow.

- **Before opening a PR**: run `/cdd-pre-pr` to verify CI gates pass and that architecture/feature docs and the roadmap reflect the change.
- **To start a new task**: run `/cdd-next-step` from the main worktree to produce a handoff, then run `<PROJECT_SLUG>-worktree <branch>` to spin up the implementation worktree.
- **When main has advanced under a feature branch**: run `/cdd-merge-base` from the feature branch.
- Keep `doc/architecture/`, `doc/features/`, and this file current as part of every change.
