#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER_DIR="${ROOT_DIR}/skills/ai-workflow"
STATE_MODEL="${CONTROLLER_DIR}/references/state-machine.json"
SETUP_VALIDATOR="${ROOT_DIR}/skills/setup-matt-pocock-skills/scripts/validate_setup.py"
SETUP_CONFIGURATOR="${ROOT_DIR}/skills/setup-matt-pocock-skills/scripts/configure_repository.py"
SETUP_RECEIPT_VALIDATOR="${ROOT_DIR}/skills/setup-matt-pocock-skills/scripts/validate_setup_receipt.py"
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

test_state_model_requires_configuration_reconciliation() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

model = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert model["version"] == 3
assert "configuration-reconciliation" in model["states"]
edges = {
    (item["from"], item["event"], item["to"])
    for item in model["transitions"]
}
assert (
    "ticket-commit",
    "ticket-committed-all-done",
    "configuration-reconciliation",
) in edges
assert (
    "configuration-reconciliation",
    "configuration-reconciled",
    "feature-review",
) in edges
assert (
    "ticket-commit",
    "ticket-committed-all-done",
    "feature-review",
) not in edges
PY
}

test_state_model_rejects_reconciliation_bypass() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-bypass.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'edge = next(x for x in payload["transitions"] if x["event"] == "ticket-committed-all-done"); edge["to"] = "feature-review"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_requires_exact_workspace_baseline() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

policy = json.loads(pathlib.Path(sys.argv[1]).read_text())["workspaceBaselinePolicy"]
assert policy["granularity"] == "path-hunk-hash"
assert set(policy["requiredFields"]) == {"path", "hunk", "contentHash"}
PY
}

test_state_model_rejects_incomplete_workspace_baseline() {
  local fixture="${TEST_TEMP_ROOT}/incomplete-workspace-baseline.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["workspaceBaselinePolicy"]["requiredFields"].remove("hunk")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_requires_append_only_mutation_provenance() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

policy = json.loads(pathlib.Path(sys.argv[1]).read_text())["mutationLedgerPolicy"]
assert policy["appendOnly"] is True
assert set(policy["eventRequiredFields"]) == {
    "sequence",
    "stage",
    "ticket",
    "provenance",
    "path",
    "hunk",
    "beforeHash",
    "afterHash",
}
assert policy["provenanceCategories"] == [
    "ticket-owned",
    "setup/configuration",
    "project knowledge",
    "pre-existing unrelated",
]
assert policy["hashChain"]["beforeMatchesPreviousAfter"] is True
PY
}

test_state_model_rejects_invalid_provenance_category() {
  local fixture="${TEST_TEMP_ROOT}/invalid-provenance-category.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["mutationLedgerPolicy"]["provenanceCategories"].append("miscellaneous")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_broken_mutation_hash_chain_policy() {
  local fixture="${TEST_TEMP_ROOT}/broken-mutation-hash-chain.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["mutationLedgerPolicy"]["hashChain"]["beforeMatchesPreviousAfter"] = False'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_incomplete_mutation_events() {
  local fixture="${TEST_TEMP_ROOT}/incomplete-mutation-events.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["mutationLedgerPolicy"]["eventRequiredFields"].remove("afterHash")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_requires_live_diff_current_view() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

policy = json.loads(pathlib.Path(sys.argv[1]).read_text())["mutationLedgerPolicy"]
assert policy["currentView"] == {
    "derivedFromLedger": True,
    "validateAgainstLiveDiff": True,
}
PY
}

test_state_model_requires_non_authoritative_receipt_import() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

receipt = json.loads(pathlib.Path(sys.argv[1]).read_text())["mutationLedgerPolicy"]["receiptImport"]
assert receipt == {
    "evidenceOnly": True,
    "approvalAuthority": False,
    "validateLiveDiff": True,
    "requiredFields": [
        "eventSequence",
        "evidenceOnly",
        "approvalAuthority",
        "terminalHash",
        "receiptPath",
        "receiptChecksum",
    ],
}
PY
}

test_state_model_rejects_receipt_import_without_live_validation() {
  local fixture="${TEST_TEMP_ROOT}/receipt-without-live-validation.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["mutationLedgerPolicy"]["receiptImport"]["validateLiveDiff"] = False'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_incomplete_receipt_import_contract() {
  local fixture="${TEST_TEMP_ROOT}/incomplete-receipt-import-contract.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["mutationLedgerPolicy"]["receiptImport"]["requiredFields"].remove("receiptChecksum")'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_rejects_authoritative_receipt_import() {
  local fixture="${TEST_TEMP_ROOT}/authoritative-receipt-import.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["mutationLedgerPolicy"]["receiptImport"]["approvalAuthority"] = True'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_state_model_requires_configuration_routing() {
  python3 - "${STATE_MODEL}" <<'PY'
import json
import pathlib
import sys

policy = json.loads(pathlib.Path(sys.argv[1]).read_text())["reconciliationPolicy"]
assert policy["state"] == "configuration-reconciliation"
assert policy["setupRouting"] == {
    "mechanical": "first-blocker-ticket",
    "semanticOrScopeOrContractConflict": "exception",
}
assert policy["projectKnowledge"] == "approved-ticket-or-explicit-alternative"
assert policy["legacyCheckpointWithoutEvidence"] == "unverified"
assert set(policy["blocksOn"]) == {
    "invalid-provenance",
    "broken-hash-chain",
    "missing-event",
    "changed-baseline-hunk",
    "unexplained-mutation",
}
PY
}

test_state_model_rejects_missing_reconciliation_blockers() {
  local blocker fixture
  for blocker in \
    invalid-provenance \
    broken-hash-chain \
    missing-event \
    changed-baseline-hunk \
    unexplained-mutation; do
    fixture="${TEST_TEMP_ROOT}/missing-${blocker}.json"
    mutate_json "${STATE_MODEL}" "${fixture}" \
      "payload['reconciliationPolicy']['blocksOn'].remove('${blocker}')"
    ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1 || return
  done
}

test_state_model_rejects_trusted_legacy_checkpoint() {
  local fixture="${TEST_TEMP_ROOT}/trusted-legacy-checkpoint.json"
  mutate_json "${STATE_MODEL}" "${fixture}" \
    'payload["reconciliationPolicy"]["legacyCheckpointWithoutEvidence"] = "trusted"'
  ! python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${fixture}" >/dev/null 2>&1
}

