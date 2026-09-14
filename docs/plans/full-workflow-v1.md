# Full Workflow v1 Implementation Plan

## Status

Approved planning baseline. This document records the first complete workflow scope agreed during the Grill session. It is an implementation plan, not release evidence. Deterministic checks, behavioral evals, and external end-to-end acceptance must still pass before release.

## Outcome

Deliver a Codex-only `ai-workflow` Plugin whose public controller is `$ai-workflow`. The controller runs one gated Feature Run while delegating reusable work to independently invokable, pinned Matt Pocock-derived Skills.

The first release supports one full path:

```text
$ai-workflow
-> repository setup and Project Contract preflight
-> $grill-with-docs
-> $to-spec
-> Specification Gate
-> GitHub parent issue
-> $to-tickets
-> Ticket Breakdown Gate
-> GitHub sub-issues
-> sequential ticket execution
   -> Implementation Agent + Quality Agent
   -> ticket verification and review
   -> controller-created local commit
-> feature-level verification and review
-> Delivery Gate
-> push and pull request
-> issues close only after merge
```

## Scope

### Included

- Rename the controller from `$ship-feature` to `$ai-workflow` without retaining a compatibility alias.
- Keep each workflow method independently invokable and available to the controller.
- Vendor reviewed Matt Pocock-derived Skills at one pinned upstream commit.
- Preserve MIT attribution and document every Codex or Project Contract adaptation.
- Add Matt-style per-repository setup for tracker and domain-document configuration.
- Support GitHub Issues as the only tracker for this release.
- Use a GitHub parent issue as the canonical specification and GitHub sub-issues as canonical tickets.
- Use two top-level worker roles per ticket: Implementation Agent and Quality Agent.
- Create one local commit per ticket only after ticket-level quality checks pass.
- Preserve explicit gates for repository setup writes, specification publication, ticket publication, exceptions, workspace changes, and delivery.
- Persist disposable controller checkpoints locally while keeping reconstructable work facts in GitHub.
- Retain deterministic validation and require separate behavioral and external end-to-end release evidence.

### Deferred or excluded

- `$quick-ship` or any fast/local-spec workflow.
- GitLab, Linear, Jira, local Markdown, or other tracker execution.
- `$triage` and triage-label vocabulary.
- Parallel execution of multiple ready tickets.
- Automatic merge.
- Automatic closing of GitHub issues before merge.
- A unified `$setup-ai-workflow` command. Its value may be evaluated after real onboarding use; it is not a promised follow-up.
- README changes in `vibe-engineering-base` that advertise a workflow release before the Plugin passes release acceptance.

## Public Skills

The complete USER-scope installation contains:

```text
$ai-workflow
$setup-matt-pocock-skills
$grill-with-docs
$grilling
$domain-modeling
$to-spec
$to-tickets
$implement
$tdd
$code-review
```

The two additional primitives are required by Matt's original composition: `$grill-with-docs` invokes `$grilling` for the decision tree and `$domain-modeling` for glossary and ADR updates. This ten-Skill inventory supersedes the earlier eight-Skill draft after the product decision to split every reusable Matt method into an independently invokable Skill; it is an approved public-API choice, not an implementation-only expansion.

All Skills are independently invokable. `$ai-workflow` owns Feature Run state, transitions, approvals, finding routing, and delivery authority; stage Skills return bounded artifacts and evidence and cannot advance the run themselves.

The installation must copy the complete reviewed set from one pinned repository commit. It must not download or mutate upstream Skills at runtime, overwrite conflicting USER-scope Skills, or modify the current repository.

## Matt Pocock Provenance and Adaptation

For every Matt-derived Skill:

1. Record the exact upstream repository and commit.
2. Include the applicable MIT license and attribution in `THIRD_PARTY_NOTICES.md` and the Skill package where required.
3. Keep an auditable adaptation note describing changed behavior.
4. Validate that no installer or runtime step silently fetches a newer upstream version.

Required adaptations include:

- `$implement` must not commit. The controller commits only after the Quality Agent accepts the ticket.
- External writes must obey controller authorities and gates even when upstream instructions would perform them directly.
- Tracker and domain setup must work with Codex repository instructions.
- Controller state and file ownership rules outrank stage-level defaults.

## Per-Repository Setup

`$setup-matt-pocock-skills` is installed in USER scope but executed once for each repository. It configures project-specific values; it is not global project configuration.

### Setup flow

