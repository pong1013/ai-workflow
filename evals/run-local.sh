#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-workflow-eval.XXXXXX")"
USER_SCOPE="${TEMP_ROOT}/codex-home/skills"
SOURCE_SKILL="${ROOT_DIR}/skills/ship-feature"
DEST_SKILL="${USER_SCOPE}/ship-feature"

cleanup() {
  [[ -d "${TEMP_ROOT}" && "$(basename "${TEMP_ROOT}")" == ai-workflow-eval.* ]] && \
    rm -rf -- "${TEMP_ROOT}"
}
trap cleanup EXIT

install_once() {
  if [[ -e "${DEST_SKILL}" ]]; then
    echo "conflict: ${DEST_SKILL} already exists" >&2
    return 17
  fi
  mkdir -p "${USER_SCOPE}"
  cp -R "${SOURCE_SKILL}" "${DEST_SKILL}"
}

install_once
python3 "${ROOT_DIR}/scripts/validate_markdown_links.py" "${DEST_SKILL}" >/dev/null
grep -Fq 'name: ship-feature' "${DEST_SKILL}/SKILL.md"
echo "PASS clean temporary USER-scope copy"

set +e
conflict_output="$(install_once 2>&1)"
conflict_status=$?
set -e
[[ "${conflict_status}" -eq 17 ]]
[[ "${conflict_output}" == conflict:*already\ exists ]]
echo "PASS repeat install stops on conflict"

python3 "${ROOT_DIR}/scripts/validate_plugin.py" "${ROOT_DIR}" >/dev/null
python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${DEST_SKILL}/references/state-machine.json" >/dev/null
echo "PASS installed source matches validated package"
