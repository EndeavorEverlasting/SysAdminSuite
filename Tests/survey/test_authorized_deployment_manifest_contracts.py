#!/usr/bin/env python3
"""Static contracts for the recovered PR #150 authorized-deployment manifest lane."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAuthorizedDeploymentManifest.ps1"
SCHEMA = ROOT / "schemas" / "harness" / "authorized-deployment-manifest.schema.json"
DOC = ROOT / "docs" / "AUTHORIZED_DEPLOYMENT_MANIFEST.md"
EXAMPLE = ROOT / "examples" / "authorized-deployment-manifest.example.json"
CANONICAL_INSTALLER = ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_files_exist_and_adapter_uses_canonical_engine() -> None:
    for path in (SCRIPT, SCHEMA, DOC, EXAMPLE, CANONICAL_INSTALLER):
        assert path.exists(), f"missing authorized deployment surface: {path}"
    content = read(SCRIPT)
    assert "Invoke-SasSoftwareInstall.ps1" in content
    assert "& $softwareInstallScript @invokeParameters" in content
    assert "New-PSSession" not in content
    assert "Copy-Item -LiteralPath" not in content
    assert "Start-Process" not in content


def test_manifest_is_bounded_and_mutation_is_explicit() -> None:
    content = read(SCRIPT)
    required = (
        "[ValidateRange(1, 25)]",
        "[ValidateRange(1, 100)]",
        "Unique target count",
        "Manifest row count",
        "-AllowTargetMutation",
        "Refusing target mutation without -AllowTargetMutation",
        "Use -WhatIf for request-only validation",
        "Assert-SasApprovedOutputPath",
    )
    for fragment in required:
        assert fragment in content, f"missing bounded manifest contract: {fragment}"


def test_approved_source_hash_and_argument_contracts() -> None:
    content = read(SCRIPT)
    required = (
        "approved_software_sources",
        "SoftwareShareRoot is not an approved software source",
        "InstallerRelativePath cannot contain parent-directory traversal",
        "Get-FileHash -LiteralPath $row.source_path -Algorithm SHA256",
        "HASH_MISMATCH",
        "InstallerArguments",
        "must be a JSON string array",
        "UncDirect",
        "does not yet prove staged-file SHA-256 verification before execution",
    )
    for fragment in required:
        assert fragment in content, f"missing source/hash contract: {fragment}"


def test_no_login_dependency_or_persistence_is_created() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    required = (
        "interactive_logon_required = $false",
        "public_startup_folder_used = $false",
        "service_created = $false",
        "scheduled_task_created = $false",
        "no_interactive_logon_dependency",
        "no_service_or_scheduled_task_persistence",
        "does not depend on an interactive desktop session",
    )
    combined = content + "\n" + doc
    for fragment in required:
        assert fragment in combined, f"missing pre-logon boundary: {fragment}"

    forbidden = (
        "New-Service",
        "sc.exe create",
        "Register-ScheduledTask",
        "New-ScheduledTask",
        "schtasks.exe",
        "CurrentVersion\\Run",
        "shell:startup",
        "Clear-EventLog",
        "wevtutil cl",
        "-Credential",
        "DefaultPassword",
    )
    for fragment in forbidden:
        assert fragment.lower() not in content.lower(), f"forbidden fragment present: {fragment}"


def test_schema_and_example_match_the_canonical_request_shape() -> None:
    schema = json.loads(read(SCHEMA))
    assert schema["title"] == "SysAdminSuite authorized deployment manifest"
    assert schema["maxItems"] == 100
    required = set(schema["items"]["required"])
    expected = {
        "TargetHostname",
        "PackageName",
        "SoftwareShareRoot",
        "InstallerRelativePath",
        "ExpectedSha256",
        "InstallerArguments",
        "InstallMode",
        "Owner",
        "RequestReference",
        "ChangeReference",
        "TicketReference",
    }
    assert required == expected
    assert schema["items"]["properties"]["InstallMode"]["enum"] == ["UncDirect"]
    assert schema["items"]["properties"]["InstallerArguments"]["type"] == "array"

    rows = json.loads(read(EXAMPLE))
    assert len(rows) == 1
    row = rows[0]
    assert row["SoftwareShareRoot"] == "\\\\nt2kwb972sms01\\"
    assert row["InstallerRelativePath"] == r"packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe"
    assert len(row["ExpectedSha256"]) == 64
    assert row["InstallMode"] == "UncDirect"


def test_docs_require_pilot_runtime_proof_before_expansion() -> None:
    content = read(DOC)
    required = (
        "Request-only validation",
        "Approved pilot execution",
        "Expansion gate",
        "no more than two approved pilot workstations",
        "vendor-validated arguments",
        "controlled reboot and observed automatic sign-in",
        "cleanup failure",
    )
    for fragment in required:
        assert fragment in content, f"missing runbook gate: {fragment}"


if __name__ == "__main__":
    test_files_exist_and_adapter_uses_canonical_engine()
    test_manifest_is_bounded_and_mutation_is_explicit()
    test_approved_source_hash_and_argument_contracts()
    test_no_login_dependency_or_persistence_is_created()
    test_schema_and_example_match_the_canonical_request_shape()
    test_docs_require_pilot_runtime_proof_before_expansion()
    print("PASS: 6 authorized deployment manifest contracts")
