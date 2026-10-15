#!/usr/bin/env python3
"""Validate a setup provenance receipt against its repository and live outputs."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import re
from pathlib import Path

from configure_repository import (
    END,
    RECEIPT_PATH,
    RECEIPT_SCHEMA_VERSION,
    START,
    SetupError,
    canonical_json,
    changes_for,
    repository_identity,
    receipt_scope,
    setup_plan_payload,
    sha256_text,
)


class ReceiptError(Exception):
    pass


SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")


def require_mapping(value: object, name: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ReceiptError(f"{name} must be an object")
    return value


def require_string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise ReceiptError(f"{name} must be a non-empty string")
    return value


def receipt_arguments(root: Path, approved_plan: dict[str, object]) -> argparse.Namespace:
    tracker = require_string(approved_plan.get("tracker"), "approvedPlan.tracker")
    domain_layout = require_string(
        approved_plan.get("domainLayout"), "approvedPlan.domainLayout"
    )
    instruction_file = approved_plan.get("instructionFile")
    if tracker not in {"github", "gitlab", "local-markdown"}:
        raise ReceiptError("approvedPlan.tracker is unsupported")
    if domain_layout not in {"single", "multi"}:
        raise ReceiptError("approvedPlan.domainLayout is unsupported")
    if instruction_file not in {None, "AGENTS.md", "CLAUDE.md"}:
        raise ReceiptError("approvedPlan.instructionFile is unsupported")
    return argparse.Namespace(
        repository_root=root,
        tracker=tracker,
        github_repository=approved_plan.get("githubRepository"),
        tracker_repository=approved_plan.get("trackerRepository"),
        remote_name=require_string(
            approved_plan.get("remoteName"), "approvedPlan.remoteName"
        ),
        domain_layout=domain_layout,
        instruction_file=instruction_file,
    )


def extract_managed_block(text: str, path: str) -> str:
    if text.count(START) != 1 or text.count(END) != 1:
        raise ReceiptError(f"{path} does not contain one bounded managed block")
    start = text.index(START)
    end = text.index(END, start) + len(END)
    return text[start:end]


def validate_hunks(mutation: dict[str, object], path: str, current: str) -> None:
    hunks = mutation.get("hunks")
    if not isinstance(hunks, list) or not hunks:
        raise ReceiptError(f"{path} must record at least one changed hunk")
    previous_end = {"before": 0, "after": 0}
    for expected_index, value in enumerate(hunks, start=1):
        hunk = require_mapping(value, f"{path} hunk")
        if hunk.get("index") != expected_index:
            raise ReceiptError(f"{path} hunk sequence is invalid")
        for side in ("before", "after"):
            record = require_mapping(hunk.get(side), f"{path} hunk {side}")
            if not isinstance(record.get("startLine"), int) or record["startLine"] < 1:
                raise ReceiptError(f"{path} hunk {side} startLine is invalid")
            if not isinstance(record.get("lineCount"), int) or record["lineCount"] < 0:
                raise ReceiptError(f"{path} hunk {side} lineCount is invalid")
            start = record["startLine"] - 1
            end = start + record["lineCount"]
            if start < previous_end[side]:
                raise ReceiptError(f"{path} hunk {side} ranges overlap or are out of order")
            previous_end[side] = end
            digest = require_string(record.get("hash"), f"{path} hunk {side} hash")
            if not SHA256.fullmatch(digest):
                raise ReceiptError(f"{path} hunk {side} hash is invalid")
            if side == "after":
                lines = current.splitlines(keepends=True)
                if end > len(lines) or not hmac.compare_digest(
                    sha256_text("".join(lines[start:end])), digest
                ):
                    raise ReceiptError(f"{path} hunk after hash drift")


def validate_receipt(root: Path, receipt_path: Path, expected_plan_token: str | None) -> int:
    try:
        receipt = require_mapping(json.loads(receipt_path.read_text(encoding="utf-8")), "receipt")
    except (OSError, json.JSONDecodeError) as error:
        raise ReceiptError(f"cannot read receipt: {error}") from error
    if receipt.get("schemaVersion") != RECEIPT_SCHEMA_VERSION:
        raise ReceiptError("unsupported schemaVersion")
    if receipt.get("approvalAuthority") is not False:
        raise ReceiptError("receipt must explicitly declare approvalAuthority false")
    supplied_checksum = require_string(receipt.pop("checksum", None), "checksum")
    expected_checksum = sha256_text(canonical_json(receipt))
    if not hmac.compare_digest(supplied_checksum, expected_checksum):
        raise ReceiptError("receipt checksum mismatch")

    approved_plan = require_mapping(receipt.get("approvedPlan"), "approvedPlan")
    plan_token = require_string(approved_plan.get("token"), "approvedPlan.token")
    if not SHA256.fullmatch(plan_token):
        raise ReceiptError("approvedPlan.token is invalid")
    if receipt.get("planToken") != plan_token:
        raise ReceiptError("top-level planToken does not match approvedPlan.token")
    if expected_plan_token and not hmac.compare_digest(plan_token, expected_plan_token):
        raise ReceiptError("receipt does not match the expected approved plan token")
    args = receipt_arguments(root, approved_plan)
    try:
        expected_changes, remote_urls = changes_for(args)
    except (OSError, SetupError, ValueError) as error:
        raise ReceiptError(f"cannot render approved setup plan: {error}") from error
    if receipt.get("repository") != repository_identity(args, remote_urls):
        raise ReceiptError("repository identity drift")

    mutations = receipt.get("mutations")
    if not isinstance(mutations, list) or not mutations:
        raise ReceiptError("receipt must contain at least one mutation")
    expected_paths = {path.relative_to(root).as_posix() for path in expected_changes}
    live_contents: dict[Path, str] = {}
    for target, rendered in expected_changes.items():
        relative = target.relative_to(root)
        relative_value = relative.as_posix()
        try:
            current = target.read_text(encoding="utf-8")
        except OSError as error:
            raise ReceiptError(f"cannot read {relative_value}: {error}") from error
        scope = receipt_scope(relative)
        if scope in {"complete-file", "ignore-rule"}:
            equivalent = current == rendered
        else:
            equivalent = extract_managed_block(current, relative_value) == extract_managed_block(
                rendered, relative_value
            )
        if not equivalent:
            raise ReceiptError(f"render-equivalence failed: {relative_value}")
        live_contents[target] = current

    paths: set[str] = set()
    before: dict[Path, str] = {}
    existed: dict[Path, bool] = {}
    mutation_by_path: dict[str, dict[str, object]] = {}
    for value in mutations:
        mutation = require_mapping(value, "mutation")
        relative_value = require_string(mutation.get("path"), "mutation.path")
        relative = Path(relative_value)
        if relative.is_absolute() or ".." in relative.parts or relative.as_posix() in paths:
            raise ReceiptError(f"invalid or duplicate mutation path: {relative_value}")
        paths.add(relative.as_posix())
        target = root / relative
        if target not in expected_changes:
            raise ReceiptError(f"path is not in the approved setup plan: {relative_value}")
        if mutation.get("provenance") != "setup/configuration":
            raise ReceiptError(f"{relative_value} has invalid provenance")
        scope = mutation.get("scope")
        if scope != receipt_scope(relative):
            raise ReceiptError(f"{relative_value} has incorrect render scope")
        existed_value = mutation.get("existed")
        if not isinstance(existed_value, bool):
            raise ReceiptError(f"{relative_value} has invalid existed value")
        before_hash = require_string(mutation.get("beforeHash"), f"{relative_value} beforeHash")
        after_hash = require_string(mutation.get("afterHash"), f"{relative_value} afterHash")
        for digest in (before_hash, after_hash):
            if not SHA256.fullmatch(digest):
                raise ReceiptError(f"{relative_value} has an invalid content hash")
        if hmac.compare_digest(before_hash, after_hash):
            raise ReceiptError(f"{relative_value} does not describe a mutation")
        current = live_contents[target]
        validate_hunks(mutation, relative_value, current)
        if not hmac.compare_digest(sha256_text(current), after_hash):
            raise ReceiptError(f"live content drift: {relative_value}")
        before[target] = ""
        existed[target] = existed_value
        mutation_by_path[relative_value] = mutation

    if not paths.issubset(expected_paths):
        raise ReceiptError("receipt mutation path set drift")

    for target, current in live_contents.items():
        relative_value = target.relative_to(root).as_posix()
        if relative_value not in mutation_by_path:
            before[target] = current
            existed[target] = True

    plan_payload = setup_plan_payload(args, expected_changes, before, existed, remote_urls)
    for file_record in plan_payload["files"]:
        mutation = mutation_by_path.get(file_record["path"])
        if mutation is not None:
            file_record["before"] = mutation["beforeHash"].removeprefix("sha256:")
    recomputed_token = "sha256:" + hashlib.sha256(
        canonical_json(plan_payload).encode("utf-8")
    ).hexdigest()
    if not hmac.compare_digest(plan_token, recomputed_token):
        raise ReceiptError("approved plan binding mismatch")
    return len(mutations)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("repository", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--plan-token")
    args = parser.parse_args()
    root = args.repository.resolve()
    receipt_path = args.receipt or root / RECEIPT_PATH
    if not receipt_path.is_absolute():
        receipt_path = root / receipt_path
    try:
        count = validate_receipt(root, receipt_path, args.plan_token)
    except (ReceiptError, OSError, ValueError) as error:
        print(f"Setup receipt validation error: {error}")
        raise SystemExit(1) from error
    print(f"Setup receipt validation passed ({count} mutation(s))")


if __name__ == "__main__":
    main()
