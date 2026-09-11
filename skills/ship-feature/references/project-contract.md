# Project Contract and workspace

Use this reference before any Feature Run writes to the repository.

## Establish the contract

Look for `.agents/project-contract.md`. A valid contract uses these sections in order:

1. Verification
2. Knowledge
3. Work artifacts
4. Workspace
5. Delivery

Treat the contract as a thin index, not as authority over contradictory repository evidence. Repository instructions such as `AGENTS.md` and applicable nested instruction files govern agent behavior. Executable tooling establishes available commands and actual behavior. When either conflicts with the contract, stop the affected stage, show the conflict, and ask the user which source should be corrected.

## Contract Discovery

When no contract exists:

1. Read repository instructions, README and contributor documentation, build manifests, CI configuration, test configuration, existing specifications and ADRs, tracker references, and Git remotes.
2. Distinguish observed facts from policies. Do not turn branch history, one command in a log, or another incidental pattern into a permanent rule.
3. Establish verification status and commands, knowledge locations, specification location, ticket backend, workspace policy, and delivery mode.
4. Ask one focused question for each consequential value that cannot be discovered safely. Leave nonessential values unconfigured.
5. Offer to persist the result as `.agents/project-contract.md`. Write it only after explicit approval; declining persistence does not prevent the current run from using the discovered contract.

Use this shape when persistence is approved:

```markdown
# Project Contract

## Verification

- Status: `<bootstrap|complete>`
- Bootstrap verification: `<command, required only for bootstrap>`
- Complete verification: `<command, or unconfigured during bootstrap>`
- Project checks: `<path or unconfigured>`

## Knowledge

- Repository instructions: `<path>`
- Domain language: `<path or unconfigured>`
- Architecture decisions: `<path or unconfigured>`

## Work artifacts

- Specifications: `<path>`
- Ticket backend: `<backend or unconfigured>`

## Workspace

- Default branch: `<branch or discover from repository>`
- Feature branch naming: `<policy, or omit>`
- Preserve unrelated working-tree changes: yes

## Delivery

- Mode: `<none|commit-only|push|pull-request|merge-request|unconfigured>`
- Remote and target branch: `<values or discover and confirm>`
- Require Delivery Gate: yes
```

Treat `Status: bootstrap`, an unconfigured complete command, a machine-readable `HARNESS_VERIFICATION_STATUS=bootstrap` result, or any mismatch between the contract and executable verification as incomplete verification. The run may continue through specification, but raise an Exception Gate before ticket side effects or repository implementation writes. Never advance from Review to Delivery until a complete verification entrypoint reports complete status.

## Workspace Gate

Before the first repository write:

- Reuse a clean branch or worktree already dedicated to this Feature Run.
- When the default branch is clean and no dedicated branch exists, propose a safe feature branch name and create it through the supported Git workflow.
- Follow an explicit repository naming policy. Otherwise propose a conventional safe name; do not persist a prefix inferred only from history.
- Capture the initial branch, `git status`, and diff as the ownership baseline. Record which existing paths or hunks, if any, belong to this Feature Run.
- Reusing an already-clean dedicated branch or worktree needs no extra confirmation after the baseline is recorded.
- If unrelated or uncertain working-tree changes exist, stop and ask how to isolate the run. Require a clean dedicated worktree or branch unless the user explicitly identifies the exact existing paths or hunks that this run owns. Never stash, discard, overwrite, or silently include changes.
- After the user resolves an isolation question, re-run status and diff checks before allowing a write. If ownership is still ambiguous, keep the gate closed.
- Reuse a Codex-managed worktree when the task already owns one.

Recheck the baseline when workers join and before delivery. New or changed files outside recorded ownership raise an Exception Gate. A whole file is not run-owned merely because the run later edits another hunk in it.
