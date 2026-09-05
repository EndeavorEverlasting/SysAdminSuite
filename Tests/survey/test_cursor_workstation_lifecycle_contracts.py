#!/usr/bin/env python3
"""Dependency-free contracts for the Cursor workstation lifecycle lane."""

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
SKILL = ROOT / ".claude/skills/developer-workstation/SKILL.md"
WORKFLOW = ROOT / ".github/workflows/cursor-workstation-lifecycle.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required Cursor lifecycle file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def test_profile_and_schema_contract() -> None:
    profile = load_json(PROFILE)
    schema = load_json(SCHEMA)

    assert profile["schema_version"] == "sas-cursor-workstation-profile/v1"
    assert profile["schema_path"] == "schemas/harness/cursor-workstation-profile.schema.json"
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == profile["schema_path"]
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "schema_version",
        "schema_path",
        "application",
        "installation",
        "state",
        "evidence",
        "posture",
    }
    assert {"tokenizedPath", "tokenizedPathList"} <= set(schema["$defs"])

    app = profile["application"]
    assert app["name"] == "Cursor"
    assert app["publisher"] == "Anysphere"
    assert app["official_download_url"] == "https://cursor.com/download"
    assert "Cursor.exe" in app["process_names"]
    re.compile(app["display_name_regex"])

    install = profile["installation"]
    re.compile(install["system_installer_filename_regex"])
    re.compile(install["user_installer_filename_regex"])
    assert "Anysphere" in install["authenticode_subject_regex"]
    assert {row["scope"] for row in install["uninstall_registry_roots"]} == {
        "user",
        "machine64",
        "machine32",
    }

    posture = profile["posture"]
    assert posture == {
        "system_install_required": True,
        "normal_uninstall_preserves_user_state": True,
        "recovery_purge_requires_explicit_mutation": True,
        "state_purge_requires_explicit_switch": True,
        "settings_restore_after_smoke_test_only": True,
        "local_audit_precedes_external_outage_assumption": True,
        "package_manager_required": False,
    }
    assert profile["evidence"]["tracked_runtime_evidence_allowed"] is False

    serialized = json.dumps(profile)
    assert "CheeksMcClappeth" not in serialized
    assert "C:\\\\Users\\\\" not in serialized

    tokenized_paths = (
        install["machine_install_roots"]
        + install["user_install_roots"]
        + install["cli_path_templates"]
        + profile["state"]["user_state_roots"]
        + profile["state"]["shortcut_roots"]
        + [profile["evidence"]["local_output_root"]]
    )
    for value in tokenized_paths:
        assert value.startswith("{"), f"machine-local path must be tokenized: {value}"


def test_engine_mutation_and_scope_contract() -> None:
    text = read(SCRIPT)

    for marker in (
        "SupportsShouldProcess = $true",
        "ConfirmImpact = 'High'",
        "'Audit', 'InstallSystem', 'Uninstall', 'RecoveryPurge', 'Verify'",
        "[switch]$AllowMutation",
        "[switch]$PurgeUserState",
        "Get-SasObjectPropertyValue",
        "Assert-MutationAuthorized",
        "Assert-Administrator",
        "Get-AuthenticodeSignature",
        "Get-FileHash",
        "authenticode_subject_regex",
        "user_installer_filename_regex",
        "Get-CursorUninstallEntries",
        "Get-CursorProcesses",
        "Remove-CursorRegistryRegistrations",
        "Remove-CursorCliPathEntries",
        "Remove-CursorUserState",
        "Test-CursorAbsent",
        "Test-CursorCanonicalSystemInstall",
        "UserStatePreserved = $true",
        "VERIFIED_ABSENT",
        "VERIFIED_SYSTEM",
        "PURGED_WITH_USER_STATE",
        "PURGED_INSTALL_ONLY",
    ):
        assert marker in text, f"Cursor engine missing contract marker: {marker}"

    lowered = text.lower()
    for forbidden in ("invoke-expression", "winget", "chocolatey", " choco "):
        assert forbidden not in lowered, f"Cursor engine must not use {forbidden.strip()}"

    assert "Remove-EventLog" not in text
    assert "Clear-EventLog" not in text
    assert "git clean" not in lowered
    assert "git reset" not in lowered

    purge_block = text[text.index("'RecoveryPurge' {") : text.index("$result = [ordered]@{")]
    assert "if ($PurgeUserState)" in purge_block
    assert "Remove-CursorUserState" in purge_block


def test_progressive_disclosure_and_incident_doctrine() -> None:
    doc = read(DOC)
    skill = read(SKILL)

    for marker in (
        "progressive-disclosure authority",
        "unins000.dat",
        "Error 32",
        "more than one Cursor registration",
        "system installer",
        "reboot Windows",
        "Verify -ExpectedState Absent",
        "Verify -ExpectedState System",
        "restoring settings, extensions, settings sync",
        "do not derail the operator into server-status speculation",
        "RecoveryPurge",
        "-PurgeUserState",
        "working GUI is not proof that vendor services are healthy",
    ):
        assert marker in doc, f"Cursor doctrine missing anti-regression marker: {marker}"

    assert "docs/CURSOR_WORKSTATION_LIFECYCLE.md" in skill
    assert "Manage-Cursor.cmd" in skill
    assert "unins000.dat" in skill and "Error 32" in skill
    assert "inventory local registrations/install roots/processes/CLI state" in skill
    assert "do not reinvent a one-off purge snippet" in skill
    assert "user-scoped build" in skill
    assert "vendor outage" in skill


def test_launcher_is_thin_product_front_door() -> None:
    text = read(LAUNCHER)
    assert "scripts\\Invoke-SasCursorWorkstation.ps1" in text
    assert "pwsh.exe" in text
    assert "powershell.exe" in text
    assert "%*" in text
    assert "docs\\CURSOR_WORKSTATION_LIFECYCLE.md" in text
    assert "Remove-Item" not in text
    assert "reg delete" not in text.lower()


def test_ci_contract_is_windows_executable_and_read_only() -> None:
    text = read(WORKFLOW)
    assert "windows-latest" in text
    assert "ubuntu-latest" in text
    assert "test_cursor_workstation_lifecycle_contracts.py" in text
    assert "Invoke-SasCursorWorkstation.ps1" in text
    assert "-Action Audit" in text
    assert "-Action Verify" in text
    assert "-ExpectedState Absent" in text
    assert "Parser]::ParseFile" in text
    assert "-Action InstallSystem" not in text
    assert "-Action Uninstall" not in text
    assert "-Action RecoveryPurge" not in text
    assert "-AllowMutation" not in text


def main() -> int:
    tests = [
        test_profile_and_schema_contract,
        test_engine_mutation_and_scope_contract,
        test_progressive_disclosure_and_incident_doctrine,
        test_launcher_is_thin_product_front_door,
        test_ci_contract_is_windows_executable_and_read_only,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} Cursor workstation lifecycle contract groups")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
