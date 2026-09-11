# Repository working agreement

## Architecture

- Keep cross-stage control and gate semantics in `skills/ship-feature/SKILL.md`.
- Keep stage-specific decision rules in `skills/ship-feature/references/` and load them only from the stage that needs them.
- Preserve `$ship-feature` as the only public Skill in version 1.
- Treat `.codex-plugin/plugin.json` and `skills/ship-feature/agents/openai.yaml` as product metadata, not agent instructions.

## Safety and scope

- This plugin targets Codex only in version 1.
- Preserve explicit approval before external ticket creation, destructive recovery, push, or pull/merge-request creation.
- Never store mutable project or Feature Run state in this repository's Skill files.
- Keep parallel agent write ownership disjoint and preserve unrelated user work.

## Change workflow

- Update behavioral scenarios when workflow transitions or gates change.
- Keep README installation and usage examples aligned with the Skill.
- Run `make verify` before handing off.
