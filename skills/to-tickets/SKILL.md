---
name: to-tickets
description: Break an approved specification into tracer-bullet tickets with blocking edges, review the breakdown, and publish the approved tickets as GitHub sub-issues. Use explicitly or from $ai-workflow.
---

# To Tickets

Break an approved specification into independently verifiable tracer-bullet tickets. If repository tracker/domain configuration is missing, stop and tell the user to run `$setup-matt-pocock-skills`.

## Gather context

Read the full source specification and comments, configured domain docs, relevant ADRs, and enough code to understand existing boundaries. Preserve approved terminology and architecture. Look for prefactoring that makes the change easy before making the easy change.

## Draft vertical slices

Each ticket must:

- deliver one narrow but complete path through the affected layers;
- be demonstrable or verifiable on its own;
- fit one fresh implementation context;
- carry observable acceptance criteria;
- name every ticket that genuinely blocks it;
- stay within the approved specification.

Do not split schema, API, UI, and tests into horizontal tickets. A wide mechanical refactor is the exception: use expand-contract sequencing, migrate callers in green batches, then remove the old form after every migration blocker completes. When no batch can remain green alone, use an explicitly approved integration branch and final integrate-and-verify ticket.

Do not invent shared interfaces or architecture during decomposition. A missing abstraction, conflicting seam, or scope gap returns to the controller's Exception Gate, then Grill/specification and renewed approval.

## Ticket Breakdown Gate

Before publishing, show a numbered proposal. For every ticket include title, blockers, user-visible outcome, acceptance criteria, and whether it is prefactoring, a tracer bullet, or an expand-contract step.

Ask the user to review granularity, blocking edges, order, and merge/split choices. Iterate until the exact breakdown is explicitly approved. Specification approval alone does not authorize ticket creation.

## Publish to GitHub

This release requires the configured tracker to be GitHub. Create blockers first, one issue per ticket, using this body shape:

```markdown
## Parent

<canonical parent specification issue>

## What to build

The end-to-end behavior this ticket makes work.

## Acceptance criteria

- [ ] Observable criterion

## Blocked by

- #<blocking-ticket>, or None
```

Link every ticket to the parent as a native sub-issue when available. Prefer native GitHub issue dependencies; use the explicit `Blocked by` fallback only when the capability is unavailable and record that limitation. Do not apply triage labels, assign tickets, close or modify the parent, or create any unapproved issue.

The ready frontier is the approved-order set of open tickets whose blockers are complete. This release executes only the first ready ticket and does not parallelize separate tickets.

When called by `$ai-workflow`, return identifiers, parent/sub-issue evidence, dependency graph, uncovered acceptance criteria, approval provenance, mutations, and `complete` or `blocked`; never advance the Feature Run.

## Provenance

Adapted from Matt Pocock's `to-tickets` at the commit recorded in [UPSTREAM.md](UPSTREAM.md). The tracer-bullet, prefactoring, expand-contract, review, and dependency methods are retained; publication is constrained to the approved GitHub flow and no triage labels.
