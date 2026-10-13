# Configuration Reconciliation

Configuration reconciliation accounts for durable repository changes before feature review. It is an automatic state with deterministic evidence, not a new user approval Gate.

## Workspace baseline

Also capture `workspaceBaseline.pendingDiffHashes` before the first write. Those staged, unstaged, and untracked surface digests are required to prove unchanged residual work at Delivery; a final composite diff alone cannot detect staged edits cancelled in the worktree. Follow [delivery.md](delivery.md). CLI examples here describe this Plugin source repository's maintainer validator, not a universally installed runtime prerequisite; installed controllers must still produce equivalent live Git evidence and enforce these boundaries.

Capture the baseline after workspace ownership is established and before the first Feature Run write. Anchor it to the resolved Feature Run base commit and enumerate every tracked, staged, unstaged, untracked, deleted, renamed, and binary diff. Each baseline entry has:

- `path`: the repository-relative path reported by Git; a rename also retains its source in the hunk descriptor;
- `hunk`: the exact zero-context unified-diff range, `whole-file` when line hunks do not apply, or `file-mode` for a Git mode transition;
- `contentHash`: a `sha256:` digest of the canonical patch body; whole-file entries hash `git-mode` + NUL + the final six-digit Git mode + NUL + exact bytes, and file-mode entries hash the before mode + NUL + after mode.

Record separate entries for separate hunks in one file. A path-only status list is not a baseline. Preserve the original entries for the life of the run; later observations belong in the mutation ledger.

Use the controller validator to produce the canonical observable view:

```text
python3 scripts/validate_state_machine.py <model> \
  --repository-root <root> --baseline <base-commit> \
  --emit-reconciliation-view
```

The emitted view combines the base-to-`HEAD` committed diff, index changes, unstaged changes, and non-ignored untracked files. Its patch command is `git diff --no-ext-diff --no-textconv --no-renames --binary --unified=0 <base-commit> -- <path>`: external diff programs and textconv drivers must not transform the bytes used for reconciliation hashes. Text changes remain separate line hunks; untracked and binary changes use `whole-file`. Each entry includes `surface` (`committed`, `staged`, `unstaged`, `untracked`, or `mixed` with its `origins`) plus `beforeHash` and `afterHash` for ledger anchoring. The view represents each final hunk once even when more than one Git surface contributed to it.

Text side hashes preserve the exact affected bytes, including embedded CR and whether the final line ends in LF: split patch records only at LF, preserving every other byte as source content; Git's no-newline marker removes the synthetic patch LF only from its preceding side. Whole-file side hashes remain hashes of exact bytes so setup receipt terminal hashes retain their existing binding. Those byte hashes alone do not cover mode. Every tracked Git mode transition also emits a separate `file-mode` entry whose side hashes bind the six-digit before and after modes (including `000000` for absence), so content and mode changes require their own ledger chains. Untracked files use their regular, executable, or symlink Git mode in whole-file identity; executable and symlink entries additionally emit a mode transition from the default regular-file mode `100644`. A stale content event cannot explain a missing or changed mode event, including when content and mode change together.

## Mutation ledger

Append one event after each meaningful workflow action that changes repository content. Do not record keystrokes. Every event contains `sequence`, `stage`, nullable `ticket`, `provenance`, `path`, `hunk`, `beforeHash`, and `afterHash`. Sequence is globally monotonic. For a logical path/hunk chain, the next `beforeHash` must equal the preceding `afterHash`; if shifted context makes identity ambiguous, enter Exception instead of guessing.

Use exactly one of these provenance categories:

- `ticket-owned`: change authorized by the current approved ticket;
- `setup/configuration`: validated repository-setup output;
- `project knowledge`: durable domain or ADR knowledge written during Grill;
- `pre-existing unrelated`: an unchanged hunk captured in the workspace baseline.

Every event stage must be a registered workflow state. `ticket-owned` events require a non-empty approved ticket identifier. `setup/configuration` and `project knowledge` events also require an approved ticket unless `approvedAlternatives` binds that event sequence to explicit `exception` authority and retains a non-empty `approvalReference`. The deterministic validator checks this structural evidence, while the controller must resolve the reference against the current task's actual Exception approval; checkpoint text never creates authority. A `pre-existing unrelated` event cannot claim a ticket or explain new work: it must bind the same key and unchanged content/terminal hashes already present in the workspace baseline.