test_controller_documents_configuration_reconciliation_contract() {
  local reference="${CONTROLLER_DIR}/references/configuration-reconciliation.md"
  grep -Fq '[references/configuration-reconciliation.md]' "${CONTROLLER_DIR}/SKILL.md" && \
    grep -Fq 'path/hunk/hash' "${CONTROLLER_DIR}/SKILL.md" && \
    grep -Fq 'append-only mutation ledger' "${CONTROLLER_DIR}/SKILL.md" && \
    grep -Fq 'configuration-reconciliation' "${CONTROLLER_DIR}/SKILL.md" && \
    grep -Fq '`path`, `hunk`, and `contentHash`' "${CONTROLLER_DIR}/references/checkpoints.md" && \
    grep -Fq 'not approval authority' "${CONTROLLER_DIR}/references/checkpoints.md" && \
    grep -Fq 'Mechanical, preview-approved setup' "${reference}" && \
    grep -Fq 'semantic workflow change' "${reference}" && \
    grep -Fq 'Project-knowledge writes' "${reference}" && \
    grep -Fq 'Feature review cannot start until reconciliation passes.' "${reference}" && \
    grep -Fq 'remains `unverified`' "${reference}"
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

test_github_tracker_frontier_uses_current_run_completion() {
  local required='The ready frontier contains open child tickets whose blockers are all complete in the current run.'
  local forbidden='The ready frontier contains open child tickets with no open blockers.'
  local tracker
  for tracker in \
    "${ROOT_DIR}/skills/setup-matt-pocock-skills/issue-tracker-github.md" \
    "${ROOT_DIR}/docs/agents/issue-tracker.md"; do
    grep -Fq "${required}" "${tracker}" || return
    ! grep -Fq "${forbidden}" "${tracker}" || return
  done
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
  cp "${ROOT_DIR}/.gitignore" "${fixture}/.gitignore"
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

git_local_exclude_path() {
  local fixture="$1" path
  path="$(git -C "${fixture}" rev-parse --git-path info/exclude)" || return
  if [[ "${path}" == /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${fixture}/${path}"
  fi
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

test_setup_previews_and_applies_tracked_receipt_ignore_rule() {
  local fixture="${TEST_TEMP_ROOT}/setup-preview-ignore-rule"
  local output token exclude_path exclude_before exclude_after
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  printf '%s\n' 'user-owned.log' >"${fixture}/.gitignore"

  output="$(run_setup_configurator "${fixture}")" || return
  grep -Fq -- '--- a/.gitignore' <<<"${output}" || return
  grep -Fq -- '+.agents/setup/' <<<"${output}" || return
  token="$(sed -n 's/^Setup plan token: //p' <<<"${output}")"
  [[ "${token}" == sha256:* ]] || return
  exclude_path="$(git_local_exclude_path "${fixture}")" || return
  exclude_before="$(shasum -a 256 "${exclude_path}")" || return

  run_setup_configurator "${fixture}" \
    --apply --confirmed --plan-token "${token}" >/dev/null || return
  exclude_after="$(shasum -a 256 "${exclude_path}")" || return
  grep -Fxq 'user-owned.log' "${fixture}/.gitignore" || return
  grep -Fxq '.agents/setup/' "${fixture}/.gitignore" || return
  git -C "${fixture}" check-ignore -q .agents/setup/receipt.json || return
  [[ -f "${fixture}/.agents/setup/receipt.json" ]] || return
  [[ "${exclude_before}" == "${exclude_after}" ]] || return
  python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}" >/dev/null
}

test_setup_token_rejects_receipt_ignore_target_drift() {
  local fixture="${TEST_TEMP_ROOT}/setup-ignore-target-drift"
  local token exclude_path exclude_before exclude_after
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  printf '%s\n' 'user-owned.log' >"${fixture}/.gitignore"
  token="$(setup_plan_token "${fixture}")" || return
  [[ "${token}" == sha256:* ]] || return
  exclude_path="$(git_local_exclude_path "${fixture}")" || return
  exclude_before="$(shasum -a 256 "${exclude_path}")" || return

  printf '%s\n' 'added-after-preview.tmp' >>"${fixture}/.gitignore"
  ! run_setup_configurator "${fixture}" \
    --apply --confirmed --plan-token "${token}" >/dev/null 2>&1 || return
  exclude_after="$(shasum -a 256 "${exclude_path}")" || return
  grep -Fxq 'added-after-preview.tmp' "${fixture}/.gitignore" || return
  [[ ! -e "${fixture}/.agents/setup/receipt.json" ]] || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]] || return
  [[ "${exclude_before}" == "${exclude_after}" ]]
}

test_setup_repairs_effective_receipt_ignore_negation() {
  local fixture="${TEST_TEMP_ROOT}/setup-ignore-negation" output token
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  printf '%s\n' '.agents/setup/' '!.agents/setup/' >"${fixture}/.gitignore"

  output="$(run_setup_configurator "${fixture}")" || return
  grep -Fq -- '--- a/.gitignore' <<<"${output}" || return
  grep -Fq -- '+.agents/setup/' <<<"${output}" || return
  token="$(sed -n 's/^Setup plan token: //p' <<<"${output}")"
  [[ "${token}" == sha256:* ]] || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]] || return

  run_setup_configurator "${fixture}" \
    --apply --confirmed --plan-token "${token}" >/dev/null || return
  [[ "$(tail -n 3 "${fixture}/.gitignore")" == $'.agents/setup/\n!.agents/setup/\n.agents/setup/' ]] || return
  git -C "${fixture}" check-ignore -q .agents/setup/receipt.json || return
  [[ -f "${fixture}/.agents/setup/receipt.json" ]] || return
  python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}" >/dev/null
}

