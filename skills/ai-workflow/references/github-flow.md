# GitHub Specification and Ticket Flow

GitHub Issues are the only supported tracker for this release.

## Canonical artifacts

- One GitHub parent issue is the canonical specification.
- GitHub sub-issues are canonical implementation tickets.
- Do not create a committed or `.scratch/` mirror of the specification or tickets.
- `docs/agents/issue-tracker.md` is configuration, not an artifact copy.

## Specification publication

`$to-spec` first produces a complete draft with agreed testing seams. Present the Specification Gate with the exact title/body, target owner/repository, and consequence that approval publishes one parent issue. Publish only after approval and retain its URL, number, and immutable approval evidence in the run.

## Ticket publication

`$to-tickets` drafts tracer-bullet tickets and blocker edges without publishing. Present a Ticket Breakdown Gate covering granularity, dependency edges, merge/split choices, exact issue bodies, target repository, and sub-issue relationships. Iterate until approved, then create blockers first.

Link every ticket to the parent as a native sub-issue when available. Prefer native GitHub issue dependencies; when the configured capability is unavailable, use an explicit `Blocked by: #N` fallback and record the limitation. Do not apply triage labels, close the parent, assign tickets, or perform other undisclosed tracker mutations.

The ready frontier contains open child tickets whose blockers are all complete in the current run. This release executes the first ready ticket in approved order and never runs multiple tickets concurrently.
