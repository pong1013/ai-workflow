---
name: setup-matt-pocock-skills
description: Configure one repository's issue tracker and domain-document layout for the Matt Pocock-derived engineering Skills. Use explicitly once per repository before $ai-workflow or the tracker-aware Skills.
---

# Setup Matt Pocock Skills

Configure the repository-specific values consumed by `$to-spec`, `$to-tickets`, `$code-review`, `$grill-with-docs`, and `$ai-workflow`. This Skill is installed in USER scope but writes only to the current repository after explicit confirmation. It never creates a Feature Run.

## Explore

Read existing evidence rather than guessing:

- repository root, `git remote -v`, and `.git/config`;
- root `AGENTS.md` and `CLAUDE.md`, including an existing bounded Agent-skills block;
- `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/`, and context-scoped ADRs;
- `docs/agents/` and `.scratch/`;
- genuine monorepo signals such as workspace manifests and multiple populated packages.

## Confirm the configuration

Take one section at a time and lead with the evidence-backed recommendation.

### Issue tracker

Explain that the tracker is where specs and tickets live. Recommend the provider matching the configured remote, with GitHub as the default when a GitHub remote exists. This release supports exactly three setup choices: GitHub, GitLab, or Local Markdown. Record exactly one choice in `docs/agents/issue-tracker.md`. If the user requests Jira, Linear, or another provider, stop and explain that its configuration contract is not defined in this release; do not hand-write an unvalidated tracker configuration.

This `ai-workflow` release executes only GitHub tracker operations. If the user chooses GitLab or Local Markdown, record the choice accurately and disclose that `$ai-workflow` will stop at its Exception Gate rather than pretending support.

### Domain docs

Default to one root `CONTEXT.md` and `docs/adr/`. Offer a `CONTEXT-MAP.md` with per-context docs only when existing monorepo evidence warrants it.

## Preview and write

Show the complete proposed files and instruction blocks before mutation. Obtain the Setup Confirmation Gate, then recheck repository identity and status.

Use these seed files as relevant:

- [issue-tracker-github.md](issue-tracker-github.md)
- [issue-tracker-gitlab.md](issue-tracker-gitlab.md)
- [issue-tracker-local.md](issue-tracker-local.md)
- [domain.md](domain.md)

Write the selected tracker instructions to `docs/agents/issue-tracker.md` and the domain instructions to `docs/agents/domain.md`. Replace template repository identifiers with the confirmed target. Never write credentials, tokens, CLI sessions, or secrets.

Use the bundled deterministic helper for every provided tracker choice. Run it without write flags to produce the preview, substituting the confirmed values:

```bash
python3 <skill-root>/scripts/configure_repository.py <repository-root> \
  --tracker github \
  --github-repository <owner/repository> \
  --remote-name <remote-name> \
  [--instruction-file AGENTS.md|CLAUDE.md]

python3 <skill-root>/scripts/configure_repository.py <repository-root> \
  --tracker gitlab \
  --tracker-repository <group/repository> \
  --remote-name <remote-name> \
  [--instruction-file AGENTS.md|CLAUDE.md]

python3 <skill-root>/scripts/configure_repository.py <repository-root> \
  --tracker local-markdown \
  [--instruction-file AGENTS.md|CLAUDE.md]
```

The preview prints a `Setup plan token` bound to the repository, fetch/push remote URLs when applicable, selected options, target-file set, baseline contents, and proposed contents. After the Setup Confirmation Gate, rerun the identical command with `--apply --confirmed --plan-token <approved-token>`. Any intervening file, routing, option, or remote change invalidates the token and requires a new preview and approval. The helper refuses an unconfirmed write, preserves content outside the managed block, rejects symlink targets, and is idempotent. Non-GitHub configuration remains truthful, but `$ai-workflow` cannot execute it in this release.

Update instruction files by these rules:

- only `AGENTS.md` exists: update `AGENTS.md`;
- only `CLAUDE.md` exists: update `CLAUDE.md`;
- both exist: update both with identical generated blocks and verify equality;
- neither exists: ask which to create, recommending `AGENTS.md` for Codex and `CLAUDE.md` for Claude.

Bound the managed content exactly:

```markdown
<!-- ai-workflow:agent-skills:start -->
## Agent skills

### Issue tracker

[one-line tracker summary]. See `docs/agents/issue-tracker.md`.

### Domain docs

[one-line domain layout summary]. See `docs/agents/domain.md`.
<!-- ai-workflow:agent-skills:end -->
```

Update only the bounded block; preserve all surrounding user content. If an unbounded legacy `## Agent skills` section exists, show the exact migration and obtain confirmation rather than duplicating it. Do not create or update triage configuration in this release, even when another triage Skill is installed.

## Validate and finish

Run the bundled `scripts/validate_setup.py <repository-root>` after writing. `$ai-workflow` runs it with `--require-github --remote-name <name>` so the validator reads that remote from the live Git worktree and compares it with the concrete configuration. Show the diff and stop without staging, committing, pushing, or starting `$ai-workflow`.

Users may edit `docs/agents/*.md` later. Re-run this Skill only to validate or intentionally change the repository setup.

## Provenance

Adapted from Matt Pocock's `setup-matt-pocock-skills` at the commit recorded in [UPSTREAM.md](UPSTREAM.md).
