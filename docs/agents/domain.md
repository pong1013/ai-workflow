# Domain Docs

How the engineering Skills consume this repository's domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repository root when present.
- `CONTEXT-MAP.md` when present, followed by the context files relevant to the task.
- ADRs under `docs/adr/` that affect the area being changed.

If these files do not exist, proceed silently. `$domain-modeling` creates them lazily only when a project-specific term or durable architectural decision actually settles.

## Layout

This repository is single-context. Use one root `CONTEXT.md` and system-wide ADRs under `docs/adr/`. Do not create a context map without a separately approved multi-context design.

Use glossary vocabulary in issues, tests, reviews, and implementation. Surface conflicts with an existing ADR rather than silently overriding it.
