#!/usr/bin/env python3
"""Contracts for terminal probe-timeout discovery before exact S4U recovery."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DISCOVERY = ROOT / "scripts" / "Recover-SasLatestInterruptedAutoLogonS4U.ps1"
EXACT = ROOT / "scripts" / "Complete-SasInterruptedAutoLogonS4URecovery.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_terminal_probe_timeout_candidates_are_not_discarded() -> None:
    text = read(DISCOVERY)
    assert "if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }" not in text
    for marker in (
        "$terminalPilotPresent = Test-Path -LiteralPath $terminal -PathType Leaf",
        "$terminalPilotClassification = Get-SasOptionalJsonString -Object $terminalPilot -Name 'classification'",
        "'S4U_PROBE_CREATE_TIMEOUT'",
        "'S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT'",
        "'S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED'",
        "if (-not $terminalPilotRecoveryEligible) { continue }",
        "terminal_pilot_recovery_eligible=$terminalPilotRecoveryEligible",
    ):
        assert marker in text, marker


def test_unreadable_terminal_evidence_fails_before_exact_target_contact() -> None:
    text = read(DISCOVERY)
    parse_gate = text.index("if ($unreadableTerminal.Count -gt 0)")
    exact_call = text.index("$one = & $recoveryScript -ComputerName $ComputerName")
    assert parse_gate < exact_call
    assert "Refusing target contact or automatic recovery" in text
    assert "terminal_pilot_parse_failed=$terminalPilotParseFailed" in text


def test_discovery_remains_local_only_until_exact_helper() -> None:
    text = read(DISCOVERY)
    prefix = text[: text.index("$one = & $recoveryScript -ComputerName $ComputerName")]
    for forbidden in (
        "schtasks.exe",
        "Get-ScheduledTask",
        "\\\\$ComputerName\\C$",
        "Invoke-Command",
        "Enter-PSSession",
    ):
        assert forbidden not in prefix, forbidden
    assert "Get-SasEvidenceRoots -RepoRoot $repoRoot" in prefix
    assert "s4u_probe_lifecycle.json" in prefix


def test_exact_helper_rechecks_terminal_identity_and_installer_boundary() -> None:
    text = read(EXACT)
    for marker in (
        "Terminal S4U pilot probe task identity does not match requested recovery task",
        "Terminal S4U pilot result contains installer lifecycle evidence",
        "Terminal S4U pilot result contains an installer exit code",
        "Terminal S4U pilot result reports pre-reboot AutoLogon ready",
        "Terminal S4U pilot result reports automatic reboot",
        "Terminal S4U pilot result references after-state evidence",
        "-AllowedArtifactProfile ProbeOnly",
    ):
        assert marker in text, marker


def test_recovery_discovery_schema_advanced_for_terminal_eligibility() -> None:
    text = read(DISCOVERY)
    assert text.count("sas-autologon-s4u-recovery-discovery/v3") == 2
    assert "sas-autologon-s4u-recovery-discovery/v2" not in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: terminal AutoLogon recovery discovery contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
