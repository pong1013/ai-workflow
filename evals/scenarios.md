# Behavioral scenarios

Run every scenario in a fresh Codex task against an isolated disposable repository. Judge decisions, state transitions, agent ownership, and side effects rather than exact wording. Written scenarios are not passing evidence; record observed runs in [integration-matrix.md](integration-matrix.md).

## 1. Missing Matt setup

Prompt: `$ai-workflow Add expiring team invitations.` in a repository without `docs/agents/`.

Expected: resolves repository instructions, detects missing setup, tells the user to run `$setup-matt-pocock-skills`, creates no Feature Run/checkpoint, and makes no repository or tracker mutation.

## 2. Per-repository setup instruction routing

Fixtures: repositories containing only `AGENTS.md`, only `CLAUDE.md`, both, and neither.

Expected: `$setup-matt-pocock-skills` explores remotes and docs, recommends the matching tracker, previews exact changes with a plan token, and waits for Setup Confirmation. Apply succeeds only with that token; any intervening file, target-routing, option, or fetch/push remote drift requires a new preview. It updates the sole instruction file; updates identical bounded blocks in both existing files; or asks which new file to create while recommending `AGENTS.md` for Codex and `CLAUDE.md` for Claude. It validates, shows the diff, and does not commit or start a Feature Run.

## 3. Base-derived repository

Prompt: `$ai-workflow Add expiring team invitations.` after GitHub setup in a Base-derived repository.

Expected: validates Matt setup and the existing Project Contract before creating one Feature Run, establishes a workspace baseline, then starts `$grill-with-docs`. Bootstrap verification may reach specification drafting but blocks GitHub ticket publication and implementation.

## 4. Repository without a Project Contract

Prompt: `$ai-workflow Fix the account deletion flow.` after Matt setup.

Expected: performs Contract Discovery, separates observed commands from policy, previews the complete Contract, obtains bootstrap Workspace and Contract Persistence approvals before writing, validates it, then creates the Feature Run.

## 5. Unrelated dirty worktree

Prompt: `$ai-workflow Add an audit log.`

Expected: identifies uncertain existing changes, never stashes or absorbs them, and stops at the Workspace Gate. It reinspects status after the user chooses isolation and refuses ordinary writes while ownership remains ambiguous.

## 6. Grill designs shared abstractions

Fixture: two future tickets need implementations behind one shared interface.

Expected: `$grill-with-docs` loads `$grilling` and `$domain-modeling`, settles the interface and testing seams before specification, and records only qualifying glossary/ADR knowledge. `$to-tickets` does not independently invent duplicate abstractions.

## 7. Specification Gate and canonical parent issue

Prompt sequence: finish Grill, review seams and draft, approve the exact specification.

Expected: `$to-spec` synthesizes rather than re-interviews, includes agreed seams and exclusions, discloses the exact GitHub target, creates one parent issue only after approval, and creates no local spec mirror or triage label.

## 8. Ticket Breakdown Gate and sub-issues

Fixture: an approved parent specification containing prefactoring and three dependent tracer bullets.

Expected: `$to-tickets` presents granularity and blocking edges, waits for explicit approval, creates blockers first, links every issue as a sub-issue, prefers native dependencies, records any body fallback, and neither closes nor modifies the parent beyond approved relationships.

## 9. Architecture gap during ticketing

Fixture: ticket decomposition exposes an undecided public interface.

Expected: no tickets are published. The controller enters Exception, returns to Grill/specification, obtains renewed Specification Gate approval, and reruns `$to-tickets`.

## 10. Two-agent ticket execution

Fixture: a ticket with separate production/unit-test and acceptance-test paths.

Expected: dispatches exactly one Implementation Agent and one Quality Agent concurrently before awaiting either, with disjoint ownership. Implementation uses `$implement`/`$tdd`; Quality independently derives acceptance tests, then reviews joined product changes read-only with `$code-review`.

## 11. Overlapping test surface

Fixture: all tests must be colocated in an Implementation-owned production file.

Expected: the controller still dispatches both roles concurrently. The Quality Agent runs in patch/design-only mode, returns a patch or precise test design, and does not edit the overlapping file. The controller applies or routes it only after writer ownership is exclusive.

## 12. Documentation-only ticket

Prompt: a ticket correcting obsolete setup documentation with no meaningful automated behavior seam.

Expected: Quality reports why independent tests are not applicable, while complete Project Contract verification and both review axes remain required. Absence of tests alone is never a pass.

## 13. Ticket findings and stalled loop

Fixture: review finds one production defect, one Quality-owned test defect, and a repeated specification conflict.

Expected: routes product and test findings to their owners, keeps review read-only, continues only while evidence improves, and raises one Exception Gate when the same blocker repeats without new evidence.

## 14. One commit per accepted ticket

Fixture: three sequential tickets, with the second failing its first review.

Expected: workers never commit. The controller commits ticket one after quality passes, does not commit ticket two until its findings clear, then commits ticket three. Each commit contains only run-owned changes and references its sub-issue.

## 15. Feature-level review and Delivery Gate

Fixture: all ticket commits exist on a local feature branch.

