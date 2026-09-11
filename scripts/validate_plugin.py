#!/usr/bin/env python3
"""Validate the pinned v1 subset of the Codex plugin ingestion contract."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlparse

ALLOWED_TOP_LEVEL = {
    "id", "name", "version", "description", "skills", "apps", "mcpServers",
    "interface", "author", "homepage", "repository", "license", "keywords",
}
ALLOWED_AUTHOR = {"name", "email", "url"}
ALLOWED_INTERFACE = {
    "displayName", "shortDescription", "longDescription", "developerName",
    "category", "capabilities", "websiteURL", "privacyPolicyURL",
    "termsOfServiceURL", "brandColor", "composerIcon", "logo", "logoDark",
    "screenshots", "defaultPrompt", "default_prompt",
}
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
IDENTIFIER = re.compile(r"^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$")


def nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def https_url(value: object) -> bool:
    if not nonempty_string(value):
        return False
    parsed = urlparse(str(value))
    return parsed.scheme == "https" and bool(parsed.netloc)


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    manifest_path = root / ".codex-plugin" / "plugin.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot load plugin.json: {error}"]
    if not isinstance(manifest, dict):
        return ["plugin.json must contain an object"]

    unknown = sorted(set(manifest) - ALLOWED_TOP_LEVEL)
    errors.extend(f"unsupported top-level field: {field}" for field in unknown)
    for field in ("name", "version", "description"):
        if not nonempty_string(manifest.get(field)):
            errors.append(f"{field} must be a non-empty string")
    if nonempty_string(manifest.get("name")) and not IDENTIFIER.fullmatch(manifest["name"]):
        errors.append("name is not a valid plugin identifier")
    if nonempty_string(manifest.get("version")) and not SEMVER.fullmatch(manifest["version"]):
        errors.append("version must use strict semver")

    author = manifest.get("author")
    if not isinstance(author, dict):
        errors.append("author must be an object")
    else:
        errors.extend(f"unsupported author field: {field}" for field in sorted(set(author) - ALLOWED_AUTHOR))
        if not nonempty_string(author.get("name")):
            errors.append("author.name must be a non-empty string")
        if "url" in author and not https_url(author["url"]):
            errors.append("author.url must be an absolute HTTPS URL")

    interface = manifest.get("interface")
    if not isinstance(interface, dict):
        errors.append("interface must be an object")
    else:
        errors.extend(f"unsupported interface field: {field}" for field in sorted(set(interface) - ALLOWED_INTERFACE))
        for field in ("displayName", "shortDescription", "longDescription", "developerName", "category"):
            if not nonempty_string(interface.get(field)):
                errors.append(f"interface.{field} must be a non-empty string")
        if "defaultPrompt" not in interface and "default_prompt" not in interface:
            errors.append("interface.defaultPrompt or default_prompt is required")
        capabilities = interface.get("capabilities")
        if not isinstance(capabilities, list) or not capabilities or not all(nonempty_string(item) for item in capabilities):
            errors.append("interface.capabilities must be a non-empty string array")
        for field in ("websiteURL", "privacyPolicyURL", "termsOfServiceURL"):
            if field in interface and not https_url(interface[field]):
                errors.append(f"interface.{field} must be an absolute HTTPS URL")

    skills_path = manifest.get("skills")
    if skills_path != "./skills/" or not (root / "skills").is_dir():
        errors.append("skills must point to the existing ./skills/ directory")
    if "[TODO:" in json.dumps(manifest):
        errors.append("manifest contains an unfinished placeholder")
    return errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    errors = validate(args.root.resolve())
    if errors:
        for error in errors:
            print(f"Plugin validation error: {error}")
        raise SystemExit(1)
    print("Plugin manifest validation passed")


if __name__ == "__main__":
    main()