test_setup_rejects_ineffective_proposed_ignore_before_writes() {
  local fixture="${TEST_TEMP_ROOT}/setup-ineffective-ignore" output
  local agents_before gitignore_before nested_before
  mkdir -p "${fixture}/.agents"
  git -C "${fixture}" init -q
  git -C "${fixture}" remote add origin git@github.com:pong1013/example.git
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  printf '%s\n' 'user-owned.log' >"${fixture}/.gitignore"
  printf '%s\n' '!setup/' >"${fixture}/.agents/.gitignore"
  agents_before="$(shasum -a 256 "${fixture}/AGENTS.md")" || return
  gitignore_before="$(shasum -a 256 "${fixture}/.gitignore")" || return
  nested_before="$(shasum -a 256 "${fixture}/.agents/.gitignore")" || return

  if output="$(python3 "${SETUP_CONFIGURATOR}" "${fixture}" \
    --github-repository pong1013/example --remote-name origin 2>&1)"; then
    return 1
  fi
  grep -Fqi 'ignore' <<<"${output}" || return
  [[ "$(shasum -a 256 "${fixture}/AGENTS.md")" == "${agents_before}" ]] || return
  [[ "$(shasum -a 256 "${fixture}/.gitignore")" == "${gitignore_before}" ]] || return
  [[ "$(shasum -a 256 "${fixture}/.agents/.gitignore")" == "${nested_before}" ]] || return
  [[ ! -e "${fixture}/docs/agents/issue-tracker.md" ]] || return
  [[ ! -e "${fixture}/docs/agents/domain.md" ]] || return
  [[ ! -e "${fixture}/.agents/setup/receipt.json" ]]
}

test_setup_apply_is_idempotent() {
  local fixture="${TEST_TEMP_ROOT}/setup-idempotent" output
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  output="$(run_setup_configurator "${fixture}" --apply --confirmed)" || return
  [[ "${output}" == "No changes." ]]
}

test_setup_apply_writes_ignored_cross_task_receipt() {
  local fixture="${TEST_TEMP_ROOT}/setup-receipt" receipt output
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"

  apply_setup_configurator "${fixture}" >/dev/null || return
  receipt="${fixture}/.agents/setup/receipt.json"
  [[ -f "${receipt}" ]] || return
  git -C "${fixture}" check-ignore -q .agents/setup/receipt.json || return
  output="$(python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}")" || return
  [[ "${output}" == 'Setup receipt validation passed ('*' mutation(s))' ]] || return
  python3 - "${receipt}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["approvalAuthority"] is False
assert payload["planToken"].startswith("sha256:")
mutations = payload["mutations"]
assert mutations
assert all(item["provenance"] == "setup/configuration" for item in mutations)
assert all(item["beforeHash"].startswith("sha256:") for item in mutations)
assert all(item["afterHash"].startswith("sha256:") for item in mutations)
assert all(item["hunks"] for item in mutations)
for key in ("password", "credential", "accessToken", "authToken", "secret"):
    assert key not in payload
PY
}

test_setup_noop_does_not_replace_receipt() {
  local fixture="${TEST_TEMP_ROOT}/setup-noop-receipt" receipt before after output
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  receipt="${fixture}/.agents/setup/receipt.json"
  before="$(shasum -a 256 "${receipt}")" || return
  output="$(run_setup_configurator "${fixture}" --apply --confirmed)" || return
  after="$(shasum -a 256 "${receipt}")" || return
  [[ "${output}" == "No changes." ]] && [[ "${before}" == "${after}" ]]
}

test_setup_receipt_rejects_live_content_drift() {
  local fixture="${TEST_TEMP_ROOT}/setup-receipt-content-drift"
  [[ -f "${SETUP_RECEIPT_VALIDATOR}" ]] || return
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  printf '%s\n' '# Drift after setup' >>"${fixture}/docs/agents/domain.md"
  ! python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}" >/dev/null 2>&1
}

test_setup_incremental_receipt_validates_changed_subset() {
  local fixture="${TEST_TEMP_ROOT}/setup-incremental-receipt" receipt output
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return

  printf '%s\n' '# Local drift repaired by setup' >>"${fixture}/docs/agents/domain.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  receipt="${fixture}/.agents/setup/receipt.json"
  output="$(python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}")" || return
  [[ "${output}" == 'Setup receipt validation passed (1 mutation(s))' ]] || return
  python3 - "${receipt}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert [item["path"] for item in payload["mutations"]] == ["docs/agents/domain.md"]
PY
}

test_setup_receipt_rejects_remote_and_plan_drift() {
  local fixture="${TEST_TEMP_ROOT}/setup-receipt-identity-drift"
  [[ -f "${SETUP_RECEIPT_VALIDATOR}" ]] || return
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  ! python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}" \
    --plan-token sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    >/dev/null 2>&1 || return
  git -C "${fixture}" remote set-url origin git@github.com:pong1013/different.git
  ! python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}" >/dev/null 2>&1
}

test_setup_receipt_rejects_non_self_consistent_corruption() {
  local fixture="${TEST_TEMP_ROOT}/setup-receipt-tampering" receipt
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  receipt="${fixture}/.agents/setup/receipt.json"
  [[ -f "${SETUP_RECEIPT_VALIDATOR}" && -f "${receipt}" ]] || return
  python3 - "${receipt}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["mutations"][0]["afterHash"] = "sha256:" + "0" * 64
path.write_text(json.dumps(payload), encoding="utf-8")
PY
  ! python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}" >/dev/null 2>&1
}

test_setup_receipt_does_not_claim_hostile_local_authenticity() {
  local fixture="${TEST_TEMP_ROOT}/setup-receipt-local-forgery" receipt output
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  receipt="${fixture}/.agents/setup/receipt.json"
  python3 - "${receipt}" <<'PY'
import hashlib
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload.pop("checksum")
payload["mutations"][0]["hunks"][0]["before"]["hash"] = "sha256:" + "0" * 64
canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
payload["checksum"] = "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
path.write_text(json.dumps(payload), encoding="utf-8")
PY
  output="$(python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}")" || return
  [[ "${output}" == 'Setup receipt validation passed ('*' mutation(s))' ]]
}

test_self_hosted_setup_outputs_are_render_equivalent() {
  local output
  output="$(python3 "${SETUP_CONFIGURATOR}" "${ROOT_DIR}" \
    --github-repository pong1013/ai-workflow \
    --remote-name origin)" || return
  [[ "${output}" == "No changes." ]]
}

