#!/usr/bin/env python3
"""Contracts for the repository-owned deterministic automated-test floor."""
from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "tools" / "Invoke-SasDeterministicTestFloor.ps1"
BOOTSTRAP = ROOT / "tools" / "Install-SasDeterministicTestFloorDependencies.ps1"
PESTER = ROOT / "tools" / "Test-Pester5Suite.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "deterministic-test-floor.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing deterministic test-floor surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def assert_runner_composes_existing_owners() -> None:
    text = read(RUNNER)
    for marker in (
        "Tests/test_software_tracker_installs.py",
        "Tests/survey/test_evidence_empty_and_exit_contracts.py",
        "Tests/survey/test_agent_governance_doctrine_contracts.py",
        "Tests/bash/test_target_reduction_plan_contracts.sh",
        "tools/Test-Pester5Suite.ps1",
        "scripts/Invoke-SasEndToEndValidation.ps1",
        "-Profile', 'default'",
        "e2e_validation_result.json",
        "test_floor_receipt.json",
        "candidate_sha=",
        "PYTHONHASHSEED = '0'",
        "TZ = 'UTC'",
        "$script:commit = 'unknown'",
        "$script:branch = 'unknown'",
    ):
        assert marker in text, f"deterministic runner missing required owner/control: {marker}"

    for forbidden in (
        "pip install",
        "npm install",
        "Install-Module",
        "Invoke-WebRequest",
        "Invoke-RestMethod",
        "Start-VM",
        "Restart-Computer",
    ):
        assert forbidden not in text, f"test execution must stay setup-free/offline: {forbidden}"


def assert_dependency_bootstrap_is_exact() -> None:
    text = read(BOOTSTRAP)
    for marker in (
        "pytest==8.4.1",
        "websockets==15.0.1",
        "jsonschema==4.25.1",
        "[version]'5.7.1'",
        "ws@8.18.3",
        "Install-Module Pester -RequiredVersion",
        "--no-package-lock",
        "--ignore-scripts",
    ):
        assert marker in text, f"dependency bootstrap is not pinned: {marker}"


def assert_pester_fails_closed_on_zero_tests() -> None:
    text = read(PESTER)
    for marker in (
        "[version]$RequiredPesterVersion",
        "PESTER_ZERO_TESTS",
        "$total -le 0",
        "exit 2",
    ):
        assert marker in text, f"Pester false-green guard missing: {marker}"

    pwsh = shutil.which("pwsh")
    assert pwsh, "PowerShell 7 is required for deterministic test-floor contracts"

    with tempfile.TemporaryDirectory(prefix="sas-empty-pester-") as temp_dir:
        completed = subprocess.run(
            [
                pwsh,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(PESTER),
                "-TestPath",
                temp_dir,
                "-RequiredPesterVersion",
                "5.7.1",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
    combined = completed.stdout + completed.stderr
    assert completed.returncode != 0, "zero discovered Pester tests must not return success"
    assert "PESTER_ZERO_TESTS" in combined, combined


def assert_workflow_is_thin_and_unattended_safe() -> None:
    text = read(WORKFLOW)
    for marker in (
        "name: Deterministic Test Floor",
        "pull_request:",
        "push:",
        "workflow_dispatch:",
        "contents: read",
        "concurrency:",
        "cancel-in-progress: true",
        "python-version: '3.12.10'",
        "node-version: '20.19.4'",
        "actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
        "actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065",
        "actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020",
        "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
        "Install-SasDeterministicTestFloorDependencies.ps1",
        "Invoke-SasDeterministicTestFloor.ps1",
        "candidate_sha=${{ github.sha }}",
    ):
        assert marker in text, f"workflow missing deterministic/unattended contract: {marker}"

    assert text.count("Install-SasDeterministicTestFloorDependencies.ps1") == 1
    assert text.count("Invoke-SasDeterministicTestFloor.ps1") == 1
    assert "paths:" not in text, "required test floor must not be bypassed by path filtering"
    assert "schedule:" not in text, "no AFK schedule was requested; do not add ceremonial cron"
    for forbidden in ("contents: write", "pull-requests: write", "deploy", "release", "secrets."):
        assert forbidden not in text, f"test workflow gained forbidden authority: {forbidden}"


def main() -> int:
    assert_runner_composes_existing_owners()
    assert_dependency_bootstrap_is_exact()
    assert_pester_fails_closed_on_zero_tests()
    assert_workflow_is_thin_and_unattended_safe()
    print("[PASS] deterministic test floor composes existing repository owners")
    print("[PASS] dependency bootstrap pins pytest/Pester/E2E dependencies exactly")
    print("[PASS] Pester zero-test discovery fails closed with a dedicated nonzero result")
    print("[PASS] GitHub Actions routing is push/PR/manual, read-only, action-SHA-pinned, unfiltered by path, and unscheduled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
