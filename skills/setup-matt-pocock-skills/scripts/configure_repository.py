#!/usr/bin/env python3
"""Plan or apply deterministic GitHub repository setup for ai-workflow."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import hmac
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import urlparse


START = "<!-- ai-workflow:agent-skills:start -->"
END = "<!-- ai-workflow:agent-skills:end -->"
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
TRACKER_REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+$")
REMOTE_NAME = re.compile(r"^[A-Za-z0-9._/-]+$")


class SetupError(Exception):
    pass


def github_repository(remote_url: str) -> str:
    value = remote_url.strip()
    if value.startswith("git@github.com:"):
        path = value.removeprefix("git@github.com:")
    else:
        parsed = urlparse(value)
        if parsed.hostname != "github.com":
            raise SetupError("remote URL is not a GitHub repository")
        path = parsed.path.lstrip("/")
    path = path.removesuffix(".git").rstrip("/")
    if not REPOSITORY.fullmatch(path):
        raise SetupError("remote URL does not contain one GitHub owner/repository")
    return path


def remote_repository_path(remote_url: str) -> str:
    value = remote_url.strip()
    scp_match = re.match(r"^[^@]+@[^:]+:(.+)$", value)
    if scp_match:
        path = scp_match.group(1)
    else:
        parsed = urlparse(value)
        if not parsed.scheme or not parsed.netloc:
            raise SetupError("remote URL is not a supported network repository")
        path = parsed.path.lstrip("/")
    path = path.removesuffix(".git").rstrip("/")
    if not TRACKER_REPOSITORY.fullmatch(path):
        raise SetupError("remote URL does not contain a concrete repository path")
    return path


def remote_hostname(remote_url: str) -> str:
    value = remote_url.strip()
    scp_match = re.match(r"^[^@]+@([^:]+):", value)
    if scp_match:
        return scp_match.group(1).lower()
    hostname = urlparse(value).hostname
    if not hostname:
        raise SetupError("remote URL has no hostname")
    return hostname.lower()


def git_remote_urls(root: Path, remote_name: str) -> tuple[str, ...]:
    urls: list[str] = []
    for mode in ((), ("--push",)):
        result = subprocess.run(
            ["git", "-C", str(root), "remote", "get-url", *mode, "--all", remote_name],
            check=False,
            capture_output=True,
            text=True,
        )
        values = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if result.returncode != 0 or not values:
            raise SetupError(f"cannot resolve Git remote {remote_name}")
        urls.extend(values)
    urls = list(dict.fromkeys(urls))
    return tuple(urls)


def git_remote_url(root: Path, remote_name: str) -> str:
    urls = git_remote_urls(root, remote_name)
    identities = {github_repository(url) for url in urls}
    if len(identities) != 1:
        raise SetupError(f"Git remote {remote_name} has conflicting fetch/push targets")
    return urls[0]


def ensure_safe_target(root: Path, path: Path) -> None:
    try:
        relative = path.relative_to(root)
    except ValueError as error:
        raise SetupError(f"write target is outside repository: {path}") from error
    current = root
    for component in relative.parts:
        current = current / component
        if current.is_symlink():
            raise SetupError(f"write target traverses a symlink: {relative}")
    if path.exists() and not path.is_file():
        raise SetupError(f"write target is not a regular file: {relative}")


def instruction_targets(root: Path, requested: str | None) -> list[Path]:
    agents = root / "AGENTS.md"
    claude = root / "CLAUDE.md"
    existing = [path for path in (agents, claude) if path.exists()]
    if existing:
        return existing
    if requested is None:
        raise SetupError(
            "neither AGENTS.md nor CLAUDE.md exists; select --instruction-file after user confirmation"
        )
    return [root / requested]


def managed_block(tracker_name: str, tracker_summary: str, domain_layout: str) -> str:
    domain_summary = (
        "This is a single-context repository with lazy root domain documentation."
        if domain_layout == "single"
        else "This is a multi-context repository using CONTEXT-MAP.md for discovery."
    )
    return f"""{START}
## Agent skills

### Issue tracker