1. Inspect the repository, existing instructions, domain docs, ADRs, `.scratch/`, and Git remotes.
2. Recommend a tracker based on evidence and ask the user to confirm it.
3. Record GitLab or Local Markdown truthfully when the user selects it, but disclose that this release of `$ai-workflow` executes only GitHub and will stop at the Exception Gate for either supported non-GitHub configuration. Reject custom providers because their setup contract is not defined in this release.
4. Draft tracker and domain-document configuration.
5. Show every proposed repository change.
6. Obtain Setup Confirmation Gate approval.
7. Write and validate configuration.
8. Show the resulting diff and stop without commit or push.

### Setup artifacts

Commit these shared project-policy files:

```text
docs/agents/issue-tracker.md
docs/agents/domain.md
AGENTS.md and/or CLAUDE.md
```

Do not create `docs/agents/triage-labels.md` because `$triage` is excluded.

Instruction-file behavior:

- If only `AGENTS.md` exists, update it.
- If only `CLAUDE.md` exists, update it.
- If both exist, update the same generated block in both and validate equality.
- If neither exists, ask which one to create; recommend `AGENTS.md` for Codex and `CLAUDE.md` for Claude.
- Bound generated content with `<!-- ai-workflow:agent-skills:start -->` and `<!-- ai-workflow:agent-skills:end -->`.
- Never alter user-authored content outside the generated block.

For GitHub, `docs/agents/issue-tracker.md` contains repository identity, the operations used by this workflow, and relationship behavior. The supported non-GitHub configurations are GitLab and Local Markdown; they record provider identity and the unsupported execution boundary only. Unknown providers fail validation. This release does not configure labels, and no tracker configuration may contain credentials or tokens.

## Project Contract Integration

The Project Contract and Matt setup have separate authority:

- `.agents/project-contract.md` controls verification, knowledge, workspace safety, work-artifact policy, and delivery.
- `docs/agents/issue-tracker.md` is the source of truth for tracker selection and tracker operations.
- `docs/agents/domain.md` is the source of truth for domain-document layout consumed by Matt-derived methods.
- A conflict between these sources is never resolved silently; it enters the Exception Gate.

The Base Contract interface must support referencing tracker configuration without duplicating the tracker configuration itself. Preserve existing repository-path and `unconfigured` forms while adding a validated reference form for `docs/agents/issue-tracker.md`. The validator must continue enforcing correct sections, safe repository-relative paths, and truthful verification status.

If Matt setup is missing, `$ai-workflow` stops before creating a Feature Run and asks the user to run `$setup-matt-pocock-skills`. If the Project Contract is missing after setup succeeds, `$ai-workflow` performs Contract Discovery, shows the draft, obtains the required workspace and persistence approvals, writes and validates the Contract, and only then creates the Feature Run.

## Runtime Preflight

Every `$ai-workflow` invocation must:

1. Resolve the current repository root.
2. Read repository instructions.
3. Require and validate `docs/agents/issue-tracker.md` and `docs/agents/domain.md`.
4. Read and validate `.agents/project-contract.md`, or perform approved Contract Discovery.
5. Compare configured GitHub repository identity with current Git remotes.
6. Confirm required GitHub tooling, authentication, and repository access before dependent operations.
7. Inspect branch, worktree, and unrelated changes.
8. Reuse a safe dedicated workspace baseline when possible; require Workspace Gate approval for branch or worktree creation/switching, or unresolved ownership risk.

Stable configuration is not re-asked on every run. Missing, unsafe, unsupported, or conflicting evidence triggers one evidence-backed gate or stops the run.

## Feature Run and Resume Model

- One Codex task owns at most one unfinished Feature Run.
- Different features run in different Codex tasks and isolated branches or worktrees when edits may overlap.
- Setup and Contract preflight complete before a Feature Run is created.
- GitHub stores canonical specification, tickets, dependencies, and merge-linked completion facts.
- `.agents/runs/<feature-id>.json` stores disposable local controller checkpoints and is ignored by Git.
- Checkpoints may contain stage, branch, baseline, current ticket, verification evidence, and unresolved findings, but no credentials.
- If local state is lost, `$ai-workflow` can reconstruct a run from an explicit GitHub parent issue, its sub-issues, branch, and commits.
- Reconstructed runs do not inherit old Workspace, Exception, or Delivery approvals without current evidence and renewed authorization.

Supported invocation forms include:

```text
$ai-workflow Add team invitations with expiring email links.
$ai-workflow Start with Grill and stop after Grill.
$ai-workflow Continue from GitHub spec #123.
$ai-workflow Continue from the existing tickets for #123.
```

## Grill, Specification, and Architecture

New full-path features always pass through `$grill-with-docs`; it may finish immediately when no consequential decision remains. Explicit resume from an approved spec or approved tickets bypasses Grill after provenance and approval checks.

