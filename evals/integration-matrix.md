# Version 0.2 integration evidence

This is the release gate, not a roadmap claim. Deterministic checks prove repository invariants only. Fresh-task behavior, public installation, GitHub mutations, and delivery require direct evidence before release.

| Scenario | Required for release | Status | Evidence or blocker |
| --- | --- | --- | --- |
| `make verify` | yes | passed locally | 71 tests, 0 failures on 2026-09-14; see [deterministic evidence](evidence/full-workflow-v1-local-2026-09-14.md). |
| Base Contract tracker-reference compatibility | yes | passed locally | Base `make verify`: 31 tests, 0 failures; configured-reference positive and unsafe/malformed negative fixtures pass. |
| Official Codex Skill and Plugin validators | yes | passed locally | All 10 Skills and the Plugin passed `make canonical-validate` on 2026-09-14. Repeat at the release commit. |
| Temporary clean ten-Skill USER-scope copy | yes | passed locally | `bash evals/run-local.sh`; all Skill metadata, links, state model, and setup-validator payload are present. |
| Repeat or partial-install conflict | yes | passed locally | Runner preflights all destinations and leaves a conflicting scope untouched. |
| Migration from legacy `ship-feature` install | yes | passed locally | Synthetic runner stages and validates all 10 Skills, moves the legacy Skill to a recoverable backup, and leaves no live alias. Public installer behavior remains covered by the separate GitHub-install row. |
| Repository setup validator | yes | passed locally | All supplied tracker choices use preview-bound plan tokens; routing, confirmation, drift rejection, idempotency, concrete non-GitHub configuration, and real Git-worktree fetch/push matching pass. Missing/ambiguous/mismatched remotes, split push targets, symlink escapes, placeholders, tracker/instruction conflicts, credentials, and triage fixtures fail. |
| Install complete set from public GitHub commit | yes | not run | Requires a committed and pushed source revision, then an isolated USER-scope install pinned to that SHA. |
| Fresh Codex task loads all Skills | yes | not run | Requires the public pinned install and a restarted/new Codex task. |
| `$setup-matt-pocock-skills` behavior | yes | not run | Run scenarios for `AGENTS.md`, `CLAUDE.md`, both, and neither in disposable repos; confirm preview, gate, idempotency, and no commit. |
| Missing setup stops before Feature Run | yes | not run | Requires a fresh task against an isolated unconfigured fixture. |
| New feature Grill through GitHub parent issue | yes | not run | Requires disposable GitHub Issues and explicit Specification Gate approval. |
| Stage and Gate progress in every reply | yes | not run | Run [scenario 23](scenarios.md) in a fresh task; inspect every reply across Gates, ordinary progress, and Exception. Deterministic state-model policy is separate evidence. |
| One consequential Grill question per reply | yes | not run | Run [scenario 24](scenarios.md) with two initial decisions plus a later ADR decision; reject any reply containing two decision questions. The negative state-model fixture only checks policy integrity. |
| Independent `$grilling` and composed `$grill-with-docs` | yes | not run | Run [scenario 25](scenarios.md) in separate fresh tasks; verify the interview and domain documentation roles. |
| Ticket Breakdown through GitHub sub-issues/dependencies | yes | not run | Requires disposable GitHub Issues and explicit Ticket Breakdown approval; record native/fallback behavior. |
| Two-agent ticket execution and patch-only overlap fallback | yes | not run | Requires a Base-derived fixture with safe disjoint test and product surfaces. |
| One local commit per accepted ticket | yes | not run | Requires behavioral observation of a multi-ticket run; no push is needed for this row. |
| Review finding routing and no-progress stop | yes | not run | Requires injected production, test, and repeated specification findings. |
| Checkpoint loss and GitHub reconstruction | yes | not run | Requires existing disposable parent/tickets/branch and removal of only the test checkpoint. |
| Two concurrent tasks, different features | yes | not run | Requires separate tasks and isolated branches/worktrees. |
| Base-derived full Feature Run | yes | not run | Must run setup/preflight, Grill, spec, tickets, workers, ticket commits, feature review, and Delivery Gate. |
| Delivery Gate to test pull request | yes | blocked | Requires an approved disposable remote and explicit Delivery Gate authorization. Issues must remain open until merge. |
| Post-restart `$ai-workflow` availability | yes | not run | Restart Codex after public install and invoke from a clean task. |
| GitLab, Linear, Jira, local Markdown execution | no | unsupported | Deliberately outside 0.2. Setup may configure GitLab or Local Markdown truthfully, but `$ai-workflow` stops before a Feature Run. Linear, Jira, and other custom tracker configurations are rejected because this release defines no contract for them. |
| Automatic merge or direct issue closure | no | unsupported | Deliberately prohibited. Delivery ends after pull-request creation. |

Do not mark version 0.2 release-ready while any required row is `blocked` or `not run`. Record commands, task identifiers, output, issue/PR URLs, and resulting state when a row is exercised; never replace evidence with a prose assertion.
