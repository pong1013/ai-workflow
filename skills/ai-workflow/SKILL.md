---
name: ai-workflow
description: Run one software feature through repository setup preflight, Project Contract discovery, Grill, GitHub specification and tickets, two-agent implementation and quality, verification, and explicitly approved pull-request delivery. Use only when the user explicitly invokes $ai-workflow.
---

# AI Workflow

Own one Feature Run from intake until completion, cancellation, a requested stopping point, or a genuine blocker. User replies advance the current run; do not require another invocation after every gate.

## Load the workflow contract

Read [references/state-machine.json](references/state-machine.json) before starting. Resolve every Skill named by `stageSkills`; a missing or conflicting Skill stops before mutation. Stage Skills return artifacts and evidence, while this controller alone owns transitions, gates, agent ownership, ticket commits, and delivery.

Read only the references needed for the current stage:

- Before creating a Feature Run, read [references/preflight.md](references/preflight.md).
- Before the first repository write or branch change, read [references/workspace-and-contract.md](references/workspace-and-contract.md).
- Before creating tickets or workers, read [references/github-flow.md](references/github-flow.md).
- Before assigning workers or reviewing a ticket, read [references/quality-loop.md](references/quality-loop.md).
- When saving or reconstructing progress, read [references/checkpoints.md](references/checkpoints.md).
- Before committing, pushing, or creating a pull request, read [references/delivery.md](references/delivery.md).

## Preserve one run

- Refuse a second unfinished Feature Run in the same Codex task. Different features belong in different tasks and isolated branches or worktrees when edits may overlap.
- Keep one run envelope containing repository identity, state, requested stopping point, Project Contract, workspace baseline, GitHub parent and ticket identifiers, approvals, ownership, an ordered round ledger, verification, findings, and checkpoint path. Append each ticket implementation/quality round and feature verification/review round; later passes never erase earlier failures or retries.
- Never treat a filename, tracker label, issue state, branch, or commit message as approval provenance.

## Show progress in every reply

Start every `$ai-workflow` user-facing reply with a compact status line naming the current state or Gate, completed milestone and ticket progress when known, the pending decision or blocker (or "none"), and the next step. This includes repository setup, Contract, and Workspace preflight before the Feature Run exists, as well as interim updates, Grill questions, Gate requests, stopping-point reports, and final reports. Before run creation, label the pre-run phase explicitly; afterward use the state names in `state-machine.json`. Name an active Gate explicitly. If a transition has not happened, report the existing state; do not imply approval or completion from a proposed action. Explain the question flow at Grill: show the current question number, its prerequisite, and known queued decisions without promising a fixed total.

## Route the full path

1. Complete repository setup and Project Contract preflight before creating the Feature Run.
2. Establish a safe workspace before any feature or durable domain-knowledge write.
3. For a new feature, invoke `$grill-with-docs`. It may finish immediately when no consequential decision remains. An explicit resume from an approved specification or ticket set enters the Resume Gate instead.
4. Invoke `$to-spec`. The Specification Gate approves the exact specification and authorizes its publication as one GitHub parent issue. It does not authorize ticket publication, delivery, or unrelated work.
5. Invoke `$to-tickets`. The Ticket Breakdown Gate approves granularity, blocking edges, merge/split choices, and the exact GitHub sub-issues to publish.
6. Work one dependency-ready ticket at a time. Dispatch a fresh Implementation Agent and Quality Agent concurrently before awaiting either worker, following [references/quality-loop.md](references/quality-loop.md).
7. After ticket-level verification and review pass, create one local ticket commit. Then advance to the next dependency-ready ticket. Record each attempt before deciding whether it passed, needs an owned fix, or enters Exception.
8. After all tickets pass, run feature-level verification and a fresh `$code-review` across the complete branch. Record each feature-level round, including retries after findings.
9. Present the Delivery Gate. Approval enters `delivery-approved` and authorizes only its exact push and pull-request bundle. Enter `complete` only after both operations succeed; otherwise retain the nonterminal failure and enter Exception as needed. Never merge or close issues directly.

## Invoke independent Skills

Load the exact registered Skill instead of reproducing it from memory. Supply a bounded envelope with the current request, approved artifacts, authorities, ownership, baseline, and relevant evidence. Validate its returned mutations and status before transitioning.

The public method chain is:

```text
$grill-with-docs -> $to-spec -> $to-tickets -> $implement/$tdd -> $code-review
```

`$setup-matt-pocock-skills` is a prerequisite, not an automatically invoked stage. `$grilling` can independently interview the user through a design tree. `$grill-with-docs` composes it with `$domain-modeling` to record settled repository terminology and decisions. When invoked by this controller, both follow the same one-consequential-question-per-reply limit, including domain or ADR questions.

## Stop and resume

Honor natural-language stopping points and return current artifacts without pretending the run is complete. On resume, verify repository identity, GitHub artifacts, current diff, branch, ticket relationships, and approval provenance. If current-task approval is unavailable, present a Resume Gate describing scope, entry stage, external effects, automatic worker work, ticket commits, and the separate Delivery Gate.

At an Exception Gate, pause workers and present the stage, blocker, attempts, evidence, options, recommendation, and impact. Include the ordered round ledger accumulated so far when the run stops. Ask one consequential decision question. Continue only when the decision supplies the missing authority or evidence. Stop a review loop when the same blocker repeats without new evidence.

## Finish

Complete only after the approved push and pull-request creation succeed. Report the parent specification, tickets, ticket commits, the complete ordered round ledger, verification, both review axes, pull request, and accepted limitations. A stopping-point or blocked-run report also includes the ledger accumulated so far. Passing deterministic checks alone never establishes release readiness or external integration success.
