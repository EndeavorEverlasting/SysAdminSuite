#!/usr/bin/env python3
"""Static contracts for the technician-executed AutoLogon runtime proof lane."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonTechnicianRuntimeProof.ps1"
LAUNCHER = ROOT / "scripts" / "Start-SasAutoLogonTechnicianRuntimeProof.cmd"
DOC = ROOT / "docs" / "AUTOLOGON_TECHNICIAN_RUNTIME_PROOF.md"
EXAMPLE = ROOT / "docs" / "examples" / "autologon-runtime-proof.example.json"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_surfaces_and_example_exist() -> None:
    for path in (SCRIPT, LAUNCHER, DOC, EXAMPLE):
        assert path.exists(), f"missing technician runtime surface: {path}"

    config = json.loads(read(EXAMPLE))
    assert config["schema_version"] == "sas-autologon-technician-runtime-config/v1"
    assert config["disposable_state_acknowledged"] is True
    assert config["stop_existing_process"] is False
    assert config["safe_to_stop_existing_process"] is False
    assert len(config["access_paths"]) >= 2


def test_repo_owned_session_access_dependency_is_composed() -> None:
    content = read(SCRIPT)
    required = (
        "Invoke-SasAutoLogonSessionAccessProof.ps1",
        "$accessProof = & $sessionAccessScript @accessParams",
        "Current-session access proof failed",
        "identity matched",
    )
    lowered = content.lower()
    for fragment in required:
        assert fragment.lower() in lowered, f"missing session dependency: {fragment}"


def test_clean_start_is_explicit_and_bounded() -> None:
    content = read(SCRIPT)
    required = (
        "stop_existing_process",
        "safe_to_stop_existing_process",
        "Pre-existing $expectedProcessName process blocks a clean runtime proof",
        "Stop-Process -Id $existingProcess.Id",
        "Wait-SasProcessAbsent",
        "stop_timeout_seconds must be between 1 and 120",
    )
    for fragment in required:
        assert fragment in content, f"missing safe-start contract: {fragment}"

    assert "Stop-Process -Name *" not in content
    assert "taskkill /f /im *" not in content.lower()


def test_launcher_does_not_depend_on_terminal_focus() -> None:
    content = read(SCRIPT)
    required = (
        "Start-Process -FilePath $applicationPath",
        "-PassThru",
        "Start-Process ACK observed with process id",
        "Wait-SasApplicationReady",
        "surface_ready_mode",
    )
    for fragment in required:
        assert fragment in content

    forbidden = (
        "AppActivate",
        "SendKeys",
        "SetForegroundWindow",
        "WScript.Shell",
    )
    for fragment in forbidden:
        assert fragment.lower() not in content.lower(), f"focus-dependent behavior: {fragment}"


def test_every_wait_and_retry_is_bounded() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    required = (
        "stop_timeout_seconds must be between 1 and 120",
        "ready_timeout_seconds must be between 1 and 180",
        "access_retry_count must be between 0 and 5",
        "access_retry_delay_seconds must be between 1 and 30",
        "[DateTime]::UtcNow.AddSeconds",
    )
    for fragment in required:
        assert fragment in content
    assert "No continuous watcher or background retry process is created." in doc
    assert "while ($true)" not in content.lower()


def test_disposable_state_and_secret_boundaries_are_enforced() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    required = (
        "disposable_state_acknowledged",
        "personal_data_mutation_authorized = $false",
        "forbidden secret/credential-like property name",
        "Do not use personal, patient, account, or production-save data",
    )
    for fragment in required:
        assert fragment in content, f"missing data-safety contract: {fragment}"
    assert "Do not put passwords, secrets, tokens, credentials, patient data" in doc

    forbidden = (
        "Get-Credential",
        "[pscredential]",
        "ConvertTo-SecureString",
        "Register-ScheduledTask",
        "New-ScheduledTask",
        "New-Service",
        "CurrentVersion\Run",
    )
    for fragment in forbidden:
        assert fragment.lower() not in content.lower(), f"forbidden runtime behavior: {fragment}"


def test_proof_chain_and_exact_levels_are_materialized() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    stages = (
        "repo_floor",
        "session_attach",
        "safe_start",
        "launcher_attach",
        "target_surface_ready",
        "trigger_issued",
        "command_ack",
        "behavior_observed",
        "runtime_artifact",
    )
    for stage in stages:
        assert f"'{stage}'" in content, f"missing runtime stage: {stage}"
        assert stage in doc

    levels = (
        "TECHNICIAN_OBSERVED_LIVE_RUNTIME",
        "LIVE_RUNTIME_BEHAVIOR_FAILED",
        "LIVE_RUNTIME_INCOMPLETE",
        "FIXTURE_ONLY",
        "FIXTURE_FAILED",
    )
    for level in levels:
        assert level in content
        assert level in doc

    assert "runtime_proof = $false" in content
    assert "$summary.runtime_proof = -not $FixtureMode" in content


def test_behavior_requires_observation_not_only_launch_or_ack() -> None:
    content = read(SCRIPT)
    required = (
        "A concrete observed-behavior description is required",
        "ObservationResult must be Pass or Fail",
        "Technician observed behavior failure",
        "behavior_observed",
    )
    for fragment in required:
        assert fragment in content

    live_level = content.index("TECHNICIAN_OBSERVED_LIVE_RUNTIME")
    observation_gate = content.index("if ($ObservationResult -eq 'Pass')")
    assert observation_gate < live_level


def test_artifacts_are_written_with_failure_reason() -> None:
    content = read(SCRIPT)
    required = (
        "runtime-proof-summary.json",
        "runtime-proof-chain.log",
        "$summary.failure_reason = $_.Exception.Message",
        "Write-SasJson -Path $summaryPath -Value $summary",
        "proof_level=$($summary.proof_level)",
        "failure_reason=$($summary.failure_reason)",
    )
    for fragment in required:
        assert fragment in content


def test_cmd_launcher_uses_repo_runner_and_preserves_exit_code() -> None:
    content = read(LAUNCHER)
    required = (
        "Invoke-SasAutoLogonTechnicianRuntimeProof.ps1",
        "powershell.exe -NoProfile -ExecutionPolicy Bypass",
        "set \"EXIT_CODE=%ERRORLEVEL%\"",
        "exit /b %EXIT_CODE%",
        "SAS_RUNTIME_NO_PAUSE",
    )
    for fragment in required:
        assert fragment in content


def test_runbook_rejects_lower_proof_claims() -> None:
    content = read(DOC)
    required = (
        "successful installer exit, process launch, route issuance, or command ACK",
        "not enough. The runner records the exact proof level",
        "must name the exact proof level",
        "Never rewrite a process ACK or static/fixture result as live application behavior",
        "Fixture success validates the runner only",
    )
    normalized = " ".join(content.split())
    for fragment in required:
        assert fragment in normalized


def main() -> None:
    tests = [
        test_surfaces_and_example_exist,
        test_repo_owned_session_access_dependency_is_composed,
        test_clean_start_is_explicit_and_bounded,
        test_launcher_does_not_depend_on_terminal_focus,
        test_every_wait_and_retry_is_bounded,
        test_disposable_state_and_secret_boundaries_are_enforced,
        test_proof_chain_and_exact_levels_are_materialized,
        test_behavior_requires_observation_not_only_launch_or_ack,
        test_artifacts_are_written_with_failure_reason,
        test_cmd_launcher_uses_repo_runner_and_preserves_exit_code,
        test_runbook_rejects_lower_proof_claims,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon technician runtime proof contracts")


if __name__ == "__main__":
    main()
