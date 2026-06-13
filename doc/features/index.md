# CDD Repository Features

What this repo provides. This index is a pointer list — the content lives in the per-feature documents.

## Documents

- [The Claude-Driven Development process](process.md) — the documented human-in-the-loop workflow itself
- [The template](template.md) — copy-paste directory + bootstrap script, including the `/bootstrap` and `/retrofit` commands
- [The demo](demo.md) — the Markdown Renderer seed: visual demo of the task cycle + dogfooding greenfield

## Status

All three are usable. The process doc is complete enough to follow. The template + bootstrap script have been used to bootstrap the first downstream projects (`sprint-planning-automation-poc`, Markdown Renderer demo); friction surfaced from those uses has been folded back into the template and process doc. The manual sed recipe that was the known weak spot has been replaced by the non-interactive script and is CI-guarded.

See `doc/knowledge_base/roadmap.md` for the planned work.
