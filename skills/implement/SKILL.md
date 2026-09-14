---
name: implement
description: Implement one approved specification or ticket with test-driven slices inside assigned ownership, run focused and complete checks, and return evidence without committing. Use explicitly or as the $ai-workflow Implementation Agent method.
---

# Implement

Implement only the approved specification or current ticket. Read repository instructions, the Project Contract, configured domain docs, agreed testing seams, workspace baseline, and assigned file ownership before writing.

Use [$tdd](../tdd/SKILL.md) where a pre-agreed seam and implementation-owned test surface exist. Work in thin behavior slices, run typechecking and focused tests regularly, and run the Project Contract's complete verification at the end. Do not weaken tests, change the specification, or add speculative scope to make the work pass.

Respect concurrent ownership. Production code and any implementation-owned unit tests may be assigned here; never edit Quality Agent paths or hunks. If a necessary change overlaps another writer, changes a shared public interface, reveals missing architecture, or exceeds approved scope, stop and return the evidence.

Do not invoke `$code-review` as self-approval. The separate Quality Agent owns independent tests and read-only review after writes join.

Never stage, commit, push, publish tracker changes, close issues, or deliver. Return changed paths/hunks, TDD and verification evidence, permitted implementation decisions, blockers, and `complete` or `blocked`. The controller alone decides ticket acceptance and commit.

## Provenance

Adapted from Matt Pocock's `implement` at the commit recorded in [UPSTREAM.md](UPSTREAM.md). TDD and verification remain; self-review and automatic commit move to the independent Quality Agent and controller.
