# Implementation and independent testing

Use this reference after approved tickets exist.

## Select the test lane

Immediately after specification approval, decide whether the work has independently testable behavior.

- Start a Test Agent when acceptance behavior can be asserted independently of the implementation.
- Skip it for documentation or work with no meaningful test surface, record why, and still run complete Project Contract verification.
- If tests are warranted but the repository lacks required infrastructure, raise an Exception Gate instead of treating absence as permission to proceed untested.

## Assign parallel workers

Use Codex subagents when available. Start an Implementation Agent and eligible Test Agent in parallel only after giving them non-overlapping writable ownership.

Implementation Agent:

- receives the approved specification, assigned tickets, Project Contract, and production-file ownership;
- implements only the approved scope;
- reports changed files, focused checks, and blockers.

Test Agent:

- derives assertions from the specification and tickets before considering the new implementation;
- may inspect existing code and test infrastructure to use public seams correctly;
- owns separate test files and must not weaken expectations to match the implementation;
- reports the initial failing evidence when it can run before implementation completes.

When tests must be colocated with production code or ownership cannot be separated, the Test Agent produces a patch or test design without editing the overlapping file. Apply it only after the conflicting writer has returned control.

## Join the lanes

Wait for both workers. Do not let one worker declare the feature complete. Inspect their artifacts, resolve only mechanical integration issues within approved scope, run affected focused checks, and pass the combined diff and evidence to independent review.