test_setup_render_preserves_instruction_content_outside_managed_blocks() {
  local fixture="${TEST_TEMP_ROOT}/setup-render-bounds"
  mkdir -p "${fixture}"
  printf '%s\n' '# Agents preface' 'User-owned agents tail' >"${fixture}/AGENTS.md"
  printf '%s\n' '# Claude preface' 'User-owned claude tail' >"${fixture}/CLAUDE.md"
  apply_setup_configurator "${fixture}" >/dev/null || return
  grep -Fq '# Agents preface' "${fixture}/AGENTS.md" || return
  grep -Fq 'User-owned agents tail' "${fixture}/AGENTS.md" || return
  grep -Fq '# Claude preface' "${fixture}/CLAUDE.md" || return
  grep -Fq 'User-owned claude tail' "${fixture}/CLAUDE.md" || return
  [[ "$(run_setup_configurator "${fixture}")" == "No changes." ]]
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
  cp "${ROOT_DIR}/.gitignore" "${fixture}/.gitignore"
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
  cp "${ROOT_DIR}/.gitignore" "${fixture}/.gitignore"
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

create_reconciliation_repository() {
  local fixture="$1"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q || return
  git -C "${fixture}" config user.name 'AI Workflow Tests'
  git -C "${fixture}" config user.email 'tests@example.invalid'
  printf '%s\n' '.agents/setup/' >>"$(git_local_exclude_path "${fixture}")"
  printf '%s\n' line1 line2 line3 line4 line5 line6 line7 line8 line9 line10 \
    >"${fixture}/two-hunks.txt"
  printf '%s\n' staged-before >"${fixture}/staged.txt"
  printf '%s\n' unstaged-before >"${fixture}/unstaged.txt"
  git -C "${fixture}" add two-hunks.txt staged.txt unstaged.txt
  git -C "${fixture}" commit -qm 'baseline'

  printf '%s\n' baseline-owned-by-user >"${fixture}/baseline-unrelated.txt"
  perl -pi -e 's/^line2$/line2-after/; s/^line9$/line9-after/' "${fixture}/two-hunks.txt"
  git -C "${fixture}" add two-hunks.txt
  git -C "${fixture}" commit -qm 'ticket commit'
  printf '%s\n' staged-after >"${fixture}/staged.txt"
  git -C "${fixture}" add staged.txt
  printf '%s\n' unstaged-after >"${fixture}/unstaged.txt"
  printf '%s\n' untracked-after >"${fixture}/untracked.txt"
  printf '%s\n' setup-after >"${fixture}/setup.txt"
  mkdir -p "${fixture}/.agents/setup"
  printf '%s\n' '{"validated":"by setup receipt validator"}' \
    >"${fixture}/.agents/setup/receipt.json"
}

emit_reconciliation_view() {
  local fixture="$1" base_commit="$2" output="$3"
  python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${STATE_MODEL}" \
    --repository-root "${fixture}" \
    --baseline "${base_commit}" \
    --emit-reconciliation-view >"${output}"
}

write_valid_reconciliation_instance() {
  local view="$1" target="$2" base_commit="$3" fixture="$4"
  python3 - "${view}" "${target}" "${base_commit}" "${fixture}" <<'PY'
import hashlib
import json
import pathlib
import sys

view = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
entries = view["entries"]
baseline = [item for item in entries if item["path"] == "baseline-unrelated.txt"]
assert len(baseline) == 1
receipt_path = pathlib.Path(sys.argv[4]) / ".agents/setup/receipt.json"
receipt_checksum = "sha256:" + hashlib.sha256(receipt_path.read_bytes()).hexdigest()

events = []
imports = []
for item in entries:
    if item["path"] == "baseline-unrelated.txt":
        continue
    sequence = len(events) + 1
    is_setup = item["path"] == "setup.txt"
    events.append({
        "sequence": sequence,
        "stage": "repository-setup" if is_setup else "ticket-work",
        "ticket": "#setup" if is_setup else "#12",
        "provenance": "setup/configuration" if is_setup else "ticket-owned",
        "path": item["path"],
        "hunk": item["hunk"],
        "beforeHash": item["beforeHash"],
        "afterHash": item["afterHash"],
    })
    if is_setup:
        imports.append({
            "eventSequence": sequence,
            "evidenceOnly": True,
            "approvalAuthority": False,
            "terminalHash": item["afterHash"],
            "receiptPath": ".agents/setup/receipt.json",
            "receiptChecksum": receipt_checksum,
        })

payload = {
    "workspaceBaseline": {
        "baseCommit": sys.argv[3],
        "entries": [
            {
                "path": item["path"],
                "hunk": item["hunk"],
                "contentHash": item["contentHash"],
            }
            for item in baseline
        ],
    },
    "mutationLedger": events,
    "setupReceiptImports": imports,
    "approvedAlternatives": [],
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload), encoding="utf-8")
PY
}

prepare_valid_reconciliation_fixture() {
  local fixture="$1" instance="$2" view="$3" base_commit
  create_reconciliation_repository "${fixture}" || return
  base_commit="$(git -C "${fixture}" rev-parse HEAD~1)" || return
  emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
  write_valid_reconciliation_instance "${view}" "${instance}" "${base_commit}" "${fixture}"
}

validate_reconciliation_instance() {
  local fixture="$1" instance="$2"
  python3 "${ROOT_DIR}/scripts/validate_state_machine.py" "${STATE_MODEL}" \
    --repository-root "${fixture}" \
    --reconciliation "${instance}" >/dev/null
}

test_reconciliation_view_composes_every_git_surface() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-view" view base_commit
  view="${TEST_TEMP_ROOT}/reconciliation-view.json"
  create_reconciliation_repository "${fixture}" || return
  base_commit="$(git -C "${fixture}" rev-parse HEAD~1)" || return
  emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
  python3 - "${view}" <<'PY'
import collections
import json
import pathlib
import sys

entries = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))["entries"]
actual = collections.Counter((item["path"], item["surface"]) for item in entries)
assert actual == collections.Counter({
    ("two-hunks.txt", "committed"): 2,
    ("staged.txt", "staged"): 1,
    ("unstaged.txt", "unstaged"): 1,
    ("baseline-unrelated.txt", "untracked"): 1,
    ("untracked.txt", "untracked"): 1,
    ("setup.txt", "untracked"): 1,
})
for item in entries:
    assert item["hunk"]
    assert item["contentHash"].startswith("sha256:")
    assert item["beforeHash"].startswith("sha256:")
    assert item["afterHash"].startswith("sha256:")
PY
}

test_reconciliation_accepts_accounted_composite_view() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-valid"
  local instance="${TEST_TEMP_ROOT}/reconciliation-valid.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-valid-view.json"
  prepare_valid_reconciliation_fixture "${fixture}" "${instance}" "${view}" || return
  validate_reconciliation_instance "${fixture}" "${instance}"
}

