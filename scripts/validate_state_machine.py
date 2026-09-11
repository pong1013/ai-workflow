#!/usr/bin/env python3
"""Validate the complete v1 workflow graph and authorization boundaries."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

EXPECTED_EDGES = {
    ("contract", "contract-established", "workspace", None, True),
    ("workspace", "reuse-clean-workspace", "intake", None, True),
    ("workspace", "approve-workspace-change", "intake", "workspace", False),
    ("intake", "confirm-recommended-grill", "grill", "intake", False),
    ("intake", "confirm-recommended-direct-spec", "specification", "intake", False),
    ("intake", "explicit-start-grill", "grill", "invocation", True),
    ("intake", "explicit-skip-grill", "specification", "invocation", True),
    ("intake", "resume-artifact", "resume", None, True),
    ("resume", "approve-resumed-specification", "ticketing", "resume", False),
    ("resume", "approve-resumed-tickets", "implementation-testing", "resume", False),
    ("resume", "revise-artifact", "specification", None, False),
    ("grill", "decisions-settled", "specification", None, True),
    ("specification", "approve-specification", "ticketing", "specification", False),
    ("ticketing", "tickets-created", "implementation-testing", None, True),
    ("implementation-testing", "workers-joined", "review", None, True),
    ("review", "owned-findings", "implementation-testing", None, True),
    ("review", "verification-and-review-pass", "delivery", None, True),
    ("delivery", "approve-delivery", "complete", "delivery", False),
    ("exception", "decision-received", "$resume", "exception", False),
}
EXPECTED_OPERATIONS = {
    ("persist-project-contract", "contract", "contract-persistence"),
    ("create-feature-branch", "workspace", "workspace"),
    ("write-specification", "specification", "feature-request-and-workspace"),
    ("create-tickets", "ticketing", "specification"),
    ("write-repository", "implementation-testing", "specification"),
    ("stage", "delivery", "delivery"),
    ("commit", "delivery", "delivery"),
    ("push", "delivery", "delivery"),
    ("create-review-request", "delivery", "delivery"),
}
TERMINAL = {"complete", "cancelled", "blocked"}
EXPECTED_AUTHORITIES = {
    "invocation": ("invocation-directive", ()),
    "feature-request": ("invocation-scope", ()),
    "contract-persistence": ("human-gate", ()),
    "workspace": ("human-gate", ()),
    "workspace-established": ("state-evidence", ()),
    "intake": ("human-gate", ()),
    "specification": ("human-gate", ()),
    "resume": ("human-gate", ()),
    "exception": ("human-gate", ()),
    "delivery": ("human-gate", ()),
    "feature-request-and-workspace": (
        "composite",
        ("feature-request", "workspace-established"),
    ),
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    args = parser.parse_args()
    model = json.loads(args.model.read_text(encoding="utf-8"))
    errors: list[str] = []
    states = set(model.get("states", []))
    terminal = set(model.get("terminalStates", []))
    if model.get("initialState") != "contract":
        errors.append("initial state must be contract")
    if terminal != TERMINAL or not terminal <= states:
        errors.append("terminal states must be complete, cancelled, and blocked")

    edges = {
        (item.get("from"), item.get("event"), item.get("to"), item.get("gate"), item.get("automatic"))
        for item in model.get("transitions", [])
    }
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
        if kind == "composite" and (not requires or set(requires) - authority_ids or identifier in requires):
            errors.append(f"composite authority does not resolve: {identifier}")

    operations = {
        (item.get("operation"), item.get("state"), item.get("authorizedBy"))
        for item in model.get("externalOperations", [])
    }
    if operations != EXPECTED_OPERATIONS:
        errors.append("external-operation authorization differs from v1 contract")
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
