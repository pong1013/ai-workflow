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
import tempfile
from pathlib import Path
from urllib.parse import urlparse


START = "<!-- ai-workflow:agent-skills:start -->"
END = "<!-- ai-workflow:agent-skills:end -->"
RECEIPT_PATH = Path(".agents/setup/receipt.json")
RECEIPT_SCHEMA_VERSION = 1
RECEIPT_IGNORE_RULE = ".agents/setup/"
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


def receipt_ignore_context(root: Path) -> list[dict[str, object]]:
    context = []
    for relative in (Path(".agents/.gitignore"), Path(".agents/setup/.gitignore")):
        path = root / relative
        if any((root / Path(*relative.parts[:index])).is_symlink() for index in range(1, len(relative.parts) + 1)):
            raise SetupError(f"receipt ignore context traverses a symlink: {relative}")
        existed = path.exists()
        content = path.read_text(encoding="utf-8") if existed else ""
        context.append(
            {
                "path": relative.as_posix(),
                "existed": existed,
                "hash": sha256_text(content),
            }
        )
    return context


def gitignore_ignores_receipt(content: str, root: Path) -> bool:
    with tempfile.TemporaryDirectory(prefix="ai-workflow-ignore-") as temporary:
        probe = Path(temporary)
        initialized = subprocess.run(
            ["git", "-c", "core.excludesFile=/dev/null", "-C", str(probe), "init", "-q"],
            check=False,
            capture_output=True,
            text=True,
        )
        if initialized.returncode != 0:
            raise SetupError("cannot initialize isolated Git ignore validation")
        (probe / ".gitignore").write_text(content, encoding="utf-8")
        for record in receipt_ignore_context(root):
            if not record["existed"]:
                continue
            source = root / record["path"]
            target = probe / record["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
        receipt_probe = probe / RECEIPT_PATH
        receipt_probe.parent.mkdir(parents=True, exist_ok=True)
        receipt_probe.write_text("setup receipt probe\n", encoding="utf-8")
        ignored = subprocess.run(
            [
                "git",
                "-c",
                "core.excludesFile=/dev/null",
                "-C",
                str(probe),
                "check-ignore",
                "-q",
                "--no-index",
                "--",
                RECEIPT_PATH.as_posix(),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        return ignored.returncode == 0


def update_gitignore(original: str, root: Path) -> str:
    if gitignore_ignores_receipt(original, root):
        return original
    prefix = original if not original or original.endswith("\n") else original + "\n"
    proposed = f"{prefix}{RECEIPT_IGNORE_RULE}\n"
    if not gitignore_ignores_receipt(proposed, root):
        raise SetupError("cannot make .agents/setup/ effectively ignored with the proposed .gitignore")
    return proposed


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
        root / ".gitignore": update_gitignore(
            (root / ".gitignore").read_text(encoding="utf-8")
            if (root / ".gitignore").exists()
            else "",
            root,
        ),
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
    payload = setup_plan_payload(args, changes, before, existed, remote_urls)
    digest = hashlib.sha256(
        canonical_json(payload).encode("utf-8")
    ).hexdigest()
    return f"sha256:{digest}"


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return f"sha256:{hashlib.sha256(value.encode('utf-8')).hexdigest()}"


def setup_plan_payload(
    args: argparse.Namespace,
    changes: dict[Path, str],
    before: dict[Path, str],
    existed: dict[Path, bool],
    remote_urls: tuple[str, ...],
) -> dict[str, object]:
    root = args.repository_root.resolve()
    return {
        "repositoryRoot": str(root),
        "tracker": args.tracker,
        "githubRepository": args.github_repository,
        "trackerRepository": args.tracker_repository,
        "remoteName": args.remote_name,
        "remoteUrls": list(remote_urls),
        "domainLayout": args.domain_layout,
        "instructionFile": args.instruction_file,
        "receiptIgnoreContext": receipt_ignore_context(root),
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


def changed_hunks(before: str, after: str) -> list[dict[str, object]]:
    before_lines = before.splitlines(keepends=True)
    after_lines = after.splitlines(keepends=True)
    matcher = difflib.SequenceMatcher(None, before_lines, after_lines, autojunk=False)
    hunks: list[dict[str, object]] = []
    for index, group in enumerate(matcher.get_grouped_opcodes(n=3), start=1):
        first = group[0]
        last = group[-1]
        before_start, before_end = first[1], last[2]
        after_start, after_end = first[3], last[4]
        hunks.append(
            {
                "index": index,
                "before": {
                    "startLine": before_start + 1,
                    "lineCount": before_end - before_start,
                    "hash": sha256_text("".join(before_lines[before_start:before_end])),
                },
                "after": {
                    "startLine": after_start + 1,
                    "lineCount": after_end - after_start,
                    "hash": sha256_text("".join(after_lines[after_start:after_end])),
                },
            }
        )
    return hunks


def receipt_scope(relative: Path) -> str:
    if relative.parts[:2] == ("docs", "agents"):
        return "complete-file"
    if relative == Path(".gitignore"):
        return "ignore-rule"
    return "managed-block"


def repository_identity(
    args: argparse.Namespace, remote_urls: tuple[str, ...]
) -> dict[str, object]:
    identities: set[str]
    if args.tracker == "github":
        identities = {github_repository(url) for url in remote_urls}
    elif args.tracker == "gitlab":
        identities = {remote_repository_path(url) for url in remote_urls}
    else:
        identities = {".scratch/"}
    return {
        "root": str(args.repository_root.resolve()),
        "tracker": args.tracker,
        "trackerRepository": next(iter(identities)),
        "remoteName": args.remote_name,
    }


def write_setup_receipt(
    args: argparse.Namespace,
    changed: list[tuple[Path, str, str]],
    existed: dict[Path, bool],
    remote_urls: tuple[str, ...],
    plan_token: str,
) -> Path:
    root = args.repository_root.resolve()
    receipt_path = root / RECEIPT_PATH
    ensure_safe_target(root, receipt_path)
    mutations = []
    for path, before, after in sorted(changed, key=lambda item: str(item[0].relative_to(root))):
        relative = path.relative_to(root)
        mutations.append(
            {
                "path": relative.as_posix(),
                "scope": receipt_scope(relative),
                "existed": existed[path],
                "beforeHash": sha256_text(before),
                "afterHash": sha256_text(after),
                "hunks": changed_hunks(before, after),
                "provenance": "setup/configuration",
            }
        )
    receipt: dict[str, object] = {
        "schemaVersion": RECEIPT_SCHEMA_VERSION,
        "repository": repository_identity(args, remote_urls),
        "approvedPlan": {
            "token": plan_token,
            "tracker": args.tracker,
            "githubRepository": args.github_repository,
            "trackerRepository": args.tracker_repository,
            "remoteName": args.remote_name,
            "domainLayout": args.domain_layout,
            "instructionFile": args.instruction_file,
        },
        "planToken": plan_token,
        "mutations": mutations,
        "approvalAuthority": False,
    }
    receipt["checksum"] = sha256_text(canonical_json(receipt))
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return receipt_path


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
    if not gitignore_ignores_receipt(changes[root / ".gitignore"], root):
        raise SystemExit(
            "refusing to apply because the approved .gitignore does not ignore "
            ".agents/setup/receipt.json"
        )
    for path, _, after in changed:
        ensure_safe_target(root, path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(after, encoding="utf-8")
    receipt_path = write_setup_receipt(args, changed, existed, remote_urls, plan_token)
    print(f"Applied {len(changed)} setup file(s).")
    print(f"Setup receipt: {receipt_path.relative_to(root)}")


if __name__ == "__main__":
    main()
