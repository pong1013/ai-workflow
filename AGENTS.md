# Repository working agreement

<!-- ai-workflow:agent-skills:start -->
## Agent skills

### Issue tracker

Specifications and tickets are tracked in `pong1013/ai-workflow` GitHub Issues. See `docs/agents/issue-tracker.md`.

### Domain docs

This is a single-context repository with lazy root domain documentation. See `docs/agents/domain.md`.
<!-- ai-workflow:agent-skills:end -->

## Architecture

- Keep cross-stage state, transitions, authorities, Feature Run ownership, ticket commits, and delivery semantics in `skills/ai-workflow/`.
- Keep Matt-derived method decisions in their own Skills; the controller must load the exact Skill names registered in `state-machine.json` rather than recreating them from memory.
- Preserve `$ai-workflow` as the Feature Run controller while keeping every bundled Skill independently invokable and explicit-only.
- Treat `docs/agents/issue-tracker.md` as tracker configuration, `.agents/project-contract.md` as repository safety/delivery policy, and `.agents/runs/` as ignored disposable runtime state.
- Treat `.codex-plugin/plugin.json` and `skills/*/agents/openai.yaml` as product metadata, not runtime instructions.

## Safety and scope

- This Plugin targets Codex only in version 0.2 and executes only the GitHub tracker path.
- Preserve explicit approval before setup writes, Contract persistence, branch/worktree mutation, specification issue publication, ticket publication, push, or pull-request creation.
- Create ticket commits only after ticket-level verification and review pass; worker Skills never commit.
- Never merge or directly close parent/ticket issues. Use pull-request closing references that take effect after merge.
- Keep Implementation and Quality Agent write ownership disjoint and preserve unrelated user work.
- Never store credentials in tracked configuration, checkpoints, evidence, or Skill files.

## Change workflow

- Update deterministic mappings and behavioral scenarios whenever workflow transitions, authorities, public Skills, gates, or tracker effects change.
- Keep README installation, per-repository setup, invocation, and resume examples aligned with the Skills.
- Preserve the pinned upstream commit, MIT attribution, and documented adaptation boundaries in `UPSTREAM.md` and `THIRD_PARTY_NOTICES.md`.
- Run `make verify` before handing off. Treat canonical validators and external behavioral/E2E evidence as separate release gates.