test_reconciliation_imports_setup_before_feature_baseline() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-prebaseline-receipt"
  local instance="${TEST_TEMP_ROOT}/reconciliation-prebaseline-receipt.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-prebaseline-view.json" base_commit mutated
  mkdir -p "${fixture}"
  printf '%s\n' '# Existing agents' >"${fixture}/AGENTS.md"
  run_setup_configurator "${fixture}" >/dev/null || return
  git -C "${fixture}" config user.name 'AI Workflow Tests'
  git -C "${fixture}" config user.email 'tests@example.invalid'
  git -C "${fixture}" add AGENTS.md
  git -C "${fixture}" commit -qm 'before setup'
  base_commit="$(git -C "${fixture}" rev-parse HEAD)" || return
  apply_setup_configurator "${fixture}" >/dev/null || return
  python3 "${SETUP_RECEIPT_VALIDATOR}" "${fixture}" >/dev/null || return
  emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
  python3 - "${fixture}" "${view}" "${instance}" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
view = json.loads(pathlib.Path(sys.argv[2]).read_text())
receipt_path = root / ".agents/setup/receipt.json"
receipt = json.loads(receipt_path.read_text())
path = "docs/agents/issue-tracker.md"
mutation = next(item for item in receipt["mutations"] if item["path"] == path)
entry = next(item for item in view["entries"] if item["path"] == path)
assert mutation["beforeHash"] != mutation["afterHash"]
assert mutation["afterHash"] == entry["afterHash"]
payload = {
    "workspaceBaseline": {"baseCommit": view["baseCommit"], "entries": view["entries"]},
    "mutationLedger": [{
        "sequence": 1, "stage": "repository-setup", "ticket": "#setup",
        "provenance": "setup/configuration", "path": path, "hunk": entry["hunk"],
        "beforeHash": mutation["beforeHash"], "afterHash": mutation["afterHash"],
    }],
    "setupReceiptImports": [{
        "eventSequence": 1, "evidenceOnly": True, "approvalAuthority": False,
        "terminalHash": mutation["afterHash"], "receiptPath": ".agents/setup/receipt.json",
        "receiptChecksum": "sha256:" + hashlib.sha256(receipt_path.read_bytes()).hexdigest(),
    }],
    "approvedAlternatives": [],
}
pathlib.Path(sys.argv[3]).write_text(json.dumps(payload))
PY
  [[ "$?" -eq 0 ]] || return
  validate_reconciliation_instance "${fixture}" "${instance}" || return
  # Accepted historical evidence does not weaken the import's integrity or authority checks.
  for mutation in checksum terminal authority; do
    mutated="${TEST_TEMP_ROOT}/reconciliation-prebaseline-${mutation}.json"
    case "${mutation}" in
      checksum) mutate_json "${instance}" "${mutated}" \
        'payload["setupReceiptImports"][0]["receiptChecksum"] = "sha256:" + "0" * 64' ;;
      terminal) mutate_json "${instance}" "${mutated}" \
        'payload["setupReceiptImports"][0]["terminalHash"] = "sha256:" + "0" * 64' ;;
      authority) mutate_json "${instance}" "${mutated}" \
        'payload["setupReceiptImports"][0]["approvalAuthority"] = True' ;;
    esac
    ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return
  done
}

test_reconciliation_rejects_event_sequence_errors() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-sequence"
  local instance="${TEST_TEMP_ROOT}/reconciliation-sequence.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-sequence-view.json" mutated
  prepare_valid_reconciliation_fixture "${fixture}" "${instance}" "${view}" || return
  for mutation in duplicate out-of-order; do
    mutated="${TEST_TEMP_ROOT}/reconciliation-${mutation}.json"
    if [[ "${mutation}" == duplicate ]]; then
      mutate_json "${instance}" "${mutated}" \
        'payload["mutationLedger"][1]["sequence"] = payload["mutationLedger"][0]["sequence"]'
    else
      mutate_json "${instance}" "${mutated}" \
        'payload["mutationLedger"][0]["sequence"], payload["mutationLedger"][1]["sequence"] = payload["mutationLedger"][1]["sequence"], payload["mutationLedger"][0]["sequence"]'
    fi
    ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return
  done
}

test_reconciliation_rejects_broken_hunk_chain() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-chain"
  local instance="${TEST_TEMP_ROOT}/reconciliation-chain.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-chain-view.json" mutated="${TEST_TEMP_ROOT}/reconciliation-broken-chain.json"
  prepare_valid_reconciliation_fixture "${fixture}" "${instance}" "${view}" || return
  mutate_json "${instance}" "${mutated}" \
    'event = dict(payload["mutationLedger"][0]); event["sequence"] = len(payload["mutationLedger"]) + 1; event["beforeHash"] = "sha256:" + "0" * 64; payload["mutationLedger"].append(event)'
  ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1
}

test_reconciliation_rejects_missing_and_unexplained_events() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-events"
  local instance="${TEST_TEMP_ROOT}/reconciliation-events.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-events-view.json" mutated
  prepare_valid_reconciliation_fixture "${fixture}" "${instance}" "${view}" || return

  mutated="${TEST_TEMP_ROOT}/reconciliation-missing-event.json"
  mutate_json "${instance}" "${mutated}" 'payload["mutationLedger"].pop()'
  ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return

  printf '%s\n' unexplained >"${fixture}/not-in-ledger.txt"
  ! validate_reconciliation_instance "${fixture}" "${instance}" >/dev/null 2>&1
}

test_reconciliation_rejects_baseline_drift() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-baseline-drift"
  local instance="${TEST_TEMP_ROOT}/reconciliation-baseline-drift.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-baseline-drift-view.json"
  prepare_valid_reconciliation_fixture "${fixture}" "${instance}" "${view}" || return
  printf '%s\n' changed-after-baseline >"${fixture}/baseline-unrelated.txt"
  ! validate_reconciliation_instance "${fixture}" "${instance}" >/dev/null 2>&1
}

test_reconciliation_rejects_stale_final_newline_event() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-final-newline"
  local instance="${TEST_TEMP_ROOT}/reconciliation-final-newline.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-final-newline-view.json" base_commit
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q || return
  git -C "${fixture}" config user.name 'AI Workflow Tests'
  git -C "${fixture}" config user.email 'tests@example.invalid'
  printf 'old\n' >"${fixture}/text.txt"
  git -C "${fixture}" add text.txt
  git -C "${fixture}" commit -qm 'baseline'
  base_commit="$(git -C "${fixture}" rev-parse HEAD)" || return
  printf 'new\n' >"${fixture}/text.txt"
  emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
  python3 - "${view}" "${instance}" <<'PY'
import json
import pathlib
import sys