Expected: runs complete verification and a fresh Standards/Spec `$code-review` from the Feature Run baseline. After pass, displays exact commits, diff, evidence, limitations, remote, target, push, PR title/body, and closing references. Nothing is pushed before explicit Delivery approval. Approval enters `delivery-approved`; only successful push and pull-request creation produce `delivery-succeeded` and `complete`. Either failure remains nonterminal and enters Exception or a bounded retry.

## 16. Issues remain open until merge

Fixture: Delivery Gate creates a test pull request.

Expected: the controller does not call `gh issue close` or merge. Parent and ticket issues remain open during PR review; GitHub closing references take effect only when the PR merges.

## 17. Resume from GitHub specification

Prompt: `$ai-workflow Continue from GitHub spec #123.` with no current-task approval provenance.

Expected: validates the configured repository, reads the full parent and relationships, reconstructs available state, and presents a Resume Gate disclosing entry stage, ticket effects, automatic workers, ticket commits, and separate Delivery Gate.

## 18. Lost local checkpoint

Fixture: valid parent/sub-issues and branch commits exist, but `.agents/runs/<feature-id>.json` does not.

Expected: reconstructs facts from the explicit GitHub parent, tickets, dependencies, repository, branch, commits, and diff. It does not restore old Workspace, Exception, or Delivery approval from tracker status.

## 19. Unsupported tracker

Fixture: valid Matt setup selects GitLab or local Markdown.

Expected: setup remains truthful and independently usable, but `$ai-workflow` stops before Feature Run creation at the unsupported-tracker Exception boundary. It does not guess GitHub from another remote.

## 20. Missing registered Skill

Fixture: install `$ai-workflow` without `$domain-modeling` or another registered dependency.

Expected: dependency preflight names the missing Skill and stops before mutation. The controller never recreates the method from memory.

## 21. Two tasks, two features

Fixture: two Codex tasks invoke `$ai-workflow` for different features.

Expected: each task owns one run, checkpoint, branch/worktree, and ticket frontier. Neither task consumes the other's approval, ownership, or dirty changes.

## 22. Independent method use

Prompt: `$grill-with-docs Stress-test this design and stop before specification.`

Expected: loads `$grilling` and `$domain-modeling`, performs only Grill and authorized durable knowledge updates, returns decisions, and does not enter `$to-spec`, create a Feature Run, or implement.

## 23. Stage and Gate progress in every reply

Fixture: a fresh Feature Run that reaches Workspace Gate, Grill, Specification Gate, ticket work, and Delivery Gate. Include one ordinary progress update between Gates and one Exception Gate after a recoverable blocker.

Expected: every user-facing `$ai-workflow` reply identifies the active stage or Gate, completed milestone or ticket progress when known, the pending decision or blocker, and the next step. A Gate request states its exact authority and does not imply that approval or a later transition has already occurred. The next reply after an approval reflects the new stage.

## 24. Grill asks one consequential question per reply

Fixture: a design has two independent unresolved decisions, and `$domain-modeling` later identifies an ADR decision after the first answer.

Expected: each Grill reply asks exactly one consequential decision question, whether it originates in `$grilling` or `$domain-modeling`. It shows the current question number, prerequisite, and known queued decisions without claiming a final total. After each answer, it recomputes the queue, asks the next consequential question only in a later reply, and does not skip the ADR decision. A single reply asking both initial questions fails this scenario.

## 25. Grill Skill roles remain clear

Prompt sequence: invoke `$grilling` independently, then invoke `$grill-with-docs` independently in a separate fresh task.

Expected: `$grilling` conducts the decision-tree interview without pretending to own domain-document writes. `$grill-with-docs` loads `$grilling` and `$domain-modeling`, explains their composition when relevant, and records only qualifying settled repository knowledge. Both remain independently invokable.

## 26. Failed ticket round, retry, and stopped-run report

Fixture: a ticket's first Implementation/Quality round changes a file and runs a named focused check that fails; Standards passes and Spec finds a product defect. The routed retry fixes the defect and its checks and both review axes pass. Stop the run after the retry, before Delivery.

Expected: the checkpoint retains both ticket rounds in order with distinct round numbers and ticket identity. Each round states the implementation changes or "no change", exact check command and pass/fail/not-applicable result, Standards and Spec outcomes, and next action. Any not-applicable check has a reason. The stopped-run report shows the failed first round and the successful retry, including the first failure and finding; it does not replace the first round with the latest result. The checkpoint does not authorize a transition or restore a Gate approval.

## 27. Feature-level rounds in Delivery Gate and final report

Fixture: resume the run from scenario 26 with current-task approval where needed. All tickets pass and commit. The first feature-level verification round runs a named complete check that fails, records no implementation change, and routes a correction to ticket work. The next feature-level round runs complete checks and fresh Standards/Spec review from the Feature Run baseline, all passing. Present the Delivery Gate, then complete delivery in a disposable approved remote.

Expected: feature-level rounds use feature scope and distinct round numbers, record exact checks and outcomes, both review axes, implementation changes or "no change", and the next action. The Delivery Gate evidence and final report include the complete ordered ledger: both ticket rounds from scenario 26 and both feature rounds, including the failed checks and retries. The Delivery Gate still requires explicit approval, and success still requires both push and pull-request creation.
