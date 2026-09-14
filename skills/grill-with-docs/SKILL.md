---
name: grill-with-docs
description: Stress-test a plan through $grilling while $domain-modeling records settled glossary terms and durable decisions. Use explicitly before specification when a repository should retain the resulting domain knowledge.
---

# Grill with Docs

Load and apply both [$grilling](../grilling/SKILL.md) and [$domain-modeling](../domain-modeling/SKILL.md). `$grilling` owns the design-tree interview; `$domain-modeling` challenges terminology and records only knowledge that actually settles.

Inspect the repository, configured domain docs, relevant code, `CONTEXT.md` or `CONTEXT-MAP.md`, and applicable ADRs before asking questions. Facts are the agent's job; decisions are the user's.

When called by `$ai-workflow`, use the established workspace and `write-project-knowledge` authority. Without that authority, preview any proposed knowledge mutation and obtain explicit approval. A template or `vibe-engineering-base` repository requires confirmation that knowledge is project-specific before writing inherited docs.

Do not write a specification, create tracker issues, implement code, or advance a Feature Run. Return settled decisions and terminology, changed glossary/ADR paths, unresolved frontier decisions, mutations, and `complete` or `blocked` status.

## Provenance

Adapted from Matt Pocock's `grill-with-docs`, `grilling`, and `domain-modeling` at the commit recorded in [UPSTREAM.md](UPSTREAM.md).
