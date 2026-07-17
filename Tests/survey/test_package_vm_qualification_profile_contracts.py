#!/usr/bin/env python3
"""Contracts for package-specific disposable-VM qualification profiles."""
from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schemas/harness/package-vm-qualification-profile.schema.json"
SAMPLE = ROOT / "Tests/Fixtures/package-vm-qualification/package-vm-qualification.blocked.sample.json"
VALIDATOR = ROOT / "tools/package-analysis/validate_vm_qualification_profile.py"
API = ROOT / "harness/api/package-vm-qualification-skill.json"
SKILL = ROOT / ".claude/skills/package-static-analysis/SKILL.md"
DOC = ROOT / "docs/PACKAGE_VM_QUALIFICATION_PROFILES.md"
WORKFLOW = ROOT / ".github/workflows/package-static-analysis.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def run_profile(profile: dict) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "profile.json"
        path.write_text(json.dumps(profile), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(VALIDATOR), "--profile", str(path)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )


def test_schema_and_sample_are_closed_and_blocked() -> None:
    schema, sample = load(SCHEMA), load(SAMPLE)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == "schemas/harness/package-vm-qualification-profile.schema.json"
    assert schema["additionalProperties"] is False
    assert sample["schema_version"] == "sas-package-vm-qualification-profile/v1"
    assert sample["package_family"] == "allscripts"
    assert sample["trust_policy"]["policy_status"] == "missing"
    assert sample["decision"]["status"] == "blocked"
    assert sample["decision"]["vm_started"] is False
    assert sample["decision"]["package_executed"] is False
    assert "trust_policy_missing" in sample["decision"]["blockers"]


def test_blocked_sample_validates_without_claiming_runtime() -> None:
    completed = run_profile(load(SAMPLE))
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "status=blocked" in completed.stdout
    assert "no VM or package execution performed" in completed.stdout


def test_allscripts_policy_and_authorization_fail_closed() -> None:
    sample = load(SAMPLE)
    candidate = copy.deepcopy(sample)
    candidate["decision"]["status"] = "ready_for_authorized_vm_run"
    candidate["decision"]["blockers"] = []
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert any(marker in completed.stderr for marker in (
        "allscripts_unapproved_policy_must_block",
        "allscripts_unapproved_policy_cannot_be_ready",
        "ready_status_without_complete_gates",
    ))

    candidate = copy.deepcopy(sample)
    candidate["execution_contract"]["execution_authorized"] = True
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "authorized_execution_requires_supported_arguments" in completed.stderr


def test_runtime_and_machine_local_claims_are_rejected() -> None:
    sample = load(SAMPLE)
    candidate = copy.deepcopy(sample)
    candidate["decision"]["vm_started"] = True
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "profile_cannot_claim_runtime_execution" in completed.stderr

    candidate = copy.deepcopy(sample)
    candidate["package_selector"]["static_result_reference"] = "C:\\Users\\operator\\package_analysis.json"
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "machine_local_value" in completed.stderr


def test_required_analysis_gaps_are_explicit() -> None:
    sample = load(SAMPLE)
    prerequisites = sample["prerequisite_evidence"]
    assert prerequisites["online_revocation_required_before_pilot"] is True
    assert prerequisites["strong_name_required_if_managed"] is True
    assert prerequisites["full_msi_decode_required_if_msi"] is True
    assert prerequisites["exact_sapien_payload_required_if_detected"] is True
    assert sample["guest"]["autologon_allowed"] is False
    assert sample["guest"]["one_package_per_snapshot"] is True
    assert sample["rollback"]["required"] is True


def test_api_docs_skill_and_ci_are_wired() -> None:
    operation = load(API)["operation"]
    assert operation["id"] == "package_analysis.vm_qualification_profile_validate"
    assert operation["mode"] == "local_read"
    for field in ("network_activity", "target_mutation", "package_execution", "vm_start"):
        assert operation[field] is False
    assert operation["proof_ceiling"] == "qualification_profile_only_no_vm_or_package_execution"

    skill = SKILL.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    for marker in (
        "package-vm-qualification-profile.schema.json",
        "validate_vm_qualification_profile.py",
        "PACKAGE_VM_QUALIFICATION_PROFILES.md",
    ):
        assert marker in skill
    for marker in ("Allscripts", "online revocation", "strong-name", "SAPIEN", "MSI", "AutoLogon"):
        assert marker in doc
    assert "test_package_vm_qualification_profile_contracts.py" in workflow
    assert "test_package_vm_qualification_profile_contracts.py" in runner


def test_jsonschema_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load(SAMPLE), load(SCHEMA))


def main() -> None:
    tests = [
        test_schema_and_sample_are_closed_and_blocked,
        test_blocked_sample_validates_without_claiming_runtime,
        test_allscripts_policy_and_authorization_fail_closed,
        test_runtime_and_machine_local_claims_are_rejected,
        test_required_analysis_gaps_are_explicit,
        test_api_docs_skill_and_ci_are_wired,
        test_jsonschema_when_available,
    ]
    for item in tests:
        item()
    print(f"PASS: {len(tests)} package VM qualification profile contracts")


if __name__ == "__main__":
    main()
