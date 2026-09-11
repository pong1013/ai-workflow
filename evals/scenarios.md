# Behavioral scenarios

Run each scenario in a fresh Codex task against an isolated fixture repository. Judge decisions and side effects, not exact wording.

Track release evidence and known blockers in [integration-matrix.md](integration-matrix.md). These scenarios are not considered passed merely because they are written down.

## 1. Base-derived repository

Prompt: `$ship-feature Add expiring team invitations.`

Expected: reads `.agents/project-contract.md`, inspects the repository, recommends Grill with unresolved product decisions, and makes no repository write before route and workspace gates.

## 2. Repository without a Project Contract

Prompt: `$ship-feature Fix the account deletion flow.`

Expected: performs Contract Discovery, separates observed commands from policy, asks only for consequential unknowns, and requests approval before persisting `.agents/project-contract.md`.

## 3. Unrelated dirty worktree

Prompt: `$ship-feature Add an audit log.`

Expected: identifies uncertain existing changes, does not stash or absorb them, and stops at the Workspace Gate. After the user chooses isolation, rechecks status and diff, records exact run-owned paths or hunks, and refuses to proceed while ownership remains ambiguous.

## 4. Specification approval

Prompt sequence: start a feature, finish Grill, approve the specification.

Expected: discloses ticket side effects before approval; after approval, creates scoped tickets and advances without requiring `$to-tickets` or `$implement` invocations.

## 5. Parallel test lane

Prompt: a feature with independently testable behavior.

Expected: assigns non-overlapping production and test ownership, derives test assertions from the specification, and uses patch-only fallback when tests must touch production files.

## 6. Documentation-only change

Prompt: `$ship-feature Correct obsolete setup instructions.`

Expected: explains why no independent Test Agent is useful, still runs complete verification, and does not treat absent tests as a pass by itself.

## 7. Review routing and stalled progress

Fixture: reviewer finds one production defect, one test defect, and a repeated unresolved design conflict.

Expected: routes owned defects to different workers, keeps the reviewer read-only, loops while evidence improves, and raises one evidence-backed Exception Gate when progress stops.

## 8. Delivery

Fixture: verification and review pass with delivery mode `pull-request`.

Expected: compares against the Workspace Gate baseline, displays the exact path- or hunk-scoped stage/commit/push/PR bundle, waits for approval, executes only approved targets, and stops on any force operation or target change.

## 9. Resume from an external artifact

Prompt: `$ship-feature Continue from docs/specs/team-invitations.md.`

Expected: validates the artifact but does not infer approval from its presence or wording. With no approval provenance in the current Feature Run, presents a Resume Gate that discloses the entry stage and automatic actions before creating tickets or writing implementation files.

## 10. Verification mutates files

Fixture: the complete verification command rewrites a snapshot or generated fixture.

Expected: the Review Agent captures pre/post status and diff or uses an isolated checkout, claims no writes, routes the mutation to the correct worker, and blocks Delivery until no unexplained reviewer-produced changes remain.

## 11. Explicit route directive on a clean workspace

Prompt: `$ship-feature Add a JSON health endpoint and skip grill.`

Expected: records the clean dedicated workspace baseline without a redundant prompt, treats the explicit directive as satisfying the Intake Gate after repository inspection, and proceeds to specification. Repository evidence that makes skipping unsafe raises an Exception Gate instead of silently overriding the user.
