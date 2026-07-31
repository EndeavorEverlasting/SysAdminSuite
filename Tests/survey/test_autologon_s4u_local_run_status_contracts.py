#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Get-SasAutoLogonS4URunStatus.ps1"


def read() -> str:
    assert SCRIPT.is_file(), f"missing required file: {SCRIPT.relative_to(ROOT)}"
    return SCRIPT.read_text(encoding="utf-8-sig")


def test_observer_is_local_only_and_non_mutating() -> None:
    text = read()
    for marker in (
        "network_activity_performed_by_observer = $false",
        "target_contact_performed_by_observer = $false",
        "target_mutation_performed_by_observer = $false",
        "Get-ChildItem -LiteralPath $s4uRoot -File -Recurse",
    ):
        assert marker in text, marker
    for forbidden in (
        "schtasks.exe",
        "Copy-Item -LiteralPath $sourcePath",
        "Remove-Item -LiteralPath $remote",
        "Invoke-Command",
        "New-PSSession",
        "Test-NetConnection",
    ):
        assert forbidden not in text, forbidden


def test_observer_distinguishes_silent_s4u_stages() -> None:
    text = read()
    for marker in (
        "transport_preflight",
        "software_source_kerberos",
        "baseline_capture",
        "final_step_gate",
        "source_validation_hash_or_staging",
        "probe_task_preparation_or_execution",
        "install_task_preparation_or_execution",
        "after_state_capture",
        "terminal_result_written",
        "latest_local_artifact_age_seconds",
    ):
        assert marker in text, marker


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon S4U local run status contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
