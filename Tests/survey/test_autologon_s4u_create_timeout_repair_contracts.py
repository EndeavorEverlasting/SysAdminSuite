#!/usr/bin/env python3
"""Contracts for the protected-runtime S4U create-timeout confirmation repair."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPAIR = ROOT / "scripts" / "Repair-SasAutoLogonS4UCreateTimeoutRuntime.ps1"
WINDOWS_FIXTURE = ROOT / "Tests" / "PowerShell" / "Test-SasAutoLogonS4UCreateTimeoutRuntimeRepair.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_repair_is_local_only_and_rollback_capable() -> None:
    text = read(REPAIR)
    for marker in (
        "git_activity = 'NONE'",
        "network_activity = 'NONE'",
        "target_contact = 'NONE'",
        "target_mutation = 'NONE'",
        "Copy-Item -LiteralPath $pilotPath -Destination $backupPath -Force",
        "Copy-Item -LiteralPath $backupPath -Destination $pilotPath -Force",
        "Assert-SasPowerShellParses -Path $pilotPath",
        "PASS_ALREADY_APPLIED",
        "FAILED_RESTORED",
    ):
        assert marker in text, marker
    for forbidden in (
        "git fetch",
        "git checkout",
        "git reset",
        "Invoke-WebRequest",
        "Invoke-RestMethod",
        "Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "Invoke-SasAutoLogonS4URestartDeployment.ps1",
    ):
        assert forbidden not in text, forbidden


def test_repair_preserves_bounded_create_timeout_and_confirms_exact_task() -> None:
    text = read(REPAIR)
    for marker in (
        "create_timeout_confirmation = $null",
        "if ([bool]$create.timed_out)",
        "'/Query','/S',$Target,'/TN',$TaskName",
        "-TimeoutSeconds $NativeTimeoutSeconds",
        "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_PRESENT",
        "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_ABSENT",
        "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED",
        "create_timeout_confirmed_present",
        "elseif ([int]$create.exit_code -ne 0)",
    ):
        assert marker in text, marker
    assert "NativeTaskTimeoutSeconds = 60" not in text
    assert "Start-Sleep" not in text


def test_repair_is_crlf_lf_safe_and_exact_anchor_scoped() -> None:
    text = read(REPAIR)
    for marker in (
        '$lineEnding = if ($original.Contains("`r`n"))',
        '$normalized = $original.Replace("`r`n", "`n")',
        "$normalized.IndexOf($nativeAnchor) -ne $normalized.LastIndexOf($nativeAnchor)",
        "$normalized.IndexOf($createAnchor) -ne $normalized.LastIndexOf($createAnchor)",
        "$repairedNormalized = $normalized.Replace($nativeAnchor, $nativeReplacement).Replace($createAnchor, $createReplacement)",
        'New-Object Text.UTF8Encoding($false)',
    ):
        assert marker in text, marker


def test_windows_execution_fixture_is_registered() -> None:
    text = read(WINDOWS_FIXTURE)
    for marker in (
        "LF",
        "CRLF",
        "PASS_REPAIRED",
        "PASS_ALREADY_APPLIED",
        "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_PRESENT",
        "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_ABSENT",
        "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED",
        "git_activity",
        "network_activity",
        "target_contact",
        "target_mutation",
    ):
        assert marker in text, marker


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon S4U create-timeout repair contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
