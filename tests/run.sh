#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="${ROOT_DIR}/skills/ship-feature"
TEST_TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-workflow-test.XXXXXX")"
tests_run=0
failures=0

cleanup() {
  [[ -d "${TEST_TEMP_ROOT}" && "$(basename "${TEST_TEMP_ROOT}")" == ai-workflow-test.* ]] && \
    rm -rf -- "${TEST_TEMP_ROOT}"
}
trap cleanup EXIT

run_test() {
  local name="$1"
  shift
  tests_run=$((tests_run + 1))
  if "$@"; then
    echo "PASS: ${name}"
  else
    echo "FAIL: ${name}" >&2
    failures=$((failures + 1))
  fi
}

test_plugin_manifest() {
  python3 "${ROOT_DIR}/scripts/validate_plugin.py" "${ROOT_DIR}" >/dev/null
}

test_plugin_rejects_unsupported_field() {
  local fixture="${TEST_TEMP_ROOT}/invalid-plugin"
  mkdir -p "${fixture}/.codex-plugin"
  cp -R "${ROOT_DIR}/skills" "${fixture}/skills"
  cp "${ROOT_DIR}/.codex-plugin/plugin.json" "${fixture}/.codex-plugin/plugin.json"
  python3 - "${fixture}/.codex-plugin/plugin.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["hooks"] = "./hooks.json"
path.write_text(json.dumps(payload))
PY
  ! python3 "${ROOT_DIR}/scripts/validate_plugin.py" "${fixture}" >/dev/null 2>&1
}

test_skill_metadata() {
  python3 "${ROOT_DIR}/scripts/validate_skill.py" "${SKILL_DIR}" >/dev/null
}

test_skill_rejects_unsupported_frontmatter() {
  local fixture="${TEST_TEMP_ROOT}/invalid-skill/ship-feature"
  mkdir -p "${fixture}"
  cp -R "${SKILL_DIR}/." "${fixture}/"
  sed -i.bak '/^description:/a\
unsupported-field: true' "${fixture}/SKILL.md"
  ! python3 "${ROOT_DIR}/scripts/validate_skill.py" "${fixture}" >/dev/null 2>&1
}

test_skill_rejects_invalid_agent_metadata() {
  local fixture="${TEST_TEMP_ROOT}/invalid-agent-metadata/ship-feature"
  mkdir -p "${fixture}"
  cp -R "${SKILL_DIR}/." "${fixture}/"
  sed -i.bak 's/allow_implicit_invocation: false/allow_implicit_invocation: sometimes/' \
    "${fixture}/agents/openai.yaml"
  ! python3 "${ROOT_DIR}/scripts/validate_skill.py" "${fixture}" >/dev/null 2>&1
}

test_only_public_skill() {
  local skill_count
  skill_count="$(find "${ROOT_DIR}/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')"
  [[ "${skill_count}" == "1" && -f "${SKILL_DIR}/SKILL.md" ]]
}

test_explicit_invocation_metadata() {
  grep -Fq 'allow_implicit_invocation: false' "${SKILL_DIR}/agents/openai.yaml" && \
    grep -Fq '$ship-feature' "${SKILL_DIR}/agents/openai.yaml"
}

test_no_placeholders() {
  ! grep -R -Fq '[TODO:' "${ROOT_DIR}/.codex-plugin" "${ROOT_DIR}/skills"
}

test_all_markdown_links() {
  python3 "${ROOT_DIR}/scripts/validate_markdown_links.py" "${ROOT_DIR}" >/dev/null
}

test_state_model() {
  python3 "${ROOT_DIR}/scripts/validate_state_machine.py" \
    "${SKILL_DIR}/references/state-machine.json" >/dev/null
}

test_state_model_rejects_shortcut() {
  local fixture="${TEST_TEMP_ROOT}/invalid-state-machine.json"
  cp "${SKILL_DIR}/references/state-machine.json" "${fixture}"
  python3 - "${fixture}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["transitions"].append({
    "from": "review",
    "event": "skip-delivery-gate",
    "to": "complete",
    "gate": None,
    "automatic": True,
})
path.write_text(json.dumps(payload))
PY
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_ungated_push() {
  local fixture="${TEST_TEMP_ROOT}/invalid-operations.json"
  cp "${SKILL_DIR}/references/state-machine.json" "${fixture}"
  python3 - "${fixture}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
for operation in payload["externalOperations"]:
    if operation["operation"] == "push":
        operation["authorizedBy"] = "specification"
path.write_text(json.dumps(payload))
PY
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_dangling_authority() {
  local fixture="${TEST_TEMP_ROOT}/dangling-authority.json"
  cp "${SKILL_DIR}/references/state-machine.json" "${fixture}"
  python3 - "${fixture}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["externalOperations"][0]["authorizedBy"] = "missing-gate"
path.write_text(json.dumps(payload))
PY
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_safety_contract_is_wired() {
  grep -Fq 'references/state-machine.json' "${SKILL_DIR}/SKILL.md" && \
    grep -Fq 'HARNESS_VERIFICATION_STATUS=bootstrap' "${SKILL_DIR}/references/project-contract.md" && \
    grep -Fq 'Always stop at the Delivery Gate' "${SKILL_DIR}/references/delivery.md"
}

run_test "pinned Plugin manifest schema passes" test_plugin_manifest
run_test "Plugin schema rejects unsupported fields" test_plugin_rejects_unsupported_field
run_test "Skill and agent metadata schemas pass" test_skill_metadata
run_test "Skill schema rejects unsupported frontmatter" test_skill_rejects_unsupported_frontmatter
run_test "agent metadata schema rejects invalid policy" test_skill_rejects_invalid_agent_metadata
run_test "ship-feature is the only public Skill" test_only_public_skill
run_test "ship-feature is explicit-only" test_explicit_invocation_metadata
run_test "published assets contain no placeholders" test_no_placeholders
run_test "all relative Markdown links resolve" test_all_markdown_links
run_test "v1 state and authorization model passes" test_state_model
run_test "state model rejects a shortcut edge" test_state_model_rejects_shortcut
run_test "state model rejects an incorrectly authorized push" test_state_model_rejects_ungated_push
run_test "state model rejects a dangling authority" test_state_model_rejects_dangling_authority
run_test "runtime safety contract is wired into the Skill" test_safety_contract_is_wired

echo "${tests_run} tests, ${failures} failures"
[[ "${failures}" -eq 0 ]]
