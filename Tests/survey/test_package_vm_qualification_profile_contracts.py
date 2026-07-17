#!/usr/bin/env python3
"""Contracts for package-specific disposable-VM qualification profiles."""
from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import traceback
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


def ready_profile() -> dict:
    profile = copy.deepcopy(load(SAMPLE))
    profile["package_family"] = "generic_windows_application"
    selector = profile["package_selector"]
    selector["trust_result_reference"] = "survey/output/package-analysis/sample/package_trust_verification.json"
    selector["revocation_result_reference"] = "survey/output/package-analysis/sample/package_revocation_verification.json"
    prerequisite = profile["prerequisite_evidence"]
    prerequisite["offline_trust_complete"] = True
    prerequisite["online_revocation_status"] = "verified"
    prerequisite["managed_code_present"] = False
    prerequisite["strong_name_status"] = "not_applicable"
    prerequisite["msi_present"] = False
    prerequisite["msi_decode_status"] = "not_applicable"
    prerequisite["sapien_detected"] = False
    prerequisite["sapien_payload_status"] = "not_applicable"
    profile["trust_policy"] = {
        "package_family_policy_required": True,
        "policy_status": "approved",
        "policy_reference": "survey/output/package-analysis/sample/package_trust_policy.json",
    }
    profile["guest"]["provider"] = "hyper_v"
    profile["execution_contract"].update({
        "installer_type": "exe",
        "supported_arguments_source": "vendor_documentation",
        "supported_arguments": ["/quiet"],
        "reboot_expected": "possible",
        "execution_authorized": True,
        "authorization_reference": "change-record-0001",
    })
    profile["acceptance"]["criteria_status"] = "approved"
    profile["decision"]["status"] = "ready_for_authorized_vm_run"
    profile["decision"]["blockers"] = []
    return profile


def test_schema_and_sample_are_closed_and_blocked() -> None:
    schema, sample = load(SCHEMA), load(SAMPLE)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == "schemas/harness/package-vm-qualification-profile.schema.json"
    assert schema["additionalProperties"] is False
    assert sample["schema_version"] == "sas-package-vm-qualification-profile/v2"
    assert sample["package_family"] == "allscripts"
    assert sample["trust_policy"]["policy_status"] == "missing"
    assert sample["decision"]["status"] == "blocked"
    assert sample["decision"]["vm_started"] is False
    assert sample["decision"]["package_executed"] is False
    for blocker in (
        "trust_policy_missing", "online_revocation_unproven", "strong_name_unproven",
        "msi_decode_incomplete", "exact_sapien_payload_unrecovered",
    ):
        assert blocker in sample["decision"]["blockers"]


def test_blocked_sample_validates_without_claiming_runtime() -> None:
    completed = run_profile(load(SAMPLE))
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "status=blocked" in completed.stdout
    assert "no VM or package execution performed" in completed.stdout


def test_derived_evidence_blockers_cannot_be_removed_manually() -> None:
    for blocker in (
        "online_revocation_unproven", "strong_name_unproven",
        "msi_decode_incomplete", "exact_sapien_payload_unrecovered",
    ):
        candidate = copy.deepcopy(load(SAMPLE))
        candidate["decision"]["blockers"].remove(blocker)
        completed = run_profile(candidate)
        assert completed.returncode != 0
        assert "decision_blockers_mismatch" in completed.stderr
        assert blocker in completed.stderr


def test_completed_evidence_requires_canonical_result_references() -> None:
    candidate = copy.deepcopy(load(SAMPLE))
    candidate["prerequisite_evidence"]["strong_name_status"] = "verified"
    candidate["decision"]["blockers"].remove("strong_name_unproven")
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "strong_name_result_reference_must_be_canonical_repo_reference" in completed.stderr

    candidate = copy.deepcopy(load(SAMPLE))
    candidate["prerequisite_evidence"]["msi_decode_status"] = "complete"
    candidate["decision"]["blockers"].remove("msi_decode_incomplete")
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "deep_analysis_result_reference_must_be_canonical_repo_reference" in completed.stderr


