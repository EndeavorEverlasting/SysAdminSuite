#!/usr/bin/env python3
"""Contracts for the read-only Cursor workstation safety floor."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "Config/cursor-workstation-profile.json"
SCHEMA = ROOT / "schemas/harness/cursor-workstation-profile.schema.json"
SCRIPT = ROOT / "scripts/Invoke-SasCursorWorkstation.ps1"
LAUNCHER = ROOT / "Manage-Cursor.cmd"
DOC = ROOT / "docs/CURSOR_WORKSTATION_LIFECYCLE.md"
WORKFLOW = ROOT / ".github/workflows/cursor-workstation-lifecycle.yml"
ROUTING = ROOT / "harness/api/developer-workstation-agent-routing.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required Cursor file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_profile_schema_and_readonly_posture() -> None:
    profile = load(PROFILE); schema = load(SCHEMA)
    assert profile["schema_version"] == "sas-cursor-workstation-profile/v1"
    assert profile["schema_path"] == schema["$id"]
    assert profile["posture"]["mutation_available"] is False
    assert profile["posture"]["current_security_principal_only"] is True
    assert profile["posture"]["system_verification_requires_registration_and_executable"] is True
    assert profile["application"]["expected_executable"] == "Cursor.exe"
    pattern = schema["properties"]["installation"]["properties"]["uninstall_registry_roots"]["items"]["properties"]["path"]["pattern"]
    for row in profile["installation"]["uninstall_registry_roots"]:
        assert re.match(pattern, row["path"]), row
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.Draft202012Validator(schema).validate(profile)


def test_engine_is_readonly_and_fail_closed() -> None:
    text = read(SCRIPT)
    assert "[ValidateSet('Audit', 'Verify')]" in text
    assert "mutation_available = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "VERIFIED_ABSENT_CURRENT_CONTEXT" in text
    assert "ProcessInspectionSucceeded" in text and "inspection-incomplete" in text
    assert "[Guid]::NewGuid()" in text
    assert "if ([string]::IsNullOrWhiteSpace($replacement)) { return '' }" in text
    assert "MachineInstallEvidence" in text and "ExecutableExists" in text
    assert "ExternalCommandPathsIgnored" in text
    for forbidden in (
        "Start-Process", "Stop-Process", "Remove-Item", "Remove-ItemProperty",
        "SetEnvironmentVariable", "InstallerPath", "AllowMutation", "RecoveryPurge",
        "InstallSystem", "UninstallString", "Get-AuthenticodeSignature",
    ):
        assert forbidden not in text, f"read-only engine contains mutating lifecycle marker: {forbidden}"


def test_launcher_refuses_mutation_actions() -> None:
    text = read(LAUNCHER)
    assert 'if /I "%~1"=="Audit" goto run' in text
    assert 'if /I "%~1"=="Verify" goto run' in text
    assert "Cursor mutation is intentionally unavailable" in text
    assert "InstallSystem, Uninstall, and RecoveryPurge are intentionally disabled" in text
    assert "scripts\\Invoke-SasCursorWorkstation.ps1" in text


def test_doctrine_explains_quarantine_and_proof_ceiling() -> None:
    text = read(DOC)
    for marker in (
        "read-only", "Audit", "Verify", "VERIFIED_ABSENT_CURRENT_CONTEXT",
        "current security principal", "unins000.dat", "Error 32",
        "mutation trust boundary", "registered uninstall executables",
        "REG_EXPAND_SZ", "collision-resistant evidence run IDs",
    ):
        assert marker in text, marker
    assert re.search(r"(?:cannot|does not) prove a physical workstation repair", text, re.IGNORECASE)


def test_routing_and_ci_are_registered() -> None:
    routing = load(ROUTING)
    phrases = {row["phrase"] for row in routing["triggers"]}
    assert {"install Cursor", "uninstall Cursor", "Cursor Error 32", "unins000.dat"} <= phrases
    workflow = read(WORKFLOW)
    assert workflow.count("persist-credentials: false") == 2
    assert "test_cursor_workstation_lifecycle_contracts.py" in workflow
    assert "test_developer_workstation_agent_harness_contracts.py" in workflow
    assert "-Action Audit" in workflow and "-Action Verify -ExpectedState Absent" in workflow
    assert "InstallSystem" not in workflow and "RecoveryPurge" not in workflow


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} Cursor read-only contract groups")
