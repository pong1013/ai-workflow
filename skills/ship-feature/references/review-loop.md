# Verification and review loop

Use this reference after implementation and eligible independent tests have joined.

## Review independently

Start a Review Agent that did not implement the feature or author its tests. It is read-only with respect to the reviewed files. Give it the approved specification, tickets, Project Contract, Workspace Gate baseline, combined diff, and test evidence.

The Review Agent must:

1. run affected focused tests;
2. run the complete verification entrypoint from the Project Contract;
3. review behavior against the specification and repository rules;
4. report only actionable findings with evidence and ownership;
5. state any verification it could not exercise.

Run verification in an isolated checkout when practical. Otherwise capture status and diff immediately before and after every command that may mutate the worktree. The reviewer must not claim or retain those mutations. Classify every generated snapshot, fixture, lockfile, or other changed file and route it to the Implementation or Test Agent; unexplained changes raise an Exception Gate. Re-run the affected verification after the owning worker resolves them.

## Route findings

The Workflow Controller classifies findings:

- production defect → Implementation Agent;
- test defect or coverage gap → Test Agent;
- conflict between implementation and test interpretations → controller examines the approved specification;
- missing specification decision, expanded scope, or architectural trade-off → Exception Gate;
- stale Project Contract → contract conflict resolution before continuing.

After a worker corrects a finding, rerun affected tests and complete verification, then return the new diff and evidence to the Review Agent. The reviewer never fixes its own findings.

## Detect progress

Continue automatically while findings shrink, change, or produce new evidence. Raise an Exception Gate when:

- the same blocker repeats without new evidence;
- implementation and tests remain in unresolved conflict;
- a correction would exceed approved scope;
- complete verification cannot run;
- a required Codex subagent or tool is unavailable and no equivalent safe path exists.

Do not use a fixed retry count when the work is measurably converging. Do not loop merely to obtain a passing label.

Advance to Delivery only when complete verification passes, the Review Agent reports no blocking findings, and its post-verification status contains no unexplained or reviewer-owned changes.

A zero exit status from a bootstrap command is not complete verification. Require both the Project Contract's `Status: complete` and any machine-readable verification status emitted by the command to agree. Missing, bootstrap, incomplete, or conflicting status raises an Exception Gate.
