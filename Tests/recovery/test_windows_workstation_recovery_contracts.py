import json
import re
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
COLLECTOR = ROOT / "recovery/windows/Get-SasWindowsRecoveryEvidence.ps1"
COMMON = ROOT / "recovery/windows/SasWindowsRecovery.Common.psm1"
STALL = ROOT / "recovery/windows/Test-SasDismActivity.ps1"
REPAIR = ROOT / "recovery/windows/Repair-SasWindowsIntegrity.ps1"
DOC = ROOT / "recovery/windows/README.md"
SCHEMA = ROOT / "schemas/harness/windows-workstation-recovery-evidence.schema.json"
FIXTURE = ROOT / "Tests/Fixtures/windows-recovery/healthy.json"
BEHAVIOR = ROOT / "Tests/recovery/Test-WindowsRecoveryBehavior.ps1"
RUNNER = ROOT / "scripts/Test-SasWindowsRecoveryFloor.ps1"
REQUIREMENTS = ROOT / "requirements-test.txt"
WORKFLOW = ROOT / ".github/workflows/windows-workstation-recovery-proof.yml"
FRONT = ROOT / "Inspect-WindowsWorkstationRecovery.cmd"
START = ROOT / "START-HERE-WINDOWS-WORKSTATION-RECOVERY.md"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_fixture_matches_schema_and_is_sanitized():
    schema = json.loads(read(SCHEMA))
    fixture = json.loads(read(FIXTURE))
    jsonschema.Draft202012Validator(schema).validate(fixture)
    assert fixture["proof"]["destructive_actions_performed"] is False
    assert all(m.get("disk_serial") is None for m in fixture["storage"]["drive_mappings"])
    assert fixture["backup"]["identity"]["distinct_physical_disk"] is True
    assert fixture["backup"]["identity"]["expectations_pinned"] is True


def test_test_dependencies_are_declared_and_version_pinned():
    lines = [line.strip() for line in read(REQUIREMENTS).splitlines() if line.strip() and not line.startswith("#")]
    assert any(line.startswith("pytest==") for line in lines)
    assert any(line.startswith("jsonschema==") for line in lines)
    for line in lines:
        requirement = line.split(";", 1)[0].strip()
        assert "==" in requirement, f"unversioned test dependency: {line}"


def test_collector_uses_executable_helpers_and_fails_closed_on_identity():
    text = read(COLLECTOR)
    lowered = text.lower()
    assert "saswindowsrecovery.common.psm1" in lowered
    assert "test-sasbackuptargetidentity" in lowered
    assert "invoke-sasnativecapture" in lowered
    assert "get-sasdeepstoragepaths" in lowered
    assert "safe_pinned" in lowered and "safe_unpinned" in lowered
    assert "wbadmin.exe" in lowered and "windowsimagebackup" in lowered
    for forbidden in (
        "format-volume",
        "clear-disk",
        "remove-item",
        "stop-process",
        "diskpart",
        "wbadmin.exe start backup",
        "powercfg /h off",
        "vssadmin delete",
        "chkdsk.exe /f",
        "'c:\\users'",
        "'c:\\windows'",
    ):
        assert forbidden not in lowered, forbidden
    assert ".adapterram" not in lowered


def test_common_helpers_cover_previous_false_green_seams():
    text = read(COMMON).lower()
    for required in (
        "invoke-sasnativecapture",
        "$erroractionpreference = 'continue'",
        "finally",
        "identity_unresolved",
        "target_not_mounted",
        "unsafe_same_physical_disk",
        "get-sasdeepstoragepaths",
        "convert-sasdismhealthstate",
        "raw_output_captured_not_locale_normalized",
    ):
        assert required in text, required

    behavior = read(BEHAVIOR).lower()
    for required in (
        "missing system mapping degrades without throwing",
        "system-drive windows path",
        "native stderr command exit code",
        "fixture-error",
        "dism repairable enum",
    ):
        assert required in behavior, required


def test_repair_apply_is_profile_gated_and_network_closed():
    text = read(REPAIR).lower()
    assert "[switch]$apply" in text
    assert "blocked_profile_authority_unavailable" in text
    assert "mutation_performed = $false" in text
    assert "network_access_attempted = $false" in text
    assert "/limitaccess" in text
    assert "approved-local-source" in text
    assert "exit 3" in text
    for forbidden in ("invoke-repairstep", "stop-process", "format-volume", "clear-disk", "vssadmin delete"):
        assert forbidden not in text


def test_dism_sampler_never_terminates_servicing():
    text = read(STALL).lower()
    for required in ("dismhost", "tiworker", "trustedinstaller", "start-sleep", "bytes_added", "cpu_delta_seconds"):
        assert required in text
    for forbidden in ("stop-process", "taskkill", "kill(", "terminateprocess"):
        assert forbidden not in text
    assert "static percentage" in text


def test_canonical_runner_prevents_silent_skip_and_emits_candidate_sha():
    text = read(RUNNER).lower()
    assert "candidate_sha=" in text
    assert "@('-c', $reporoot, 'rev-parse', 'head')" in text
    assert "pytest" in text
    assert "test-windowsrecoverybehavior.ps1" in text
    assert "blocked_profile_authority_unavailable" in text
    assert "assert-exitcode -expected 3" in text
    assert "windows_recovery_test_floor=pass" in text
    assert "unable to resolve the active powershell executable" in text


def test_workflow_only_orchestrates_the_canonical_floor():
    workflow = read(WORKFLOW).lower()
    assert "permissions:" in workflow and "contents: read" in workflow
    assert "concurrency:" in workflow
    assert "pull_request:" in workflow and "push:" in workflow and "workflow_dispatch:" in workflow
    assert "requirements-test.txt" in workflow
    assert "test-saswindowsrecoveryfloor.ps1" in workflow
    assert "3.12.8" in workflow
    assert "shell: powershell" in workflow
    assert "parser]::parsefile" not in workflow
    assert "convertfrom-json" not in workflow


def test_entrypoints_docs_and_floor_are_discoverable():
    assert FRONT.exists() and START.exists() and RUNNER.exists() and BEHAVIOR.exists()
    front = read(FRONT).lower()
    assert "get-saswindowsworkstationrecoveryevidence.ps1" not in front
    assert "get-saswindowsrecoveryevidence.ps1" in front
    doc = read(DOC).lower()
    for required in (
        "drive letters",
        "not identities",
        "bare-metal restore test",
        "static dism percentage",
        "reparse points",
        "pagefile",
        "hibernation",
        "active repositories",
        "adapterram",
        "exact module count",
        "proof levels",
        "test-saswindowsrecoveryfloor.ps1",
        "profile authority",
        "/limitaccess",
    ):
        assert required in doc, required
    assert "recovery/systemrescue" in doc


def test_cmd_launcher_propagates_collector_exit_status():
    text = read(FRONT).lower()
    assert "if errorlevel 1 goto use_windows_powershell" in text
    assert text.count("exit /b %errorlevel%") == 2
    assert not re.search(r"if\s+%errorlevel%", text)
