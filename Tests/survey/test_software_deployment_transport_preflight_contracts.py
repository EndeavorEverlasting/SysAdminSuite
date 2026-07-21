#!/usr/bin/env python3
"""Dependency-free static contracts for the read-only transport preflight."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "scripts/Test-SasSoftwareDeploymentTransport.ps1"
MODULE = ROOT / "scripts/SasSoftwareDeploymentTransport.psm1"
PESTER = ROOT / "Tests/Pester/SoftwareDeploymentTransport.Tests.ps1"
SCHEMA = ROOT / "schemas/harness/software-deployment-transport-result.schema.json"
WORKFLOW = ROOT / "harness/workflows/software-deployment-transport.yaml"
CI = ROOT / ".github/workflows/harness-contracts.yml"
OFFLINE = ROOT / "tests/survey/run_offline_survey_tests.sh"
FIXTURE = ROOT / "Tests/Fixtures/software-deployment-transport/kerberos-smb-task-ready.fixture.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_front_door_contract_is_bounded_explicit_and_noninteractive() -> None:
    text = read(ENTRYPOINT)
    for token in (
        "#Requires -Version 5.1",
        "[string]$ComputerName",
        "[switch]$AllowNetworkActivity",
        "[System.Management.Automation.PSCredential]$Credential",
        "[switch]$FixtureMode",
        "[string]$FixturePath",
        "[ValidateRange(1, 30)]",
        "[int]$TimeoutSeconds = 5",
        "New-SasRunContext",
        "Register-SasArtifact",
        "software_deployment_transport_result.json",
        "english_summary.txt",
    ):
        assert token in text, f"front door missing {token}"
    assert "Get-Credential" not in text
    assert "ConvertFrom-SecureString" not in text
    assert "ConvertTo-SecureString" not in text
    assert text.index("if ($FixtureMode)") < text.index("Invoke-SasSoftwareDeploymentTransportObservation")
    assert "-NetworkActivityPerformed $networkActivity" in text


def test_module_collects_required_read_only_observations() -> None:
    text = read(MODULE)
    for token in (
        "Resolve-SasBoundedDns",
        "Test-SasBoundedTcpPort",
        "klist.exe",
        "HTTP",
        "HOST",
        "CIFS",
        "port_5985",
        "port_5986",
        "port_445",
        "port_135",
        "ADMIN$",
        "Win32_Service",
        "Name='Schedule'",
        "MSFT_ScheduledTask",
        "Root/Microsoft/Windows/TaskScheduler",
        "schtasks.exe",
        '"/Query /S {0} /FO CSV /NH"',
        "ticket_bytes_emitted = $false",
        "target_mutation_performed = $false",
    ):
        assert token in text, f"collector missing {token}"

    forbidden = (
        r"\bEnable-PSRemoting\b",
        r"winrm\s+quickconfig",
        r"\bTrustedHosts\b",
        r"\bCredSSP\b",
        r"\bRegister-ScheduledTask\b",
        r"\bNew-ScheduledTask\b",
        r"schtasks(?:\.exe)?\s+/(?:Create|Delete|Run|Change)",
        r"\bStart-Service\b",
        r"\bStop-Service\b",
        r"\bSet-Service\b",
        r"\bSet-ItemProperty\b",
        r"\bNew-ItemProperty\b",
        r"\bInvoke-Command\b",
        r"netsh\s+advfirewall",
    )
    for pattern in forbidden:
        assert re.search(pattern, text, re.IGNORECASE) is None, f"forbidden target mutation surface: {pattern}"


def test_decision_vocabulary_and_fail_closed_flags_match_p01() -> None:
    text = read(MODULE)
    schema = json.loads(read(SCHEMA))
    expected = set(schema["properties"]["decision"]["properties"]["classification"]["enum"])
    for classification in expected:
        assert f"'{classification}'" in text
    assert "silent_fallback_permitted = $false" in text
    assert "fallback_after_mutation_permitted = $false" in text
    assert text.index("elseif ($winrmReady)") < text.index("elseif ($smbReady)")
    assert "elseif ($timedOut)" in text
    assert "elseif ($authorizationDenied)" in text
    assert "elseif ($allPortsTested -and -not $anyPortReachable)" in text


def test_sanitized_fixture_and_artifact_contracts_are_registered() -> None:
    fixture = json.loads(read(FIXTURE))
    assert fixture["evidence_class"] == "sanitized_fixture"
    assert fixture["network_activity_performed"] is False
    assert fixture["target_mutation_performed"] is False
    assert fixture["target_scope"]["identifier_emitted"] is False

    entrypoint = read(ENTRYPOINT)
    assert "target_identifier_emitted = $false" in entrypoint
    assert "username_emitted = $false" in entrypoint
    assert "credential_emitted = $false" in entrypoint
    assert "ticket_bytes_emitted = $false" in entrypoint
    assert "raw_faults_emitted = $false" in entrypoint
    assert "$Credential" not in entrypoint[entrypoint.index("$resultPath =") :]


def test_pester_ci_workflow_and_offline_runner_are_wired() -> None:
    pester = read(PESTER)
    for scenario in (
        "kerberos_smb_task_ready",
        "winrm_ready",
        "only DNS",
        "445 is closed",
        "135 is closed",
        "ADMIN share",
        "Schedule service denial",
        "scheduled-task read-query denial",
        "timed-out observation",
        "runtime-only PSCredential",
        "no interactive prompt",
        "does not leak ticket bytes",
    ):
        assert scenario in pester, f"focused Pester coverage missing {scenario}"

    ci = read(CI)
    offline = read(OFFLINE)
    workflow = read(WORKFLOW)
    assert "test_software_deployment_transport_preflight_contracts.py" in ci
    assert "SoftwareDeploymentTransport.Tests.ps1" in ci
    assert "Test-SasSoftwareDeploymentTransport.ps1" in ci
    assert "test_software_deployment_transport_preflight_contracts.py" in offline
    assert "scripts/Test-SasSoftwareDeploymentTransport.ps1" in workflow
    assert "implementation_status: implemented_p02" in workflow


def main() -> int:
    tests = [value for name, value in globals().items() if name.startswith("test_") and callable(value)]
    for test in sorted(tests, key=lambda item: item.__name__):
        test()
        print(f"PASS {test.__name__}")
    print("Software deployment transport preflight contracts passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
