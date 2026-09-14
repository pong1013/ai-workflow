# Workspace and Project Contract

## Contract authority

The Project Contract controls verification, knowledge, work artifacts, workspace policy, and delivery. `docs/agents/issue-tracker.md` controls tracker identity and operations; `docs/agents/domain.md` controls domain-document discovery. A disagreement enters the Exception Gate instead of being resolved silently.

When the Contract is missing, discover values from repository instructions, executable tooling, CI, docs, and Git configuration. Distinguish observed facts from policy. Show the complete draft and obtain both the bootstrap Workspace Gate and Contract Persistence Gate before writing `.agents/project-contract.md`. Neither authority is sufficient alone.

A bootstrap Contract may support Grill and specification drafting, but cannot authorize GitHub ticket publication, implementation, ticket commits, push, or pull-request creation. Complete verification must be real and must agree with emitted `HARNESS_VERIFICATION_STATUS` evidence.

## Workspace Gate

Before the first repository write or branch mutation:

1. Inspect branch, status, diff, worktrees, default branch, and naming policy.
2. Record exact pre-existing paths and hunks.
3. Reuse a clean feature-dedicated branch or Codex-managed worktree after recording its baseline.
4. Obtain Workspace Gate approval before creating or switching a branch or worktree, or when ownership is ambiguous.
5. Never stash, discard, overwrite, stage, or absorb unrelated work.

Contract Discovery itself may need to write before a normal feature workspace exists. In that case, present a bootstrap workspace bundle covering only the Contract path and any exact instruction/config updates. Reinspect status after approval and before writing, then record bootstrap workspace evidence so the state machine's composite Contract-write authority can be satisfied.