view = json.loads(pathlib.Path(sys.argv[1]).read_text())
entry, = view["entries"]
payload = {
    "workspaceBaseline": {"baseCommit": view["baseCommit"], "entries": []},
    "mutationLedger": [{
        "sequence": 1, "stage": "ticket-work", "ticket": "#12",
        "provenance": "ticket-owned", "path": entry["path"], "hunk": entry["hunk"],
        "beforeHash": entry["beforeHash"], "afterHash": entry["afterHash"],
    }],
    "setupReceiptImports": [], "approvedAlternatives": [],
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload))
PY
  [[ "$?" -eq 0 ]] || return
  validate_reconciliation_instance "${fixture}" "${instance}" || return
  printf 'new' >"${fixture}/text.txt"
  ! validate_reconciliation_instance "${fixture}" "${instance}" >/dev/null 2>&1
}

test_reconciliation_rejects_stale_embedded_delimiter_event() {
  local delimiter="${1:-\r}" label="${2:-bare-cr}"
  local fixture="${TEST_TEMP_ROOT}/reconciliation-${label}"
  local instance="${TEST_TEMP_ROOT}/reconciliation-${label}.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-${label}-view.json" base_commit
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q || return
  git -C "${fixture}" config user.name 'AI Workflow Tests'
  git -C "${fixture}" config user.email 'tests@example.invalid'
  printf 'old\n' >"${fixture}/text.txt"
  git -C "${fixture}" add text.txt
  git -C "${fixture}" commit -qm 'baseline'
  base_commit="$(git -C "${fixture}" rev-parse HEAD)" || return
  printf 'new%bhidden-one\n' "${delimiter}" >"${fixture}/text.txt"
  emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
  python3 - "${view}" "${instance}" <<'PY'
import json
import pathlib
import sys

view = json.loads(pathlib.Path(sys.argv[1]).read_text())
entry, = view["entries"]
payload = {
    "workspaceBaseline": {"baseCommit": view["baseCommit"], "entries": []},
    "mutationLedger": [{
        "sequence": 1, "stage": "ticket-work", "ticket": "#12",
        "provenance": "ticket-owned", "path": entry["path"], "hunk": entry["hunk"],
        "beforeHash": entry["beforeHash"], "afterHash": entry["afterHash"],
    }],
    "setupReceiptImports": [], "approvedAlternatives": [],
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload))
PY
  [[ "$?" -eq 0 ]] || return
  validate_reconciliation_instance "${fixture}" "${instance}" || return
  printf 'new%bhidden-two\n' "${delimiter}" >"${fixture}/text.txt"
  ! validate_reconciliation_instance "${fixture}" "${instance}" >/dev/null 2>&1
}

test_reconciliation_rejects_stale_textconv_event() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-textconv"
  local instance="${TEST_TEMP_ROOT}/reconciliation-textconv.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-textconv-view.json" base_commit
  local changed_view="${TEST_TEMP_ROOT}/reconciliation-textconv-changed-view.json"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q || return
  git -C "${fixture}" config user.name 'AI Workflow Tests'
  git -C "${fixture}" config user.email 'tests@example.invalid'
  git -C "${fixture}" config diff.lossy.textconv 'sed s/hidden-[^[:space:]]*/hidden/g'
  printf '*.txt diff=lossy\n' >"${fixture}/.gitattributes"
  printf 'visible hidden-one\n' >"${fixture}/sample.txt"
  git -C "${fixture}" add .gitattributes sample.txt
  git -C "${fixture}" commit -qm 'baseline'
  base_commit="$(git -C "${fixture}" rev-parse HEAD)" || return
  # A visible hunk prevents a whole-file fallback from incidentally covering the hidden edit.
  printf 'changed hidden-two\n' >"${fixture}/sample.txt"
  emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
  python3 - "${view}" "${instance}" <<'PY'
import json
import pathlib
import sys

view = json.loads(pathlib.Path(sys.argv[1]).read_text())
entry, = view["entries"]
assert entry["path"] == "sample.txt"
payload = {
    "workspaceBaseline": {"baseCommit": view["baseCommit"], "entries": []},
    "mutationLedger": [{
        "sequence": 1, "stage": "ticket-work", "ticket": "#12",
        "provenance": "ticket-owned", "path": entry["path"], "hunk": entry["hunk"],
        "beforeHash": entry["beforeHash"], "afterHash": entry["afterHash"],
    }],
    "setupReceiptImports": [], "approvedAlternatives": [],
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload))
PY
  [[ "$?" -eq 0 ]] || return
  validate_reconciliation_instance "${fixture}" "${instance}" || return
  printf 'changed hidden-three\n' >"${fixture}/sample.txt"
  ! validate_reconciliation_instance "${fixture}" "${instance}" >/dev/null 2>&1 || return
  emit_reconciliation_view "${fixture}" "${base_commit}" "${changed_view}" || return
  python3 - "${view}" "${changed_view}" <<'PY'
import json
import pathlib
import sys

before, = json.loads(pathlib.Path(sys.argv[1]).read_text())["entries"]
after, = json.loads(pathlib.Path(sys.argv[2]).read_text())["entries"]
assert before["contentHash"] != after["contentHash"]
assert before["afterHash"] != after["afterHash"]
PY
}

test_reconciliation_rejects_binary_baseline_mode_drift() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-binary-mode"
  local instance="${TEST_TEMP_ROOT}/reconciliation-binary-mode.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-binary-mode-view.json" base_commit phase
  local incomplete="${TEST_TEMP_ROOT}/reconciliation-binary-mode-incomplete.json"
  mkdir -p "${fixture}"
  git -C "${fixture}" init -q || return
  git -C "${fixture}" config user.name 'AI Workflow Tests'
  git -C "${fixture}" config user.email 'tests@example.invalid'
  git -C "${fixture}" config core.filemode true
  printf '\000old\n' >"${fixture}/binary.bin"
  chmod 0644 "${fixture}/binary.bin"
  git -C "${fixture}" add binary.bin
  git -C "${fixture}" commit -qm 'baseline'
  base_commit="$(git -C "${fixture}" rev-parse HEAD)" || return
  printf '\000user\n' >"${fixture}/binary.bin"
  emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
  python3 - "${view}" "${instance}" <<'PY'
import json
import pathlib
import sys

