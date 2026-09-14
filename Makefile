SHELL := /bin/bash

.PHONY: verify test canonical-validate

verify:
	@python3 -c 'import yaml' >/dev/null 2>&1 || { echo "Install verification dependencies: python3 -m pip install -r requirements-dev.txt" >&2; exit 1; }
	@bash tests/run.sh

test:
	@bash tests/run.sh

canonical-validate:
	@python3 -c 'import yaml' >/dev/null 2>&1 || { echo "Install pinned development dependencies: python3 -m pip install -r requirements-dev.txt" >&2; exit 1; }
	@for skill in skills/*; do python3 "$${CODEX_SKILL_CREATOR:-$${HOME}/.codex/skills/.system/skill-creator}/scripts/quick_validate.py" "$$skill" || exit; done
	@python3 "$${CODEX_PLUGIN_CREATOR:-$${HOME}/.codex/skills/.system/plugin-creator}/scripts/validate_plugin.py" .