def test_not_applicable_statuses_must_match_detected_package_shape() -> None:
    candidate = copy.deepcopy(load(SAMPLE))
    candidate["prerequisite_evidence"]["managed_code_present"] = False
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "strong_name_status_must_be_not_applicable_without_managed_code" in completed.stderr

    candidate = copy.deepcopy(load(SAMPLE))
    candidate["prerequisite_evidence"]["msi_present"] = False
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "msi_decode_status_must_be_not_applicable_without_msi" in completed.stderr


def test_ready_profile_requires_every_derived_gate() -> None:
    candidate = ready_profile()
    completed = run_profile(candidate)
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "status=ready_for_authorized_vm_run" in completed.stdout

    candidate = ready_profile()
    candidate["prerequisite_evidence"]["online_revocation_status"] = "indeterminate"
    candidate["package_selector"]["revocation_result_reference"] = None
    completed = run_profile(candidate)
    assert completed.returncode != 0
    assert "decision_blockers_mismatch" in completed.stderr
    assert "online_revocation_unproven" in completed.stderr


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


def test_api_docs_skill_and_ci_are_wired() -> None:
    operation = load(API)["operation"]
    assert operation["id"] == "package_analysis.vm_qualification_profile_validate"
    assert operation["mode"] == "local_read"
    for field in ("network_activity", "target_mutation", "package_execution", "vm_start"):
        assert operation[field] is False
    assert "derived_evidence_blockers_must_match_profile" in operation["guardrails"]
    assert operation["proof_ceiling"] == "qualification_profile_only_no_vm_or_package_execution"

    skill = SKILL.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    doc_lower = doc.lower()
    workflow = WORKFLOW.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    for marker in (
        "package-vm-qualification-profile.schema.json",
        "validate_vm_qualification_profile.py",
        "PACKAGE_VM_QUALIFICATION_PROFILES.md",
    ):
        assert marker in skill
    for marker in ("derived blockers", "online revocation", "strong-name", "sapien", "msi", "autologon"):
        assert marker in doc_lower
    assert "test_package_vm_qualification_profile_contracts.py" in workflow
    assert "test_package_vm_qualification_profile_contracts.py" in runner


def test_jsonschema_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load(SAMPLE), load(SCHEMA))
    jsonschema.validate(ready_profile(), load(SCHEMA))


def main() -> None:
    tests = [
        test_schema_and_sample_are_closed_and_blocked,
        test_blocked_sample_validates_without_claiming_runtime,
        test_derived_evidence_blockers_cannot_be_removed_manually,
        test_completed_evidence_requires_canonical_result_references,
        test_not_applicable_statuses_must_match_detected_package_shape,
        test_ready_profile_requires_every_derived_gate,
        test_runtime_and_machine_local_claims_are_rejected,
        test_api_docs_skill_and_ci_are_wired,
        test_jsonschema_when_available,
    ]
    diagnostic_lines: list[str] = []
    diagnostic_path = os.environ.get("SAS_VM_QUALIFICATION_DIAGNOSTIC")
    for item in tests:
        start = f"RUN: {item.__name__}"
        print(start, flush=True)
        diagnostic_lines.append(start)
        try:
            item()
        except Exception:
            failure = f"FAIL: {item.__name__}\n{traceback.format_exc()}"
            print(failure, file=sys.stderr, flush=True)
            diagnostic_lines.append(failure)
            if diagnostic_path:
                Path(diagnostic_path).write_text("\n".join(diagnostic_lines) + "\n", encoding="utf-8")
            raise
        passed = f"PASS: {item.__name__}"
        print(passed, flush=True)
        diagnostic_lines.append(passed)
    summary = f"PASS: {len(tests)} package VM qualification profile contracts"
    print(summary)
    diagnostic_lines.append(summary)
    if diagnostic_path:
        Path(diagnostic_path).write_text("\n".join(diagnostic_lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
