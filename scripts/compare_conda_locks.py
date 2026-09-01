#!/usr/bin/env python3
"""Compare conda-lock files while ignoring generation-path-only metadata."""

from __future__ import annotations

import argparse
import difflib
from pathlib import Path
import sys


def normalize_lock(text: str) -> str:
    """Return lock content normalized for non-semantic generation paths."""
    lines = text.splitlines()

    try:
        start = next(i for i, line in enumerate(lines) if line.startswith("version:"))
    except StopIteration as exc:
        raise ValueError("lockfile does not contain a version field") from exc

    lines = lines[start:]
    normalized: list[str] = []
    in_sources = False

    for line in lines:
        if line == "  sources:":
            in_sources = True
            normalized.append(line)
            continue

        if in_sources and line.startswith("  - "):
            raw = line[4:].strip()
            quote = ""
            if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in {"'", '"'}:
                quote = raw[0]
                raw = raw[1:-1]
            basename = raw.replace("\\", "/").rsplit("/", 1)[-1]
            normalized.append(f"  - {quote}{basename}{quote}")
            continue

        if in_sources:
            in_sources = False

        normalized.append(line.rstrip())

    return "\n".join(normalized).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("canonical", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()

    for path in (args.canonical, args.candidate):
        if not path.is_file():
            print(f"error: lockfile is missing: {path}", file=sys.stderr)
            return 2

    try:
        canonical = normalize_lock(args.canonical.read_text())
        candidate = normalize_lock(args.candidate.read_text())
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if canonical == candidate:
        print("Lockfiles match after normalizing non-semantic generation paths.")
        return 0

    print(
        "error: canonical lockfile differs from freshly generated candidate.",
        file=sys.stderr,
    )
    diff = difflib.unified_diff(
        canonical.splitlines(),
        candidate.splitlines(),
        fromfile=str(args.canonical),
        tofile=str(args.candidate),
        lineterm="",
    )
    for index, line in enumerate(diff):
        if index >= 200:
            print("... diff truncated after 200 lines ...", file=sys.stderr)
            break
        print(line, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
