#!/usr/bin/env python3
"""Validate repository output produced by setup-matt-pocock-skills."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from configure_repository import (
    SetupError,
    git_remote_urls,
    github_repository,
    remote_hostname,
    remote_repository_path,
)


START = "<!-- ai-workflow:agent-skills:start -->"
END = "<!-- ai-workflow:agent-skills:end -->"
TRACKER = re.compile(r"^# Issue tracker: ([^\n]+)$", re.MULTILINE)
TRACKER_REPOSITORY = re.compile(
    r"^- \*\*Repository:\*\* `([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)`$",
    re.MULTILINE,
)
REMOTE_NAME = re.compile(r"^- \*\*Configured from remote:\*\* `([^`]+)`$", re.MULTILINE)
SECRET_PATTERNS = (
    re.compile(r"\bghp_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"(?i)\bauthorization\s*:\s*(?:bearer|token)\s+\S+"),
    re.compile(r"(?i)\b(?:github[_-]?)?token\s*[:=]\s*[`\"']?[A-Za-z0-9_./+-]{12,}"),
)
REQUIRED_BLOCK_PARTS = (
    "## Agent skills",
    "### Issue tracker",
    "`docs/agents/issue-tracker.md`",
    "### Domain docs",
    "`docs/agents/domain.md`",
)
KNOWN_TRACKERS = {"GitHub", "GitLab", "Local Markdown"}


def managed_block(path: Path, errors: list[str]) -> str | None:
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    if text.count(START) != 1 or text.count(END) != 1:
        errors.append(f"{path.name} must contain exactly one managed Agent skills block")
        return None
    start = text.index(START)
    end = text.find(END, start + len(START))
    if end < 0:
        errors.append(f"{path.name} managed Agent skills block markers are out of order")
        return None
    block = text[start : end + len(END)]
    positions = [block.find(part) for part in REQUIRED_BLOCK_PARTS]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        errors.append(
            f"{path.name} managed Agent skills block must contain the tracker and domain sections in order"
        )
        return None
    return block


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("repository", type=Path)
    parser.add_argument("--require-github", action="store_true")
    parser.add_argument("--remote-name")
    args = parser.parse_args()

    root = args.repository.resolve()
    errors: list[str] = []
    tracker_path = root / "docs" / "agents" / "issue-tracker.md"
    domain_path = root / "docs" / "agents" / "domain.md"

    try:
        tracker_text = tracker_path.read_text(encoding="utf-8")
    except OSError as error:
        errors.append(f"cannot read docs/agents/issue-tracker.md: {error}")
        tracker_text = ""
    try:
        domain_text = domain_path.read_text(encoding="utf-8")
    except OSError as error:
        errors.append(f"cannot read docs/agents/domain.md: {error}")
        domain_text = ""

    tracker_match = TRACKER.search(tracker_text)
    tracker_name = tracker_match.group(1).strip() if tracker_match else ""
    if not tracker_name:
        errors.append("issue-tracker.md must declare '# Issue tracker: <provider>'")
    elif tracker_name not in KNOWN_TRACKERS:
        errors.append(
            f"unsupported tracker {tracker_name}; expected GitHub, GitLab, or Local Markdown"
        )
    if args.require_github and tracker_name != "GitHub":
        errors.append("this ai-workflow release requires the GitHub tracker")
    if "<confirmed-" in tracker_text:
        errors.append("issue tracker config contains an unresolved template value")

    repository_match = TRACKER_REPOSITORY.search(tracker_text)
    configured_remote = REMOTE_NAME.search(tracker_text)
    if tracker_name in {"GitHub", "GitLab"}:
        if repository_match is None:
            errors.append(f"{tracker_name} tracker config must contain one concrete repository")
        if configured_remote is None:
            errors.append(f"{tracker_name} tracker config must contain one concrete remote name")
        if args.remote_name and repository_match is not None:
            try:
                urls = git_remote_urls(root, args.remote_name)
                if tracker_name == "GitLab" and any(
                    remote_hostname(url) == "github.com" for url in urls
                ):
                    raise SetupError("GitLab tracker cannot use a GitHub remote")
                identities = {
                    github_repository(url)
                    if tracker_name == "GitHub"
                    else remote_repository_path(url)
                    for url in urls
                }
            except SetupError as error:
                errors.append(str(error))
            else:
                if len(identities) != 1:
                    errors.append(f"{tracker_name} remote has conflicting fetch/push targets")
                elif repository_match.group(1) != next(iter(identities)):
                    errors.append(f"{tracker_name} tracker repository does not match the live remote")
        if args.remote_name and (
            configured_remote is None or configured_remote.group(1) != args.remote_name
        ):
            errors.append(f"{tracker_name} configured remote name does not match the live remote")
    local_root_match = None
    if tracker_name == "Local Markdown":
        local_root_match = re.search(r"^- \*\*Root:\*\* `([^`]+)`$", tracker_text, re.MULTILINE)
        if local_root_match is None:
            errors.append("Local Markdown tracker config must contain one concrete Root")

    if not domain_text.startswith("# Domain Docs"):
        errors.append("domain.md must start with '# Domain Docs'")

    agents_path = root / "AGENTS.md"
    claude_path = root / "CLAUDE.md"
    agents_block = managed_block(agents_path, errors)
    claude_block = managed_block(claude_path, errors)
    if agents_block is None and claude_block is None:
        errors.append("AGENTS.md or CLAUDE.md must contain the managed Agent skills block")
    if agents_path.exists() and claude_path.exists():
        if agents_block is None or claude_block is None:
            errors.append("both existing instruction files must contain the managed block")
        elif agents_block != claude_block:
            errors.append("AGENTS.md and CLAUDE.md managed blocks differ")

    for path_name, block in (("AGENTS.md", agents_block), ("CLAUDE.md", claude_block)):
        if block is None or not tracker_name:
            continue
        if tracker_name not in block:
            errors.append(f"{path_name} managed block does not match tracker {tracker_name}")
        contradictory = sorted(name for name in KNOWN_TRACKERS - {tracker_name} if name in block)
        if contradictory:
            errors.append(
                f"{path_name} managed block contains contradictory tracker names: {contradictory}"
            )
        expected_summary = None
        if tracker_name == "GitHub" and repository_match is not None:
            expected_summary = (
                f"Specifications and tickets are tracked in `{repository_match.group(1)}` "
                "GitHub Issues. See `docs/agents/issue-tracker.md`."
            )
        elif tracker_name == "GitLab" and repository_match is not None:
            expected_summary = (
                f"Specifications and tickets are configured for `{repository_match.group(1)}` "
                "GitLab. See `docs/agents/issue-tracker.md`."
            )
        elif tracker_name == "Local Markdown" and local_root_match is not None:
            expected_summary = (
                f"Specifications and tickets use Local Markdown under `{local_root_match.group(1)}`. "
                "See `docs/agents/issue-tracker.md`."
            )
        tracker_section = (
            block.split("### Issue tracker", 1)[1]
            .split("### Domain docs", 1)[0]
            .strip()
        )
        if expected_summary and tracker_section != expected_summary:
            errors.append(
                f"{path_name} managed tracker section must exactly match its canonical identity"
            )

    if (root / "docs" / "agents" / "triage-labels.md").exists():
        errors.append("triage configuration is outside this release")
    if any("### Triage labels" in block for block in (agents_block, claude_block) if block):
        errors.append("managed blocks must not configure triage in this release")

    combined = "\n".join((tracker_text, domain_text, agents_block or "", claude_block or ""))
    for pattern in SECRET_PATTERNS:
        if pattern.search(combined):
            errors.append("setup output appears to contain a credential or token")
            break

    if errors:
        for error in errors:
            print(f"Setup validation error: {error}")
        raise SystemExit(1)
    print(f"Repository setup validation passed ({tracker_name})")


if __name__ == "__main__":
    main()
