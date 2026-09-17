#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER_DIR="${ROOT_DIR}/skills/ai-workflow"
STATE_MODEL="${CONTROLLER_DIR}/references/state-machine.json"
SETUP_VALIDATOR="${ROOT_DIR}/skills/setup-matt-pocock-skills/scripts/validate_setup.py"
SETUP_CONFIGURATOR="${ROOT_DIR}/skills/setup-matt-pocock-skills/scripts/configure_repository.py"
UPSTREAM_COMMIT="3cca18b368ae95cdbdebbff572ccafa662551015"
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
MATT_SKILLS=(
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

mutate_json() {
  local source="$1"
  local target="$2"
  local expression="$3"
  cp "${source}" "${target}"
  python3 - "${target}" "${expression}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
exec(sys.argv[2], {"payload": payload})
path.write_text(json.dumps(payload))
PY
}

test_plugin_manifest() {
  python3 "${ROOT_DIR}/scripts/validate_plugin.py" "${ROOT_DIR}" >/dev/null
}

test_plugin_rejects_unsupported_field() {
  local fixture="${TEST_TEMP_ROOT}/invalid-plugin"
  mkdir -p "${fixture}/.codex-plugin"
  cp -R "${ROOT_DIR}/skills" "${fixture}/skills"
  cp "${ROOT_DIR}/.codex-plugin/plugin.json" "${fixture}/.codex-plugin/plugin.json"
  mutate_json "${fixture}/.codex-plugin/plugin.json" "${fixture}/mutated.json" \
    'payload["hooks"] = "./hooks.json"'
  mv "${fixture}/mutated.json" "${fixture}/.codex-plugin/plugin.json"
  ! python3 "${ROOT_DIR}/scripts/validate_plugin.py" "${fixture}" >/dev/null 2>&1
}

test_skill_metadata() {
  local skill
  for skill in "${EXPECTED_SKILLS[@]}"; do
    python3 "${ROOT_DIR}/scripts/validate_skill.py" "${ROOT_DIR}/skills/${skill}" >/dev/null || return
  done
}

test_skill_rejects_unsupported_frontmatter() {
  local fixture="${TEST_TEMP_ROOT}/invalid-skill/ai-workflow"
  mkdir -p "${fixture}"
  cp -R "${CONTROLLER_DIR}/." "${fixture}/"
  sed -i.bak '/^description:/a\
unsupported-field: true' "${fixture}/SKILL.md"
  ! python3 "${ROOT_DIR}/scripts/validate_skill.py" "${fixture}" >/dev/null 2>&1
}

test_skill_rejects_invalid_agent_metadata() {
  local fixture="${TEST_TEMP_ROOT}/invalid-agent/ai-workflow"
  mkdir -p "${fixture}"
  cp -R "${CONTROLLER_DIR}/." "${fixture}/"
  sed -i.bak 's/allow_implicit_invocation: false/allow_implicit_invocation: sometimes/' \
    "${fixture}/agents/openai.yaml"
  ! python3 "${ROOT_DIR}/scripts/validate_skill.py" "${fixture}" >/dev/null 2>&1
}

test_exact_skill_set() {
  local actual expected
  actual="$(find "${ROOT_DIR}/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"
  expected="$(printf '%s\n' "${EXPECTED_SKILLS[@]}" | sort)"
  [[ "${actual}" == "${expected}" ]]
}

test_explicit_invocation_metadata() {
  local skill
  for skill in "${EXPECTED_SKILLS[@]}"; do
    grep -Fq 'allow_implicit_invocation: false' "${ROOT_DIR}/skills/${skill}/agents/openai.yaml" || return
    grep -Fq "\$${skill}" "${ROOT_DIR}/skills/${skill}/agents/openai.yaml" || return
  done
}

test_no_placeholders() {
  ! grep -R -Fq '[TODO:' "${ROOT_DIR}/.codex-plugin" "${ROOT_DIR}/skills"
}

test_all_markdown_links() {
  python3 "${ROOT_DIR}/scripts/validate_markdown_links.py" "${ROOT_DIR}" >/dev/null
}

test_state_model() {
  python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${STATE_MODEL}" >/dev/null
}

test_state_model_rejects_shortcut() {
  local fixture="${TEST_TEMP_ROOT}/shortcut.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["transitions"].append({"from":"feature-review","event":"skip-delivery","to":"complete","gate":None,"automatic":True})'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_delivery_approval_as_completion() {
  local fixture="${TEST_TEMP_ROOT}/delivery-approval-completes.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["transitions"] if x["event"] == "approve-delivery")["to"] = "complete"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_requires_both_delivery_results() {
  local fixture="${TEST_TEMP_ROOT}/delivery-without-result-evidence.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["transitions"] if x["event"] == "delivery-succeeded")["gate"] = None'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_ungated_push() {
  local fixture="${TEST_TEMP_ROOT}/ungated-push.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["externalOperations"] if x["operation"] == "push-feature-branch")["authorizedBy"] = "specification"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_dangling_authority() {
  local fixture="${TEST_TEMP_ROOT}/dangling-authority.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["externalOperations"][0]["authorizedBy"] = "missing-gate"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_dangling_composite() {
  local fixture="${TEST_TEMP_ROOT}/dangling-composite.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["authorities"] if x["id"] == "ticket-commit-authority")["requires"].append("missing-evidence")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_unsafe_ticket_commit() {
  local fixture="${TEST_TEMP_ROOT}/unsafe-ticket-commit.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["externalOperations"] if x["operation"] == "commit-ticket")["authorizedBy"] = "ticket-breakdown"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_contract_without_bootstrap_workspace() {
  local fixture="${TEST_TEMP_ROOT}/unsafe-contract-persistence.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["externalOperations"] if x["operation"] == "persist-project-contract")["authorizedBy"] = "contract-persistence"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_early_checkpoint() {
  local fixture="${TEST_TEMP_ROOT}/early-checkpoint.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["externalOperations"] if x["operation"] == "write-run-checkpoint")["states"].insert(0, "contract")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_setup_without_exception_path() {
  local fixture="${TEST_TEMP_ROOT}/setup-without-exception.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["interruptions"]["from"].remove("repository-setup")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_ungated_worktree() {
  local fixture="${TEST_TEMP_ROOT}/ungated-worktree.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'next(x for x in payload["externalOperations"] if x["operation"] == "create-or-switch-feature-worktree")["authorizedBy"] = "invocation"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_serial_workers() {
  local fixture="${TEST_TEMP_ROOT}/serial-workers.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["qualityPolicy"]["dispatch"] = "implementation-then-quality"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_unsafe_overlap_fallback() {
  local fixture="${TEST_TEMP_ROOT}/unsafe-overlap.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["qualityPolicy"]["overlapFallback"] = "both-write"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_unbounded_review_loop() {
  local fixture="${TEST_TEMP_ROOT}/unbounded-review-loop.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["qualityPolicy"]["reviewLoop"]["sameBlockerWithoutNewEvidence"] = "continue"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_wrong_finding_route() {
  local fixture="${TEST_TEMP_ROOT}/wrong-finding-route.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["qualityPolicy"]["findingRoutes"]["production"] = "quality"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_mutating_review() {
  local fixture="${TEST_TEMP_ROOT}/mutating-review.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["qualityPolicy"]["reviewMutation"] = "fix-directly"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_requires_complete_round_ledger() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

policy = json.loads(pathlib.Path(sys.argv[1]).read_text())["roundLedgerPolicy"]
assert policy["ordered"] is True
assert policy["scopes"] == ["ticket", "feature"]
assert {
    "sequence", "scope", "ticket", "roundNumber", "implementationChanges", "checks",
    "standardsReview", "specReview", "nextAction",
} <= set(policy["roundRequiredFields"])
assert {"command", "outcome"} <= set(policy["checkRequiredFields"])
assert set(policy["outcomes"]) == {"pass", "fail", "not-applicable"}
assert policy["notApplicableRequiresReason"] is True
assert policy["preserveFailedRounds"] is True
assert {"checkpoint", "stopped-run", "delivery-gate", "final"} <= set(policy["reportSurfaces"])
PY
}

test_state_model_rejects_dropped_failed_rounds() {
  local fixture="${TEST_TEMP_ROOT}/dropped-failed-rounds.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["roundLedgerPolicy"]["preserveFailedRounds"] = False'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_missing_feature_rounds() {
  local fixture="${TEST_TEMP_ROOT}/missing-feature-rounds.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["roundLedgerPolicy"]["scopes"] = ["ticket"]'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_missing_round_number() {
  local fixture="${TEST_TEMP_ROOT}/missing-round-number.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["roundLedgerPolicy"]["roundRequiredFields"].remove("roundNumber")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_missing_delivery_ledger() {
  local fixture="${TEST_TEMP_ROOT}/missing-delivery-ledger.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["roundLedgerPolicy"]["reportSurfaces"].remove("delivery-gate")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_unexplained_not_applicable() {
  local fixture="${TEST_TEMP_ROOT}/unexplained-not-applicable.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["roundLedgerPolicy"]["notApplicableRequiresReason"] = False'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_wrong_stage_skill() {
  local fixture="${TEST_TEMP_ROOT}/wrong-stage.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["stageSkills"]["specification"] = ["write-anything"]'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_requires_reply_progress_and_one_grill_question() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

model = json.loads(pathlib.Path(sys.argv[1]).read_text())
policy = model["interactionPolicy"]
assert policy["grill"]["maxConsequentialQuestionsPerReply"] == 1
assert {
    "stage",
    "progress",
    "pendingDecisionOrBlocker",
    "nextStep",
} <= set(policy["workflowReply"]["requiredFields"])
PY
}

test_state_model_rejects_batched_grill_questions() {
  local fixture="${TEST_TEMP_ROOT}/batched-grill-questions.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["interactionPolicy"]["grill"]["maxConsequentialQuestionsPerReply"] = 2'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_missing_reply_progress() {
  local fixture="${TEST_TEMP_ROOT}/missing-reply-progress.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["interactionPolicy"]["workflowReply"]["requiredFields"].remove("progress")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_duplicate_transition() {
  local fixture="${TEST_TEMP_ROOT}/duplicate-transition.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["transitions"].append(dict(payload["transitions"][0]))'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_duplicate_operation() {
  local fixture="${TEST_TEMP_ROOT}/duplicate-operation.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["externalOperations"].append(dict(payload["externalOperations"][0]))'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_unknown_state() {
  local fixture="${TEST_TEMP_ROOT}/unknown-state.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["states"].append("shadow-state"); payload["interruptions"]["from"].append("shadow-state")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_duplicate_state() {
  local fixture="${TEST_TEMP_ROOT}/duplicate-state.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["states"].append(payload["states"][0])'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_controller_dependencies_resolve() {
  python3 - "${ROOT_DIR}" "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
model = json.loads(pathlib.Path(sys.argv[2]).read_text())
for names in model["stageSkills"].values():
    for name in names:
        assert (root / "skills" / name / "SKILL.md").is_file(), name
PY
}

test_upstream_provenance() {
  local skill
  grep -Fq "${UPSTREAM_COMMIT}" "${ROOT_DIR}/UPSTREAM.md" || return
  for skill in "${MATT_SKILLS[@]}"; do
    grep -Fq 'UPSTREAM.md' "${ROOT_DIR}/skills/${skill}/SKILL.md" || return
    grep -Fq "\`${skill}\`" "${ROOT_DIR}/UPSTREAM.md" || return
    grep -Fq "${skill}" "${ROOT_DIR}/THIRD_PARTY_NOTICES.md" || return
    cmp -s "${ROOT_DIR}/UPSTREAM.md" "${ROOT_DIR}/skills/${skill}/UPSTREAM.md" || return
    grep -Fq 'Copyright (c) 2026 Matt Pocock' "${ROOT_DIR}/skills/${skill}/LICENSE" || return
  done
}

test_no_triage_payload() {
  [[ ! -e "${ROOT_DIR}/skills/setup-matt-pocock-skills/triage-labels.md" ]] && \
    ! grep -R -Fq '$triage' "${ROOT_DIR}/skills/setup-matt-pocock-skills" && \
    ! grep -Fq '[triage-labels.md]' "${ROOT_DIR}/skills/setup-matt-pocock-skills/SKILL.md" && \
    ! grep -Fq '### Triage labels' "${ROOT_DIR}/skills/setup-matt-pocock-skills/SKILL.md"
}

test_non_github_seeds_have_no_workflow_operations() {
  ! grep -Eiq 'Wayfinding operations|wayfinder:|glab issue (create|update|close)|Status: (claimed|resolved)' \
    "${ROOT_DIR}/skills/setup-matt-pocock-skills/issue-tracker-gitlab.md" \
    "${ROOT_DIR}/skills/setup-matt-pocock-skills/issue-tracker-local.md"
}

test_implement_does_not_commit() {
  ! grep -Fq 'Commit your work to the current branch.' "${ROOT_DIR}/skills/implement/SKILL.md" && \
    grep -Fq 'Never stage, commit, push' "${ROOT_DIR}/skills/implement/SKILL.md" && \
    grep -Fq 'controller alone decides ticket acceptance and commit' "${ROOT_DIR}/skills/implement/SKILL.md"
}

test_github_only_publication_contract() {
  grep -Fq 'Specification Gate' "${ROOT_DIR}/skills/to-spec/SKILL.md" && \
    grep -Fq 'one parent issue' "${ROOT_DIR}/skills/to-spec/SKILL.md" && \
    grep -Fq 'Ticket Breakdown Gate' "${ROOT_DIR}/skills/to-tickets/SKILL.md" && \
    grep -Fq 'native sub-issue' "${ROOT_DIR}/skills/to-tickets/SKILL.md" && \
    ! grep -Fq 'ready-for-agent' "${ROOT_DIR}/skills/to-spec/SKILL.md" && \
    ! grep -Fq 'ready-for-agent' "${ROOT_DIR}/skills/to-tickets/SKILL.md"
}

test_readme_installs_complete_staged_set() {
  local skill
  grep -Fq 'temporary' "${ROOT_DIR}/README.md" || return
  grep -Fq 'staging destination' "${ROOT_DIR}/README.md" || return
  grep -Fq 'Preflight all 10 final destinations' "${ROOT_DIR}/README.md" || return
  grep -Fq 'outside the live USER skills directory' "${ROOT_DIR}/README.md" || return
  for skill in "${EXPECTED_SKILLS[@]}"; do
    grep -Fq "skills/${skill}" "${ROOT_DIR}/README.md" || return
  done
}

write_valid_setup_fixture() {
  local fixture="$1"
  mkdir -p "${fixture}/docs/agents"
  cp "${ROOT_DIR}/docs/agents/issue-tracker.md" "${fixture}/docs/agents/issue-tracker.md"
  cp "${ROOT_DIR}/docs/agents/domain.md" "${fixture}/docs/agents/domain.md"
  cp "${ROOT_DIR}/AGENTS.md" "${fixture}/AGENTS.md"
}

test_valid_setup_output() {
  local fixture="${TEST_TEMP_ROOT}/valid-setup"
  write_valid_setup_fixture "${fixture}"
  python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github >/dev/null
}

run_setup_configurator() {
  local fixture="$1"
  shift
  mkdir -p "${fixture}"
  if ! git -C "${fixture}" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "${fixture}" init -q
    git -C "${fixture}" remote add origin git@github.com:pong1013/example.git
  fi
  python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --github-repository pong1013/example \
    --remote-name origin \
    "$@"
}

setup_plan_token() {
  local fixture="$1"
  shift
  run_setup_configurator "${fixture}" "$@" | sed -n 's/^Setup plan token: //p'
}

apply_setup_configurator() {
  local fixture="$1"
  shift
  local token
  token="$(setup_plan_token "${fixture}" "$@")" || return
  [[ "${token}" == sha256:* ]] || return
  run_setup_configurator "${fixture}" "$@" \
    --apply --confirmed --plan-token "${token}"
}

test_setup_routes_instruction_files() {
  local fixture kind
  for kind in agents claude both; do
    fixture="${TEST_TEMP_ROOT}/setup-routing-${kind}"
    mkdir -p "${fixture}"
    [[ "${kind}" == claude ]] || printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
    [[ "${kind}" == agents ]] || printf '%s\n' '# Existing claude' >"${fixture}/CLAUDE.md"
    apply_setup_configurator "${fixture}" >/dev/null || return
    [[ "${kind}" == claude ]] || grep -Fq '<!-- ai-workflow:agent-skills:start -->' "${fixture}/AGENTS.md" || return
    [[ "${kind}" == agents ]] || grep -Fq '<!-- ai-workflow:agent-skills:start -->' "${fixture}/CLAUDE.md" || return
    if [[ "${kind}" == both ]]; then
      python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github \
        --remote-name origin >/dev/null || return
    fi
  done

  fixture="${TEST_TEMP_ROOT}/setup-routing-neither"
  mkdir -p "${fixture}"
  ! run_setup_configurator "${fixture}" >/dev/null 2>&1 || return
  apply_setup_configurator "${fixture}" --instruction-file AGENTS.md >/dev/null
}

test_setup_requires_confirmation_and_previews() {
  local fixture="${TEST_TEMP_ROOT}/setup-confirmation"
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  run_setup_configurator "${fixture}" >/dev/null || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]] || return
  ! run_setup_configurator "${fixture}" --apply >/dev/null 2>&1 || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_apply_is_idempotent() {
  local fixture="${TEST_TEMP_ROOT}/setup-idempotent" output
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  output="$(run_setup_configurator "${fixture}" --apply --confirmed)" || return
  [[ "${output}" == "No changes." ]]
}

