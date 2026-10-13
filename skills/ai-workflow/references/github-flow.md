# GitHub Specification and Ticket Flow

GitHub Issues are the only supported tracker for this release.

## Canonical artifacts

Deferred configuration follow-ups are a separate standalone GitHub issue type authorized only by the exact Exception decision. Record originating feature relationship, reason, provenance and exact path/hunk/hash evidence; keep them outside the current parent's child-ticket/dependency graph. Follow [delivery.md](delivery.md); neither receipt validation nor the current Ticket Breakdown Gate authorizes their publication, and publication cannot initiate a post-merge branch/run.

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

When validated setup evidence describes only mechanical, preview-approved repository setup required by the requesting feature, the breakdown makes that work the first blocker ticket. Setup that changes workflow semantics, expands the approved product scope, or conflicts with the Project Contract enters Exception rather than being silently added. Durable project-knowledge writes likewise require approved ticket scope or an explicitly approved alternative before configuration reconciliation can pass.
