# <PROJECT_NAME> — Project Overview

The project's charter: what it is, why it exists, and where its boundaries sit. A fresh session
reads this first, before descending into the architecture and feature docs. Keep it **current** —
unlike decision records and investigation notes, this document is not append-only; update it as the
project's scope and constraints evolve.

## What it is

<One paragraph: what this project is, in plain terms. The same description as the opening line of
CLAUDE.md, expanded to a paragraph.>

## Goals

<Why this project exists — the problem it solves or the outcome it produces. A few bullets or a
short paragraph. What does success look like?>

## What it does

<The high-level capabilities, from a user/consumer perspective. Bulleted, coarse-grained — not a
feature list (that lives in `doc/features/`), just enough to convey the shape of the thing.>

## What it explicitly does not do

<The non-goals: things a reader might reasonably expect this project to do but that are deliberately
out of scope. This section is load-bearing — it prevents scope creep and tells a future session
where to stop.>

## Constraints

<The constraints that shape decisions: language/platform, hard technical limits, regulatory or
business constraints, compatibility requirements, deadlines. The highest-frequency coding rules go
in CLAUDE.md's "Critical constraints"; this section captures the broader, project-defining ones.>

## Architecture intentions

<The intended high-level shape: major components, how they relate, where the boundary with external
systems sits, and any structural principles the project commits to. This is intent, written early;
the living structural description grows in `doc/architecture/` as the project takes form. Point
there once it exists.>

## Audience

<Who consumes this project — end users, other services, a team, future-you. Shapes what "done" and
"good" mean.>
