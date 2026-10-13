#!/usr/bin/env python3
"""Validate the complete workflow graph, reconciliation, and authorization boundaries."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

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
    ("ticket-commit", "ticket-committed-all-done", "configuration-reconciliation", None, True),
    ("configuration-reconciliation", "owned-findings", "ticket-work", None, True),
    (
        "configuration-reconciliation",
        "configuration-reconciled",
        "feature-review",
        "configuration-reconciled",
        True,
    ),
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
            "configuration-reconciliation",
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
    ("create-deferred-configuration-follow-up", "exception", "exception"),
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
    "configuration-reconciliation",
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
    "configuration-reconciled": ("state-evidence", ()),
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
EXPECTED_ROUND_LEDGER_POLICY = {
    "ordered": True,
    "scopes": ["ticket", "feature"],
    "roundRequiredFields": [
        "sequence",
        "roundNumber",
        "scope",
        "ticket",
        "implementationChanges",
        "checks",
        "standardsReview",
        "specReview",
        "nextAction",
    ],
    "checkRequiredFields": ["command", "outcome"],
    "outcomes": ["pass", "fail", "not-applicable"],
    "notApplicableRequiresReason": True,
    "preserveFailedRounds": True,
    "reportSurfaces": ["checkpoint", "stopped-run", "delivery-gate", "final"],
}
EXPECTED_WORKSPACE_BASELINE_POLICY = {
    "granularity": "path-hunk-hash",
    "requiredFields": ["path", "hunk", "contentHash"],
}
EXPECTED_MUTATION_LEDGER_POLICY = {
    "appendOnly": True,
    "eventRequiredFields": [
        "sequence",
        "stage",
        "ticket",
        "provenance",
        "path",
        "hunk",
        "beforeHash",
        "afterHash",
    ],
    "provenanceCategories": [
        "ticket-owned",
        "setup/configuration",
        "project knowledge",
        "pre-existing unrelated",
    ],
    "hashChain": {"beforeMatchesPreviousAfter": True},
    "currentView": {
        "derivedFromLedger": True,
        "validateAgainstLiveDiff": True,
    },
    "receiptImport": {
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
    },
}
EXPECTED_RECONCILIATION_POLICY = {
    "state": "configuration-reconciliation",
    "setupRouting": {
        "mechanical": "first-blocker-ticket",
        "semanticOrScopeOrContractConflict": "exception",
    },
    "projectKnowledge": "approved-ticket-or-explicit-alternative",
    "legacyCheckpointWithoutEvidence": "unverified",
    "blocksOn": [
        "invalid-provenance",
        "broken-hash-chain",
        "missing-event",
        "changed-baseline-hunk",
        "unexplained-mutation",
    ],
}
EXPECTED_INTERACTION_POLICY = {
    "workflowReply": {
        "requiredFields": ["stage", "progress", "pendingDecisionOrBlocker", "nextStep"],
        "nameActiveGate": True,
        "reportActualStateBeforeTransition": True,
    },
    "grill": {
        "maxConsequentialQuestionsPerReply": 1,
        "showQuestionNumber": True,
        "showPrerequisite": True,
        "showKnownQueuedDecisions": True,
        "recomputeAfterEachAnswer": True,
        "includeDomainModelingQuestions": True,
    },
}

EXPECTED_DELIVERY_POLICY = {
    "requiresReconciliation": True,
    "pendingChanges": "clean-or-exact-unchanged-baseline-unrelated",
    "residualDisclosure": "path-hunk-hash-in-existing-delivery-gate",
    "residualApproval": "delivery",
    "baselineDriftRoute": "configuration-reconciliation-or-exception",
    "deferredFollowUp": {
        "authority": "exception",
        "artifact": "standalone-github-issue",
        "inParentChildGraph": False,
        "automaticPostMergeBranch": False,
        "laterRun": "origin-pr-merged-and-new-workspace-gate",
    },
}

SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")
HUNK_HEADER = re.compile(
    rb"^@@ -(?:\d+)(?:,(?:\d+))? \+(?:\d+)(?:,(?:\d+))? @@"
)
SURFACE_ORDER = ("committed", "staged", "unstaged")


class ReconciliationError(Exception):
    """A concrete Feature Run reconciliation instance is invalid."""


def sha256_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def git(root: Path, *arguments: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ReconciliationError(f"git {' '.join(arguments)} failed: {detail}")
    return result.stdout


def nul_paths(value: bytes) -> set[str]:
    return {
        item.decode("utf-8", errors="surrogateescape")
        for item in value.split(b"\0")
        if item
    }


def repository_file_bytes(root: Path, relative: str) -> bytes:
    target = root / relative
    try:
        target.lstat()
    except FileNotFoundError:
        return b""
    if target.is_symlink():
        return os.readlink(target).encode("utf-8", errors="surrogateescape")
    if not target.is_file():
        raise ReconciliationError(f"unsupported non-file worktree entry: {relative}")
    return target.read_bytes()


def commit_file_bytes(root: Path, commit: str, relative: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{commit}:{relative}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        return b""
    return result.stdout


def path_surfaces(root: Path, base_commit: str) -> dict[str, set[str]]:
    surfaces: dict[str, set[str]] = {}
    commands = {
        "committed": ("diff", "--name-only", "-z", "--no-renames", base_commit, "HEAD", "--"),
        "staged": ("diff", "--cached", "--name-only", "-z", "--no-renames", "HEAD", "--"),
        "unstaged": ("diff", "--name-only", "-z", "--no-renames", "--"),
    }
    for surface, command in commands.items():
        for relative in nul_paths(git(root, *command)):
            surfaces.setdefault(relative, set()).add(surface)
    for relative in nul_paths(git(root, "ls-files", "--others", "--exclude-standard", "-z")):
        surfaces.setdefault(relative, set()).add("untracked")
    return surfaces


def patch_records(value: bytes) -> list[bytes]:
    # Git separates patch records with LF; a bare CR belongs to source content.
    records = value.split(b"\n")
    return [record + b"\n" for record in records[:-1]] + (
        [records[-1]] if records[-1] else []
    )


def hunk_sides(body: bytes) -> tuple[bytes, bytes]:
    before = bytearray()
    after = bytearray()
    previous_prefix = b""
    for line in patch_records(body):
        if line.startswith(b"\\ No newline at end of file"):
            # Git adds a patch-record LF even when the source line has none.
            # The marker applies only to the immediately preceding side(s).
            if previous_prefix in {b" ", b"-"} and before.endswith(b"\n"):
                del before[-1:]
            if previous_prefix in {b" ", b"+"} and after.endswith(b"\n"):
                del after[-1:]
            previous_prefix = b""
            continue
        previous_prefix = line[:1]
        if line.startswith(b" "):
            before.extend(line[1:])
            after.extend(line[1:])
        elif line.startswith(b"-"):
            before.extend(line[1:])
        elif line.startswith(b"+"):
            after.extend(line[1:])
    return bytes(before), bytes(after)


def text_hunks(patch: bytes) -> list[tuple[str, bytes, bytes, bytes]]:
    lines = patch_records(patch)
    results: list[tuple[str, bytes, bytes, bytes]] = []
    index = 0
    occurrence: dict[str, int] = {}
    while index < len(lines):
        match = HUNK_HEADER.match(lines[index])
        if not match:
            index += 1
            continue
        header = lines[index].decode("utf-8", errors="replace").rstrip("\r\n")
        index += 1
        body_start = index
        while index < len(lines) and not HUNK_HEADER.match(lines[index]):
            index += 1
        body = b"".join(lines[body_start:index])
        occurrence[header] = occurrence.get(header, 0) + 1
        identifier = header
        if occurrence[header] > 1:
            identifier = f"{header} #{occurrence[header]}"
        before, after = hunk_sides(body)
        results.append((identifier, body, before, after))
    return results


def origin_fields(origins: set[str]) -> dict[str, Any]:
    ordered = [name for name in (*SURFACE_ORDER, "untracked") if name in origins]
    if len(ordered) == 1:
        return {"surface": ordered[0]}
    return {"surface": "mixed", "origins": ordered}


def git_file_modes(root: Path, base_commit: str) -> dict[str, tuple[bytes, bytes]]:
    records = git(root, "diff", "--raw", "-z", "--no-renames", base_commit, "--").split(b"\0")
    modes: dict[str, tuple[bytes, bytes]] = {}
    for index in range(0, len(records) - 1, 2):
        fields = records[index].split()
        relative = records[index + 1].decode("utf-8", errors="surrogateescape")
        modes[relative] = (fields[0][1:], fields[1])
    return modes


def whole_file_content_hash(mode: bytes, content: bytes) -> str:
    return sha256_bytes(b"git-mode\0" + mode + b"\0" + content)


def file_mode_entry(relative: str, before: bytes, after: bytes) -> dict[str, Any]:
    return {
        "path": relative,
        "hunk": "file-mode",
        "contentHash": sha256_bytes(before + b"\0" + after),
        "beforeHash": sha256_bytes(before),
        "afterHash": sha256_bytes(after),
    }


def emit_reconciliation_view(root: Path, base_commit: str) -> dict[str, Any]:
    root = root.resolve()
    actual_root = Path(
        git(root, "rev-parse", "--show-toplevel").decode().strip()
    ).resolve()
    if actual_root != root:
        raise ReconciliationError(
            f"repository root mismatch: expected {root}, found {actual_root}"
        )
    resolved_base = (
        git(root, "rev-parse", "--verify", f"{base_commit}^{{commit}}").decode().strip()
    )
    git(root, "merge-base", "--is-ancestor", resolved_base, "HEAD")
    surfaces = path_surfaces(root, resolved_base)
    tracked_modes = git_file_modes(root, resolved_base)
    entries: list[dict[str, Any]] = []
    for relative in sorted(tracked_modes):
        before_mode, after_mode = tracked_modes[relative]
        patch = git(
            root,
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "--no-renames",
            "--binary",
            "--unified=0",
            resolved_base,
            "--",
            relative,
        )
        hunks = text_hunks(patch)
        if hunks and b"GIT binary patch" not in patch and b"Binary files " not in patch:
            for identifier, body, before, after in hunks:
                entry = {
                    "path": relative,
                    "hunk": identifier,
                    "contentHash": sha256_bytes(body),
                    "beforeHash": sha256_bytes(before),
                    "afterHash": sha256_bytes(after),
                }
                entry.update(origin_fields(surfaces.get(relative, set())))
                entries.append(entry)
        else:
            before = commit_file_bytes(root, resolved_base, relative)
            after = repository_file_bytes(root, relative)
            entry = {
                "path": relative,
                "hunk": "whole-file",
                "contentHash": whole_file_content_hash(after_mode, after),
                "beforeHash": sha256_bytes(before),
                "afterHash": sha256_bytes(after),
            }
            entry.update(origin_fields(surfaces.get(relative, set())))
            entries.append(entry)
        if before_mode != after_mode:
            entry = file_mode_entry(relative, before_mode, after_mode)
            entry.update(origin_fields(surfaces.get(relative, set())))
            entries.append(entry)
    for relative in sorted(path for path, kinds in surfaces.items() if "untracked" in kinds):
        after = repository_file_bytes(root, relative)
        target = root / relative
        after_mode = (
            b"120000" if target.is_symlink()
            else b"100755" if target.stat().st_mode & 0o111
            else b"100644"
        )
        entries.append(
            {
                "path": relative,
                "hunk": "whole-file",
                "contentHash": whole_file_content_hash(after_mode, after),
                "beforeHash": sha256_bytes(b""),
                "afterHash": sha256_bytes(after),
                "surface": "untracked",
            }
        )
        if after_mode != b"100644":
            entry = file_mode_entry(relative, b"100644", after_mode)
            entry.update(origin_fields({"untracked"}))
            entries.append(entry)
    entries.sort(key=lambda item: (item["path"], item["hunk"]))
    return {"baseCommit": resolved_base, "entries": entries}


def require_mapping(value: object, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ReconciliationError(f"{name} must be an object")
    return value


def require_list(value: object, name: str) -> list[Any]:
    if not isinstance(value, list):
        raise ReconciliationError(f"{name} must be an array")
    return value


def require_string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise ReconciliationError(f"{name} must be a non-empty string")
    return value


def require_hash(value: object, name: str) -> str:
    digest = require_string(value, name)
    if not SHA256.fullmatch(digest):
        raise ReconciliationError(f"{name} must be a sha256 digest")
    return digest


def reconciliation_entry(value: object, name: str) -> dict[str, Any]:
    entry = require_mapping(value, name)
    require_string(entry.get("path"), f"{name}.path")
    require_string(entry.get("hunk"), f"{name}.hunk")
    require_hash(entry.get("contentHash"), f"{name}.contentHash")
    if "beforeHash" in entry:
        require_hash(entry.get("beforeHash"), f"{name}.beforeHash")
    if "afterHash" in entry:
        require_hash(entry.get("afterHash"), f"{name}.afterHash")
    return entry


def entry_key(entry: dict[str, Any]) -> tuple[str, str]:
    return (entry["path"], entry["hunk"])


def validate_reconciliation_instance(root: Path, instance_path: Path) -> None:
    try:
        instance = require_mapping(
            json.loads(instance_path.read_text(encoding="utf-8")), "reconciliation"
        )
    except (OSError, json.JSONDecodeError) as error:
        raise ReconciliationError(f"cannot read reconciliation instance: {error}") from error
    baseline = require_mapping(instance.get("workspaceBaseline"), "workspaceBaseline")
    base_commit = require_string(baseline.get("baseCommit"), "workspaceBaseline.baseCommit")
    live = emit_reconciliation_view(root, base_commit)
    resolved_instance_base = (
        git(root, "rev-parse", "--verify", f"{base_commit}^{{commit}}").decode().strip()
    )
    if live["baseCommit"] != resolved_instance_base:
        raise ReconciliationError("workspace baseline commit does not resolve consistently")

    baseline_entries: dict[tuple[str, str], dict[str, Any]] = {}
    baseline_values = require_list(baseline.get("entries"), "workspaceBaseline.entries")
    for index, value in enumerate(baseline_values):
        entry = reconciliation_entry(value, f"workspaceBaseline.entries[{index}]")
        key = entry_key(entry)
        if key in baseline_entries:
            raise ReconciliationError(f"duplicate workspace baseline entry: {key}")
        baseline_entries[key] = entry

    live_entries: dict[tuple[str, str], dict[str, Any]] = {}
    for value in live["entries"]:
        key = entry_key(value)
        if key in live_entries:
            raise ReconciliationError(f"duplicate live current-view entry: {key}")
        live_entries[key] = value

    events = require_list(instance.get("mutationLedger"), "mutationLedger")
    event_by_sequence: dict[int, dict[str, Any]] = {}
    chains: dict[tuple[str, str], list[dict[str, Any]]] = {}
    required_fields = set(EXPECTED_MUTATION_LEDGER_POLICY["eventRequiredFields"])
    categories = set(EXPECTED_MUTATION_LEDGER_POLICY["provenanceCategories"])
    for index, value in enumerate(events, start=1):
        event = require_mapping(value, f"mutationLedger[{index - 1}]")
        missing = required_fields - set(event)
        if missing:
            raise ReconciliationError(
                f"mutation event {index} is missing fields: {sorted(missing)}"
            )
        if event.get("sequence") != index:
            raise ReconciliationError(
                "mutation ledger sequence must be contiguous, ordered, and start at 1"
            )
        if event.get("provenance") not in categories:
            raise ReconciliationError(f"mutation event {index} has invalid provenance")
        stage = require_string(event.get("stage"), f"mutationLedger[{index - 1}].stage")
        if stage not in EXPECTED_STATES:
            raise ReconciliationError(f"mutation event {index} references an unknown stage")
        ticket = event.get("ticket")
        if ticket is not None and (not isinstance(ticket, str) or not ticket):
            raise ReconciliationError(f"mutation event {index} has an invalid ticket")
        require_string(event.get("path"), f"mutationLedger[{index - 1}].path")
        require_string(event.get("hunk"), f"mutationLedger[{index - 1}].hunk")
        require_hash(event.get("beforeHash"), f"mutationLedger[{index - 1}].beforeHash")
        require_hash(event.get("afterHash"), f"mutationLedger[{index - 1}].afterHash")
        event_by_sequence[index] = event
        chains.setdefault(entry_key(event), []).append(event)

    alternatives = require_list(instance.get("approvedAlternatives", []), "approvedAlternatives")
    alternative_sequences: set[int] = set()
    for index, value in enumerate(alternatives):
        alternative = require_mapping(value, f"approvedAlternatives[{index}]")
        sequence = alternative.get("eventSequence")
        if not isinstance(sequence, int) or sequence not in event_by_sequence:
            raise ReconciliationError(f"approved alternative {index} references an unknown event")
        if sequence in alternative_sequences:
            raise ReconciliationError(f"duplicate approved alternative event: {sequence}")
        if alternative.get("authority") != "exception":
            raise ReconciliationError("approved alternative requires Exception authority")
        require_string(
            alternative.get("approvalReference"),
            f"approvedAlternatives[{index}].approvalReference",
        )
        event = event_by_sequence[sequence]
        if event["provenance"] not in {"setup/configuration", "project knowledge"}:
            raise ReconciliationError(
                "approved alternative applies only to setup/configuration or project knowledge"
            )
        if event["ticket"] is not None:
            raise ReconciliationError("approved alternative is only needed when ticket is null")
        alternative_sequences.add(sequence)

    for event in events:
        provenance = event["provenance"]
        sequence = event["sequence"]
        if provenance == "ticket-owned" and event["ticket"] is None:
            raise ReconciliationError("ticket-owned mutation requires an approved ticket")
        if (
            provenance in {"setup/configuration", "project knowledge"}
            and event["ticket"] is None
            and sequence not in alternative_sequences
        ):
            raise ReconciliationError(
                f"{provenance} mutation requires a ticket or approved Exception alternative"
            )
        if provenance == "pre-existing unrelated":
            key = entry_key(event)
            baseline_entry = baseline_entries.get(key)
            live_entry = live_entries.get(key)
            if event["ticket"] is not None:
                raise ReconciliationError("pre-existing unrelated mutation cannot claim a ticket")
            if (
                baseline_entry is None
                or live_entry is None
                or baseline_entry["contentHash"] != live_entry["contentHash"]
                or event["beforeHash"] != live_entry["afterHash"]
                or event["afterHash"] != live_entry["afterHash"]
            ):
                raise ReconciliationError(
                    "pre-existing unrelated provenance must bind an unchanged baseline hunk"
                )

    imports = require_list(instance.get("setupReceiptImports"), "setupReceiptImports")
    imported_sequences: set[int] = set()
    for index, value in enumerate(imports):
        receipt = require_mapping(value, f"setupReceiptImports[{index}]")
        sequence = receipt.get("eventSequence")
        if not isinstance(sequence, int) or sequence not in event_by_sequence:
            raise ReconciliationError(f"setup receipt import {index} references an unknown event")
        if sequence in imported_sequences:
            raise ReconciliationError(f"duplicate setup receipt import event: {sequence}")
        imported_sequences.add(sequence)
        if receipt.get("evidenceOnly") is not True:
            raise ReconciliationError("setup receipt import must be evidence-only")
        if receipt.get("approvalAuthority") is not False:
            raise ReconciliationError("setup receipt import cannot grant approval authority")
        receipt_path_value = require_string(
            receipt.get("receiptPath"), f"setupReceiptImports[{index}].receiptPath"
        )
        receipt_path = Path(receipt_path_value)
        if (
            receipt_path.is_absolute()
            or ".." in receipt_path.parts
            or receipt_path.parts[:2] != (".agents", "setup")
        ):
            raise ReconciliationError(
                "setup receipt import must reference a repository-local .agents/setup path"
            )
        setup_root = (root.resolve() / ".agents" / "setup").resolve()
        target = (root.resolve() / receipt_path).resolve()
        if setup_root not in target.parents or not target.is_file():
            raise ReconciliationError("setup receipt import references a missing or unsafe file")
        receipt_checksum = require_hash(
            receipt.get("receiptChecksum"),
            f"setupReceiptImports[{index}].receiptChecksum",
        )
        if receipt_checksum != sha256_bytes(target.read_bytes()):
            raise ReconciliationError("setup receipt reference checksum drift")
        terminal_hash = require_hash(
            receipt.get("terminalHash"), f"setupReceiptImports[{index}].terminalHash"
        )
        event = event_by_sequence[sequence]
        if event["provenance"] != "setup/configuration":
            raise ReconciliationError("setup receipt import must bind a setup/configuration event")
        if terminal_hash != event["afterHash"]:
            raise ReconciliationError(
                "setup receipt terminal hash does not bind the imported event"
            )

    setup_sequences = {
        event["sequence"]
        for event in events
        if event["provenance"] == "setup/configuration"
    }
    if setup_sequences != imported_sequences:
        raise ReconciliationError("every setup/configuration event requires one receipt import")

    for key, chain in chains.items():
        live_entry = live_entries.get(key)
        baseline_entry = baseline_entries.get(key)
        if live_entry is None:
            raise ReconciliationError(f"mutation chain has no live current-view hunk: {key}")
        expected_initial = (
            baseline_entry.get("afterHash", baseline_entry["contentHash"])
            if baseline_entry is not None
            else live_entry["beforeHash"]
        )
        anchored = chain[0]["beforeHash"] == expected_initial
        if baseline_entry is not None and not anchored:
            # Imported setup can predate capture: bind its terminal state to the
            # baseline, then continue any later events without replaying setup.
            for event in chain:
                if event["sequence"] not in imported_sequences:
                    break
                if event["afterHash"] == expected_initial:
                    anchored = True
                    break
        if not anchored:
            raise ReconciliationError(
                f"mutation chain is not anchored at the Feature Run baseline: {key}"
            )
        for previous, current in zip(chain, chain[1:]):
            if previous["afterHash"] != current["beforeHash"]:
                raise ReconciliationError(f"broken mutation hash chain: {key}")
        if chain[-1]["afterHash"] != live_entry["afterHash"]:
            raise ReconciliationError(
                f"mutation terminal hash does not match live current view: {key}"
            )

    for key, baseline_entry in baseline_entries.items():
        live_entry = live_entries.get(key)
        if live_entry is None:
            raise ReconciliationError(f"baseline hunk is missing or changed: {key}")
        if key not in chains and baseline_entry["contentHash"] != live_entry["contentHash"]:
            raise ReconciliationError(f"unchanged baseline hunk drifted: {key}")

    for key in live_entries:
        if key not in baseline_entries and key not in chains:
            raise ReconciliationError(f"unexplained live hunk has no mutation event: {key}")


def pending_diff_hashes(root: Path) -> dict[str, str]:
    """Bind index and worktree separately, including cancelling staged changes."""
    if git(root, "ls-files", "--unmerged", "-z"):
        raise ReconciliationError("Delivery requires a resolved index without merge conflicts")
    common = ("--no-ext-diff", "--no-textconv", "--no-renames", "--binary", "--unified=0")
    untracked = bytearray()
    for path in sorted(nul_paths(git(root, "ls-files", "--others", "--exclude-standard", "-z"))):
        target = root / path
        mode = b"120000" if target.is_symlink() else (
            b"100755" if target.stat().st_mode & 0o111 else b"100644"
        )
        content = repository_file_bytes(root, path)
        untracked.extend(path.encode("utf-8", errors="surrogateescape") + b"\0" + mode + b"\0")
        untracked.extend(str(len(content)).encode() + b"\0" + content)
    return {
        "staged": sha256_bytes(git(root, "diff", "--cached", *common, "HEAD", "--")),
        "unstaged": sha256_bytes(git(root, "diff", *common, "--")),
        "untracked": sha256_bytes(bytes(untracked)),
    }


def emit_delivery_view(root: Path) -> dict[str, Any]:
    view = emit_reconciliation_view(root, "HEAD")
    view["pendingDiffHashes"] = pending_diff_hashes(root)
    return view


def validate_delivery_instance(root: Path, instance_path: Path) -> None:
    # A caller's cached success flag never replaces live reconciliation.
    validate_reconciliation_instance(root, instance_path)
    instance = json.loads(instance_path.read_text(encoding="utf-8"))
    delivery = require_mapping(instance.get("delivery"), "delivery")
    if delivery.get("configurationReconciled") is not True:
        raise ReconciliationError("Delivery requires successful configuration reconciliation")
    baseline = instance["workspaceBaseline"]
    baseline_entries = {entry_key(item): item for item in baseline["entries"]}
    pending = emit_delivery_view(root)
    disclosure = require_list(delivery.get("residualBaselineEntries"), "delivery.residualBaselineEntries")
    disclosed: dict[tuple[str, str], dict[str, Any]] = {}
    for index, value in enumerate(disclosure):
        entry = reconciliation_entry(value, f"delivery.residualBaselineEntries[{index}]")
        if entry_key(entry) in disclosed:
            raise ReconciliationError("duplicate Delivery residual disclosure")
        disclosed[entry_key(entry)] = entry
    pending_entries = {entry_key(item): item for item in pending["entries"]}
    if set(disclosed) != set(pending_entries):
        raise ReconciliationError("Delivery residual disclosure must match every pending hunk")
    for key, entry in pending_entries.items():
        original = baseline_entries.get(key)
        if original is None or original["contentHash"] != entry["contentHash"]:
            raise ReconciliationError("Delivery pending mutation is not unchanged baseline unrelated work")
        if disclosed[key]["contentHash"] != entry["contentHash"]:
            raise ReconciliationError("Delivery residual disclosure hash drift")
        if any(entry_key(event) == key and event["provenance"] != "pre-existing unrelated"
               for event in instance["mutationLedger"]):
            raise ReconciliationError("Delivery residual mutation has run-owned provenance")
    empty_hash = sha256_bytes(b"")
    dirty = any(value != empty_hash for value in pending["pendingDiffHashes"].values())
    if dirty:
        original_hashes = require_mapping(baseline.get("pendingDiffHashes"), "workspaceBaseline.pendingDiffHashes")
        if original_hashes != pending["pendingDiffHashes"]:
            raise ReconciliationError("Delivery index/worktree surfaces changed from baseline")
        if not pending_entries:
            raise ReconciliationError("Delivery has cancelling staged/unstaged mutations without baseline hunks")


def validate_deferred_follow_up(instance_path: Path) -> None:
    try:
        follow_up = require_mapping(json.loads(instance_path.read_text(encoding="utf-8")), "deferredFollowUp")
    except (OSError, json.JSONDecodeError) as error:
        raise ReconciliationError(f"cannot read deferred follow-up: {error}") from error
    for field, expected in {
        "state": "exception", "authority": "exception",
        "artifact": "standalone-github-issue", "inParentChildGraph": False,
        "automaticPostMergeBranch": False,
        "laterRun": "origin-pr-merged-and-new-workspace-gate",
    }.items():
        if follow_up.get(field) != expected or (
            isinstance(expected, bool) and follow_up.get(field) is not expected
        ):
            raise ReconciliationError(f"deferred follow-up has invalid {field}")
    for field in ("approvalReference", "originatingFeature", "reason"):
        require_string(follow_up.get(field), f"deferredFollowUp.{field}")
    mutations = require_list(follow_up.get("mutations"), "deferredFollowUp.mutations")
    if not mutations:
        raise ReconciliationError("deferred follow-up requires exact mutation evidence")
    keys: set[tuple[str, str]] = set()
    for index, value in enumerate(mutations):
        entry = reconciliation_entry(value, f"deferredFollowUp.mutations[{index}]")
        if entry.get("provenance") not in {"setup/configuration", "project knowledge"}:
            raise ReconciliationError("deferred follow-up requires configuration provenance")
        if entry_key(entry) in keys:
            raise ReconciliationError("duplicate deferred follow-up mutation")
        keys.add(entry_key(entry))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("--repository-root", type=Path)
    parser.add_argument("--baseline")
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--emit-reconciliation-view", action="store_true")
    actions.add_argument("--reconciliation", type=Path)
    actions.add_argument("--emit-delivery-view", action="store_true")
    actions.add_argument("--delivery", type=Path)
    actions.add_argument("--deferred-follow-up", type=Path)
    args = parser.parse_args()
    model = json.loads(args.model.read_text(encoding="utf-8"))
    errors: list[str] = []
    raw_states = model.get("states", [])
    states = set(raw_states)
    terminal = set(model.get("terminalStates", []))
    if model.get("version") != 3:
        errors.append("state model version must be 3")
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
    if model.get("roundLedgerPolicy") != EXPECTED_ROUND_LEDGER_POLICY:
        errors.append("round ledger policy differs from the workflow contract")
    if model.get("workspaceBaselinePolicy") != EXPECTED_WORKSPACE_BASELINE_POLICY:
        errors.append("workspace baseline policy differs from the workflow contract")
    if model.get("mutationLedgerPolicy") != EXPECTED_MUTATION_LEDGER_POLICY:
        errors.append("mutation ledger policy differs from the workflow contract")
    if model.get("reconciliationPolicy") != EXPECTED_RECONCILIATION_POLICY:
        errors.append("reconciliation policy differs from the workflow contract")
    if model.get("interactionPolicy") != EXPECTED_INTERACTION_POLICY:
        errors.append("interaction policy differs from the workflow contract")
    if model.get("deliveryPolicy") != EXPECTED_DELIVERY_POLICY:
        errors.append("delivery policy differs from the workflow contract")

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
    try:
        if args.deferred_follow_up is not None:
            if args.repository_root is not None or args.baseline is not None:
                parser.error("--deferred-follow-up validates a publication draft without repository options")
            validate_deferred_follow_up(args.deferred_follow_up)
            print("Deferred configuration follow-up structure validation passed; approval must be resolved by controller")
            return
        if args.emit_reconciliation_view:
            if args.repository_root is None or args.baseline is None:
                parser.error(
                    "--emit-reconciliation-view requires --repository-root and --baseline"
                )
            print(
                json.dumps(
                    emit_reconciliation_view(args.repository_root, args.baseline),
                    indent=2,
                    sort_keys=True,
                )
            )
            return
        if args.emit_delivery_view:
            if args.repository_root is None or args.baseline is not None:
                parser.error("--emit-delivery-view requires --repository-root and uses HEAD")
            print(json.dumps(emit_delivery_view(args.repository_root), indent=2, sort_keys=True))
            return
        if args.delivery is not None:
            if args.repository_root is None or args.baseline is not None:
                parser.error("--delivery requires --repository-root; baseline comes from instance")
            validate_delivery_instance(args.repository_root, args.delivery)
            print("Feature Run reconciled Delivery validation passed")
            return
        if args.reconciliation is not None:
            if args.repository_root is None:
                parser.error("--reconciliation requires --repository-root")
            if args.baseline is not None:
                parser.error("--baseline is read from the reconciliation instance")
            validate_reconciliation_instance(args.repository_root, args.reconciliation)
            print("Feature Run configuration reconciliation passed")
            return
        if args.repository_root is not None or args.baseline is not None:
            parser.error(
                "--repository-root/--baseline require --emit-reconciliation-view or --reconciliation"
            )
    except ReconciliationError as error:
        print(f"Configuration reconciliation error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print("Workflow state model validation passed")


if __name__ == "__main__":
    main()
