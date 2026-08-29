#!/usr/bin/env python3
"""Validate the private repository ledger without writing ledger data."""
from __future__ import annotations

import ast
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "scripts" / "sas-private-ledger.py"
POST_COMMIT = ROOT / ".githooks" / "post-commit"
DOC = ROOT / "docs" / "PRIVATE_REPOSITORY_LEDGER.md"
GITIGNORE = ROOT / ".gitignore"
LEDGER = "runs/private-ledger/ledger.jsonl"


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    for path in (WRITER, POST_COMMIT, DOC, GITIGNORE):
        if not path.is_file():
            fail(f"required private-ledger surface missing: {path.relative_to(ROOT)}")

    writer = WRITER.read_text(encoding="utf-8")
    post_commit = POST_COMMIT.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    ignore = GITIGNORE.read_text(encoding="utf-8")

    ast.parse(writer, filename=str(WRITER))
    if "runs/" not in ignore.splitlines():
        fail("runs/ must remain ignored so the private ledger cannot be staged by default")

    ignored = subprocess.run(
        ["git", "-C", str(ROOT), "check-ignore", LEDGER],
        text=True,
        capture_output=True,
        check=False,
    )
    if ignored.returncode != 0:
        fail(f"private ledger path is not ignored: {LEDGER}")

    for marker in (
        "scripts/sas-private-ledger.py commit-hook",
        "python3",
        "python",
    ):
        if marker not in post_commit:
            fail(f"post-commit hook missing: {marker}")

    for marker in (
        "sas-private-ledger/v1",
        "runs/private-ledger",
        "commit-hook",
        "append",
        "decision",
        "plan",
        "SAS-Decision",
        "SAS-Plan",
        "status",
    ):
        if marker not in writer and marker not in doc:
            fail(f"private ledger contract missing marker: {marker}")

    combined = writer + "\n" + post_commit
    for forbidden in (
        r"https?://",
        r"\brequests\b",
        r"\burllib\b",
        r"\bsocket\b",
        r"Invoke-WebRequest",
        r"Test-NetConnection",
        r"Start-Process",
    ):
        if re.search(forbidden, combined, re.IGNORECASE):
            fail(f"private ledger contains forbidden network/runtime surface: {forbidden}")

    if "diff-tree" not in writer or "--name-only" not in writer:
        fail("commit capture must remain metadata-only changed-path capture")
    if "git diff" in writer or "git show --patch" in writer:
        fail("private ledger must not capture diff bodies")

    print("PASS: private repository ledger writer parses")
    print("PASS: runs/private-ledger/ledger.jsonl is gitignored")
    print("PASS: post-commit hook routes commit metadata to the local writer")
    print("PASS: explicit decision/plan capture and commit trailers are documented")
    print("PASS: no network, launcher, target, or diff-body capture surface")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
