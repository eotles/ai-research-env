#!/usr/bin/env python3
"""Enforce repository maintenance and CI guardrails."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"

LOCK_PAIRS = {
    "environment.yml": "conda-lock.yml",
    "scripts/generate-lockfile.sh": "conda-lock.yml",
    "environment-gpu.yml": "conda-lock-gpu.yml",
    "scripts/generate-gpu-lockfile.sh": "conda-lock-gpu.yml",
}

LOCK_CHECK_REQUIREMENTS = {
    ".github/workflows/lockfile-check.yml": (
        "cp conda-lock.yml",
        "--file environment.yml",
        "scripts/compare_conda_locks.py",
        "conda-lock.yml",
    ),
    ".github/workflows/gpu-lockfile-check.yml": (
        "scripts/generate-gpu-lockfile.sh",
        "scripts/compare_conda_locks.py",
        "conda-lock-gpu.yml",
    ),
}

LOCK_MAINTENANCE_WORKFLOWS = (
    ".github/workflows/lockfile-update.yml",
    ".github/workflows/gpu-lockfile-update.yml",
)

DOCKER_LOCK_REQUIREMENTS = {
    "Dockerfile": "conda-lock.yml",
    "Dockerfile.gpu": "conda-lock-gpu.yml",
}


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def top_level_block(text: str, key: str) -> tuple[str, list[str]] | None:
    lines = text.splitlines()
    key_prefix = f"{key}:"
    for index, line in enumerate(lines):
        if not line.startswith(key_prefix):
            continue
        inline = line[len(key_prefix) :].strip()
        block: list[str] = []
        for following in lines[index + 1 :]:
            if (
                following
                and not following[0].isspace()
                and not following.lstrip().startswith("#")
            ):
                break
            block.append(following)
        return inline, block
    return None


def workflow_has_pull_request(text: str) -> bool:
    event_block = top_level_block(text, "on")
    if event_block is None:
        return False
    inline, block = event_block
    return "pull_request" in inline or any(
        re.match(r"^\s+pull_request\s*:", line) for line in block
    )


def pull_request_has_path_filter(text: str) -> bool:
    """Return True when the pull_request trigger is limited by path filters."""
    event_block = top_level_block(text, "on")
    if event_block is None:
        return False

    inline, block = event_block
    if "pull_request" in inline:
        return False

    for index, line in enumerate(block):
        if not re.match(r"^\s{2}pull_request\s*:", line):
            continue

        for following in block[index + 1 :]:
            if re.match(r"^\s{2}[A-Za-z0-9_-]+\s*:", following):
                break
            if re.match(r"^\s{4}(?:paths|paths-ignore)\s*:", following):
                return True
        return False

    return False


def top_level_permissions_grant_write(text: str) -> bool:
    permission_block = top_level_block(text, "permissions")
    if permission_block is None:
        return False
    inline, block = permission_block
    if inline in {"write-all", "write"}:
        return True
    return any(
        re.match(r"^\s{2}[A-Za-z0-9_-]+\s*:\s*write\s*(?:#.*)?$", line)
        for line in block
    )


def changed_files(base: str, head: str) -> tuple[set[str], set[str]]:
    proc = subprocess.run(
        ["git", "diff", "--name-status", f"{base}...{head}"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    changed: set[str] = set()
    added: set[str] = set()

    for raw_line in proc.stdout.splitlines():
        fields = raw_line.split("\t")
        if not fields:
            continue
        status = fields[0]
        paths = fields[1:]
        if status.startswith("R") or status.startswith("C"):
            paths = paths[-1:]
        for path in paths:
            changed.add(path)
            if status == "A":
                added.add(path)

    return changed, added


def check_static(errors: list[str]) -> None:
    for path, tokens in LOCK_CHECK_REQUIREMENTS.items():
        full_path = ROOT / path
        if not full_path.is_file():
            fail(errors, f"required lock validation workflow is missing: {path}")
            continue
        text = full_path.read_text()
        for token in tokens:
            if token not in text:
                fail(
                    errors,
                    f"{path} must retain strict lock validation token: {token}",
                )

    for path in LOCK_MAINTENANCE_WORKFLOWS:
        full_path = ROOT / path
        if not full_path.is_file():
            fail(errors, f"required lock maintenance workflow is missing: {path}")
            continue
        text = full_path.read_text()
        if top_level_permissions_grant_write(text):
            fail(
                errors,
                f"{path} must remain read-only and may not grant workflow-scope write permissions.",
            )
        if re.search(r"(?m)^\s*git\s+push(?:\s|$)", text):
            fail(
                errors,
                f"{path} may not push directly to a protected branch; lock updates belong in pull requests.",
            )
        if re.search(r"(?m)^\s*gh\s+workflow\s+run(?:\s|$)", text):
            fail(
                errors,
                f"{path} may not dispatch publication workflows after an unreviewed lock update.",
            )

    workflow_lint = ROOT / ".github/workflows/workflow-lint.yml"
    if not workflow_lint.is_file():
        fail(errors, "workflow-lint.yml is missing")
    else:
        workflow_lint_text = workflow_lint.read_text()
        if "scripts/check_repo_protocol.py" not in workflow_lint_text:
            fail(errors, "workflow-lint.yml must run scripts/check_repo_protocol.py")
        if not workflow_has_pull_request(workflow_lint_text):
            fail(errors, "workflow-lint.yml must run on pull requests")
        if pull_request_has_path_filter(workflow_lint_text):
            fail(
                errors,
                "workflow-lint.yml pull_request trigger must remain unfiltered so the "
                "required lint status is present on every PR.",
            )
        if not re.search(r"(?m)^\s{2}lint\s*:\s*$", workflow_lint_text):
            fail(
                errors,
                "workflow-lint.yml must retain the stable `lint` job used by main "
                "branch protection.",
            )

    protection_doc = ROOT / "docs/repository-protection.md"
    if not protection_doc.is_file():
        fail(errors, "docs/repository-protection.md is missing")
    elif "`lint`" not in protection_doc.read_text():
        fail(
            errors,
            "docs/repository-protection.md must document the required `lint` check",
        )

    for path, lock_name in DOCKER_LOCK_REQUIREMENTS.items():
        full_path = ROOT / path
        if not full_path.is_file():
            fail(errors, f"required Dockerfile is missing: {path}")
        elif lock_name not in full_path.read_text():
            fail(errors, f"{path} must continue to consume canonical {lock_name}")

    if WORKFLOWS.is_dir():
        for workflow in sorted(WORKFLOWS.glob("*.y*ml")):
            text = workflow.read_text()
            if workflow_has_pull_request(text) and top_level_permissions_grant_write(text):
                fail(
                    errors,
                    f"{workflow.relative_to(ROOT)} handles pull requests but grants "
                    "write permission at workflow scope; keep PR validation read-only "
                    "and grant write only to non-PR publishing jobs.",
                )


def check_diff(errors: list[str], base: str, head: str) -> None:
    try:
        changed, added = changed_files(base, head)
    except subprocess.CalledProcessError as exc:
        fail(errors, f"could not inspect PR diff: {exc.stderr.strip()}")
        return

    for source, lock in LOCK_PAIRS.items():
        if source in changed and lock not in changed:
            fail(
                errors,
                f"{source} changed without {lock}. Regenerate and commit the "
                "canonical lockfile in the same PR.",
            )

    for path in sorted(added):
        if not path.startswith(".github/workflows/") or not path.endswith(
            (".yml", ".yaml")
        ):
            continue
        text = (ROOT / path).read_text()
        if re.search(
            r"(?m)^\s+[A-Za-z0-9_-]+\s*:\s*write\s*(?:#.*)?$",
            text,
        ):
            fail(
                errors,
                f"new workflow {path} requests write permission. New workflows must "
                "start read-only; add publishing/write behavior through an explicit "
                "protocol change reviewed by the repository owner.",
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--head")
    args = parser.parse_args()

    if bool(args.base) != bool(args.head):
        parser.error("--base and --head must be supplied together")

    errors: list[str] = []
    check_static(errors)

    if args.base and args.head:
        check_diff(errors, args.base, args.head)

    if errors:
        print("Repository protocol check failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("Repository protocol checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
