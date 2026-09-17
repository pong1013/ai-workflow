# Ticket Workers and Quality Loop

Create exactly two top-level worker roles for each ticket.

## Ownership plan

Before delegation, assign disjoint paths or hunks and record them in the run envelope. Dispatch both top-level workers concurrently before awaiting either one:

- Implementation Agent: production code and, when useful, implementation-owned unit tests used for `$tdd`.
- Quality Agent: independent acceptance or integration tests, verification evidence, and read-only product review.

No two writers may own the same path or hunk concurrently. An inability to isolate test writes does not serialize the roles: launch the Quality Agent concurrently in patch/design-only mode. When independent tests must be colocated with implementation-owned content, the Quality Agent returns a patch or precise test design without writing it.

## Implementation Agent

Give the agent the approved parent specification, current ticket, agreed seams, repository instructions, Project Contract, baseline, and ownership. It invokes the adapted `$implement`, uses `$tdd` only within assigned ownership, runs focused checks, and returns mutations, evidence, and blockers. It never commits, pushes, publishes tracker content, changes the specification, or approves its own work.

## Quality Agent

Give the agent the specification and ticket independently of implementation reasoning. It derives tests from the approved behavior and seams, records pre-implementation failing evidence when timing and isolation permit, and writes only Quality-owned files. After worker writes join, it verifies the combined ticket and invokes `$code-review` read-only against the ticket baseline.

`$code-review` may use parallel Standards and Spec sub-reviewers internally. They are read-only review perspectives, not additional top-level writer roles. The Quality Agent must not claim independent review of tests it authored; report that limitation explicitly.

## Routing

- Maintain one append-only, run-wide round ledger in execution order. Open a ticket round when workers begin an implementation/quality attempt, including a retry, and close it after the joined work, checks, and read-only review are assessed. Open a feature round for each feature-wide verification/review attempt after ticket commits, including a retry after routed findings. Give each entry a monotonic global `sequence`, a `roundNumber` that starts at 1 and increments separately for each ticket or the feature-review scope, scope (`ticket` with issue ID or `feature`), and baseline or commit/diff identity. Never replace an entry with the latest result.
- For every round, record the required fields in `state-machine.json`'s `roundLedgerPolicy`: sequence; round number; scope; ticket ID (or `null` for a feature round); implementation changes (owned paths or hunks and a concise summary, or explicitly `no change`); checks; separate Standards and Spec review outcomes; and next action. Each check records its exact command or check name, outcome (`pass`, `fail`, or `not-applicable`), and evidence reference when available. Give every `not-applicable` outcome a reason, including an interrupted check that was not run. Review outcomes include findings or why review was not applicable. A failed or interrupted round is still an entry; never turn an unrun check into a pass by omission.
- Keep the ledger distinct from the latest actionable verification summary. A retry adds a new entry and links back to the failed round; preserve the earlier result. Before a ticket commit or feature pass, require a closed passing round for that scope and current diff. Show the relevant ledger entries when reporting progress, a stopping point, or an Exception, and include all entries at the Delivery Gate and in the final report.
- Production findings return to the Implementation Agent.
- Test defects or coverage gaps return to the Quality Agent.
- New public interfaces, shared abstractions, scope changes, or missing architecture enter the Exception Gate and return to Grill/specification when required.
- Re-run focused and complete verification, ownership checks, and read-only review after fixes.
- Continue while evidence changes. Stop when the same blocker repeats without new evidence.

## Ticket acceptance

A ticket passes only when acceptance criteria are covered, focused checks and complete Contract verification pass, no blocking Standards or Spec finding remains, and post-verification status contains no unexplained mutation. Only then may the controller create the ticket commit.