Do not relabel history. A later authorized change to a baseline hunk is a new event with its own provenance; it is no longer eligible to pass as unchanged `pre-existing unrelated` work.

Derive the current view from the latest `afterHash` of each ledger chain plus baseline entries that have no later event. The first event for a chain binds to the emitted baseline/current-view `beforeHash` (or a baseline entry's emitted `afterHash`), adjacent event hashes must join exactly, and the terminal hash binds to the emitted live `afterHash`. An imported receipt may explain history that predates baseline capture: validate its import first, then bind the terminal `afterHash` of the imported setup prefix to the matching baseline `afterHash`, rather than requiring its historical `beforeHash` to equal the baseline. Any subsequent run events continue from that terminal state, and the complete chain still binds to the live hunk without applying setup a second time. Compare every resulting path/hunk/hash with the combined live Git view. Also reject live hunks that are neither baseline-accounted nor represented by an event. The round ledger explains attempts and checks; the mutation ledger explains repository causality. Neither replaces the other.

## Setup receipt import and routing

A receipt under `.agents/setup/` is local evidence, never approval authority. Before import, run the setup receipt validator against the current repository, the approved plan token when available, and all rendered outputs. This independent setup validation owns receipt schema, plan binding, render equivalence, and live setup-output validation; configuration reconciliation does not duplicate the setup renderer.

Import only the validated receipt's changed paths/hunks as `setup/configuration` events. Each `setupReceiptImports` record identifies its `eventSequence`, retains a repository-local `.agents/setup/` `receiptPath` and the `receiptChecksum` of its exact bytes, declares `evidenceOnly: true` and `approvalAuthority: false`, and binds the receipt's `terminalHash` to that event's `afterHash`. The reconciliation validator rejects a missing/unsafe receipt reference or checksum drift, preserving the exact artifact that passed independent validation. Do not infer provenance from render-equivalent content when the receipt is missing or invalid.

Classify the validated setup output before ticket publication:

- Mechanical, preview-approved setup required for this feature becomes the current Feature Run's first blocker ticket.
- A semantic workflow change, product-scope expansion, or Project Contract conflict enters Exception so the user can include it explicitly or move it to a separate Feature Run.

Project-knowledge writes follow the same ownership rule: include them in an approved ticket or obtain the explicitly approved alternative recorded by the controller. The Feature Run request and workspace evidence authorize the write during Grill, but do not by themselves authorize its eventual commit.

## Reconciliation state

Enter `configuration-reconciliation` after the last ticket commit. Re-capture the live status/diff, validate the append-only sequence and every hash chain, derive the current view, and compare it with the live diff. Reconciliation passes only when:

1. every live durable mutation has a valid ledger event;
2. every event uses a registered provenance category and resolves to its approved ticket or disposition;
3. setup receipts used as evidence still validate and are not treated as authority;
4. project-knowledge and setup/configuration changes are ticket-owned or have an explicitly approved alternative;
5. each `pre-existing unrelated` hunk is byte-for-byte identical to its baseline identity; and
6. the resulting current view exactly matches the live diff.

Invalid provenance, a broken hash chain, a missing event, a changed baseline hunk, or any unexplained mutation prevents `configuration-reconciled` evidence. Route an owned fix back through ticket work; route a consequential classification, scope, Contract, or evidence gap to Exception. Feature review cannot start until reconciliation passes.

Validate the concrete checkpoint instance, rather than only the policy model:

```text
python3 scripts/validate_state_machine.py <model> \
  --repository-root <root> --reconciliation <instance.json>
```

The instance contains `workspaceBaseline` (`baseCommit` and path/hunk/hash `entries`), the complete `mutationLedger`, optional Exception-authorized `approvedAlternatives`, and `setupReceiptImports`. Sequence gaps or reordering, unknown stages, missing ticket/disposition ownership, false pre-existing provenance, broken per-hunk chains, baseline drift, unexplained live hunks, missing events, authoritative receipt claims, missing/drifted validated-receipt references, and receipt terminal mismatches fail deterministically.

## Resume and legacy evidence

On resume, validate the repository identity, baseline, complete mutation history, receipt references, and live diff again. A checkpoint created before this model, or any checkpoint lacking valid baseline or ledger evidence, remains `unverified`. Do not synthesize historical events, infer approval from Git commits, or silently upgrade legacy state. Use independently valid evidence where available; otherwise present the unresolved provenance at the Resume or Exception Gate.
