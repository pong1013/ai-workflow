# Configuration reconciliation lifecycle

`$ai-workflow` accounts for durable configuration as part of the requesting feature. Configuration reconciliation is an automatic state before feature review, not a new approval Gate. The controller owns transitions, ticket commits, and external operations; workers return changes and evidence without committing.

## From setup to a Feature Run

1. Explicitly invoke `$setup-matt-pocock-skills`. Its preview binds the exact outputs, options, remote identity, and preserved content to a plan token. Setup Confirmation approves that exact preview. Apply refuses drift and validates effective ignore coverage before writing.
2. A successful mutating apply writes ignored `.agents/setup/receipt.json`. A no-op apply leaves any existing receipt untouched. Setup validates and reports changes but never commits or pushes.
3. `$ai-workflow` checks repository instructions, tracker identity, live remotes, tools/access, and the Project Contract. Missing setup stops before a Feature Run. Unsupported tracker execution or conflicts enter pre-run Exception. Contract persistence and branch/worktree mutation retain their own explicit authorities.
4. Establish workspace ownership and capture the resolved base commit, path/hunk/hash baseline, and independent pending Git surface hashes before the first run write. A baseline records unrelated work without authorizing changes to it.
5. Validate any setup receipt before importing it. Mechanical, preview-approved setup required by the feature becomes its first blocker ticket. Semantic workflow changes, product-scope expansion, or Project Contract conflicts enter Exception for an explicit inclusion or separate-run decision. Grill project-knowledge writes also need approved ticket ownership or an explicit Exception disposition before commit/reconciliation.
6. Publish the canonical GitHub parent only after Specification approval, and the blocker graph only after Ticket Breakdown approval. Implement and independently verify/review one dependency-ready ticket at a time. Append mutation events after meaningful actions; retain failed quality rounds separately. Commit each ticket only after ticket-quality passes.
7. After the final ticket commit, enter `configuration-reconciliation`. Resolve all live mutations and hash chains before complete feature verification and fresh Standards/Spec review. A new owned fix repeats ticket work, quality, commit, and reconciliation.
8. Validate Delivery against live index/worktree surfaces, disclose exact residual baseline work in the existing Delivery Gate, then obtain approval of the push/PR bundle. Complete only after both operations succeed. Issues close through PR closing references after merge; the controller never merges or directly closes them.

## Baseline and observable Git views

Run from the repository root, substituting its resolved feature base SHA:

```sh
python3 scripts/validate_state_machine.py skills/ai-workflow/references/state-machine.json \
  --repository-root . --baseline <base-sha> --emit-reconciliation-view
python3 scripts/validate_state_machine.py skills/ai-workflow/references/state-machine.json \
  --repository-root . --emit-delivery-view
```

Copy the first output into `workspaceBaseline`; also retain the second output's `pendingDiffHashes` there before writes. Reconciliation combines committed base-to-HEAD changes, index, unstaged, and non-ignored untracked changes into one final view. Delivery uses HEAD as its comparison base and additionally hashes staged and unstaged raw patches independently, plus a length-delimited untracked path/mode/content stream. Thus base=A, index=B, worktree=A is dirty even though its final worktree diff is empty. Ignored disposable runtime files are outside the observable durable scope; tracked files remain observable regardless of ignore rules.

Every baseline entry retains `path`, `hunk`, `contentHash`; retain emitted `beforeHash`, `afterHash`, `surface`, and mixed `origins` too. Text entries hash the exact zero-context patch body; side hashes preserve CR and final LF bytes. Binary/untracked whole-file identities bind Git mode and exact bytes. A tracked mode change gets its own `file-mode` entry. Renames are observed with `--no-renames` as deletion/addition; never infer identity from a filename. External diff and textconv transformations are disabled. Ambiguous shifted hunk identities block instead of being guessed.

For an illustrative tracked file changing `A\n` to `B\n`, the observable entry is shaped as follows. Digest notation in these documentation examples is symbolic; use the full emitted `sha256:` plus 64 lowercase hex digits in executable instances.

```json
{
  "baseCommit": "<resolved-base-sha>",
  "entries": [{
    "path": "config.txt", "hunk": "@@ -1 +1 @@",
    "contentHash": "sha256:<digest of -A\\n+B\\n>",
    "beforeHash": "sha256:<digest of A\\n>",
    "afterHash": "sha256:<digest of B\\n>", "surface": "unstaged"
  }],
  "pendingDiffHashes": {
    "staged": "sha256:<digest of staged patch>",
    "unstaged": "sha256:<digest of unstaged patch>",
    "untracked": "sha256:<digest of untracked stream>"
  }
}
```