test_setup_token_rejects_target_drift() {
  local fixture="${TEST_TEMP_ROOT}/setup-target-drift" token
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  token="$(setup_plan_token "${fixture}")" || return
  printf '%s\n' '# Added after preview' >"${fixture}/CLAUDE.md"
  ! run_setup_configurator "${fixture}" \
    --apply --confirmed --plan-token "${token}" >/dev/null 2>&1 || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_token_rejects_content_drift() {
  local fixture="${TEST_TEMP_ROOT}/setup-content-drift" token
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  token="$(setup_plan_token "${fixture}")" || return
  printf '%s\n' '# Changed after preview' >"${fixture}/AGENTS.md"
  ! run_setup_configurator "${fixture}" \
    --apply --confirmed --plan-token "${token}" >/dev/null 2>&1 || return
  [[ "$(head -n 1 "${fixture}/AGENTS.md")" == '# Changed after preview' ]] && \
    [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_token_rejects_file_creation_drift() {
  local fixture="${TEST_TEMP_ROOT}/setup-file-creation-drift" token
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  token="$(setup_plan_token "${fixture}")" || return
  mkdir -p "${fixture}/docs/agents"
  : >"${fixture}/docs/agents/issue-tracker.md"
  ! run_setup_configurator "${fixture}" \
    --apply --confirmed --plan-token "${token}" >/dev/null 2>&1 || return
  [[ ! -s "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_token_rejects_remote_drift() {
  local fixture="${TEST_TEMP_ROOT}/setup-token-remote-drift" token
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  token="$(setup_plan_token "${fixture}")" || return
  git -C "${fixture}" remote set-url --push origin git@github.com:pong1013/fork.git
  ! run_setup_configurator "${fixture}" \
    --apply --confirmed --plan-token "${token}" >/dev/null 2>&1 || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_rejects_remote_mismatch() {
  local fixture="${TEST_TEMP_ROOT}/setup-remote-mismatch"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin git@github.com:pong1013/different.git
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  ! python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --github-repository pong1013/example \
    --remote-name origin \
    --apply --confirmed >/dev/null 2>&1 || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_rejects_ambiguous_remote() {
  local fixture="${TEST_TEMP_ROOT}/setup-ambiguous-remote"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin git@github.com:pong1013/example.git
  git -C "${fixture}" remote set-url --add origin git@github.com:pong1013/other.git
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  ! python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --github-repository pong1013/example \
    --remote-name origin \
    --apply --confirmed >/dev/null 2>&1 || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_rejects_missing_remote() {
  local fixture="${TEST_TEMP_ROOT}/setup-missing-remote"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  ! python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --github-repository pong1013/example \
    --remote-name origin \
    --apply --confirmed >/dev/null 2>&1 || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_rejects_split_push_remote() {
  local fixture="${TEST_TEMP_ROOT}/setup-split-push-remote"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin git@github.com:pong1013/example.git
  git -C "${fixture}" remote set-url --push origin git@github.com:pong1013/fork.git
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  ! python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --github-repository pong1013/example \
    --remote-name origin \
    --apply --confirmed >/dev/null 2>&1 || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]]
}

test_setup_rejects_symlinked_instruction_file() {
  local fixture="${TEST_TEMP_ROOT}/setup-symlink-instruction"
  local outside="${TEST_TEMP_ROOT}/outside-agents.md"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin git@github.com:pong1013/example.git
  printf '%s\n' 'outside sentinel' >"${outside}"
  ln -s "${outside}" "${fixture}/AGENTS.md"
  ! run_setup_configurator "${fixture}" --apply --confirmed >/dev/null 2>&1 || return
  [[ "$(cat "${outside}")" == "outside sentinel" ]]
}

test_setup_rejects_symlinked_docs_directory() {
  local fixture="${TEST_TEMP_ROOT}/setup-symlink-docs"
  local outside="${TEST_TEMP_ROOT}/outside-docs"
  mkdir -p "${fixture}/docs" "${outside}"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin git@github.com:pong1013/example.git
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  printf '%s\n' 'outside sentinel' >"${outside}/sentinel"
  ln -s "${outside}" "${fixture}/docs/agents"
  ! run_setup_configurator "${fixture}" --apply --confirmed >/dev/null 2>&1 || return
  [[ "$(cat "${outside}/sentinel")" == "outside sentinel" ]] && \
    [[ ! -e "${outside}/issue-tracker.md" ]]
}

test_setup_rejects_unsupported_tracker() {
  local fixture="${TEST_TEMP_ROOT}/unsupported-tracker"
  write_valid_setup_fixture "${fixture}"
  sed -i.bak 's/# Issue tracker: GitHub/# Issue tracker: GitLab/' \
    "${fixture}/docs/agents/issue-tracker.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github >/dev/null 2>&1
}

test_setup_rejects_unknown_tracker() {
  local fixture="${TEST_TEMP_ROOT}/unknown-tracker" output
  write_valid_setup_fixture "${fixture}"
  sed -i.bak 's/# Issue tracker: GitHub/# Issue tracker: Jira/' \
    "${fixture}/docs/agents/issue-tracker.md"
  sed -i.bak 's/GitHub/Jira/g' "${fixture}/AGENTS.md"
  if output="$(python3 "${SETUP_VALIDATOR}" "${fixture}" 2>&1)"; then
    return 1
  fi
  grep -Fq 'unsupported tracker Jira; expected GitHub, GitLab, or Local Markdown' <<<"${output}"
}

write_valid_gitlab_setup_fixture() {
  local fixture="$1"
  mkdir -p "${fixture}/docs/agents"
  cp "${ROOT_DIR}/skills/setup-matt-pocock-skills/issue-tracker-gitlab.md" \
    "${fixture}/docs/agents/issue-tracker.md"
  sed -i.bak \
    -e 's#<confirmed-owner>/<confirmed-repository>#pong1013/ai-workflow#' \
    -e 's#<confirmed-remote-name>#origin#' \
    "${fixture}/docs/agents/issue-tracker.md"
  cp "${ROOT_DIR}/docs/agents/domain.md" "${fixture}/docs/agents/domain.md"
  cp "${ROOT_DIR}/AGENTS.md" "${fixture}/AGENTS.md"
  sed -i.bak \
    's#Specifications and tickets are tracked.*#Specifications and tickets are configured for `pong1013/ai-workflow` GitLab. See `docs/agents/issue-tracker.md`.#' \
    "${fixture}/AGENTS.md"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin https://gitlab.com/pong1013/ai-workflow.git
}

test_valid_non_github_setup_output() {
  local fixture="${TEST_TEMP_ROOT}/valid-gitlab-setup"
  write_valid_gitlab_setup_fixture "${fixture}"
  python3 "${SETUP_VALIDATOR}" "${fixture}" --remote-name origin >/dev/null
}

test_non_github_setup_helper_uses_plan_tokens() {
  local fixture token

  fixture="${TEST_TEMP_ROOT}/configured-gitlab-setup"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin https://gitlab.com/pong1013/ai-workflow.git
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  token="$(python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --tracker gitlab --tracker-repository pong1013/ai-workflow --remote-name origin \
    | sed -n 's/^Setup plan token: //p')" || return
  [[ "${token}" == sha256:* ]] || return
  python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --tracker gitlab --tracker-repository pong1013/ai-workflow --remote-name origin \
    --apply --confirmed --plan-token "${token}" >/dev/null || return
  python3 "${SETUP_VALIDATOR}" "${fixture}" --remote-name origin >/dev/null || return

  fixture="${TEST_TEMP_ROOT}/configured-local-setup"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  token="$(python3 "${SETUP_CONFIGURATOR}" "${fixture}" --tracker local-markdown \
    | sed -n 's/^Setup plan token: //p')" || return
  [[ "${token}" == sha256:* ]] || return
  python3 "${SETUP_CONFIGURATOR}" "${fixture}" --tracker local-markdown \
    --apply --confirmed --plan-token "${token}" >/dev/null || return
  python3 "${SETUP_VALIDATOR}" "${fixture}" >/dev/null
}

test_setup_rejects_non_github_placeholder() {
  local fixture="${TEST_TEMP_ROOT}/gitlab-placeholder"
  write_valid_gitlab_setup_fixture "${fixture}"
  sed -i.bak 's#pong1013/ai-workflow#<confirmed-owner>/<confirmed-repository>#' \
    "${fixture}/docs/agents/issue-tracker.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --remote-name origin >/dev/null 2>&1
}

test_setup_rejects_non_github_instruction_conflict() {
  local fixture="${TEST_TEMP_ROOT}/gitlab-instruction-conflict"
  write_valid_gitlab_setup_fixture "${fixture}"
  sed -i.bak 's/ GitLab\./ GitHub./' "${fixture}/AGENTS.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --remote-name origin >/dev/null 2>&1
}

test_setup_rejects_same_provider_repository_drift() {
  local fixture="${TEST_TEMP_ROOT}/gitlab-repository-drift"
  write_valid_gitlab_setup_fixture "${fixture}"
  sed -i.bak 's#`pong1013/ai-workflow` GitLab#`someone/other` GitLab#' \
    "${fixture}/AGENTS.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --remote-name origin >/dev/null 2>&1
}

test_setup_rejects_additional_same_provider_repository() {
  local fixture="${TEST_TEMP_ROOT}/gitlab-additional-repository"
  write_valid_gitlab_setup_fixture "${fixture}"
  sed -i.bak \
    's#Specifications and tickets are configured for `pong1013/ai-workflow` GitLab\. See `docs/agents/issue-tracker.md`\.#Specifications and tickets are configured for `pong1013/ai-workflow` GitLab. See `docs/agents/issue-tracker.md`.\
Specifications and tickets are configured for `someone/other` GitLab. See `docs/agents/issue-tracker.md`\.#' \
    "${fixture}/AGENTS.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --remote-name origin >/dev/null 2>&1
}

test_setup_rejects_local_root_drift() {
  local fixture="${TEST_TEMP_ROOT}/local-root-drift"
  mkdir -p "${fixture}/docs/agents"
  cp "${ROOT_DIR}/skills/setup-matt-pocock-skills/issue-tracker-local.md" \
    "${fixture}/docs/agents/issue-tracker.md"
  cp "${ROOT_DIR}/docs/agents/domain.md" "${fixture}/docs/agents/domain.md"
  cp "${ROOT_DIR}/AGENTS.md" "${fixture}/AGENTS.md"
  sed -i.bak \
    's#Specifications and tickets are tracked.*#Specifications and tickets use Local Markdown under `other/`. See `docs/agents/issue-tracker.md`.#' \
    "${fixture}/AGENTS.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" >/dev/null 2>&1
}

test_setup_rejects_non_github_remote_mismatch() {
  local fixture="${TEST_TEMP_ROOT}/gitlab-remote-mismatch"
  write_valid_gitlab_setup_fixture "${fixture}"
  git -C "${fixture}" remote set-url origin https://gitlab.com/pong1013/different.git
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --remote-name origin >/dev/null 2>&1
}

test_valid_local_markdown_setup_output() {
  local fixture="${TEST_TEMP_ROOT}/valid-local-setup"
  mkdir -p "${fixture}/docs/agents"
  cp "${ROOT_DIR}/skills/setup-matt-pocock-skills/issue-tracker-local.md" \
    "${fixture}/docs/agents/issue-tracker.md"
  cp "${ROOT_DIR}/docs/agents/domain.md" "${fixture}/docs/agents/domain.md"
  cp "${ROOT_DIR}/AGENTS.md" "${fixture}/AGENTS.md"
  sed -i.bak \
    's#Specifications and tickets are tracked.*#Specifications and tickets use Local Markdown under `.scratch/`. See `docs/agents/issue-tracker.md`.#' \
    "${fixture}/AGENTS.md"
  python3 "${SETUP_VALIDATOR}" "${fixture}" >/dev/null
}

test_setup_rejects_additional_local_root() {
  local fixture="${TEST_TEMP_ROOT}/local-additional-root"
  mkdir -p "${fixture}/docs/agents"
  cp "${ROOT_DIR}/skills/setup-matt-pocock-skills/issue-tracker-local.md" \
    "${fixture}/docs/agents/issue-tracker.md"
  cp "${ROOT_DIR}/docs/agents/domain.md" "${fixture}/docs/agents/domain.md"
  cp "${ROOT_DIR}/AGENTS.md" "${fixture}/AGENTS.md"
  sed -i.bak \
    's#Specifications and tickets are tracked.*#Specifications and tickets use Local Markdown under `.scratch/`. See `docs/agents/issue-tracker.md`.\
Specifications and tickets use Local Markdown under `other/`. See `docs/agents/issue-tracker.md`.#' \
    "${fixture}/AGENTS.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" >/dev/null 2>&1
}

test_setup_rejects_additional_tracker_prose() {
  local fixture="${TEST_TEMP_ROOT}/github-additional-tracker-prose"
  write_valid_setup_fixture "${fixture}"
  sed -i.bak \
    's#Specifications and tickets are tracked in `pong1013/ai-workflow` GitHub Issues\. See `docs/agents/issue-tracker.md`\.#Specifications and tickets are tracked in `pong1013/ai-workflow` GitHub Issues. See `docs/agents/issue-tracker.md`.\
Also use `someone/other` as the GitHub repository.#' \
    "${fixture}/AGENTS.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github >/dev/null 2>&1
}

test_setup_rejects_instruction_drift() {
  local fixture="${TEST_TEMP_ROOT}/instruction-drift"
  write_valid_setup_fixture "${fixture}"
  cp "${fixture}/AGENTS.md" "${fixture}/CLAUDE.md"
  sed -i.bak 's/single-context repository/multi-context repository/' "${fixture}/CLAUDE.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github >/dev/null 2>&1
}

test_setup_rejects_incomplete_managed_block() {
  local fixture="${TEST_TEMP_ROOT}/incomplete-managed-block"
  write_valid_setup_fixture "${fixture}"
  sed -i.bak '/### Domain docs/,/docs\/agents\/domain.md/d' "${fixture}/AGENTS.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github >/dev/null 2>&1
}

test_setup_rejects_credentials() {
  local fixture="${TEST_TEMP_ROOT}/credential"
  write_valid_setup_fixture "${fixture}"
  printf '%s\n' 'Token: github_pat_abcdefghijklmnopqrstuvwxyz123456' \
    >> "${fixture}/docs/agents/issue-tracker.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github >/dev/null 2>&1
}

test_setup_rejects_triage_configuration() {
  local fixture="${TEST_TEMP_ROOT}/triage-configuration"
  write_valid_setup_fixture "${fixture}"
  printf '%s\n' '# Triage Labels' >"${fixture}/docs/agents/triage-labels.md"
  ! python3 "${SETUP_VALIDATOR}" "${fixture}" --require-github >/dev/null 2>&1
}

test_runtime_safety_contract() {
  grep -Fq 'setup-matt-pocock-skills' "${CONTROLLER_DIR}/references/preflight.md" && \
    grep -Fq 'exactly two top-level worker roles' "${CONTROLLER_DIR}/references/quality-loop.md" && \
    grep -Fq 'Dispatch both top-level workers concurrently before awaiting either one' "${CONTROLLER_DIR}/references/quality-loop.md" && \
    grep -Fq 'one local ticket commit' "${CONTROLLER_DIR}/SKILL.md" && \
    grep -Fq 'Never merge or close issues directly' "${CONTROLLER_DIR}/SKILL.md" && \
    grep -Fq '.agents/runs/<feature-id>.json' "${CONTROLLER_DIR}/references/checkpoints.md" && \
    grep -Fq 'Delivery Gate' "${CONTROLLER_DIR}/references/delivery.md"
}

test_old_controller_is_not_published() {
  [[ ! -e "${ROOT_DIR}/skills/ship-feature" ]] && \
    ! grep -R -Fq '$ship-feature' "${ROOT_DIR}/.codex-plugin" "${ROOT_DIR}/skills"
}

run_test "pinned Plugin manifest schema passes" test_plugin_manifest
run_test "Plugin schema rejects unsupported fields" test_plugin_rejects_unsupported_field
run_test "Skill and agent metadata schemas pass" test_skill_metadata
run_test "Skill schema rejects unsupported frontmatter" test_skill_rejects_unsupported_frontmatter
run_test "agent metadata schema rejects invalid policy" test_skill_rejects_invalid_agent_metadata
run_test "Plugin contains the exact final Skill set" test_exact_skill_set
run_test "all workflow Skills are explicit-only" test_explicit_invocation_metadata
run_test "published assets contain no scaffold placeholders" test_no_placeholders
run_test "all relative Markdown links resolve" test_all_markdown_links
run_test "v2 state and authorization model passes" test_state_model
run_test "state model rejects a delivery shortcut" test_state_model_rejects_shortcut
run_test "state model separates Delivery approval from success" test_state_model_rejects_delivery_approval_as_completion
run_test "state model requires push and pull-request success evidence" test_state_model_requires_both_delivery_results
run_test "state model rejects an incorrectly authorized push" test_state_model_rejects_ungated_push
run_test "state model rejects a dangling authority" test_state_model_rejects_dangling_authority
run_test "state model rejects a dangling composite authority" test_state_model_rejects_dangling_composite
run_test "state model rejects a ticket commit without quality" test_state_model_rejects_unsafe_ticket_commit
run_test "state model rejects Contract persistence without bootstrap workspace" test_state_model_rejects_contract_without_bootstrap_workspace
run_test "state model rejects a checkpoint before workspace establishment" test_state_model_rejects_early_checkpoint
run_test "state model rejects setup without an Exception path" test_state_model_rejects_setup_without_exception_path
run_test "state model rejects an ungated worktree mutation" test_state_model_rejects_ungated_worktree
run_test "state model rejects serial ticket workers" test_state_model_rejects_serial_workers
run_test "state model rejects an unsafe overlap fallback" test_state_model_rejects_unsafe_overlap_fallback
run_test "state model rejects an unbounded review loop" test_state_model_rejects_unbounded_review_loop
run_test "state model rejects an incorrect finding route" test_state_model_rejects_wrong_finding_route
run_test "state model rejects a mutating review policy" test_state_model_rejects_mutating_review
run_test "state model requires a complete ordered round ledger" test_state_model_requires_complete_round_ledger
run_test "state model preserves failed rounds after retry" test_state_model_rejects_dropped_failed_rounds
run_test "state model includes feature-level rounds" test_state_model_rejects_missing_feature_rounds
run_test "state model requires an explicit round number" test_state_model_rejects_missing_round_number
run_test "state model includes the ledger at Delivery Gate" test_state_model_rejects_missing_delivery_ledger
run_test "state model requires reasons for inapplicable checks" test_state_model_rejects_unexplained_not_applicable
run_test "state model rejects a substituted stage Skill" test_state_model_rejects_wrong_stage_skill
run_test "state model requires reply progress and one Grill question" test_state_model_requires_reply_progress_and_one_grill_question
run_test "state model rejects batched Grill questions" test_state_model_rejects_batched_grill_questions
run_test "state model rejects missing reply progress" test_state_model_rejects_missing_reply_progress
run_test "state model rejects a duplicate transition" test_state_model_rejects_duplicate_transition
run_test "state model rejects a duplicate external operation" test_state_model_rejects_duplicate_operation
run_test "state model rejects an unknown state" test_state_model_rejects_unknown_state
run_test "state model rejects a duplicate state" test_state_model_rejects_duplicate_state
run_test "controller stage dependencies resolve" test_controller_dependencies_resolve
run_test "Matt upstream provenance is pinned and complete" test_upstream_provenance
run_test "setup package contains no triage behavior" test_no_triage_payload
run_test "non-GitHub seeds contain no bundled workflow operations" test_non_github_seeds_have_no_workflow_operations
run_test "adapted implement never commits" test_implement_does_not_commit
run_test "GitHub specification and ticket gates are wired" test_github_only_publication_contract
run_test "README installs the complete staged Skill set" test_readme_installs_complete_staged_set
run_test "valid repository setup passes" test_valid_setup_output
run_test "setup routes AGENTS and CLAUDE instruction files" test_setup_routes_instruction_files
run_test "setup previews and refuses unconfirmed writes" test_setup_requires_confirmation_and_previews
run_test "setup apply is idempotent" test_setup_apply_is_idempotent
run_test "setup plan token rejects target routing drift" test_setup_token_rejects_target_drift
run_test "setup plan token rejects approved-content drift" test_setup_token_rejects_content_drift
run_test "setup plan token rejects file-creation drift" test_setup_token_rejects_file_creation_drift
run_test "setup plan token rejects remote drift" test_setup_token_rejects_remote_drift
run_test "setup rejects a live remote mismatch" test_setup_rejects_remote_mismatch
run_test "setup rejects an ambiguous live remote" test_setup_rejects_ambiguous_remote
run_test "setup rejects a missing live remote" test_setup_rejects_missing_remote
run_test "setup rejects split fetch and push targets" test_setup_rejects_split_push_remote
run_test "setup rejects a symlinked instruction file" test_setup_rejects_symlinked_instruction_file
run_test "setup rejects a symlinked docs directory" test_setup_rejects_symlinked_docs_directory
run_test "setup validator rejects unsupported tracker" test_setup_rejects_unsupported_tracker
run_test "setup validator rejects an unknown tracker" test_setup_rejects_unknown_tracker
run_test "setup validator accepts a concrete GitLab configuration" test_valid_non_github_setup_output
run_test "setup validator accepts a concrete Local Markdown configuration" test_valid_local_markdown_setup_output
run_test "non-GitHub setup helper uses approved plan tokens" test_non_github_setup_helper_uses_plan_tokens
run_test "setup validator rejects non-GitHub placeholders" test_setup_rejects_non_github_placeholder
run_test "setup validator rejects tracker/instruction conflict" test_setup_rejects_non_github_instruction_conflict
run_test "setup validator rejects same-provider repository drift" test_setup_rejects_same_provider_repository_drift
run_test "setup validator rejects an additional same-provider repository" test_setup_rejects_additional_same_provider_repository
run_test "setup validator rejects Local Markdown root drift" test_setup_rejects_local_root_drift
run_test "setup validator rejects an additional Local Markdown root" test_setup_rejects_additional_local_root
run_test "setup validator rejects additional tracker prose" test_setup_rejects_additional_tracker_prose
run_test "setup validator rejects non-GitHub remote mismatch" test_setup_rejects_non_github_remote_mismatch
run_test "setup validator rejects AGENTS and CLAUDE drift" test_setup_rejects_instruction_drift
run_test "setup validator rejects an incomplete managed block" test_setup_rejects_incomplete_managed_block
run_test "setup validator rejects credentials" test_setup_rejects_credentials
run_test "setup validator rejects triage configuration" test_setup_rejects_triage_configuration
run_test "runtime safety contract is wired" test_runtime_safety_contract
run_test "old ship-feature controller is not published" test_old_controller_is_not_published

echo "${tests_run} tests, ${failures} failures"
[[ "${failures}" -eq 0 ]]
