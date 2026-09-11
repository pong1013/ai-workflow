# Intake and Grill

Use this reference after establishing the Project Contract and before writing a specification.

## Recommend a route

Inspect the request and repository, then recommend one route:

- Enter Grill when product behavior, domain language, architecture, compatibility, safety, or another consequential trade-off remains unresolved.
- Skip Grill when an approved specification already exists, or the request is small, precise, low risk, and contains enough acceptance detail.
- Honor `start with grill` or `skip grill` from the initial request. That explicit directive satisfies the Intake Gate after repository inspection, so do not ask for duplicate confirmation; raise an Exception Gate only if evidence makes the chosen route unsafe or materially underspecified.

Without an explicit directive, explain the evidence behind the recommendation and wait for the user to confirm it.

## Grill a decision tree

- Resolve discoverable repository facts before asking questions.
- Identify consequential decisions and their dependencies.
- Ask exactly one decision question at a time, recommend an answer, and state the important trade-off.
- Challenge ambiguous or conflicting language instead of silently choosing a meaning.
- Do not implement the feature during Grill.
- Continue until the important decision branches are settled, then move directly to specification without requiring another Skill invocation.

## Record durable knowledge

Update a repository's existing domain glossary only when a project-specific term becomes canonical. Use a concise definition and identify ambiguous alternatives to avoid.

Offer an ADR only when the decision is hard to reverse, surprising without its rationale, and based on a real trade-off. Use the repository's established ADR format and location; otherwise use `docs/adr/NNNN-short-slug.md` with one paragraph stating context, choice, and rationale. Do not turn ADRs into specifications.

If the current repository is itself a template, warn that generated knowledge will be inherited and obtain confirmation before writing it.
