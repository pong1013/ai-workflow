#!/usr/bin/env python3
"""Validate installable Skill frontmatter and Codex agent metadata."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import yaml

FRONTMATTER_KEYS = {"name", "description", "license", "allowed-tools", "metadata"}
OPENAI_KEYS = {"interface", "dependencies", "policy"}
INTERFACE_KEYS = {
    "display_name", "short_description", "icon_small", "icon_large",
    "brand_color", "default_prompt",
}
POLICY_KEYS = {"allow_implicit_invocation"}
NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def mapping(value: object, label: str, errors: list[str]) -> dict:
    if not isinstance(value, dict):
        errors.append(f"{label} must be a YAML mapping")
        return {}
    return value


def load_yaml(text: str, label: str, errors: list[str]) -> dict:
    try:
        return mapping(yaml.safe_load(text), label, errors)
    except yaml.YAMLError as error:
        errors.append(f"{label} is invalid YAML: {error}")
        return {}


def reject_unknown(payload: dict, allowed: set[str], label: str, errors: list[str]) -> None:
    errors.extend(f"{label} contains unsupported field: {key}" for key in sorted(set(payload) - allowed))


def validate_frontmatter(skill_dir: Path, errors: list[str]) -> None:
    skill_file = skill_dir / "SKILL.md"
    try:
        content = skill_file.read_text(encoding="utf-8")
    except OSError as error:
        errors.append(f"cannot read SKILL.md: {error}")
        return
    match = re.match(r"^---\n(.*?)\n---(?:\n|$)", content, re.DOTALL)
    if match is None:
        errors.append("SKILL.md must start with YAML frontmatter delimited by ---")
        return
    frontmatter = load_yaml(match.group(1), "SKILL.md frontmatter", errors)
    reject_unknown(frontmatter, FRONTMATTER_KEYS, "SKILL.md frontmatter", errors)
    name = frontmatter.get("name")
    description = frontmatter.get("description")
    if not isinstance(name, str) or not NAME.fullmatch(name) or len(name) > 64:
        errors.append("frontmatter name must be <=64 characters in hyphen-case")
    elif name != skill_dir.name:
        errors.append("frontmatter name must match the Skill directory")
    if not isinstance(description, str) or not description.strip():
        errors.append("frontmatter description must be a non-empty string")
    elif len(description) > 1024 or "<" in description or ">" in description:
        errors.append("frontmatter description exceeds Codex constraints")
    if "metadata" in frontmatter and not isinstance(frontmatter["metadata"], dict):
        errors.append("frontmatter metadata must be a mapping")
    if "[TODO:" in match.group(1):
        errors.append("frontmatter contains an unfinished placeholder")


def validate_openai_metadata(skill_dir: Path, errors: list[str]) -> None:
    metadata_file = skill_dir / "agents" / "openai.yaml"
    try:
        payload = load_yaml(metadata_file.read_text(encoding="utf-8"), "agents/openai.yaml", errors)
    except OSError as error:
        errors.append(f"cannot read agents/openai.yaml: {error}")
        return
    reject_unknown(payload, OPENAI_KEYS, "agents/openai.yaml", errors)
    interface = mapping(payload.get("interface"), "interface", errors)
    reject_unknown(interface, INTERFACE_KEYS, "interface", errors)
    for field in ("display_name", "short_description", "default_prompt"):
        value = interface.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"interface.{field} must be a non-empty string")
    short_description = interface.get("short_description")
    if isinstance(short_description, str) and not 25 <= len(short_description) <= 64:
        errors.append("interface.short_description must contain 25-64 characters")
    default_prompt = interface.get("default_prompt")
    if isinstance(default_prompt, str) and f"${skill_dir.name}" not in default_prompt:
        errors.append(f"interface.default_prompt must mention ${skill_dir.name}")
    policy = mapping(payload.get("policy", {}), "policy", errors)
    reject_unknown(policy, POLICY_KEYS, "policy", errors)
    if "allow_implicit_invocation" in policy and not isinstance(policy["allow_implicit_invocation"], bool):
        errors.append("policy.allow_implicit_invocation must be boolean")
    dependencies = payload.get("dependencies")
    if dependencies is not None and not isinstance(dependencies, dict):
        errors.append("dependencies must be a mapping")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("skill_dir", type=Path)
    args = parser.parse_args()
    skill_dir = args.skill_dir.resolve()
    errors: list[str] = []
    validate_frontmatter(skill_dir, errors)
    validate_openai_metadata(skill_dir, errors)
    if errors:
        for error in errors:
            print(f"Skill metadata validation error: {error}")
        raise SystemExit(1)
    print("Skill metadata validation passed")


if __name__ == "__main__":
    main()
