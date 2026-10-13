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

Expected: `$to-tickets` presents granularity and blocking edges, waits for explicit approval, creates blockers first, links every issue as a sub-issue, prefers native dependencies, records any body fallback, and neither closes nor modifies the parent beyond approved relationships. After a blocker ticket passes ticket-level verification and review and receives its local ticket commit, its dependent ticket enters the ready frontier even though the blocker issue remains open; the controller does not wait for final pull-request merge.

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

Expected: enters `configuration-reconciliation` before feature review, derives the current provenance view from the append-only mutation ledger, and compares it with the complete run surface from Feature Run base through committed, staged, unstaged, and untracked changes while preserving unchanged baseline-unrelated hunks. This is deterministic state evidence, not a new user Gate. Only `configuration-reconciled` evidence permits complete verification and a fresh Standards/Spec `$code-review` from the Feature Run baseline. After pass, displays exact commits, diff, evidence, limitations, remote, target, push, PR title/body, and closing references. Nothing is pushed before explicit Delivery approval. Approval enters `delivery-approved`; only successful push and pull-request creation produce `delivery-succeeded` and `complete`. Either failure remains nonterminal and enters Exception or a bounded retry.

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

## 28. Reconciliation rejects invalid or unexplained mutations

Fixture: after the final ticket commit, exercise separate disposable runs with an invalid provenance category, duplicate or out-of-order event sequence, broken per-hunk before/after chain, missing event, changed baseline-unrelated hunk, and an unexplained live hunk. Include a previously valid `old\n` → `new\n` ledger event whose live text loses its final LF, a valid ledger for `new\rhidden-one\n` whose live text becomes `new\rhidden-two\n` (also exercise CRLF, vertical-tab, and form-feed content), and a pre-existing binary baseline hunk whose bytes remain unchanged while its mode changes from `100644` to `100755` without a ledger event. Configure a lossy textconv that hides `hidden-*` suffixes, retain a visible `visible` → `changed` hunk, accept a ledger for raw `changed hidden-two\n`, then reject that stale ledger after raw content becomes `changed hidden-three\n`; both emitted content and terminal hashes must change.

Expected: each case remains in `configuration-reconciliation`; none produces `configuration-reconciled` evidence or starts feature review. An owned implementation or test defect returns through ticket work, quality, commit, and reconciliation. A consequential classification, scope, Contract, or evidence gap enters Exception. Earlier mutation and round history remains append-only.

## 29. Setup receipt import is evidence, not authority

Fixture: a real approved setup apply creates and validates a receipt for A→B before the Feature Run captures baseline B. Its changed hunk is imported with the original A→B hashes and terminal B, followed by variants whose import claims approval authority, whose receipt checksum drifted, whose terminal hash does not bind to the baseline/live hunk, and whose live output drifted.

Expected: the valid receipt imports only its changed hunks as `setup/configuration` evidence and is not applied twice. Reconciliation accepts the historical event by binding its terminal B to captured baseline B rather than requiring its pre-run A to start a new B-based mutation chain. Mechanical preview-approved setup becomes the Feature Run's first blocker ticket; semantic, scope-expanding, or Contract-conflicting setup enters Exception. Authority-bearing, checksum-drifted, terminal-hash-mismatched, or drifted imports remain unverified and cannot satisfy reconciliation.

## 30. Project knowledge and legacy checkpoints require evidence

Fixture: one run writes durable project knowledge during Grill without ticket ownership; another resumes a checkpoint created before mutation provenance existed.

Expected: the project-knowledge write must enter approved ticket scope or an explicitly approved alternative before reconciliation. The legacy checkpoint remains unverified and is never silently upgraded; independently valid evidence may be imported, otherwise the unresolved provenance appears at Resume or Exception.

## 31. Clean reconciliation precedes feature review and Delivery

Fixture: all ticket changes are verified and committed in a disposable clean repository. Validate the concrete mutation ledger against the Feature Run base, then complete feature verification and a fresh Standards/Spec review. Repeat with a missing mutation event while retaining a declared `configurationReconciled: true` flag.

Expected: only the successful live reconciliation enters feature review. A clean index and worktree pass the Delivery residual check; the declared flag cannot bypass invalid live reconciliation. The existing Delivery Gate approves the exact push and pull-request bundle, and both operations must succeed before completion.

