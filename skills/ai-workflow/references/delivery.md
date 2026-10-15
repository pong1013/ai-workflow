# Ticket Commits and Delivery

CLI options below belong to the maintainer validator in this Plugin's source repository. Installed Skills do not assume that script exists in a target repository; the controller must obtain equivalent live Git evidence and enforce the same policy using available tools.

## Deferred configuration schema and authority

Only explicit Exception approval of the exact target repository and issue title/body authorizes `create-deferred-configuration-follow-up`. The standalone GitHub issue records each exact path/hunk/contentHash, configuration provenance, reason for deferral, and originating feature issue/PR relationship. It is outside the current parent's native sub-issues and dependency graph; do not add `Part of` or closing references that imply it is a current child ticket.

The publication draft fields are `state: "exception"`, `authority: "exception"`, nonempty `approvalReference`, `artifact: "standalone-github-issue"`, `inParentChildGraph: false`, `automaticPostMergeBranch: false`, `laterRun: "origin-pr-merged-and-new-workspace-gate"`, nonempty `originatingFeature` and `reason`, and a nonempty `mutations` list. Each unique mutation contains `path`, `hunk`, full `sha256:` `contentHash`, and `provenance` (`setup/configuration` or `project knowledge`). The source validator checks this with `--deferred-follow-up <draft.json>`.

Resolve `approvalReference` against actual current-task user approval; structural validation never grants authority. Revalidate tracker identity/access before publication, retain the resulting URL and approved evidence in the checkpoint, and never publish from an evidence-only receipt. Deferral does not make pending run-owned work deliverable: isolate it safely under approved ownership and reconcile again or remain blocked.

Never create a merge-triggered branch or Feature Run. After confirming the originating PR merged, a later explicitly requested follow-up run requires its own new Workspace Gate before any branch/worktree mutation. No new baseline-acceptance Gate is introduced.

## Ticket commit

After a ticket passes the Quality Agent's verification and review, show the exact run-owned changes to commit and the proposed message referencing the GitHub ticket. Recheck status, diff, and ownership immediately before staging. Stage only run-owned paths or hunks and create one local commit.

Ticket Breakdown approval and successful ticket-quality evidence authorize only that ticket's local stage and commit. They never authorize push, issue closure, pull-request creation, or unrelated changes. If changes cannot be isolated from pre-existing work, keep the ticket uncommitted and enter the Exception Gate.

## Feature review

After all ticket commits exist, complete `configuration-reconciliation` before running complete verification and a fresh `$code-review` from the Feature Run baseline across the whole branch. Append a feature-level round with the exact checks and separate Standards/Spec outcomes, even if it fails or has no implementation change. Resolve routed findings and repeat while evidence improves, retaining each earlier round; any new fix returns through ticket work, commit, and reconciliation before another feature review.

## Delivery Gate

Always inspect the index and worktree separately, even without maintainer tooling. Capture and compare exact-byte SHA-256 digests of `git diff --cached --no-ext-diff --no-textconv --no-renames --binary --unified=0 HEAD --` and `git diff --no-ext-diff --no-textconv --no-renames --binary --unified=0 --`. Enumerate non-ignored untracked paths with `git ls-files --others --exclude-standard -z`, sort paths, and hash their concatenated records: path bytes + NUL + six-digit Git mode + NUL + ASCII byte length + NUL + exact content bytes (symlink target bytes for mode `120000`). These three hashes are `pendingDiffHashes.staged`, `.unstaged`, and `.untracked`; an empty surface hashes empty bytes. Retain them before run writes, never recapture a changed surface as the baseline. Inspect unresolved Git conflicts as blockers. Preserve unrelated work throughout.

The concrete Delivery instance retains the reconciliation instance fields plus `delivery: {"configurationReconciled": true, "residualBaselineEntries": [...]}`. Each residual entry contains `path`, `hunk`, and full `sha256:` `contentHash`; the empty list describes clean delivery. Bind each residual to the exact baseline and current HEAD-to-worktree hunk identity/hash, exclude any run-owned ledger chain, and require all pending surface hashes to equal the original baseline. The same complete baseline/ledger/receipt validation required before feature review remains required here.

Before presenting the Gate, perform the live evidence checks above; when the source maintainer validator is available, run `--delivery <instance.json> --repository-root <root>`. This reruns reconciliation and compares pending HEAD-to-worktree hunks with `workspaceBaseline.entries` and `delivery.residualBaselineEntries`. Set `delivery.configurationReconciled: true` only after successful reconciliation; the flag alone never proves it. Clean means every staged, unstaged, and non-ignored untracked surface is empty. Dirty means every residual is exact unchanged baseline unrelated work, with no run-owned ledger chain, and all three `workspaceBaseline.pendingDiffHashes` equal current raw surface digests. This detects staged changes cancelled by unstaged edits even when the final worktree equals HEAD. Capture those hashes before run writes; source maintainers can use `--emit-delivery-view`.

Disclose residual presence in this same Delivery Gate; its single approval covers preserving those hunks while excluding them from the push/PR. Do not add a baseline-acceptance Gate. Missing baseline surface evidence, changed hashes, run-owned residuals, or unexplained work block Delivery and route to configuration reconciliation or Exception. Recheck after approval and immediately before each external operation.

Present one exact bundle containing:

- parent issue and tickets;
- ordered ticket commits;
- the complete ordered ledger of ticket implementation/quality and feature verification/review rounds, including failures, retries, no-change rounds, exact check outcomes, both review axes, and next actions;
- run-owned diff and confirmation that unrelated changes are excluded;
- successful live configuration reconciliation and clean index/worktree proof, or the exact unchanged baseline unrelated residual list (path, hunk, contentHash) plus independent staged/unstaged/untracked surface hashes;
- complete verification and Standards/Spec review evidence;
- known limitations and unverified integrations;
- current branch, remote, target branch, push, and pull-request title/body;
- closing references that take effect only when the pull request merges.

Explicit approval advances the run to `delivery-approved` and authorizes only the displayed push and pull-request creation. Revalidate repository, branch, commits, worktree, remote, target, and authentication immediately before acting. Record separate `push-succeeded` and `pull-request-created` evidence. If either operation fails, do not mark the run complete; retain failure evidence and enter Exception or retry only within the approved bundle. Transition to `complete` only on `delivery-succeeded` after the composite `delivery-operations-succeeded` evidence resolves. Stop on drift, force operations, changed targets, missing access, or undisclosed effects. Never merge, directly close issues, or silently broaden delivery authority.