{tracker_summary} See `docs/agents/issue-tracker.md`.

### Domain docs

{domain_summary} See `docs/agents/domain.md`.
{END}"""


def update_instruction(original: str, block: str, name: str) -> str:
    start_count = original.count(START)
    end_count = original.count(END)
    if start_count != end_count or start_count > 1:
        raise SetupError(f"{name} has malformed or duplicate managed block markers")
    if start_count == 1:
        start = original.index(START)
        end = original.index(END, start) + len(END)
        return original[:start] + block + original[end:]
    if re.search(r"(?m)^## Agent skills\s*$", original):
        raise SetupError(f"{name} has an unbounded Agent skills section requiring approved migration")
    prefix = original.rstrip()
    return f"{prefix}\n\n{block}\n" if prefix else f"{block}\n"


def render_tracker(template: str, repository: str, remote_name: str) -> str:
    return (
        template.replace("<confirmed-owner>/<confirmed-repository>", repository)
        .replace("<confirmed-remote-name>", remote_name)
        .replace("<owner/repository>", repository)
    )


def changes_for(args: argparse.Namespace) -> tuple[dict[Path, str], tuple[str, ...]]:
    root = args.repository_root.resolve()
    if not root.is_dir() or not (root / ".git").exists():
        raise SetupError("repository root must be an existing Git worktree")
    if not REMOTE_NAME.fullmatch(args.remote_name) or args.remote_name.startswith("-"):
        raise SetupError("--remote-name contains unsupported characters")

    skill_root = Path(__file__).resolve().parent.parent
    if args.tracker == "github":
        tracker_repository = args.github_repository
        if not tracker_repository or not REPOSITORY.fullmatch(tracker_repository):
            raise SetupError("GitHub setup requires --github-repository owner/repository")
        remote_urls = git_remote_urls(root, args.remote_name)
        remote_identities = {github_repository(url) for url in remote_urls}
        tracker_name = "GitHub"
        tracker_template_name = "issue-tracker-github.md"
        tracker_summary = f"Specifications and tickets are tracked in `{tracker_repository}` GitHub Issues."
    elif args.tracker == "gitlab":
        tracker_repository = args.tracker_repository
        if not tracker_repository or not TRACKER_REPOSITORY.fullmatch(tracker_repository):
            raise SetupError("GitLab setup requires --tracker-repository group/repository")
        remote_urls = git_remote_urls(root, args.remote_name)
        if any(remote_hostname(url) == "github.com" for url in remote_urls):
            raise SetupError("GitLab setup cannot use a GitHub remote")
        remote_identities = {remote_repository_path(url) for url in remote_urls}
        tracker_name = "GitLab"
        tracker_template_name = "issue-tracker-gitlab.md"
        tracker_summary = f"Specifications and tickets are configured for `{tracker_repository}` GitLab."
    else:
        tracker_repository = ".scratch/"
        remote_urls = ()
        remote_identities = {tracker_repository}
        tracker_name = "Local Markdown"
        tracker_template_name = "issue-tracker-local.md"
        tracker_summary = "Specifications and tickets use Local Markdown under `.scratch/`."
    if len(remote_identities) != 1:
        raise SetupError(f"Git remote {args.remote_name} has conflicting fetch/push targets")
    remote_repository = next(iter(remote_identities))
    if remote_repository != tracker_repository:
        raise SetupError(
            f"configured repository {tracker_repository} does not match remote {remote_repository}"
        )

    tracker_template = (skill_root / tracker_template_name).read_text(encoding="utf-8")
    domain_template = (skill_root / "domain.md").read_text(encoding="utf-8")
    block = managed_block(tracker_name, tracker_summary, args.domain_layout)
    changes = {
        root / "docs/agents/issue-tracker.md": render_tracker(
            tracker_template, tracker_repository, args.remote_name
        ),
        root / "docs/agents/domain.md": domain_template,
    }
    for target in instruction_targets(root, args.instruction_file):
        ensure_safe_target(root, target)
        original = target.read_text(encoding="utf-8") if target.exists() else ""
        changes[target] = update_instruction(original, block, target.name)
    for target in changes:
        ensure_safe_target(root, target)
    return changes, remote_urls


def setup_plan_token(
    args: argparse.Namespace,
    changes: dict[Path, str],
    before: dict[Path, str],
    existed: dict[Path, bool],
    remote_urls: tuple[str, ...],
) -> str:
    root = args.repository_root.resolve()
    payload = {
        "repositoryRoot": str(root),
        "tracker": args.tracker,
        "githubRepository": args.github_repository,
        "trackerRepository": args.tracker_repository,
        "remoteName": args.remote_name,
        "remoteUrls": list(remote_urls),
        "domainLayout": args.domain_layout,
        "instructionFile": args.instruction_file,
        "files": [
            {
                "path": str(path.relative_to(root)),
                "existed": existed[path],
                "before": hashlib.sha256(before[path].encode("utf-8")).hexdigest(),
                "after": hashlib.sha256(changes[path].encode("utf-8")).hexdigest(),
            }
            for path in sorted(changes, key=lambda item: str(item.relative_to(root)))
        ],
    }
    digest = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return f"sha256:{digest}"


def print_diff(path: Path, before: str, after: str, root: Path) -> None:
    relative = path.relative_to(root)
    diff = difflib.unified_diff(
        before.splitlines(keepends=True),
        after.splitlines(keepends=True),
        fromfile=f"a/{relative}",
        tofile=f"b/{relative}",
    )
    print("".join(diff), end="")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("repository_root", type=Path)
    parser.add_argument("--tracker", choices=("github", "gitlab", "local-markdown"), default="github")
    parser.add_argument("--github-repository")
    parser.add_argument("--tracker-repository")
    parser.add_argument("--remote-name", default="origin")
    parser.add_argument("--domain-layout", choices=("single", "multi"), default="single")
    parser.add_argument("--instruction-file", choices=("AGENTS.md", "CLAUDE.md"))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirmed", action="store_true")
    parser.add_argument("--plan-token")
    args = parser.parse_args()

    if args.confirmed and not args.apply:
        raise SystemExit("--confirmed is valid only with --apply")

    try:
        changes, remote_urls = changes_for(args)
    except (OSError, SetupError, ValueError) as error:
        raise SystemExit(f"setup configuration error: {error}") from error

    root = args.repository_root.resolve()
    before = {}
    existed = {}
    changed = []
    for path, after in changes.items():
        existed[path] = path.exists()
        before[path] = path.read_text(encoding="utf-8") if existed[path] else ""
        if before[path] != after:
            changed.append((path, before[path], after))
            print_diff(path, before[path], after, root)
    if not changed:
        print("No changes.")
        return
    plan_token = setup_plan_token(args, changes, before, existed, remote_urls)
    if not args.apply:
        print(f"Setup plan token: {plan_token}")
        print(
            "Preview only; rerun the identical command with --apply --confirmed "
            "--plan-token <token> after Setup Confirmation Gate."
        )
        return
    if not args.confirmed or not args.plan_token:
        raise SystemExit(
            "refusing to write without --apply, --confirmed, and the approved --plan-token"
        )
    if not hmac.compare_digest(args.plan_token, plan_token):
        raise SystemExit("setup plan changed after preview; preview and approve the new diff")
    try:
        fresh_changes, fresh_remote_urls = changes_for(args)
    except (OSError, SetupError, ValueError) as error:
        raise SystemExit(f"setup configuration changed after preview: {error}") from error
    if fresh_changes != changes or fresh_remote_urls != remote_urls:
        raise SystemExit("setup targets or remote changed after preview; preview again")
    for path, original in before.items():
        ensure_safe_target(root, path)
        current_exists = path.exists()
        current = path.read_text(encoding="utf-8") if current_exists else ""
        if current_exists != existed[path] or current != original:
            raise SystemExit(f"{path.relative_to(root)} changed after preview; preview again")
    for path, _, after in changed:
        ensure_safe_target(root, path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(after, encoding="utf-8")
    print(f"Applied {len(changed)} setup file(s).")


if __name__ == "__main__":
    main()
