#!/usr/bin/env python3
"""Dependency-free contracts for Cybernet physical power-button hardening."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ORCHESTRATOR = ROOT / "scripts" / "Invoke-SasCybernetPowerHardening.ps1"
LOCAL_PRESET = ROOT / "QRTasks" / "Set-PowerComfortDefaults.ps1"
PROBE = ROOT / "QRTasks" / "Test-DisplayMenuButtonEvent.ps1"
DISPATCHER = ROOT / "QRTasks" / "Invoke-TechTask.ps1"
DOC = ROOT / "docs" / "CYBERNET_POWER_HARDENING.md"
OFFLINE = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required Cybernet power surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_required_surfaces_exist() -> None:
    for path in (ORCHESTRATOR, LOCAL_PRESET, PROBE, DISPATCHER, DOC, OFFLINE):
        assert path.is_file(), f"missing required Cybernet power surface: {path.relative_to(ROOT)}"


def test_known_good_physical_power_button_contract_is_preserved() -> None:
    text = read(LOCAL_PRESET)
    assert "7648efa3-dd9c-4e3e-b566-50f929386280" in text
    assert "'/setacvalueindex', $g, 'SUB_BUTTONS', $powerButtonAction, '0'" in text
    assert "'/setdcvalueindex', $g, 'SUB_BUTTONS', $powerButtonAction, '0'" in text
    assert "power button=do nothing" in text
    assert "UIBUTTON_ACTION" not in text, "Windows Start-menu action must not masquerade as display-button hardening"


def test_network_lane_is_bounded_authorized_and_non_scanning() -> None:
    text = read(ORCHESTRATOR)
    for fragment in (
        "SupportsShouldProcess = $true",
        "ConfirmImpact = 'High'",
        "[switch]$AllowTargetMutation",
        "[switch]$FixtureMode",
        "[int]$MaxTargets = 25",
        "Refusing target mutation without -AllowTargetMutation",
        "$PSCmdlet.ShouldProcess",
        "Invoke-Command -ComputerName $target",
        "SasTargetIntake.psm1",
        "Assert-SasApprovedInputPath",
        "Assert-SasApprovedOutputPath",
    ):
        assert fragment in text, f"missing bounded network guardrail: {fragment}"

    lower = text.lower()
    for forbidden in ("test-connection", "ping.exe", "invoke-expression", "enter-pssession", "uibutton_action"):
        assert forbidden not in lower, f"forbidden broad or false-control behavior present: {forbidden}"


def test_whatif_and_fixture_paths_precede_remote_contact() -> None:
    text = read(ORCHESTRATOR)
    whatif = text.index("if ($WhatIfPreference)")
    fixture = text.index("if ($FixtureMode)")
    remote = text.index("Invoke-Command -ComputerName $target")
    assert whatif < remote
    assert fixture < remote
    for fragment in (
        "status = 'PLANNED_WHATIF'",
        "network_activity_performed = $false",
        "target_mutation_performed = $false",
        "status = 'FIXTURE_PASS'",
    ):
        assert fragment in text


def test_remote_lane_applies_and_verifies_only_physical_button_action() -> None:
    text = read(ORCHESTRATOR)
    for fragment in (
        "7648efa3-dd9c-4e3e-b566-50f929386280",
        "'/setacvalueindex', $scheme.guid, 'SUB_BUTTONS', $powerButtonAction, '0'",
        "'/setdcvalueindex', $scheme.guid, 'SUB_BUTTONS', $powerButtonAction, '0'",
        "Current AC Power Setting Index",
        "Current DC Power Setting Index",
        "APPLIED_VERIFIED",
    ):
        assert fragment in text, f"missing physical power-button apply/verify fragment: {fragment}"

    for broad_setting in ("VIDEOIDLE", "STANDBYIDLE", "HIBERNATEIDLE", "DISKIDLE", "LIDACTION"):
        assert broad_setting not in text, f"network lane must not broaden into comfort setting: {broad_setting}"


def test_display_menu_button_claim_fails_closed() -> None:
    orchestrator = read(ORCHESTRATOR)
    probe = read(PROBE)
    doc = read(DOC)
    dispatcher = read(DISPATCHER)

    assert "NOT_APPLIED_UNPROVEN" in orchestrator
    assert "Do not claim this button is disabled" in orchestrator
    assert "DisplayMenuButtonProbe" in dispatcher
    assert "OBSERVED_WINDOWS_EVENT" in probe
    assert "NO_WINDOWS_EVENT_OBSERVED" in probe
    assert "never claims the physical display/menu button is disabled" in probe
    assert "UIBUTTON_ACTION = 0" in doc
    assert "Start-menu power action to Sleep" in doc
    assert "NOT_APPLIED_UNPROVEN" in doc


def test_display_menu_probe_is_read_only_toward_system_state() -> None:
    text = read(PROBE)
    assert "Get-WinEvent" in text
    assert "GetInfo\\Output\\QRTasks" in text
    lower = text.lower()
    for forbidden in (
        "powercfg",
        "set-itemproperty",
        "new-itemproperty",
        "remove-itemproperty",
        "clear-eventlog",
        "wevtutil",
        "invoke-command",
        "enter-pssession",
        "new-service",
        "register-scheduledtask",
    ):
        assert forbidden not in lower, f"display/menu probe must remain read-only: {forbidden}"


def test_local_evidence_contract_and_runner_registration() -> None:
    text = read(ORCHESTRATOR)
    for fragment in (
        "cybernet_power_hardening_events.jsonl",
        "cybernet_power_hardening_results.csv",
        "cybernet_power_hardening_summary.json",
        "operator_handoff.txt",
        "sas-cybernet-power-hardening-summary/v1",
    ):
        assert fragment in text
    assert "test_cybernet_power_hardening_contracts.py" in read(OFFLINE)


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} Cybernet power-hardening contracts")