Grill owns shared concepts, public interfaces, architectural tradeoffs, and ADR-worthy decisions. `$to-spec` records the approved shared contract, testing seams, acceptance criteria, and out-of-scope decisions. Testing seams are reviewed as part of the Specification Gate rather than through a separate gate.

`$to-tickets` decomposes the approved design into tracer-bullet tickets and dependency edges. It must not invent architecture. If it discovers a missing shared abstraction or public-interface decision, the controller stops at the Exception Gate, returns to Grill/specification, requires renewed Specification Gate approval, and reruns ticket decomposition.

## GitHub Publication

### Specification

- The approved GitHub parent issue is the only canonical specification.
- Do not create a committed or `.scratch/` specification mirror.
- Publication requires Specification Gate approval.

### Tickets

- `$to-tickets` drafts vertical tracer-bullet tickets, prefactoring work, and blocking edges.
- The user reviews granularity, ordering, dependencies, and merge/split choices at the Ticket Breakdown Gate.
- After approval, publish GitHub sub-issues blockers-first.
- Prefer native sub-issue and blocking relationships. Use an explicit `Blocked by` fallback only when the configured GitHub capability cannot express an edge.
- Do not close or mutate the parent issue while creating tickets.

## Ticket Execution

The first release executes one dependency-ready ticket at a time. A new Implementation Agent and Quality Agent pair is created for each ticket.

### Implementation Agent

- Reads only the approved spec, current ticket, relevant repository context, and assigned file ownership.
- Uses the adapted `$implement` and `$tdd` methods for product code.
- Does not commit, push, create or close issues, or modify files assigned to the Quality Agent.
- Reports changed files, evidence, blockers, and newly discovered design gaps.

### Quality Agent

- Independently derives tests and review criteria from the approved spec and current ticket.
- May write tests only within disjoint ownership assigned by the controller.
- When safe isolation is impossible, returns a patch or test design instead of writing overlapping files.
- Runs verification and performs read-only product review.
- May use `$code-review`'s Standards and Spec perspectives internally; these are read-only reviewers, not additional top-level worker roles.
- Does not claim independent review of tests it authored. This limitation is mitigated by spec-derived tests, repository verification, feature-level review, and controller finding routing.

### Finding routing and loop control

- Product findings return to the Implementation Agent.
- Test findings return to the Quality Agent.
- Specification or architecture gaps enter the Exception Gate.
- Continue review loops while new evidence or measurable progress exists.
- Stop when the same blocker repeats without new evidence.
- Reviewers never directly modify reviewed production content.

## Commit and Delivery Policy

After a ticket passes ticket-level verification and review, the controller creates one local commit referencing the GitHub sub-issue. Stage Skills and worker agents do not commit.

After all tickets pass, run feature-level verification and review across the complete branch. The Delivery Gate presents the exact commit set, diff summary, verification evidence, unresolved limitations, remote, target branch, and proposed pull request.

Only explicit Delivery Gate approval authorizes push and pull-request creation. The controller does not merge. GitHub issues remain open during local work and pull-request review; closing references in the pull request close the parent specification and tickets only after merge.

## State Machine and Authorities

Update the machine-readable state model and authority registry so that:

- Every transition gate resolves to a registered authority.
- Every external operation's `authorizedBy` resolves to a registered authority.
- Composite authorities reference only registered authorities.
- Setup occurs before Contract preflight and Feature Run creation.
- Specification and Ticket Breakdown approvals authorize only their displayed publication scopes.
- Ticket commits require successful ticket quality status.
- Push and pull-request creation require Delivery Gate approval, and approval remains distinct from successful delivery completion.
- Unsupported trackers, conflicts, new public architecture, stalled review loops, and unsafe workspace conditions reach the Exception Gate.
- Shortcut/resume edges require explicit artifact provenance and renewed authority when prior approval is unavailable.

## Implementation Sequence

### 1. Reconcile the existing branch

- Inventory the current uncommitted custom stage-Skill refactor.
- Preserve useful deterministic validators and evidence.
- Replace superseded custom stage names deliberately; do not mix old and new controller registries.
- Rename `skills/ship-feature/` to `skills/ai-workflow/` and update metadata, references, tests, evals, and documentation without an alias.

### 2. Vendor Matt-derived Skills

- Select and record one upstream commit.
- Import the required Skills, references, licenses, and notices.
- Apply the bounded adaptations in this plan.
- Add regression checks that catch unintended upstream behavior such as `$implement` committing.

### 3. Implement setup and Contract integration