The exact empty-byte digest, useful for a clean baseline, is `sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

## Append-only mutation ledger

Each meaningful action appends one event per affected path/hunk, never a keystroke log. `sequence` starts at 1 and is contiguous globally; `stage` is a registered controller state; `ticket` is an approved issue identifier string or null. Four provenance categories are valid:

| Category | Meaning and ownership |
| --- | --- |
| `ticket-owned` | Approved current ticket work; non-null approved ticket required. |
| `setup/configuration` | Independently validated receipt output; ticket or explicit Exception alternative required, with one receipt import per event. |
| `project knowledge` | Durable domain/ADR knowledge; ticket or explicit Exception alternative required. |
| `pre-existing unrelated` | Exact unchanged baseline hunk; null ticket, unchanged content/terminal hashes, no new work claim. |

```json
{
  "sequence": 1, "stage": "ticket-work", "ticket": "#11",
  "provenance": "setup/configuration", "path": "docs/agents/domain.md",
  "hunk": "@@ -0,0 +1,14 @@",
  "beforeHash": "sha256:<before affected bytes>",
  "afterHash": "sha256:<after affected bytes>"
}
```

The first event anchors to the live before-state or captured baseline after-state; each next `beforeHash` equals the preceding `afterHash`, and the terminal state matches the live view. An independently validated imported setup prefix may predate baseline capture: its terminal state must bind to the baseline before later events continue. Import does not replay setup. Do not relabel history: authorized changes to a baseline hunk append new owned events and lose eligibility as unchanged unrelated residuals.

For a null-ticket setup/project-knowledge disposition, `approvedAlternatives` binds `eventSequence`, `authority: "exception"`, and a nonempty `approvalReference`. The controller resolves that reference against actual user approval; a JSON string never creates authority. The separate round ledger records attempts, exact checks, both review axes, and next actions, preserving failures and retries.

## Setup receipt schema and trust

The setup renderer emits schema version 1 with `repository` identity (`root`, `remoteName`, `tracker`, `trackerRepository`), `approvedPlan` (token, tracker, repository options, remote name, domain layout, instruction file), matching top-level `planToken`, nonempty `mutations`, `approvalAuthority: false`, and `checksum`. Remote URLs participate in plan-token binding rather than being copied into receipt identity. Each mutation contains `path`, `scope` (`complete-file` for agent docs, `ignore-rule` for `.gitignore`, or `managed-block` for instruction files), `existed`, full-file `beforeHash`/`afterHash`, `provenance: "setup/configuration"`, and changed `hunks`. Each hunk has a sequential `index` and before/after records containing `startLine`, `lineCount`, and `hash`. The checksum hashes canonical JSON excluding the checksum field.

For example, a one-line insertion has `before: {"startLine": 1, "lineCount": 0, "hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}` and an `after` record with start line 1, count 1, and the inserted line's digest. Complete `docs/agents/*.md` outputs are render-validated; only bounded managed instruction blocks in `AGENTS.md`/`CLAUDE.md` are render-compared, preserving surrounding user content. Every unchanged output in the plan is also re-rendered. Render equivalence and setup idempotency remain separate checks.

```sh
python3 skills/setup-matt-pocock-skills/scripts/validate_setup_receipt.py . \
  --plan-token <retained-approved-token>
```

Omit the optional token only when unavailable, recording that limitation. This validator checks schema, self-integrity, repository/plan binding, live outputs and changed hunk hashes. Missing, stale, mismatched, or non-self-consistent evidence remains unverified; render-equivalent content alone cannot establish historical provenance.

After independent receipt validation, record one import per setup event:

```json
{
  "eventSequence": 1, "receiptPath": ".agents/setup/receipt.json",
  "receiptChecksum": "sha256:<digest of exact receipt file bytes>",
  "terminalHash": "sha256:<matching event afterHash>",
  "evidenceOnly": true, "approvalAuthority": false
}
```

The import checksum covers the entire receipt file's exact bytes and differs from its internal canonical-JSON checksum. Reconciliation checks the safe repository-local reference, exact-byte checksum, terminal binding, and every event chain; it does not duplicate the setup renderer. Preserve the referenced bytes if later setup would replace a receipt; revalidate any retained local receipt before import.

Receipts and checkpoints are local, non-authoritative evidence, never credentials or signatures. They detect accidental corruption, stale data, and non-self-consistent edits. A local actor who can rewrite both the evidence and its unkeyed checksum can forge self-consistency; defending against that requires an external trust anchor or managed signing key and is outside this release's approved threat model. Valid evidence cannot replace Setup, Workspace, Specification, Ticket Breakdown, Exception, Resume, or Delivery approval.

## Reconciliation outcomes and Delivery proof

```sh
python3 scripts/validate_state_machine.py skills/ai-workflow/references/state-machine.json \
  --repository-root . --reconciliation <instance.json>
```

The instance contains `workspaceBaseline`, complete `mutationLedger`, `setupReceiptImports` (empty when unused), and optional `approvedAlternatives`. Pass requires registered categories/stages, owned dispositions, contiguous sequences, anchored/joined/terminal hash chains, exact baseline identities, non-authoritative receipt imports, and no unexplained live hunks. Success supplies `configuration-reconciled` state evidence, allowing feature review. Missing events, broken chains, drift, invalid receipts, or changed unrelated hunks block. Owned fixes return to ticket work; consequential scope/Contract/provenance gaps enter Exception. Deterministic success does not establish external behavioral/E2E release readiness.

Before Delivery add:

```json
"delivery": {
  "configurationReconciled": true,
  "residualBaselineEntries": [
    {"path": "config.txt", "hunk": "@@ -1 +1 @@",
     "contentHash": "sha256:<exact unchanged baseline patch digest>"}
  ]
}
```

Use an empty list for clean delivery. Run `--delivery <instance.json> --repository-root .` with the same model. It reruns live reconciliation; the cached boolean cannot bypass it. Every pending hunk must match baseline and disclosure and have no owned mutation chain. Dirty surfaces must exactly match captured `workspaceBaseline.pendingDiffHashes`. Missing surface evidence remains unverified, including legacy baselines. Cancellations between index and worktree cannot pass as clean. Conservative raw-surface comparison can block moved hunk coordinates after feature edits; preserve work and resolve the ambiguity through Exception rather than weakening hashes.

The existing Delivery Gate displays all residual path/hunk/hash identities and continued presence alongside ordered ticket commits, complete round ledger, verification/review, limitations, branch/remote/target, exact push and PR body/closing references. One Delivery approval covers residual presence and the displayed operations; no additional baseline-acceptance Gate exists. Revalidate live evidence immediately before external operations. Drift routes back to reconciliation/Exception, never silent staging or absorption. Push/PR failure retains nonterminal evidence; both successes are needed for completion.

## Deferred configuration follow-ups

Intentional deferral requires explicit Exception approval of the exact standalone GitHub issue and target repository. Record exact mutation identities, provenance, reason, and originating feature issue/PR relationship. The issue is outside the current parent's child-ticket/dependency graph, and creates no automatic branch or run. A draft is structurally checkable with `--deferred-follow-up <draft.json>`:

```json
{
  "state": "exception", "authority": "exception",
  "approvalReference": "current task user decision approving this exact issue",
  "artifact": "standalone-github-issue", "inParentChildGraph": false,
  "automaticPostMergeBranch": false,
  "laterRun": "origin-pr-merged-and-new-workspace-gate",
  "originatingFeature": "https://github.com/owner/repo/issues/10",
  "reason": "Semantic configuration change deferred from this feature",
  "mutations": [{"path": "docs/agents/domain.md", "hunk": "@@ -1 +1 @@",
    "contentHash": "sha256:<exact patch digest>", "provenance": "setup/configuration"}]
}
```

Structural validation checks required evidence and declared boundaries, not actual GitHub publication or approval authenticity. The controller must resolve the approval reference and recheck tracker identity/access before publishing. A deferred issue is no excuse to deliver pending run-owned changes: isolate them only under approved ownership and reconcile again, or remain blocked. After confirming the origin PR merged, a later explicit request starts a new Feature Run with a new Workspace Gate before branch/worktree mutation.

## Resume and troubleshooting

Checkpoints at ignored `.agents/runs/<feature-id>.json` cache identities, baseline, full mutation/round history, receipt imports, dispositions, and approval references. Resume revalidates live repository, branch, GitHub relationships, diffs and receipt bytes. Missing historical provenance stays `unverified`; do not fabricate events from commit messages, silently upgrade old checkpoints, or restore approvals from checkpoint text. Use a Resume Gate when current-task approval is unavailable, and Exception for unresolved causality.

| Symptom | Required response |
| --- | --- |
| Receipt checksum, repository, token or rendered output drift | Preserve evidence, validate independent source, mark unverified and enter Exception if unexplained. |
| Missing receipt despite matching managed output | Do not infer setup causality from rendering; obtain independent evidence or an Exception disposition. |
| Missing event, discontinuous sequence, unknown provenance/stage | Resolve owned evidence/fix without rewriting prior history; reconcile again. |
| Baseline content/mode/hunk changed | Stop calling it unrelated; resolve ownership through reconciliation/Exception. |
| Delivery disclosure incomplete or raw index/worktree hashes changed | Block Delivery and inspect both surfaces; do not stash/stage unrelated changes. |
| Legacy checkpoint lacks baseline/ledger/surface proof | Keep it unverified, reconstruct only independently supported facts, use Resume/Exception for gaps. |
| Follow-up proposes a child link or automatic post-merge branch | Correct the exact standalone draft; retain explicit Exception and later Workspace boundaries. |
| Canonical checks pass but integration is untested | Report separate external behavioral evidence and its limitation; do not claim release readiness. |

The canonical repository check is `make verify`; behavioral scenarios in `evals/scenarios.md` describe the separate external gate. State/authority mappings live in `skills/ai-workflow/references/state-machine.json`, with concrete instance checks in `scripts/validate_state_machine.py`.
