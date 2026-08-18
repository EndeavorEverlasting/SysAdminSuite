#!/usr/bin/env python3
"""Contracts for the protected-runtime S4U create-timeout confirmation and recovery lane."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPAIR = ROOT / "scripts" / "Repair-SasAutoLogonS4UCreateTimeoutRuntime.ps1"
RECOVERY = ROOT / "scripts" / "Complete-SasInterruptedAutoLogonS4URecovery.ps1"
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
        '$nativeAnchorNormalized = $nativeAnchor.Replace("`r`n", "`n")',
        '$nativeReplacementNormalized = $nativeReplacement.Replace("`r`n", "`n")',
        '$createAnchorNormalized = $createAnchor.Replace("`r`n", "`n")',
        '$createReplacementNormalized = $createReplacement.Replace("`r`n", "`n")',
        "$normalized.IndexOf($nativeAnchorNormalized) -ne $normalized.LastIndexOf($nativeAnchorNormalized)",
        "$normalized.IndexOf($createAnchorNormalized) -ne $normalized.LastIndexOf($createAnchorNormalized)",
        "$repairedNormalized = $normalized.Replace($nativeAnchorNormalized, $nativeReplacementNormalized).Replace($createAnchorNormalized, $createReplacementNormalized)",
        'New-Object Text.UTF8Encoding($false)',
    ):
        assert marker in text, marker


def test_terminal_probe_timeout_result_is_recovery_eligible_only_fail_closed() -> None:
    text = read(RECOVERY)
    for marker in (
        "S4U_PROBE_CREATE_TIMEOUT",
        "S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT",
        "S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED",
        "terminal_pilot_recovery_eligible",
        "Terminal S4U pilot probe task identity does not match requested recovery task",
        "Terminal S4U pilot result contains installer lifecycle evidence; refusing probe-only recovery.",
        "Terminal S4U pilot result contains an installer exit code; refusing probe-only recovery.",
        "Terminal S4U pilot result reports pre-reboot AutoLogon ready; refusing probe-only recovery.",
        "Terminal S4U pilot result reports automatic reboot; refusing probe-only recovery.",
        "Terminal S4U pilot result references after-state evidence; refusing probe-only recovery.",
        "-AllowedArtifactProfile ProbeOnly",
        "task_absent_before_cleanup",
        "task_absent_after_cleanup",
        "autologon_installer_launched_by_recovered_transaction = $false",
    ):
        assert marker in text, marker
    assert "A terminal S4U pilot result already exists; use that result instead of interrupted recovery." not in text
    for forbidden in (
        "Invoke-SasAutoLogonKerberosS4UPilot.ps1",
        "Invoke-SasAutoLogonS4URestartDeployment.ps1",
        "Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
    ):
        assert forbidden not in text, forbidden


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
    print(f"PASS: AutoLogon S4U create-timeout repair/recovery contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
