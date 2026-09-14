# Repository Setup Preflight

Complete this preflight before creating a Feature Run.

1. Resolve the current repository root and read applicable `AGENTS.md` and `CLAUDE.md` instructions.
2. Require `docs/agents/issue-tracker.md` and `docs/agents/domain.md`.
3. If either file is missing, stop and ask the user to run `$setup-matt-pocock-skills`. Do not invoke it automatically or create a Feature Run.
4. Require the configured issue tracker to be GitHub for this release. An unsupported tracker enters the Exception Gate from `repository-setup`; it does not create a Feature Run or checkpoint.
5. Compare the configured owner/repository with current Git remotes. A missing, ambiguous, fork/upstream, or conflicting target enters the same pre-run Exception Gate.
6. Check that `gh` is available. Check authentication and repository access before the first GitHub-dependent read or write; never store credentials in repository files or checkpoints.
7. Read `.agents/project-contract.md`. If it is absent, continue to approved Contract Discovery using [workspace-and-contract.md](workspace-and-contract.md).

Do not repeat stable setup questions on every run. Revalidate live repository identity, remote, tools, and access, and ask only when evidence is missing, unsafe, unsupported, or contradictory.
