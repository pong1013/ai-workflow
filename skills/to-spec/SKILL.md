---
name: to-spec
description: Turn settled conversation and repository decisions into a specification, review its testing seams, and publish the approved result as one GitHub parent issue. Use explicitly after Grill or from $ai-workflow.
---

# To Spec

Synthesize decisions already made; do not restart the interview or invent details to fill a template. If `docs/agents/issue-tracker.md` or `docs/agents/domain.md` is missing, stop and tell the user to run `$setup-matt-pocock-skills`.

## Gather evidence

Read relevant repository instructions, configured domain docs, ADRs, code, the request, and settled Grill decisions. Use the project's canonical vocabulary and surface any contradiction instead of silently choosing a side.

## Agree testing seams

Before drafting prose, identify the public boundaries where feature behavior will be observed. Prefer existing seams and the highest useful seam; propose as few new seams as possible. Ask the user to confirm the seams as part of specification review. A new major public interface or unresolved architecture stops at the controller's Exception Gate rather than being invented here.

## Draft the specification

Use this structure when a section has real content:

```markdown
## Problem Statement

The user's problem and why it matters.

## Solution

The approved user-visible outcome.

## User Stories

Numbered actor, capability, and benefit stories covering positive and important negative behavior.

## Implementation Decisions

Approved modules, public interfaces, architecture, schema, API contracts, compatibility, migration, and safety decisions. Avoid file paths and ordinary code details that will quickly stale.

## Testing Decisions

The agreed public seams, observable behavior, relevant prior-art tests, and completion evidence.

## Out of Scope

Decisions deliberately excluded from this feature.

## Further Notes

Only additional context needed by fresh ticket sessions.
```

Include only decisions established by the user or authoritative repository evidence. Record unresolved consequential decisions explicitly and do not publish while any blocks implementation.

## Specification Gate and publication

For this release, require `docs/agents/issue-tracker.md` to configure GitHub. Present the exact issue title/body, owner/repository, testing seams, scope, exclusions, and the consequence that approval creates one canonical GitHub parent issue. Delivery and ticket publication remain separately gated.

Apply revisions until explicitly approved, then revalidate the target and create exactly one parent issue. Do not create a local spec mirror, apply triage labels, create tickets, close anything, or infer approval from an existing issue state.

When used independently, this Skill owns the same Specification Gate. When called by `$ai-workflow`, return the draft or published issue URL/number, approval evidence, mutations, unresolved decisions, and `approved`, `needs-revision`, or `blocked`; do not advance the Feature Run.

## Provenance

Adapted from Matt Pocock's `to-spec` at the commit recorded in [UPSTREAM.md](UPSTREAM.md). The adaptation separates approval from publication, removes the uninstalled triage-label dependency, and fixes GitHub as this release's canonical tracker.
