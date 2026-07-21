#!/usr/bin/env python3
"""Enforce the repository-root SysAdminSuite agent governance doctrine."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE = ROOT / "AGENTS.md"

REQUIRED_HEADINGS = (
    "## Agent operating principles",
    "## Instruction precedence",
    "## Mandatory sprint declaration",
    "## SysAdminSuite virtual-machine doctrine",
    "## Completion standard",
    "## Forbidden behaviors",
)

REQUIRED_MARKERS = (
    "single source of truth",
    "Evidence before action",
    "Floor before furniture",
    "Bounded sprints with declared scope",
    "One writer per branch",
    "Reuse before replacing",
    "No completion without proof",
    "Platform, security, legal, and repo-owner instructions.",
    "This governance contract.",
    "Task-specific prompts.",
    "Generic defaults.",
    "repo and branch",
    "lane and mission",
    "owned scope and forbidden scope",
    "expected artifacts and validation commands",
    "proof ceiling",
    "changed files are named",
    "validation commands were actually run",
    "a commit SHA exists",
    "push and PR state are reported",
    "one exact next command is given",
    "Acknowledgment without mutation",
    "Plans without execution",
    "Summaries without proof",
    "Completion claims without running checks",
    "Secret, credential",
)

VM_MARKERS = (
    "The SysAdminSuite VM is Python-generated.",
    "Never assume Hyper-V",
    "canonical Python generator/launcher",
    "start or resume the VM",
    "wait for guest and network readiness",
    "execute the requested action inside the intended guest",
    "capture sanitized evidence",
    "shutdown, rollback, or destruction",
    "Do not hand over only an inner guest command",
    "management-boundary network or Kerberos certification",
    "do not fabricate a launcher",
)


def read_governance() -> str:
    assert GOVERNANCE.is_file(), "missing governance contract: AGENTS.md"
    return GOVERNANCE.read_text(encoding="utf-8-sig")


def assert_tracked() -> None:
    completed = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "AGENTS.md"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, "AGENTS.md is not tracked by git"


def assert_headings_and_markers(text: str) -> None:
    positions = []
    for heading in REQUIRED_HEADINGS:
        index = text.find(heading)
        assert index >= 0, f"missing governance heading: {heading}"
        positions.append(index)
    assert positions == sorted(positions), "governance headings are out of contract order"

    for marker in REQUIRED_MARKERS:
        assert marker in text, f"missing governance marker: {marker}"

    for marker in VM_MARKERS:
        assert marker in text, f"missing VM governance marker: {marker}"


def assert_precedence_order(text: str) -> None:
    section = text.split("## Instruction precedence", 1)[1].split("## Mandatory sprint declaration", 1)[0]
    ordered = (
        "1. Platform, security, legal, and repo-owner instructions.",
        "2. This governance contract.",
        "3. Task-specific prompts.",
        "4. Generic defaults.",
    )
    indexes = [section.find(item) for item in ordered]
    assert all(index >= 0 for index in indexes), "instruction precedence list is incomplete"
    assert indexes == sorted(indexes), "instruction precedence order is incorrect"


def assert_compact_and_safe(text: str) -> None:
    line_count = len(text.splitlines())
    assert line_count <= 120, f"AGENTS.md exceeds compact line budget: {line_count}/120"
    forbidden = (
        "BEGIN PRIVATE KEY",
        "password=",
        "Authorization: Bearer",
        "WHH270OPR029",
    )
    for marker in forbidden:
        assert marker not in text, f"governance contract contains forbidden private material: {marker}"


def main() -> int:
    text = read_governance()
    assert_tracked()
    assert_headings_and_markers(text)
    assert_precedence_order(text)
    assert_compact_and_safe(text)
    print("[PASS] AGENTS.md is tracked, ordered, compact, and governance-complete")
    print("[PASS] Python-generated SysAdminSuite VM doctrine is explicit and fail-closed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
