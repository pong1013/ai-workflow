# Ticket Commits and Delivery

## Ticket commit

After a ticket passes the Quality Agent's verification and review, show the exact run-owned changes to commit and the proposed message referencing the GitHub ticket. Recheck status, diff, and ownership immediately before staging. Stage only run-owned paths or hunks and create one local commit.

Ticket Breakdown approval and successful ticket-quality evidence authorize only that ticket's local stage and commit. They never authorize push, issue closure, pull-request creation, or unrelated changes. If changes cannot be isolated from pre-existing work, keep the ticket uncommitted and enter the Exception Gate.

## Feature review

After all ticket commits exist, run complete verification and a fresh `$code-review` from the Feature Run baseline across the whole branch. Append a feature-level round with the exact checks and separate Standards/Spec outcomes, even if it fails or has no implementation change. Resolve routed findings and repeat while evidence improves, retaining each earlier round.

## Delivery Gate

Present one exact bundle containing:

- parent issue and tickets;
- ordered ticket commits;
- the complete ordered ledger of ticket implementation/quality and feature verification/review rounds, including failures, retries, no-change rounds, exact check outcomes, both review axes, and next actions;
- run-owned diff and confirmation that unrelated changes are excluded;
- complete verification and Standards/Spec review evidence;
- known limitations and unverified integrations;
- current branch, remote, target branch, push, and pull-request title/body;
- closing references that take effect only when the pull request merges.

Explicit approval advances the run to `delivery-approved` and authorizes only the displayed push and pull-request creation. Revalidate repository, branch, commits, worktree, remote, target, and authentication immediately before acting. Record separate `push-succeeded` and `pull-request-created` evidence. If either operation fails, do not mark the run complete; retain failure evidence and enter Exception or retry only within the approved bundle. Transition to `complete` only on `delivery-succeeded` after the composite `delivery-operations-succeeded` evidence resolves. Stop on drift, force operations, changed targets, missing access, or undisclosed effects. Never merge, directly close issues, or silently broaden delivery authority.