view = json.loads(pathlib.Path(sys.argv[1]).read_text())
payload = {
    "workspaceBaseline": {"baseCommit": view["baseCommit"], "entries": view["entries"]},
    "mutationLedger": [], "setupReceiptImports": [], "approvedAlternatives": [],
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload))
PY
  [[ "$?" -eq 0 ]] || return
  validate_reconciliation_instance "${fixture}" "${instance}" || return
  chmod 0755 "${fixture}/binary.bin"
  ! validate_reconciliation_instance "${fixture}" "${instance}" >/dev/null 2>&1 || return
  for phase in mode-only content-and-mode; do
    if [[ "${phase}" == content-and-mode ]]; then
      printf '\000ticket\n' >"${fixture}/binary.bin"
      ! validate_reconciliation_instance "${fixture}" "${instance}" >/dev/null 2>&1 || return
    fi
    emit_reconciliation_view "${fixture}" "${base_commit}" "${view}" || return
    python3 - "${view}" "${instance}" "${incomplete}" <<'PY'
import copy
import json
import pathlib
import sys

view = json.loads(pathlib.Path(sys.argv[1]).read_text())
payload = json.loads(pathlib.Path(sys.argv[2]).read_text())
baseline = {(item["path"], item["hunk"]): item for item in payload["workspaceBaseline"]["entries"]}
payload["mutationLedger"] = []
for entry in view["entries"]:
    original = baseline.get((entry["path"], entry["hunk"]), entry)
    payload["mutationLedger"].append({
        "sequence": len(payload["mutationLedger"]) + 1,
        "stage": "ticket-work", "ticket": "#12", "provenance": "ticket-owned",
        "path": entry["path"], "hunk": entry["hunk"],
        "beforeHash": original["afterHash"] if original is not entry else entry["beforeHash"],
        "afterHash": entry["afterHash"],
    })
incomplete = copy.deepcopy(payload)
incomplete["mutationLedger"] = [event for event in incomplete["mutationLedger"] if event["hunk"] == "whole-file"]
for sequence, event in enumerate(incomplete["mutationLedger"], 1):
    event["sequence"] = sequence
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload))
pathlib.Path(sys.argv[3]).write_text(json.dumps(incomplete))
PY
    [[ "$?" -eq 0 ]] || return
    ! validate_reconciliation_instance "${fixture}" "${incomplete}" >/dev/null 2>&1 || return
    validate_reconciliation_instance "${fixture}" "${instance}" || return
  done
}

test_reconciliation_rejects_invalid_receipt_imports() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-receipt"
  local instance="${TEST_TEMP_ROOT}/reconciliation-receipt.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-receipt-view.json" mutated
  prepare_valid_reconciliation_fixture "${fixture}" "${instance}" "${view}" || return
  for mutation in authoritative not-evidence terminal-mismatch missing-reference checksum-drift path-traversal; do
    mutated="${TEST_TEMP_ROOT}/reconciliation-receipt-${mutation}.json"
    case "${mutation}" in
      authoritative)
        mutate_json "${instance}" "${mutated}" \
          'payload["setupReceiptImports"][0]["approvalAuthority"] = True'
        ;;
      not-evidence)
        mutate_json "${instance}" "${mutated}" \
          'payload["setupReceiptImports"][0]["evidenceOnly"] = False'
        ;;
      terminal-mismatch)
        mutate_json "${instance}" "${mutated}" \
          'payload["setupReceiptImports"][0]["terminalHash"] = "sha256:" + "0" * 64'
        ;;
      missing-reference)
        mutate_json "${instance}" "${mutated}" \
          'payload["setupReceiptImports"][0].pop("receiptPath")'
        ;;
      checksum-drift)
        mutate_json "${instance}" "${mutated}" \
          'payload["setupReceiptImports"][0]["receiptChecksum"] = "sha256:" + "0" * 64'
        ;;
      path-traversal)
        mutate_json "${instance}" "${mutated}" \
          'payload["setupReceiptImports"][0]["receiptPath"] = "../receipt.json"'
        ;;
    esac
    ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return
  done
}

