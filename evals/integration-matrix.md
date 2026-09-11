# Version 1 integration evidence

This is a release gate, not a roadmap claim. `make verify` covers deterministic repository checks; rows below require evidence from the named environment before version 1 is published.

| Scenario | Status | Evidence or blocker |
| --- | --- | --- |
| Temporary clean USER-scope copy | passed locally | `bash evals/run-local.sh`; see `evals/evidence/local-packaging-2026-09-11.md` |
| Repeat install conflict | passed locally | The local runner requires exit 17 and preserves the first install. |
| Official Codex Skill and Plugin validators | passed locally | `make canonical-validate` with pinned PyYAML 6.0.2 on 2026-09-11. Repeat before release. |
| Install from public GitHub URL | blocked | Repository has no remote or published `main` branch. |
| Fresh Codex task loads installed Skill | blocked | Requires the published install path and a new Codex task. |
| Explicit `start with grill` | not run | Run the behavioral scenario in an isolated Codex task. |
| Explicit `skip grill` | passed by forward test | Independent read-only evaluation; see [forward-test evidence](evidence/forward-skip-grill-2026-09-11.md). |
| Two concurrent Codex tasks, different features | not run | Requires two isolated branches or worktrees and task-level observation. |
| Base-derived full Feature Run | not run | Requires a published install and a disposable derived repository. |
| Delivery Gate to test pull request | blocked | Requires an approved disposable remote and explicit Delivery Gate approval. |
| GitHub Issues | not run | External tracker mutation requires a disposable project and approval. |
| GitLab Issues / merge request | not run | External tracker and remote mutation require disposable targets and approval. |
| Linear | not run | External tracker mutation requires a disposable workspace and approval. |

Do not mark the plugin release-ready while any required row is `blocked` or `not run`. Record commands, task identifiers, relevant output, and resulting URLs when a row is exercised; never replace evidence with a prose assertion.
