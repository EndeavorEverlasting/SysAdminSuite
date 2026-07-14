#!/usr/bin/env python3
"""Static contracts for the AutoLogon final-step gate."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonFinalStepGate.ps1"
DOC = ROOT / "docs" / "AUTOLOGON_FINAL_STEP_CONTRACT.md"
PESTER = ROOT / "Tests" / "Pester" / "AutoLogonFinalStepGate.Tests.ps1"
CATALOG = ROOT / "configs" / "software-packages" / "approved-apps.json"
FIXTURES = ROOT / "Tests" / "Fixtures" / "autologon_final_step"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


# ── File existence contracts ───────────────────────────────────────────

def test_gate_script_exists():
    assert SCRIPT.exists(), "missing Invoke-SasAutoLogonFinalStepGate.ps1"


def test_gate_doc_exists():
    assert DOC.exists(), "missing AUTOLOGON_FINAL_STEP_CONTRACT.md"


def test_gate_pester_exists():
    assert PESTER.exists(), "missing AutoLogonFinalStepGate.Tests.ps1"


def test_fixtures_exist():
    for name in (
        "approved-apps-valid.json",
        "approved-apps-empty.json",
        "approved-apps-disabled.json",
        "run_manifest_before_valid.json",
        "run_manifest_before_wrong_phase.json",
        "run_manifest_before_wrong_runid.json",
    ):
        assert (FIXTURES / name).exists(), f"missing fixture: {name}"


# ── Script structure contracts ─────────────────────────────────────────

def test_gate_script_has_fail_closed_behavior():
    content = read(SCRIPT)
    for fragment in (
        "Set-StrictMode -Version 2.0",
        "$ErrorActionPreference = 'Stop'",
        "gate_id",
        "gate_version",
        "overall_pass",
        "blocked_reason",
    ):
        assert fragment in content, f"missing gate contract: {fragment}"


def test_gate_script_checks_four_mandatory_prerequisites():
    content = read(SCRIPT)
    for prereq_id in (
        "run_id_format",
        "host_eligibility",
        "approved_catalog",
        "before_snapshot",
    ):
        assert f"'{prereq_id}'" in content or f'"{prereq_id}"' in content, \
            f"missing mandatory prerequisite: {prereq_id}"


def test_gate_script_checks_two_recommended_prerequisites():
    content = read(SCRIPT)
    for prereq_id in ("runtime_proof", "file_access_posture"):
        assert f"'{prereq_id}'" in content or f'"{prereq_id}"' in content, \
            f"missing recommended prerequisite: {prereq_id}"


def test_gate_script_never_exposes_default_password():
    content = read(SCRIPT)
    forbidden = (
        "Get-RegistryValueSafe -Path $winlogonPath -Name 'DefaultPassword'",
        "Get-ItemPropertyValue -Path $winlogonPath -Name 'DefaultPassword'",
        "default_password =",
        "password_value =",
    )
    for frag in forbidden:
        assert frag not in content, f"gate script must not read DefaultPassword: {frag}"


def test_gate_script_has_no_override_path():
    content = read(SCRIPT)
    for fragment in ("-Force", "FORCE", "override", "bypass", "skip_gate"):
        assert fragment not in content, f"gate script must not have override: {fragment}"


def test_gate_script_validates_run_id_format():
    content = read(SCRIPT)
    assert "autologon-delta-" in content, "gate must validate autologon-delta run ID format"


def test_gate_script_writes_structured_json():
    content = read(SCRIPT)
    assert "ConvertTo-Json" in content, "gate must produce JSON output"
    assert "autologon_final_step_gate.json" in content, "gate must write named output file"


def test_gate_script_records_timestamp():
    content = read(SCRIPT)
    assert "timestamp_utc" in content, "gate must record UTC timestamp"


def test_gate_script_records_technician_label():
    content = read(SCRIPT)
    assert "technician_label" in content, "gate must record technician label"


def test_gate_script_records_fixture_mode():
    content = read(SCRIPT)
    assert "fixture_mode" in content, "gate must record fixture mode flag"


def test_gate_script_records_exec_context():
    content = read(SCRIPT)
    assert "exec_context" in content, "gate must record execution context in result"


def test_gate_script_has_exec_context_parameter():
    content = read(SCRIPT)
    assert "ExecContext" in content, "gate must accept ExecContext parameter"
    assert "ValidateSet" in content, "gate must validate ExecContext values"


# ── Catalog fixture contracts ──────────────────────────────────────────

def test_valid_catalog_fixture_is_well_formed():
    catalog = load_json(FIXTURES / "approved-apps-valid.json")
    assert catalog["schema_version"] == "sas-approved-software-catalog/v1"
    autologon = next(p for p in catalog["packages"] if p["id"] == "autologon")
    assert autologon["install_enabled"] is True
    assert autologon["installer_file"] == "NW_AutoLogon_Setup_x64.exe"


def test_empty_catalog_fixture_has_no_packages():
    catalog = load_json(FIXTURES / "approved-apps-empty.json")
    assert len(catalog["packages"]) == 0


def test_disabled_catalog_fixture_has_install_enabled_false():
    catalog = load_json(FIXTURES / "approved-apps-disabled.json")
    autologon = next(p for p in catalog["packages"] if p["id"] == "autologon")
    assert autologon["install_enabled"] is False


def test_valid_before_snapshot_fixture_is_well_formed():
    snapshot = load_json(FIXTURES / "run_manifest_before_valid.json")
    assert snapshot["run_id"] == "autologon-delta-20260714-143000-1a2b3c4d"
    assert snapshot["phase"] == "before_complete"
    assert len(snapshot["targets"]) == 2


def test_wrong_runid_snapshot_fixture_has_different_run_id():
    snapshot = load_json(FIXTURES / "run_manifest_before_wrong_runid.json")
    assert snapshot["run_id"] == "autologon-delta-20260714-999999-ffffffff"


def test_wrong_phase_snapshot_fixture_has_in_progress_phase():
    snapshot = load_json(FIXTURES / "run_manifest_before_wrong_phase.json")
    assert snapshot["phase"] == "in_progress"


# ── Doc contracts ──────────────────────────────────────────────────────

def test_doc_defines_failure_classifications():
    content = read(DOC)
    assert "Failure classifications" in content, "doc must define failure classifications"
    for prereq_id in ("run_id_format", "host_eligibility", "approved_catalog", "before_snapshot"):
        assert prereq_id in content, f"doc must classify failure for {prereq_id}"


def test_doc_defines_integration_sequence():
    content = read(DOC)
    assert "Integration sequence" in content, "doc must define integration sequence"
    assert "FINAL-STEP GATE" in content, "doc must identify the gate step"


def test_doc_states_no_override():
    content = read(DOC)
    assert "no override" in content.lower() or "no -Force" in content or "There is no override" in content, \
        "doc must state there is no override"


def test_doc_states_never_reads_default_password():
    content = read(DOC)
    assert "DefaultPassword" in content
    assert "never reads DefaultPassword" in content.lower() or "never reads" in content.lower(), \
        "doc must state it never reads DefaultPassword"


def test_doc_states_fail_closed():
    content = read(DOC)
    assert "fail-closed" in content.lower() or "fail closed" in content.lower(), \
        "doc must state fail-closed behavior"


# ── Pester test contracts ─────────────────────────────────────────────

def test_pester_tests_exist():
    content = read(PESTER)
    assert "Describe" in content
    assert "Invoke-SasAutoLogonFinalStepGate" in content


def test_pester_tests_cover_mandatory_failures():
    content = read(PESTER)
    for scenario in (
        "malformed run ID",
        "approved apps catalog is missing",
        "no autologon package",
        "install_enabled is false",
        "Before snapshot is missing",
        "wrong run ID",
        "wrong phase",
        "target is not in Before snapshot",
    ):
        assert scenario.lower() in content.lower(), \
            f"pester tests must cover: {scenario}"


def test_pester_tests_cover_passing_case():
    content = read(PESTER)
    assert "all mandatory prerequisites are satisfied" in content.lower() or \
        "passes when all mandatory" in content.lower(), \
        "pester tests must cover the passing case"


def test_pester_tests_cover_no_password_leak():
    content = read(PESTER)
    assert "DefaultPassword" in content, "pester tests must verify no password data leak"


def test_pester_tests_cover_prerequisite_count():
    content = read(PESTER)
    assert "6 prerequisites" in content or "6 prerequisites" in content.lower() or \
        "exactly 6" in content.lower(), \
        "pester tests must verify prerequisite count"


# ── Cross-reference contracts ──────────────────────────────────────────

def test_gate_references_state_delta_scripts():
    content = read(DOC)
    assert "Invoke-SasAutoLogonStateDelta" in content, "doc must reference state-delta collector"
    assert "Start-SasAutoLogonStateDelta" in content, "doc must reference state-delta launcher"


def test_gate_references_host_eligibility():
    content = read(DOC)
    assert "Test-SasHostEligibility" in content, "doc must reference host eligibility gate"


def test_gate_references_approved_software_catalog():
    content = read(DOC)
    assert "approved-apps.json" in content, "doc must reference approved software catalog"


def test_gate_references_software_install_harness():
    content = read(DOC)
    assert "Invoke-SasSoftwareInstall" in content, "doc must reference software install harness"


def test_script_references_approved_apps_path_parameter():
    content = read(SCRIPT)
    assert "ApprovedAppsPath" in content, "script must accept ApprovedAppsPath parameter"


def test_script_references_before_snapshot_path_parameter():
    content = read(SCRIPT)
    assert "BeforeSnapshotPath" in content, "script must accept BeforeSnapshotPath parameter"
