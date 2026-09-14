# Issue tracker: GitHub

Issues and specifications for this repository live in GitHub Issues. Use the `gh` CLI for operations.

## Repository identity

- **Repository:** `pong1013/ai-workflow`
- **Configured from remote:** `origin`

Never infer a target again when this repository and current remotes disagree; stop and ask the user to resolve the conflict. Do not store GitHub tokens or credentials in this file.

## Read operations

- Read an issue and comments with `gh issue view <number> --repo pong1013/ai-workflow --comments` and request structured JSON fields when exact metadata is needed.
- List issues with `gh issue list --repo pong1013/ai-workflow --state <state> --json ...` and an explicit filter.
- Resolve a bare number as an issue or pull request before acting because GitHub shares one number space.

## Write operations

Every write requires the gate named by the calling workflow. Revalidate repository identity and authentication immediately before acting.

- Create an issue with `gh issue create --repo pong1013/ai-workflow --title <title> --body-file <file>`.
- Comment or edit only when that exact mutation was disclosed and approved.
- Never pass credentials on the command line or write them into body files.

## AI Workflow conventions

- One GitHub parent issue is the canonical specification.
- Implementation tickets are issues linked to the parent as native sub-issues when available.
- Create blockers first and prefer native issue dependencies.
- When native sub-issues or dependencies are unavailable, use `Part of #<parent>` or `Blocked by: #<number>` and report the limitation.
- Work one ready-frontier ticket at a time in approved order.
- Do not apply triage labels, assign tickets, close issues, merge, or perform undisclosed tracker mutations.
- Pull-request closing references take effect only after merge.

## When a Skill says "publish to the issue tracker"

Create only the GitHub issue authorized by the current Specification or Ticket Breakdown Gate in `pong1013/ai-workflow`.

## When a Skill says "fetch the relevant ticket"

Read the exact issue, comments, parent/sub-issue relationship, and dependencies from `pong1013/ai-workflow`.
