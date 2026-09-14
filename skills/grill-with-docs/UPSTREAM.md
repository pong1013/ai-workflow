# Upstream sources

The Matt Pocock-derived Skills in this repository are vendored from [`mattpocock/skills`](https://github.com/mattpocock/skills) at commit [`3cca18b368ae95cdbdebbff572ccafa662551015`](https://github.com/mattpocock/skills/commit/3cca18b368ae95cdbdebbff572ccafa662551015), inspected on 2026-09-14.

No installer or runtime workflow fetches upstream content. Updating this pin is a deliberate source review, adaptation, deterministic validation, and behavioral-evaluation task.

| Local Skill | Upstream source | Adaptation boundary |
| --- | --- | --- |
| `setup-matt-pocock-skills` | `skills/engineering/setup-matt-pocock-skills/` | Adds Setup Confirmation authority, dual `AGENTS.md`/`CLAUDE.md` generated blocks, no-commit finish, credential protection, and disclosure that this release executes GitHub only. |
| `grill-with-docs` | `skills/engineering/grill-with-docs/` | Preserves composition of `grilling` and `domain-modeling`; adds Project Contract workspace/knowledge authority and controller handoff. |
| `grilling` | `skills/productivity/grilling/` | Adds no-implementation and controller-return boundaries. |
| `domain-modeling` | `skills/engineering/domain-modeling/` | Adds workspace/knowledge-write authority and controller-return boundaries. |
| `to-spec` | `skills/engineering/to-spec/` | Separates the Specification Gate from publication, removes triage labels, and fixes one GitHub parent issue as canonical. |
| `to-tickets` | `skills/engineering/to-tickets/` | Retains tracer bullets, prefactoring, expand-contract, quiz, and blocking edges; adds a distinct Ticket Breakdown Gate, GitHub sub-issues, and no triage labels. |
| `implement` | `skills/engineering/implement/` | Removes self-review and commit; constrains writes to Implementation ownership and returns evidence to the controller. |
| `tdd` | `skills/engineering/tdd/` | Reuses specification-approved seams, routes new interface design to Exception, and enforces concurrent ownership. |
| `code-review` | `skills/engineering/code-review/` | Adds uncommitted ticket-diff review, run ownership, finding classification, and an explicit read-only boundary while preserving parallel Standards and Spec axes. |

The Plugin controller `ai-workflow` and its state/authority references are original integration work in this repository.