## 32. Exact unchanged unrelated residuals use the existing Delivery Gate

Fixture: capture unrelated staged, unstaged, and untracked changes at Workspace with exact path/hunk/hash and independent pending-surface hashes. Complete and commit all ticket-owned changes without touching these residuals. Supply the unchanged residual entries in the Delivery evidence. Repeat with omitted or changed disclosure hashes, and with unchanged final file bytes but a transfer from unstaged to staged state.

Expected: the exact unchanged unrelated baseline is permissible only with exact disclosure in the existing Delivery Gate; that same approval covers its presence without adding a new Gate. Missing or changed evidence blocks Delivery and routes to reconciliation or Exception. A staged/unstaged transfer is baseline drift even when the final durable diff is identical.

## 33. Net-zero durable diff is not a clean Git workspace

Fixture: starting with base content A, stage content B, then restore worktree content A while leaving index B. The final base-to-worktree diff is empty but `git status` still shows staged and unstaged changes. The Workspace baseline was clean.

Expected: Delivery fails because the actual index and worktree have unexplained pending changes. No `configurationReconciled` declaration or empty final-diff view can turn this into a clean workspace. Independent staged and unstaged surface evidence must be checked before Delivery.

## 34. Approved configuration deferral creates only a standalone follow-up

Fixture: present an Exception proposal naming the exact deferred configuration path/hunk/hash, provenance category, reason, and originating feature. Approve that exact standalone GitHub follow-up issue. Exercise variants without Exception approval, without exact evidence, with current-parent child/dependency membership, and with automatic post-merge branch creation. After merging the original feature, explicitly invoke a later run for the follow-up.

Expected: only the exact approved Exception proposal authorizes standalone follow-up publication. The follow-up records the originating feature relation without entering its child/dependency graph. Deferral cannot itself make unexplained live changes deliverable; the original run still satisfies reconciliation and residual Delivery checks. No branch or Feature Run starts automatically after merge. The later explicitly invoked run waits until the original pull request has merged and passes a new Workspace Gate. Invalid variants remain at Exception and do not publish.

## 35. Setup preserves an effective broad receipt ignore rule

Fixture: a disposable repository has a valid GitHub origin and an existing user-owned `.gitignore` with `.agents/`. Preview setup, apply the exact approved plan token, then run receipt validation and general setup validation with the required GitHub remote. Separately append an effective `!.agents/setup/` negation after a valid setup, and retain the fixtures that repair a root negation or reject an ineffective proposed rule caused by a nested ignore file.

Expected: the broad rule produces no `.gitignore` preview mutation and its bytes survive apply unchanged. Git ignores the resulting receipt, and both validators pass. An effective negation fails general setup validation even when the literal `.agents/setup/` line remains. Setup repairs a repairable root negation only through its preview-approved write; an ineffective proposed rule fails before managed files or receipts are written.

## 36. Proven canceled actions retain their append-only history

Fixture: commit base text `A\n`, record a real Git-derived ticket-owned `A\n` → `B\n` hunk, then record its inverse and restore committed `A\n` with clean index/worktree. Keep both events and a clean captured baseline. Repeat with embedded CR bytes, binary whole-file changes, mode changes, untracked creation/deletion, and a canceled text hunk alongside an accounted distant live hunk. Record insertion/deletion inverses with their original historical hunk identity and independently Git-derived side hashes. Negative variants forge only the initial hash, only the terminal hash, both equal endpoints, an unknown/out-of-range hunk, a broken link, or subsequent live drift. Also exercise count-changing cancellation alongside a remaining live hunk and disappearance of a pre-existing unrelated baseline hunk.

Expected: proven unchanged-range text, whole-file, mode, and absent untracked cancellations reconcile without removing history; clean Git state can then pass Delivery. Count-changing insertion/deletion histories also reconcile when exact whole-file base/live restoration proves the original side range. Equal endpoint hashes alone do not establish baseline anchoring. Invalid anchors, chains, ranges, drift, count-changing cancellation with ambiguous remaining same-file changes, and disappearance of baseline unrelated evidence remain blocked. Preserve scenario 33: a staged `B` with worktree `A` still blocks Delivery even after a valid earlier cancellation.
