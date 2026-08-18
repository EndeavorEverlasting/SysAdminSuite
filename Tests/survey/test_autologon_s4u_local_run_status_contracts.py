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


def test_observer_follows_only_approved_compact_transport_links() -> None:
    text = read()
    for marker in (
        "transport_preflight_link.json",
        "sas-software-deployment-transport-link/v1",
        "software_deployment_transport_result.json",
        "$approvedTransportRoot = Join-Path $repoRoot 'runs'",
        "Test-SasStatusPathUnderRoot",
        "preflight_result_path = $preflightResultPath",
        "preflight_link_present",
        "preflight_link_valid",
    ):
        assert marker in text, marker
    # A compact pointer is local evidence, never authority to follow an arbitrary path.
    assert "[IO.Path]::GetFileName($linkedPath) -eq 'software_deployment_transport_result.json'" in text
    assert "Test-Path -LiteralPath $linkedPath -PathType Leaf" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon S4U local run status contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
