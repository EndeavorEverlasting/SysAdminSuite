#!/usr/bin/env python3
"""Static contracts for bounded AutoLogon S4U Task Scheduler create recovery."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOUNDED = ROOT / "scripts" / "SasBoundedNative.psm1"
PILOT = ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1"
REPAIR = ROOT / "scripts" / "Repair-SasBoundedNativeS4UCreateRuntime.ps1"
WINDOWS_WORKFLOW = ROOT / ".github" / "workflows" / "autologon-field-path-network-regression-windows.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_only_guid_unique_autologon_s4u_creates_get_special_policy() -> None:
    text = read(BOUNDED)
    for marker in (
        "s4u_task_create_minimum_60",
        "^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$",
        "$effectiveTimeoutSeconds = 60",
        "$requestedTimeoutSeconds = $TimeoutSeconds",
    ):
        assert marker in text, marker
    assert "UnrelatedTask" not in text


def test_timeout_reconciliation_is_exact_target_and_task_query_only() -> None:
    text = read(BOUNDED)
    query = "'/Query','/S',$s4uCreateTarget,'/TN',$s4uCreateTaskName"
    assert query in text
    assert "reconciled_after_timeout = $true" in text
    assert "$reconciledAfterTimeout = (-not [bool]$reconciliation.timed_out -and [int]$reconciliation.exit_code -eq 0)" in text
    assert text.index("$result = Invoke-SasBoundedPowerShell") < text.index(query) < text.index("reconciled_after_timeout = $true")


def test_unproven_timeout_remains_failure_signal() -> None:
    text = read(BOUNDED)
    reconciled_return = text.index("if ($reconciledAfterTimeout)")
    ordinary_return = text.index("[pscustomobject][ordered]@{", reconciled_return + 1)
    tail = text[ordinary_return:]
    assert "timed_out = $result.timed_out" in tail
    assert "exit_code = $result.exit_code" in tail
    assert "reconciliation = $reconciliation" in tail


def test_pilot_uses_unique_s4u_task_names_and_consumes_bounded_result() -> None:
    text = read(PILOT)
    for marker in (
        "SysAdminSuite-AutoLogonS4UProbe-{0}",
        "SysAdminSuite-AutoLogonS4UInstall-{0}",
        "([guid]::NewGuid().ToString('N'))",
        "$create = Invoke-SasBoundedNative",
        "if ([bool]$create.timed_out)",
        "if ([int]$create.exit_code -ne 0)",
        "$effectiveCreateTimeoutSeconds = [int]$create.timeout_seconds",
        "task creation timed out after $effectiveCreateTimeoutSeconds seconds.",
    ):
        assert marker in text, marker
    assert "task creation timed out after $NativeTimeoutSeconds seconds." not in text


def test_runtime_repair_is_local_only_bounded_and_idempotent() -> None:
    text = read(REPAIR)
    for marker in (
        "SasBoundedNative.before.psm1",
        "function Invoke-SasBoundedNative {",
        "function Test-SasBoundedPath {",
        "Assert-Parse $candidate",
        "$directIntegratedLayout",
        "$wrappedLegacyLayout",
        "already_integrated_or_wrapped",
        "AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_APPLIED",
        "AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_ALREADY_PRESENT",
        "git_performed = $false",
        "network_activity_performed = $false",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
    ):
        assert marker in text, marker


def test_windows_workflow_executes_behavior_and_repair_fixtures() -> None:
    text = read(WINDOWS_WORKFLOW)
    assert "AutoLogonS4UTaskCreateTimeoutReconciliation.Tests.ps1" in text
    assert "AutoLogonS4UTaskCreateRuntimeRepair.Tests.ps1" in text
    assert "Repair-SasBoundedNativeS4UCreateRuntime.ps1" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon S4U create-timeout contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
