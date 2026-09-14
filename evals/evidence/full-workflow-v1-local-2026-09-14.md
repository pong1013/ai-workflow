# Full Workflow v1 local evidence — 2026-09-14

## Environment

- Repository: `/Users/pong/Documents/chien/ai-workflow`
- Branch: `codex/split-workflow-skills`
- Matt upstream pin: `3cca18b368ae95cdbdebbff572ccafa662551015`
- Python dependency: `PyYAML==6.0.2` in an isolated temporary virtual environment

## Deterministic verification

Command:

```bash
make verify
```

Result: 71 tests, 0 failures.

Coverage includes Plugin and Skill metadata schemas with negative fixtures, exact ten-Skill inventory and state inventory, explicit invocation policy, Markdown links, v2 state transitions, setup-time Exception routing, branch/worktree and external-operation authorities, composite authority integrity, machine-readable worker ownership/review-loop policy, bootstrap Contract and checkpoint authorities, ticket-quality commit authority, Delivery approval/success separation with composite push/PR evidence, staged complete-set installation instructions, Matt provenance/license payloads, no-commit `$implement`, GitHub publication gates, deterministic setup routing/idempotency and preview-bound plan-token drift rejection, real Git-worktree fetch/push identity matching, symlink-escape rejection, concrete non-GitHub validation, rejection of undefined tracker providers, exact managed-block provider/repository/root consistency, credential/triage rejection, bounded non-GitHub seeds, runtime safety wiring, and absence of a published `$ship-feature` alias.

## Official validators

Command:

```bash
make canonical-validate
```

Result: all 10 Skills reported valid and the Plugin validator passed.

## Isolated USER-scope packaging

Command:

```bash
bash evals/run-local.sh
```

Results:

- clean temporary ten-Skill install passed;
- repeat install stopped during preflight;
- partial conflict prevented all additional copies;
- legacy `ship-feature` migration retained a recoverable backup and installed no live alias;
- installed metadata, self-contained Markdown links, state model, provenance/license payloads, and setup validator passed;
- the source repository status was unchanged by the runner.

## Base compatibility

Command in `/Users/pong/Documents/chien/vibe-engineering-base`:

```bash
make verify
```

Result: 31 tests, 0 failures. The Base Contract validator accepts safe `configured by` tracker references and rejects unsafe or malformed references while retaining bootstrap verification status.

## Limitations

This file contains local deterministic and packaging evidence only. It does not prove public GitHub installation, fresh-task Skill loading, model behavior, GitHub issue/sub-issue/dependency mutations, parallel worker behavior, ticket commits, checkpoint reconstruction, push, or pull-request delivery. Those rows remain `not run` or `blocked` in the integration matrix.