- Adapt `$setup-matt-pocock-skills` for the agreed `AGENTS.md`/`CLAUDE.md` behavior and Setup Confirmation Gate.
- Add setup-output validation and negative fixtures.
- Add the minimal backward-compatible Base Contract reference form needed to point at tracker configuration.
- Validate cross-file conflicts and prevent credentials from entering tracked configuration.

### 4. Rebuild the controller

- Define `$ai-workflow` as the single Feature Run controller, not the only public Skill.
- Update the state machine, authority registry, stage registry, stop/resume behavior, finding routing, and no-progress rule.
- Implement ignored checkpoints and deterministic reconstruction rules.

### 5. Implement GitHub publication and ticket execution

- Implement parent issue and sub-issue publication behind their gates.
- Implement dependency-frontier calculation with sequential scheduling.
- Implement disjoint file ownership, two-agent execution, ticket quality checks, and controller commits.
- Implement final review, Delivery Gate evidence, push, and pull-request creation without merge or early issue closure.

### 6. Documentation and packaging

- Replace every `$ship-feature` example with `$ai-workflow`.
- Document the complete USER-scope installation set and conflict-safe migration.
- Document per-repository Matt setup separately from global installation.
- Explain canonical GitHub artifacts versus ignored local checkpoints.
- Keep the unified `$setup-ai-workflow` idea in Possible future improvements only.

### 7. Verification and release acceptance

- Run both repositories' deterministic suites.
- Run official Skill and Plugin validators as release gates.
- Run behavioral evals in fresh Codex tasks.
- Run USER-scope install, reinstall/conflict, and restart tests in an isolated environment.
- Run the complete cross-repository Feature Run through a test pull request.
- Record any GitHub behavior that cannot be exercised safely as not verified; deterministic checks alone never imply release readiness.

## Deterministic Acceptance

Tests must cover at least:

- Plugin manifest and every Skill's YAML/frontmatter and `agents/openai.yaml` metadata.
- Unsupported frontmatter and manifest fields as negative fixtures.
- `$ai-workflow` controller naming and absence of `$ship-feature` alias.
- Exact public Skill inventory and required references.
- Pinned upstream provenance, licenses, and adaptation notes.
- Setup file routing, preview/plan-token confirmation enforcement, drift rejection, idempotency, generated-block synchronization, live fetch/push remote matching, and no-credential policy.
- Project Contract reference-form validation and section ownership.
- Complete state transitions, rejected shortcuts, and authority referential integrity.
- Worker ownership, concurrent dispatch, and patch-only Quality fallback policy.
- Ticket commit preconditions and prohibition on worker/stage commits.
- Review finding routing, progress continuation, repeated-blocker stop, and read-only review policy.
- Delivery Gate coverage for push and pull-request creation.
- Internal Markdown links and unfinished placeholders.

## Behavioral and External Acceptance

Exercise and record evidence for:

- Base-derived repository with an existing Project Contract.
- General repository missing a Project Contract.
- Missing Matt setup.
- Setup with `AGENTS.md`, `CLAUDE.md`, both, and neither.
- Setup confirmation, idempotency, and live config/remote mismatch handling.
- Dirty worktree and existing unrelated changes.
- New feature Grill path and approved-spec/ticket resume paths.
- Architecture gap discovered during ticket breakdown or implementation.
- Ticket with a reasonable test seam and ticket with no safe write-isolated test surface.
- Product/test finding routing and a review loop with no progress.
- Concurrent worker dispatch, ownership conflict, and patch-only Quality fallback.
- One commit per accepted ticket.
- Local checkpoint loss and reconstruction from GitHub.
- Delivery Gate rejection and approval.
- Two Codex tasks operating on different features.
- USER-scope installation without repository modification, safe repeat handling, conflict refusal, and availability after restart.
- A complete test pull request whose issues stay open until merge.

## Cross-Repository Delivery Order

1. Finish and submit the Base Project Contract branch, including only the minimal tracker-reference compatibility required by this plan.
2. Rework `ai-workflow` around `$ai-workflow`, Matt-derived Skills, setup, controller behavior, tests, and evals.
3. Complete isolated installation and GitHub test-PR acceptance.
4. Only after the Plugin repository exists at a verified commit, remove `grill-with-docs` from Base and update Base positioning, documentation, links, and minor version in a separate branch/PR.
5. Keep the release blocked until both repositories pass their own verification and the external acceptance matrix is complete.

## Release Readiness Rule

Passing `make verify`, official validators, or local packaging checks is necessary but insufficient. The release remains not ready until the installation, fresh-task, multi-task, full Feature Run, GitHub publication, test pull request, and post-restart scenarios have current recorded evidence. Unsupported GitLab, Linear, Jira, and local-Markdown behavior must be described as unsupported rather than implied by Matt upstream capabilities.
