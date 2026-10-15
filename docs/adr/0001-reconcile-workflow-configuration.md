# Reconcile workflow-generated configuration before delivery

Workflow-generated durable configuration must carry action-level, append-only provenance and be reconciled against the live Git diff before feature review and delivery. This preserves the causal boundary between ticket-owned, setup/configuration, project-knowledge, and pre-existing unrelated changes without turning the checkpoint into a keystroke-level audit log.

Mechanical, preview-approved setup output may enter the requesting Feature Run as its first blocker ticket; semantic, scope-expanding, or Contract-conflicting setup changes require an Exception decision. Unchanged baseline unrelated changes are re-disclosed within the existing Delivery Gate rather than through a new gate, while intentionally deferred configuration becomes an explicitly approved standalone GitHub follow-up issue and never triggers automatic post-merge branch creation.

To preserve provenance when setup and feature execution occur in different Codex tasks, a successful setup apply writes a credential-free receipt under an ignored `.agents/setup/` location. The receipt binds repository identity and the approved setup plan to before-and-after path/hunk hashes for the subset of managed outputs changed by that apply; validation also re-renders every unchanged managed output in the plan. Later workflows must validate the receipt against the live repository before importing it, and must treat missing, stale, or non-self-consistent evidence as unverified rather than as approval.

The receipt protects against accidental corruption, stale evidence, and non-self-consistent mutation; it is not a signature and does not defend against an actor who can rewrite both the local receipt and its unkeyed integrity digest. That hostile-local-forgery model would require an external trust anchor or managed signing key and is intentionally outside this workflow's configuration-safety scope.

Self-hosting render-equivalence covers every setup-managed output: complete `docs/agents/*.md` files and only the bounded managed blocks in repository instruction files. This complements, rather than replaces, setup idempotency testing.
