# Specification and tickets

Use this reference after Intake and any Grill decisions are complete.

## Produce the specification

Synthesize the request, repository evidence, and settled decisions. Do not restart the interview. A reviewable specification names:

- outcome and user-visible behavior;
- scope and explicit exclusions;
- affected interfaces or modules;
- acceptance criteria, including meaningful negative behavior;
- compatibility, migration, and safety constraints;
- verification evidence required for completion;
- unresolved decisions that still require a gate.

Write the specification to the Project Contract's location. For a tiny change, an inline change brief may serve as the specification only when it captures the same boundaries and the repository does not require a file.

## Specification Gate

Present the specification for review. Before asking for approval, disclose the automatic actions approval will authorize:

- creation of tickets within this specification in the named local or external tracker;
- implementation and an independent test lane when eligible;
- repository verification and independent review;
- no delivery until the separate Delivery Gate.

Requested corrections return to specification. Approval fixes the authorized scope and advances automatically to ticketing.

## Resume Gate

When entering from an existing specification or ticket set, first validate the artifact against repository evidence and determine whether its approval was recorded in the current Feature Run. If not, present a fresh gate containing:

- the artifact and summarized scope;
- the stage that will be entered;
- the ticket backend and any ticket creation that will occur;
- the automatic implementation, test, verification, and review actions;
- the fact that delivery still requires its own gate.

For a specification, approval authorizes the same actions as the Specification Gate. For existing tickets, approval confirms both their bounded scope and automatic execution. Corrections update the artifact before proceeding. Do not accept labels such as `approved`, tracker state, or repository presence as proof of user authorization.

## Create tickets

Break the approved specification into independently reviewable vertical slices. Each ticket states its observable outcome, relevant acceptance criteria, dependencies or blocking edges, and verification. Prefer slices that exercise a real path through the system over horizontal layer tasks.

Create tickets in the Project Contract's backend. Missing configuration, unavailable permissions, or a ticket that requires a new consequential decision raises an Exception Gate. When tickets merely decompose the approved specification, proceed directly to implementation without a routine ticket-review prompt.
