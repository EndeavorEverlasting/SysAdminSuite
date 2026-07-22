#!/usr/bin/env python3
"""Enforce the repository-root SysAdminSuite agent governance doctrine."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE = ROOT / "AGENTS.md"
VALIDATOR = ROOT / "Tests/survey/test_agent_governance_doctrine_contracts.py"
CYBERNET_PROFILE = ROOT / "Config/cybernet-client-preferences.json"
PACKAGE_CATALOG = ROOT / "configs/software-packages/windows-native-package-sets.json"

REQUIRED_HEADINGS = (
    "## Agent operating principles",
    "## Instruction precedence",
    "## Mandatory sprint declaration",
    "## Device-profile and deployment doctrine",
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

PROFILE_MARKERS = (
    "Serial number, hostname, MAC address, model, subnet, or probe response is identity evidence, not permission to infer a profile.",
    "Cybernet, shared/user-login workstation, Neuron, tablet, Kronos clock",
    "Unknown, ambiguous, conflicting, or unsupported profile evidence fails closed to read-only review.",
    "Config/cybernet-client-preferences.json",
    "AutoLogon is forbidden on every shared/user-login workstation profile.",
    "A package set containing AutoLogon is invalid for that profile",
    "AutoLogon is selected for an eligible non-shared profile",
    "final package and final mutating configuration step",
    "Cross-profile conflation is a blocking defect",
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


def load_json(path: Path) -> dict:
    assert path.is_file(), f"missing governance authority: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def assert_tracked() -> None:
    for path in (GOVERNANCE, VALIDATOR):
        relative = path.relative_to(ROOT).as_posix()
        completed = subprocess.run(
            ["git", "ls-files", "--error-unmatch", relative],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        assert completed.returncode == 0, f"{relative} is not tracked by git"


def assert_headings_and_markers(text: str) -> None:
    positions = []
    for heading in REQUIRED_HEADINGS:
        index = text.find(heading)
        assert index >= 0, f"missing governance heading: {heading}"
        positions.append(index)
    assert positions == sorted(positions), "governance headings are out of contract order"

    for marker in REQUIRED_MARKERS + PROFILE_MARKERS + VM_MARKERS:
        assert marker in text, f"missing governance marker: {marker}"


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


def assert_cybernet_profile_contract() -> None:
    profile = load_json(CYBERNET_PROFILE)
    catalog = load_json(PACKAGE_CATALOG)

    assert profile["schema_version"] == "sas-cybernet-client-preferences/v1"
    assert profile["profile_id"] == "cybernet-clinical-workstation-default"
    software = profile["software"]
    assert software["package_set_id"] == "cybernet-clinical-workstation"
    assert software["autologon_must_be_last"] is True

    package_set = next(
        item for item in catalog["package_sets"]
        if item["id"] == software["package_set_id"]
    )
    assert package_set["package_ids"], "Cybernet package set is empty"
    assert package_set["package_ids"] == software["package_ids"]
    assert package_set["package_ids"][-1] == "autologon"
    assert package_set["package_ids"].count("autologon") == 1


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
    assert_cybernet_profile_contract()
    assert_compact_and_safe(text)
    print("[PASS] AGENTS.md and its validator are tracked, ordered, compact, and governance-complete")
    print("[PASS] Device profiles fail closed and shared/user-login profiles forbid AutoLogon")
    print("[PASS] The current Cybernet profile selects AutoLogon exactly once and last")
    print("[PASS] Python-generated SysAdminSuite VM doctrine is explicit and fail-closed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
