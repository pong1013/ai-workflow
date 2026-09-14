#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-workflow-eval.XXXXXX")"
USER_SCOPE="${TEMP_ROOT}/codex-home/skills"
SOURCE_STATUS="$(git -C "${ROOT_DIR}" status --porcelain=v1)"
EXPECTED_SKILLS=(
  ai-workflow
  code-review
  domain-modeling
  grill-with-docs
  grilling
  implement
  setup-matt-pocock-skills
  tdd
  to-spec
  to-tickets
)

cleanup() {
  [[ -d "${TEMP_ROOT}" && "$(basename "${TEMP_ROOT}")" == ai-workflow-eval.* ]] && \
    rm -rf -- "${TEMP_ROOT}"
}
trap cleanup EXIT

install_all() {
  local skill
  for skill in "${EXPECTED_SKILLS[@]}"; do
    if [[ -e "${USER_SCOPE}/${skill}" ]]; then
      echo "conflict: ${USER_SCOPE}/${skill} already exists" >&2
      return 17
    fi
  done

  mkdir -p "${USER_SCOPE}"
  for skill in "${EXPECTED_SKILLS[@]}"; do
    cp -R "${ROOT_DIR}/skills/${skill}" "${USER_SCOPE}/${skill}"
  done
}

validate_scope() {
  local scope="$1"
  local skill
  for skill in "${EXPECTED_SKILLS[@]}"; do
    python3 "${ROOT_DIR}/scripts/validate_skill.py" "${scope}/${skill}" >/dev/null
  done
  python3 "${ROOT_DIR}/scripts/validate_markdown_links.py" "${scope}" >/dev/null
  python3 "${ROOT_DIR}/scripts/validate_state_machine.py" \
    "${scope}/ai-workflow/references/state-machine.json" >/dev/null
  [[ -f "${scope}/setup-matt-pocock-skills/scripts/validate_setup.py" ]]
  [[ ! -e "${scope}/ship-feature" ]]
}

install_all
validate_scope "${USER_SCOPE}"
echo "PASS clean temporary USER-scope workflow install"

set +e
conflict_output="$(install_all 2>&1)"
conflict_status=$?
set -e
[[ "${conflict_status}" -eq 17 ]]
[[ "${conflict_output}" == conflict:*already\ exists ]]
echo "PASS repeat install stops during preflight"

conflict_root="${TEMP_ROOT}/conflict-home/skills"
mkdir -p "${conflict_root}/to-spec"
old_user_scope="${USER_SCOPE}"
USER_SCOPE="${conflict_root}"
set +e
conflict_output="$(install_all 2>&1)"
conflict_status=$?
set -e
[[ "${conflict_status}" -eq 17 ]]
[[ "${conflict_output}" == conflict:*to-spec*already\ exists ]]
[[ "$(find "${conflict_root}" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')" == "1" ]]
USER_SCOPE="${old_user_scope}"
echo "PASS conflict preflight prevents partial installation"

upgrade_scope="${TEMP_ROOT}/upgrade-home/skills"
upgrade_stage="${TEMP_ROOT}/upgrade-stage"
upgrade_backup="${TEMP_ROOT}/upgrade-backup"
mkdir -p "${upgrade_scope}/ship-feature" "${upgrade_stage}" "${upgrade_backup}"
printf '%s\n' 'old single-Skill controller' >"${upgrade_scope}/ship-feature/OLD_VERSION"
for skill in "${EXPECTED_SKILLS[@]}"; do
  cp -R "${ROOT_DIR}/skills/${skill}" "${upgrade_stage}/${skill}"
  python3 "${ROOT_DIR}/scripts/validate_skill.py" "${upgrade_stage}/${skill}" >/dev/null
  [[ ! -e "${upgrade_scope}/${skill}" ]]
done
mv "${upgrade_scope}/ship-feature" "${upgrade_backup}/ship-feature-0.1"
for skill in "${EXPECTED_SKILLS[@]}"; do
  mv "${upgrade_stage}/${skill}" "${upgrade_scope}/${skill}"
done
validate_scope "${upgrade_scope}"
[[ -f "${upgrade_backup}/ship-feature-0.1/OLD_VERSION" ]]
[[ "$(find "${upgrade_scope}" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')" == "${#EXPECTED_SKILLS[@]}" ]]
echo "PASS staged legacy migration preserves a recoverable ship-feature backup"

python3 "${ROOT_DIR}/scripts/validate_plugin.py" "${ROOT_DIR}" >/dev/null
[[ "$(git -C "${ROOT_DIR}" status --porcelain=v1)" == "${SOURCE_STATUS}" ]]
echo "PASS packaging runner leaves the source repository unchanged"
