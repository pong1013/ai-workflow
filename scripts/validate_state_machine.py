#!/usr/bin/env python3
"""Validate the complete Full Workflow v1 graph and authorization boundaries."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

EXPECTED_EDGES = {
    ("repository-setup", "setup-configured", "contract", None, True),
    ("contract", "contract-established", "workspace", None, True),
    ("workspace", "reuse-clean-workspace", "intake", None, True),
    ("workspace", "approve-workspace-change", "intake", "workspace", False),
    ("intake", "start-new-feature", "grill", "invocation", True),
    ("intake", "resume-artifact", "resume", None, True),
    ("resume", "approve-resumed-specification", "ticketing", "resume", False),
    ("resume", "approve-resumed-tickets", "ticket-work", "resume", False),
    ("resume", "revise-artifact", "specification", None, False),
    ("grill", "decisions-settled", "specification", None, True),
    ("specification", "approve-and-publish-specification", "ticketing", "specification", False),
    ("ticketing", "approve-and-publish-tickets", "ticket-work", "ticket-breakdown", False),
    ("ticket-work", "workers-joined", "ticket-quality", None, True),
    ("ticket-quality", "owned-findings", "ticket-work", None, True),
    ("ticket-quality", "ticket-quality-passed", "ticket-commit", None, True),
    ("ticket-commit", "ticket-committed-more-ready", "ticket-work", None, True),
    ("ticket-commit", "ticket-committed-all-done", "feature-review", None, True),
    ("feature-review", "owned-findings", "ticket-work", None, True),
    ("feature-review", "feature-review-passed", "delivery", None, True),
    ("delivery", "approve-delivery", "delivery-approved", "delivery", False),
    ("delivery-approved", "delivery-succeeded", "complete", "delivery-operations-succeeded", True),
    ("exception", "decision-received", "$resume", "exception", False),
}
EXPECTED_OPERATIONS = {
    ("persist-setup-configuration", "repository-setup", "setup-confirmation"),
    ("persist-project-contract", "contract", "contract-bootstrap-authority"),
    ("create-or-switch-feature-branch", "workspace", "workspace"),
    ("create-or-switch-feature-worktree", "workspace", "workspace"),
    ("configure-checkpoint-ignore", "workspace", "workspace"),
    (
        "write-run-checkpoint",
        (
            "intake",
            "resume",
            "grill",
            "specification",
            "ticketing",
            "ticket-work",
            "ticket-quality",
            "ticket-commit",
            "feature-review",
            "exception",
            "delivery",
            "delivery-approved",
        ),
        "feature-request-and-workspace",
    ),
    ("write-project-knowledge", "grill", "feature-request-and-workspace"),
    ("create-parent-specification-issue", "specification", "specification"),
    ("create-ticket-sub-issues", "ticketing", "ticket-breakdown"),
    ("write-repository", "ticket-work", "approved-work-scope"),
    ("stage-ticket", "ticket-commit", "ticket-commit-authority"),
    ("commit-ticket", "ticket-commit", "ticket-commit-authority"),
    ("push-feature-branch", "delivery-approved", "delivery"),
    ("create-pull-request", "delivery-approved", "delivery"),
}
TERMINAL = {"complete", "cancelled", "blocked"}
EXPECTED_STATES = {
    "repository-setup",
    "contract",
    "workspace",
    "intake",
    "resume",
    "grill",
    "specification",
    "ticketing",
    "ticket-work",
    "ticket-quality",
    "ticket-commit",
    "feature-review",
    "exception",
    "delivery",
    "delivery-approved",
    "complete",
    "cancelled",
    "blocked",
}
EXPECTED_AUTHORITIES = {
    "invocation": ("invocation-directive", ()),
    "feature-request": ("invocation-scope", ()),
    "setup-confirmation": ("human-gate", ()),
    "bootstrap-workspace": ("human-gate", ()),
    "contract-persistence": ("human-gate", ()),
    "workspace": ("human-gate", ()),
    "workspace-established": ("state-evidence", ()),
    "specification": ("human-gate", ()),
    "ticket-breakdown": ("human-gate", ()),
    "resume": ("human-gate", ()),
    "ticket-quality-passed": ("state-evidence", ()),
    "exception": ("human-gate", ()),
    "delivery": ("human-gate", ()),
    "push-succeeded": ("state-evidence", ()),
    "pull-request-created": ("state-evidence", ()),
    "delivery-operations-succeeded": (
        "composite",
        ("push-succeeded", "pull-request-created"),
    ),
    "contract-bootstrap-authority": (
        "composite",
        ("bootstrap-workspace", "contract-persistence"),
    ),
    "feature-request-and-workspace": (
        "composite",
        ("feature-request", "workspace-established"),
    ),
    "approved-work-scope": (
        "alternative",
        ("ticket-breakdown", "resume"),
    ),
    "ticket-commit-authority": (
        "composite",
        ("approved-work-scope", "ticket-quality-passed"),
    ),
}
EXPECTED_STAGE_SKILLS = {
    "repository-setup": ("setup-matt-pocock-skills",),
    "grill": ("grill-with-docs", "grilling", "domain-modeling"),
    "specification": ("to-spec",),
    "ticketing": ("to-tickets",),
    "ticket-work": ("implement", "tdd"),
    "ticket-quality": ("tdd", "code-review"),
    "feature-review": ("code-review",),
}
EXPECTED_QUALITY_POLICY = {
    "topLevelWorkers": ["implementation", "quality"],
    "dispatch": "concurrent-before-await",
    "overlapFallback": "quality-patch-or-test-design-only",
    "reviewMutation": "read-only",
    "findingRoutes": {
        "production": "implementation",
        "test-or-coverage": "quality",
        "specification-or-architecture": "exception",
    },
    "reviewLoop": {
        "newEvidence": "continue",
        "sameBlockerWithoutNewEvidence": "exception",
    },
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    args = parser.parse_args()
    model = json.loads(args.model.read_text(encoding="utf-8"))
    errors: list[str] = []
    raw_states = model.get("states", [])
    states = set(raw_states)
    terminal = set(model.get("terminalStates", []))
    if model.get("version") != 2:
        errors.append("state model version must be 2")
    if model.get("initialState") != "repository-setup":
        errors.append("initial state must be repository-setup")
    if states != EXPECTED_STATES:
        errors.append("state inventory differs from the v1 contract")
    if len(states) != len(raw_states):
        errors.append("state inventory contains duplicates")
    if terminal != TERMINAL or not terminal <= states:
        errors.append("terminal states must be complete, cancelled, and blocked")

    raw_stage_skills = model.get("stageSkills", {})
    if not isinstance(raw_stage_skills, dict):
        errors.append("stageSkills must be an object")
        stage_skills = {}
    else:
        stage_skills = {
            state: tuple(skills) if isinstance(skills, list) else ()
            for state, skills in raw_stage_skills.items()
        }
    if stage_skills != EXPECTED_STAGE_SKILLS:
        errors.append("stage-Skill registry differs from the workflow contract")
    unknown_skill_states = set(stage_skills) - states
    if unknown_skill_states:
        errors.append(f"stage Skills reference unknown states: {sorted(unknown_skill_states)}")
    invalid_skill_names = sorted({
        repr(skill)
        for skills in stage_skills.values()
        for skill in skills
        if not isinstance(skill, str) or not skill
    })
    if invalid_skill_names:
        errors.append(f"stage Skills contain invalid names: {invalid_skill_names}")

    transition_items = model.get("transitions", [])
    edges = {
        (item.get("from"), item.get("event"), item.get("to"), item.get("gate"), item.get("automatic"))
        for item in transition_items
    }
    if len(edges) != len(transition_items):
        errors.append("transition graph contains duplicate edges")
    if edges != EXPECTED_EDGES:
        errors.append(f"transition graph differs from v1 contract; missing={sorted(EXPECTED_EDGES - edges, key=str)} extra={sorted(edges - EXPECTED_EDGES, key=str)}")
    if any(source in terminal for source, *_ in edges):
        errors.append("terminal states must not have outgoing transitions")

    interruptions = model.get("interruptions", {})
    expected_interrupt_sources = states - terminal - {"exception"}
    if set(interruptions.get("from", [])) != expected_interrupt_sources or interruptions.get("to") != "exception":
        errors.append("every nonterminal work state must be interruptible to exception")

    termination = model.get("termination", {})
    if termination != {
        "from": "any-nonterminal-state",
        "events": ["cancel", "genuine-blocker"],
        "to": ["cancelled", "blocked"],
    }:
        errors.append("termination policy differs from v1 contract")

    if model.get("qualityPolicy") != EXPECTED_QUALITY_POLICY:
        errors.append("quality policy differs from the v1 contract")

    authorities = {}
    for item in model.get("authorities", []):
        identifier = item.get("id")
        if identifier in authorities:
            errors.append(f"duplicate authority: {identifier}")
        authorities[identifier] = (item.get("kind"), tuple(item.get("requires", [])))
    if authorities != EXPECTED_AUTHORITIES:
        errors.append("authority registry differs from v1 contract")
    authority_ids = set(authorities)
    dangling_gates = {edge[3] for edge in edges if edge[3] is not None} - authority_ids
    if dangling_gates:
        errors.append(f"transition gates do not resolve: {sorted(dangling_gates)}")
    for identifier, (kind, requires) in authorities.items():
        if kind in {"composite", "alternative"} and (
            not requires or set(requires) - authority_ids or identifier in requires
        ):
            errors.append(f"{kind} authority does not resolve: {identifier}")
        if kind == "alternative" and len(set(requires)) < 2:
            errors.append(f"alternative authority needs at least two choices: {identifier}")

    operation_items = model.get("externalOperations", [])
    operations = set()
    operation_states: set[str] = set()
    for item in operation_items:
        has_state = "state" in item
        has_states = "states" in item
        if has_state == has_states:
            errors.append(
                f"external operation must declare exactly one of state or states: {item.get('operation')}"
            )
            continue
        if has_states:
            raw_states = item.get("states")
            if (
                not isinstance(raw_states, list)
                or not raw_states
                or any(not isinstance(state, str) or not state for state in raw_states)
            ):
                errors.append(f"external operation states must be a non-empty list: {item.get('operation')}")
                continue
            normalized_state: str | tuple[str, ...] = tuple(raw_states)
            operation_states.update(raw_states)
        else:
            normalized_state = item.get("state")
            if not isinstance(normalized_state, str) or not normalized_state:
                errors.append(f"external operation state must be a non-empty string: {item.get('operation')}")
                continue
            operation_states.add(normalized_state)
        operations.add((item.get("operation"), normalized_state, item.get("authorizedBy")))
    if len(operations) != len(operation_items):
        errors.append("external operations contain duplicates")
    if operations != EXPECTED_OPERATIONS:
        errors.append("external-operation authorization differs from v1 contract")
    dangling_operation_states = operation_states - states
    if dangling_operation_states:
        errors.append(f"external operations reference unknown states: {sorted(dangling_operation_states)}")
    dangling_operation_authorities = {authority for _, _, authority in operations} - authority_ids
    if dangling_operation_authorities:
        errors.append(f"operation authorities do not resolve: {sorted(dangling_operation_authorities)}")
    if errors:
        for error in errors:
            print(f"State model validation error: {error}")
        raise SystemExit(1)
    print("Workflow state model validation passed")


if __name__ == "__main__":
    main()
