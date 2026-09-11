---
name: ship-feature
description: Drive one software feature from repository discovery and specification through implementation, independent testing, review, and explicitly approved delivery. Use only when the user explicitly invokes $ship-feature; do not use for ordinary coding requests or a second unfinished feature in the same task.
---

# Ship Feature

Own one Feature Run from intake until completion, cancellation, or a genuine blocker. Remain its Workflow Controller across user replies; treat approvals and corrections as state transitions without asking the user to invoke another Skill.

## Establish control

- Refuse to start a second unfinished Feature Run in the same Codex task. A separate task owns a separate run.
- Inspect the request, repository, Git state, and available Codex capabilities before changing files.
- Read [references/state-machine.json](references/state-machine.json) as the v1 transition and external-operation authorization model. Do not invent a shortcut edge.
- Read [references/project-contract.md](references/project-contract.md) to establish the repository contract and resolve conflicts.
- Before the first repository write, establish the Workspace Gate described in that reference. Record and revalidate its ownership baseline. Preserve unrelated work and never stash, discard, or absorb uncertain changes.
- Keep transient stage state in this task. Persist only approved specifications, tickets, project knowledge, and other durable artifacts in the repository or configured tracker. Never write run state into the global Skill or Plugin.

## Route the Feature Run

Read [references/intake-and-grill.md](references/intake-and-grill.md). Recommend Grill when consequential product, domain, architecture, or safety decisions remain; otherwise recommend a direct specification. Wait for route confirmation unless the initial invocation already gave an explicit `start with grill` or `skip grill` directive.

After Grill, or immediately when it is skipped, read [references/specification-and-tickets.md](references/specification-and-tickets.md). The Specification Gate is the normal approval boundary before implementation. Approval also authorizes ticket creation in the named tracker when the gate disclosed it.

After specification approval, continue without routine phase prompts:

1. Create tickets from the approved scope.
2. Read [references/implementation-and-testing.md](references/implementation-and-testing.md) and run the eligible implementation and test lanes.
3. Read [references/review-loop.md](references/review-loop.md), verify and review independently, then route findings until the work passes or loses progress.
4. Read [references/delivery.md](references/delivery.md) and stop at the Delivery Gate before any delivery action.

The user may request a stopping point or resume from an existing specification or ticket set. Validate the supplied artifact and its approval provenance. Approval recorded in the current Feature Run may be reused; otherwise present a fresh Resume Gate that summarizes the artifact, intended entry stage, and automatic actions before proceeding. Never infer approval from a filename, status label, commit, or ticket state.

## Apply gates

- A Human Gate is a planned approval before a consequential transition.
- An Exception Gate is conditional: raise it only for a new consequential decision, risk, scope change, unresolved conflict, missing capability, or stalled loop.
- At an Exception Gate, pause workers, preserve current work, and present: current stage, blocker, attempts, evidence, options, recommendation, and impact. Ask one decision question.
- Resume the same Feature Run from the affected stage after the user decides. Do not require another `$ship-feature` invocation.
- Prior approval covers only its displayed scope. It never silently authorizes unrelated changes, destructive recovery, force operations, or delivery.

## Finish

Complete only after the approved delivery bundle succeeds, or after the configured `none` delivery mode reaches a clean reviewed handoff. Report the specification and tickets produced, verification evidence, review outcome, delivery result, and any explicitly accepted limitations.
