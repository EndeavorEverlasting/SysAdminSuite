import json
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
COLLECTOR = ROOT / "recovery/windows/Get-SasWindowsRecoveryEvidence.ps1"
STALL = ROOT / "recovery/windows/Test-SasDismActivity.ps1"
REPAIR = ROOT / "recovery/windows/Repair-SasWindowsIntegrity.ps1"
DOC = ROOT / "recovery/windows/README.md"
SCHEMA = ROOT / "schemas/harness/windows-workstation-recovery-evidence.schema.json"
FIXTURE = ROOT / "Tests/Fixtures/windows-recovery/healthy.json"
WORKFLOW = ROOT / ".github/workflows/windows-workstation-recovery-proof.yml"
FRONT = ROOT / "Inspect-WindowsWorkstationRecovery.cmd"
START = ROOT / "START-HERE-WINDOWS-WORKSTATION-RECOVERY.md"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_fixture_matches_schema():
    schema = json.loads(read(SCHEMA))
    fixture = json.loads(read(FIXTURE))
    jsonschema.Draft202012Validator(schema).validate(fixture)
    assert fixture["proof"]["destructive_actions_performed"] is False
    assert all(m.get("disk_serial") is None for m in fixture["storage"]["drive_mappings"])


def test_collector_is_evidence_first_and_identity_aware():
    text = read(COLLECTOR)
    lowered = text.lower()
    for required in (
        "get-volume", "get-partition", "get-disk", "get-physicaldisk",
        "get-storagereliabilitycounter", "wbadmin.exe", "'get', 'versions'", "'get', 'items'",
        "windowsimagebackup", "reagentc.exe", "win32_physicalmemory",
        "configuredclockspeed", "partnumber", "win32_bios", "checkhealth",
        "scanhealth", "/verifyonly", "deepstorage"
    ):
        assert required in lowered, required
    for forbidden in (
        "format-volume", "clear-disk", "remove-item", "stop-process", "diskpart",
        "wbadmin.exe start backup", "powercfg /h off", "vssadmin delete", "chkdsk.exe /f"
    ):
        assert forbidden not in lowered, forbidden
    assert ".adapterram" not in lowered
    assert "adapterram =" not in lowered
    assert "includeserials" in lowered


def test_dism_sampler_never_terminates_servicing():
    text = read(STALL).lower()
    for required in ("dismhost", "tiworker", "trustedinstaller", "start-sleep", "bytes_added", "cpu_delta_seconds"):
        assert required in text
    for forbidden in ("stop-process", "taskkill", "kill(", "terminateprocess"):
        assert forbidden not in text
    assert "static percentage" in text


def test_integrity_repair_is_explicit_and_fail_closed():
    text = read(REPAIR).lower()
    assert "[switch]$apply" in text
    assert "restorehealth" in text
    assert "/scannow" in text
    assert "scanhealth" in text
    assert "/verifyonly" in text
    assert "sfc was not started" in text
    assert "component store is repairable" in text
    for forbidden in ("format-volume", "clear-disk", "remove-item", "stop-process", "chkdsk /f", "vssadmin delete"):
        assert forbidden not in text


def test_docs_capture_field_lessons_and_proof_ceiling():
    text = read(DOC).lower()
    for required in (
        "drive letters", "not identities", "bare-metal restore test", "static dism percentage",
        "reparse points", "pagefile", "hibernation", "active repositories", "adapterram",
        "component store is repairable", "exact module count", "proof levels"
    ):
        assert required in text, required
    assert "recovery/systemrescue" in text


def test_entrypoints_and_workflow_are_wired():
    assert FRONT.exists()
    assert START.exists()
    front = read(FRONT).lower()
    assert "get-saswindowsrecoveryevidence.ps1" in front
    workflow = read(WORKFLOW).lower()
    assert "test_windows_workstation_recovery_contracts.py" in workflow
    assert "healthy.json" in workflow
    assert "parser]::parsefile" in workflow
