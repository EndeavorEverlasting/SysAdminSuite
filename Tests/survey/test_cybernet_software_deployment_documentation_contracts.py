#!/usr/bin/env python3
"""Documentation contracts for the Cybernet SMB/Task Scheduler operator lane."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TUTORIAL = ROOT / "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md"
START = ROOT / "START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md"
REFERENCE = ROOT / "docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md"
SCRIPT = ROOT / "bash/apps/sas-install-apps.sh"
CATALOG = ROOT / "configs/software-packages/approved-apps.json"
WORKFLOW = ROOT / ".github/workflows/operational-posture.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_navigation_and_audience() -> None:
    tutorial = read(TUTORIAL)
    start = read(START)
    reference = read(REFERENCE)
    assert "authorized technicians and Windows administrators" in tutorial
    assert "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md" in start
    assert "tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md" in reference
    for path in (
        ROOT / "docs/AUTODIDACT_INSTALL_WORKFLOW.md",
        ROOT / "docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md",
        ROOT / "docs/PACKAGE_VM_QUALIFICATION_PROFILES.md",
    ):
        assert path.is_file(), f"tutorial link target is missing: {path.relative_to(ROOT)}"


def test_commands_match_the_current_entrypoint() -> None:
    tutorial = read(TUTORIAL)
    script = read(SCRIPT)
    required_flags = (
        "--targets",
        "--package",
        "--allow-legacy",
        "--dry-run",
        "--wait-timeout",
        "--no-teardown",
    )
    for flag in required_flags:
        assert flag in tutorial, f"tutorial missing {flag}"
        assert flag in script, f"script help/implementation missing {flag}"
    commands = re.findall(r"```bash\n(.*?)\n```", tutorial, flags=re.DOTALL)
    deployment_commands = [command for command in commands if "sas-install-apps.sh" in command and "--help" not in command]
    assert len(deployment_commands) >= 4
    for command in deployment_commands:
        assert "--targets" in command
        assert "--package bca" in command
        assert "--allow-legacy" in command
    assert any("--dry-run" in command and "CYBERNET-PILOT-01" in command for command in deployment_commands)
    assert any("--dry-run" not in command and "CYBERNET-PILOT-01" in command for command in deployment_commands)
    assert any("CYBERNET-01,CYBERNET-02,CYBERNET-03" in command for command in deployment_commands)


def test_safety_and_proof_boundaries_are_explicit() -> None:
    tutorial = read(TUTORIAL)
    reference = read(REFERENCE)
    combined = tutorial + "\n" + reference
    for marker in (
        "maximum of 25",
        "current approved Windows administrative token",
        "does not enable WinRM",
        "does not create a VM",
        "Transport cleanup is not software rollback",
        "does not implement a general uninstall",
        "PR #229",
        "HOST_OK",
        "technician",
        "one authorized production pilot",
        "does not restart",
    ):
        assert marker.lower() in combined.lower(), f"missing boundary: {marker}"
    for forbidden in (
        "--smb-pass PASSWORD",
        "SAS_SMB_PASS=",
        "taskkill /im",
        "tmux kill-server",
    ):
        assert forbidden.lower() not in combined.lower(), f"unsafe example present: {forbidden}"
    assert "PR #212" in tutorial and "PR #222" in tutorial
    assert "Neither is the authority" in tutorial


def test_documented_output_matches_controller_contract() -> None:
    tutorial = read(TUTORIAL)
    script = read(SCRIPT)
    for marker in (
        "DRY_RUN_OK",
        "Worker syntax preflight passed with Windows PowerShell.",
        "Staged pinned package:",
        "Result copied locally:",
        "Cleanup complete: task and run-scoped staging removed or already absent.",
        "HOST_OK",
        "HOST_FAILED",
        "Installed",
        "ExitOK_NotDetected",
        "3010",
    ):
        assert marker in tutorial, f"tutorial missing output marker: {marker}"
        assert marker in script, f"controller no longer emits/handles marker: {marker}"
    assert "transport=windows-native" in tutorial
    assert 'TRANSPORT="windows-native"' in script
    assert "transport=$TRANSPORT" in script


def test_bca_example_is_catalog_backed() -> None:
    catalog = json.loads(read(CATALOG))
    matches = [item for item in catalog["packages"] if item["id"] == "bca"]
    assert len(matches) == 1
    bca = matches[0]
    assert bca["installer_file"] == "EPIC_BCA_Web-Shortcut_1.0.msi"
    assert bca["default_installer_arguments"] == ["/qn", "/norestart"]
    assert bca["install_enabled"] is True
    tutorial = read(TUTORIAL)
    assert bca["display_name"] in tutorial
    assert bca["installer_file"] in tutorial
    assert "`/qn /norestart`" in tutorial


def test_docs_contract_is_wired_into_ci_and_offline_validation() -> None:
    workflow = read(WORKFLOW)
    runner = read(RUNNER)
    test_path = "Tests/survey/test_cybernet_software_deployment_documentation_contracts.py"
    assert test_path in workflow
    assert test_path in runner
    assert "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md" in workflow
    assert "START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md" in workflow
    assert "'docs/**'" in workflow


def test_no_machine_local_or_private_runtime_evidence_is_documented() -> None:
    combined = read(TUTORIAL) + "\n" + read(START) + "\n" + read(REFERENCE)
    assert not re.search(r"(?i)C:\\Users\\[A-Za-z0-9._-]+", combined)
    assert "<target>" in combined
    assert "CYBERNET-PILOT-01" in combined
    assert "hostname intentionally omitted" not in combined.lower()
    assert "live hostname" in combined.lower()
    assert "not committed" in combined.lower()


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} Cybernet software deployment documentation contract groups")
