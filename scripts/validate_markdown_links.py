#!/usr/bin/env python3
"""Check every relative Markdown link in the repository."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from urllib.parse import unquote

LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
FENCED_CODE = re.compile(r"^(```|~~~).*?^\1[ \t]*$", re.MULTILINE | re.DOTALL)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    errors: list[str] = []
    for markdown in sorted(root.rglob("*.md")):
        if ".git" in markdown.parts:
            continue
        text = markdown.read_text(encoding="utf-8")
        text = FENCED_CODE.sub("", text)
        for raw_target in LINK.findall(text):
            target = raw_target.split("#", 1)[0].strip().strip("<>")
            if not target or target.startswith(("http://", "https://", "mailto:", "/")):
                continue
            resolved = (markdown.parent / unquote(target)).resolve()
            try:
                resolved.relative_to(root)
            except ValueError:
                errors.append(f"{markdown.relative_to(root)} escapes repository: {target}")
                continue
            if not resolved.exists():
                errors.append(f"{markdown.relative_to(root)} has broken link: {target}")
    if errors:
        for error in errors:
            print(f"Markdown link error: {error}")
        raise SystemExit(1)
    print("Markdown link validation passed")


if __name__ == "__main__":
    main()
