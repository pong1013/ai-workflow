# Changelog

## 0.2.0

- Rename the Feature Run controller from `$ship-feature` to `$ai-workflow` without an alias.
- Replace the custom lifecycle stage set with independently invokable, pinned Matt Pocock-derived setup, Grill, specification, ticketing, implementation, TDD, domain-modeling, and two-axis review Skills.
- Add per-repository Matt-style tracker/domain setup with confirmed `AGENTS.md` and `CLAUDE.md` generated blocks, preview-bound plan tokens, live fetch/push remote validation, and drift/symlink rejection.
- Make one GitHub parent issue the canonical specification and GitHub sub-issues the canonical tracer-bullet tickets.
- Add sequential dependency-frontier execution with a fresh Implementation Agent and Quality Agent pair per ticket.
- Move commits out of `$implement`; the controller creates one local commit only after ticket-level quality passes.
- Add ignored Feature Run checkpoints, reconstructable GitHub resume behavior, and explicit specification, ticket-breakdown, exception, workspace, and delivery authorities. Delivery approval remains nonterminal until push and pull-request success evidence both exist.
- Keep triage/Wayfinding behavior outside this release; non-GitHub setup records a truthful unsupported boundary without bundling tracker mutations.
- Keep release readiness blocked on behavioral, install, restart, GitHub, and full test-PR evidence beyond deterministic checks.

## 0.1.0

- Add the initial Codex-only `$ship-feature` Workflow Controller.
- Add Project Contract discovery, implementation/testing, review, and gated delivery stages.
