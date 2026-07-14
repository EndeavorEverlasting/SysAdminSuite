#!/usr/bin/env python3
"""Contracts for automatic software-install result inspection and presentation."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Show-SasSoftwareInstallResult.ps1"
CMD = ROOT / "Inspect-LatestSoftwareInstall.cmd"
DOC = ROOT / "docs" / "SOFTWARE_INSTALL_RESULT_INSPECTION.md"
PROFILES = ROOT / "harness" / "e2e" / "e2e-profiles.json"
WORKFLOW = ROOT / ".github" / "workflows" / "default-e2e-validation.yml"
E2E_CAPABILITY = ROOT / ".claude" / "capabilities" / "end-to-end-testing.md"
FIELD_CAPABILITY = ROOT / ".claude" / "capabilities" / "field-command-design.md"
E2E_SKILL = ROOT / ".claude" / "skills" / "end-to-end-validation" / "SKILL.md"
FIELD_SKILL = ROOT / ".claude" / "skills" / "field-workflow" / "SKILL.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_cmd_is_short_and_delegates_to_the_canonical_inspector() -> None:
    text = read(CMD)
    assert "Show-SasSoftwareInstallResult.ps1" in text
    assert "pwsh.exe" in text
    assert "powershell.exe" in text
    assert "exit /b %SAS_EXIT_CODE%" in text
    assert "Invoke-SasSoftwareInstall.ps1" not in text


def test_inspector_validates_evidence_and_blocks_proof_inflation() -> None:
    text = read(SCRIPT)
    required = [
        "software_install_summary.json",
        "software_install_events.jsonl",
        "operator_handoff.txt",
        "software_install_review.json",
        "INSTALLER_EXECUTION_COMPLETE_POST_INSTALL_VERIFICATION_REQUIRED",
        "PLAN_ONLY_NO_INSTALL",
        "INSTALL_FAILED",
        "CLEANUP_REVIEW_REQUIRED",
        "EVIDENCE_INVALID",
        "NO_RUN_FOUND",
        "deployment_complete = $false",
        "post_install_verification_required",
        "summary target_count=",
        "run_started",
        "run_completed",
        "Format-Table -AutoSize",
        "exit $exitCode",
    ]
    for fragment in required:
        assert fragment in text, f"inspector missing contract: {fragment}"
    forbidden = [
        "Test-NetConnection",
        "New-PSSession",
        "Invoke-Command -ComputerName",
        "Clear-EventLog",
        "wevtutil cl",
    ]
    for fragment in forbidden:
        assert fragment not in text, f"inspector contains forbidden behavior: {fragment}"


def test_default_e2e_runs_inspector_after_real_fixture_install() -> None:
    catalog = json.loads(read(PROFILES))
    journeys = {item["id"]: item for item in catalog["journeys"]}
    default_ids = next(
        item["journey_ids"]
        for item in catalog["profiles"]
        if item["id"] == catalog["default_profile"]
    )
    assert "software-install-fixture" in default_ids
    assert "software-install-result-presentation" in default_ids
    assert default_ids.index("software-install-result-presentation") == (
        default_ids.index("software-install-fixture") + 1
    )
    journey = journeys["software-install-result-presentation"]
    assert journey["script"] == "scripts/Show-SasSoftwareInstallResult.ps1"
    assert journey["required"] is True
    assert journey["network_scope"] == "none"
    assert journey["target_mutation"] is False
    assert "-RequireCompleted" in journey["arguments"]
    assert any("software-install-fixture" in value for value in journey["arguments"])


def test_agents_must_present_the_inspector_at_the_logical_moment() -> None:
    for path in (E2E_CAPABILITY, FIELD_CAPABILITY, E2E_SKILL, FIELD_SKILL):
        text = read(path)
        assert "Show-SasSoftwareInstallResult.ps1" in text, (
            f"agent surface does not invoke canonical inspector: {path.relative_to(ROOT)}"
        )
        assert "Inspect-LatestSoftwareInstall.cmd" in text, (
            f"agent surface does not expose technician launcher: {path.relative_to(ROOT)}"
        )
        assert "post-install" in text.lower()


def test_ci_tracks_and_executes_the_inspector_contract() -> None:
    workflow = read(WORKFLOW)
    for path in [
        "Inspect-LatestSoftwareInstall.cmd",
        "scripts/Show-SasSoftwareInstallResult.ps1",
        "docs/SOFTWARE_INSTALL_RESULT_INSPECTION.md",
        "Tests/survey/test_software_install_result_inspector_contracts.py",
    ]:
        assert workflow.count(path) >= 2, (
            f"workflow does not track inspector dependency for push and PR: {path}"
        )
    assert "test_software_install_result_inspector_contracts.py" in workflow
    assert "software-install-fixture/**" in workflow


def test_document_names_required_moments_and_proof_boundary() -> None:
    text = read(DOC)
    for fragment in [
        "immediately after `Invoke-SasSoftwareInstall.ps1` returns",
        "before answering whether deployment succeeded",
        "before expanding from a pilot",
        "software_install_review.json",
        "does not prove the application is installed correctly",
    ]:
        assert fragment in text, f"inspection doc missing: {fragment}"


def main() -> None:
    tests = [
        test_cmd_is_short_and_delegates_to_the_canonical_inspector,
        test_inspector_validates_evidence_and_blocks_proof_inflation,
        test_default_e2e_runs_inspector_after_real_fixture_install,
        test_agents_must_present_the_inspector_at_the_logical_moment,
        test_ci_tracks_and_executes_the_inspector_contract,
        test_document_names_required_moments_and_proof_boundary,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} software-install result inspector contracts")


if __name__ == "__main__":
    main()