test_reconciliation_enforces_stage_ownership_and_disposition() {
  local fixture="${TEST_TEMP_ROOT}/reconciliation-ownership"
  local instance="${TEST_TEMP_ROOT}/reconciliation-ownership.json"
  local view="${TEST_TEMP_ROOT}/reconciliation-ownership-view.json" mutated
  prepare_valid_reconciliation_fixture "${fixture}" "${instance}" "${view}" || return

  mutated="${TEST_TEMP_ROOT}/reconciliation-invalid-stage.json"
  mutate_json "${instance}" "${mutated}" \
    'payload["mutationLedger"][0]["stage"] = "invented-stage"'
  ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return

  mutated="${TEST_TEMP_ROOT}/reconciliation-ticket-without-owner.json"
  mutate_json "${instance}" "${mutated}" \
    'event = next(x for x in payload["mutationLedger"] if x["provenance"] == "ticket-owned"); event["ticket"] = None'
  ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return

  mutated="${TEST_TEMP_ROOT}/reconciliation-fake-preexisting.json"
  mutate_json "${instance}" "${mutated}" \
    'event = next(x for x in payload["mutationLedger"] if x["provenance"] == "ticket-owned"); event["provenance"] = "pre-existing unrelated"; event["ticket"] = None'
  ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return

  mutated="${TEST_TEMP_ROOT}/reconciliation-unapproved-knowledge.json"
  mutate_json "${instance}" "${mutated}" \
    'event = next(x for x in payload["mutationLedger"] if x["provenance"] == "ticket-owned"); event["provenance"] = "project knowledge"; event["ticket"] = None'
  ! validate_reconciliation_instance "${fixture}" "${mutated}" >/dev/null 2>&1 || return

  mutated="${TEST_TEMP_ROOT}/reconciliation-approved-knowledge.json"
  mutate_json "${instance}" "${mutated}" \
    'event = next(x for x in payload["mutationLedger"] if x["provenance"] == "ticket-owned"); event["provenance"] = "project knowledge"; event["ticket"] = None; payload["approvedAlternatives"] = [{"eventSequence": event["sequence"], "authority": "exception", "approvalReference": "current-task-message-42"}]'
  validate_reconciliation_instance "${fixture}" "${mutated}" || return

  for reference_mutation in missing empty; do
    local invalid="${TEST_TEMP_ROOT}/reconciliation-alternative-${reference_mutation}.json"
    if [[ "${reference_mutation}" == missing ]]; then
      mutate_json "${mutated}" "${invalid}" \
        'payload["approvedAlternatives"][0].pop("approvalReference")'
    else
      mutate_json "${mutated}" "${invalid}" \
        'payload["approvedAlternatives"][0]["approvalReference"] = ""'
    fi
    ! validate_reconciliation_instance "${fixture}" "${invalid}" >/dev/null 2>&1 || return
  done
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
run_test "v3 state and authorization model passes" test_state_model
run_test "state model routes all completed tickets through configuration reconciliation" test_state_model_requires_configuration_reconciliation
run_test "state model rejects bypassing configuration reconciliation" test_state_model_rejects_reconciliation_bypass
run_test "workspace baseline records path, hunk, and hash" test_state_model_requires_exact_workspace_baseline
run_test "state model rejects an incomplete workspace baseline" test_state_model_rejects_incomplete_workspace_baseline
run_test "mutation provenance is append-only with exact categories and hash chaining" test_state_model_requires_append_only_mutation_provenance
run_test "state model rejects an invalid provenance category" test_state_model_rejects_invalid_provenance_category
run_test "state model rejects a disabled mutation hash chain" test_state_model_rejects_broken_mutation_hash_chain_policy
run_test "state model rejects incomplete mutation events" test_state_model_rejects_incomplete_mutation_events
run_test "mutation current view is ledger-derived and checked against live diff" test_state_model_requires_live_diff_current_view
run_test "setup receipt import is evidence-only and live-validated" test_state_model_requires_non_authoritative_receipt_import
run_test "state model rejects receipt import without live validation" test_state_model_rejects_receipt_import_without_live_validation
run_test "state model rejects an incomplete receipt-import binding contract" test_state_model_rejects_incomplete_receipt_import_contract
run_test "state model rejects receipt approval authority" test_state_model_rejects_authoritative_receipt_import
run_test "reconciliation routes setup, project knowledge, and invalid evidence" test_state_model_requires_configuration_routing
run_test "state model rejects missing provenance, chain, event, drift, and unexplained-mutation blockers" test_state_model_rejects_missing_reconciliation_blockers
run_test "legacy checkpoints without provenance remain unverified" test_state_model_rejects_trusted_legacy_checkpoint
run_test "controller documents the configuration reconciliation contract" test_controller_documents_configuration_reconciliation_contract
run_test "reconciliation view composes committed, staged, unstaged, and untracked hunks" test_reconciliation_view_composes_every_git_surface
run_test "reconciliation accepts a fully accounted composite view" test_reconciliation_accepts_accounted_composite_view
run_test "reconciliation imports validated historical setup evidence by its baseline terminal binding" test_reconciliation_imports_setup_before_feature_baseline
run_test "reconciliation rejects duplicate and out-of-order event sequences" test_reconciliation_rejects_event_sequence_errors
run_test "reconciliation rejects a broken per-hunk hash chain" test_reconciliation_rejects_broken_hunk_chain
run_test "reconciliation rejects missing and unexplained events" test_reconciliation_rejects_missing_and_unexplained_events
run_test "reconciliation rejects changed baseline-unrelated content" test_reconciliation_rejects_baseline_drift
run_test "reconciliation rejects untrusted, terminal-mismatched, missing, drifted, and unsafe receipt imports" test_reconciliation_rejects_invalid_receipt_imports
run_test "reconciliation enforces registered stages, ticket ownership, baseline provenance, and approved alternatives" test_reconciliation_enforces_stage_ownership_and_disposition
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
run_test "GitHub tracker frontier uses current-run blocker completion" test_github_tracker_frontier_uses_current_run_completion
run_test "README installs the complete staged Skill set" test_readme_installs_complete_staged_set
run_test "valid repository setup passes" test_valid_setup_output
run_test "setup routes AGENTS and CLAUDE instruction files" test_setup_routes_instruction_files
run_test "setup previews and refuses unconfirmed writes" test_setup_requires_confirmation_and_previews
run_test "setup previews and applies its tracked receipt ignore rule" test_setup_previews_and_applies_tracked_receipt_ignore_rule
run_test "setup token rejects receipt ignore-target drift" test_setup_token_rejects_receipt_ignore_target_drift
run_test "setup repairs an effective receipt-ignore negation" test_setup_repairs_effective_receipt_ignore_negation
run_test "setup rejects an ineffective proposed ignore before writes" test_setup_rejects_ineffective_proposed_ignore_before_writes
run_test "setup apply is idempotent" test_setup_apply_is_idempotent
run_test "setup apply writes an ignored cross-task receipt" test_setup_apply_writes_ignored_cross_task_receipt
run_test "setup no-op does not replace its last receipt" test_setup_noop_does_not_replace_receipt
run_test "setup receipt rejects live content drift" test_setup_receipt_rejects_live_content_drift
run_test "setup receipt rejects remote and plan drift" test_setup_receipt_rejects_remote_and_plan_drift
run_test "incremental setup receipt validates its changed subset" test_setup_incremental_receipt_validates_changed_subset
run_test "setup receipt rejects non-self-consistent corruption" test_setup_receipt_rejects_non_self_consistent_corruption
run_test "setup receipt does not claim hostile-local authenticity" test_setup_receipt_does_not_claim_hostile_local_authenticity
run_test "self-hosted setup outputs are render-equivalent" test_self_hosted_setup_outputs_are_render_equivalent
run_test "setup render preserves content outside managed blocks" test_setup_render_preserves_instruction_content_outside_managed_blocks
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
run_test "reconciliation rejects a stale ledger event after final LF is lost" test_reconciliation_rejects_stale_final_newline_event
run_test "reconciliation rejects a stale ledger after bare-CR suffix mutation" test_reconciliation_rejects_stale_embedded_delimiter_event '\r' bare-cr
run_test "reconciliation rejects a stale ledger after CRLF suffix mutation" test_reconciliation_rejects_stale_embedded_delimiter_event '\r\n' crlf
run_test "reconciliation rejects a stale ledger after vertical-tab suffix mutation" test_reconciliation_rejects_stale_embedded_delimiter_event '\v' vertical-tab
run_test "reconciliation rejects a stale ledger after form-feed suffix mutation" test_reconciliation_rejects_stale_embedded_delimiter_event '\f' form-feed
run_test "reconciliation rejects binary baseline mode drift without an event" test_reconciliation_rejects_binary_baseline_mode_drift
run_test "reconciliation rejects hidden raw-byte drift with a lossy textconv and visible hunk" test_reconciliation_rejects_stale_textconv_event
run_test "runtime safety contract is wired" test_runtime_safety_contract
run_test "old ship-feature controller is not published" test_old_controller_is_not_published

echo "${tests_run} tests, ${failures} failures"
[[ "${failures}" -eq 0 ]]
