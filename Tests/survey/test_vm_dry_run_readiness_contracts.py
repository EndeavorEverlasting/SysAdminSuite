#!/usr/bin/env python3
"""Executable and static contracts for offline VM dry-run readiness."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Test-SasVmDryRunReadiness.ps1"
PROFILE = ROOT / "harness" / "e2e" / "vm-dry-run-readiness.json"
PROFILE_SCHEMA = ROOT / "schemas" / "harness" / "vm-dry-run-readiness.schema.json"
RESULT_SCHEMA = ROOT / "schemas" / "harness" / "harness-proof-result.schema.json"
OUTPUT = ROOT / "survey" / "output" / "vm-dry-run-readiness-contract"


def powershell() -> str:
    command = shutil.which("pwsh") or shutil.which("powershell.exe") or shutil.which("powershell")
    assert command, "PowerShell runtime required for VM dry-run readiness contracts"
    return command


def run_readiness(*extra: str, output_name: str) -> subprocess.CompletedProcess[str]:
    output_root = OUTPUT / output_name
    return subprocess.run(
        [
            powershell(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(SCRIPT),
            "-OutputRoot",
            str(output_root),
            *extra,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def load_result(output_name: str) -> dict[str, Any]:
    path = OUTPUT / output_name / "vm_dry_run_readiness_result.json"
    assert path.is_file(), "VM readiness validator did not emit JSON"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate_harness_result(result: dict[str, Any]) -> None:
    schema = json.loads(RESULT_SCHEMA.read_text(encoding="utf-8"))
    required = set(schema["required"])
    assert required <= set(result)
    assert set(result) <= set(schema["properties"])
    assert result["schema_version"] == "sas-harness-proof/v1"
    assert result["proof_level"] == "synthetic_offline"
    for field in (
        "runtime_proof",
        "network_activity_performed",
        "launcher_execution_performed",
        "target_mutation_performed",
        "data_mutation_performed",
    ):
        assert result[field] is False, f"{field} must remain false"
    expected_counts = {
        "passed": sum(item["status"] == "PASS" for item in result["checks"]),
        "skipped": sum(item["status"] == "SKIP" for item in result["checks"]),
        "failed": sum(item["status"] == "FAIL" for item in result["checks"]),
    }
    assert result["counts"] == expected_counts


def test_profile_is_closed_and_fail_safe() -> None:
    profile = json.loads(PROFILE.read_text(encoding="utf-8"))
    schema = json.loads(PROFILE_SCHEMA.read_text(encoding="utf-8"))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] is False
    assert profile["schema_version"] == "sas-vm-dry-run-readiness/v1"
    assert profile["proof_class"] == "synthetic_offline_vm_readiness"
    assert profile["proof_ceiling"] == "readiness_only_no_vm_started"
    safety = profile["safety"]
    for field in (
        "readiness_validator_starts_vm",
        "readiness_validator_executes_real_package",
        "readiness_validator_mutates_host",
        "readiness_validator_contacts_target",
        "readiness_validator_uses_external_network",
        "autologon_allowed",
    ):
        assert safety[field] is False
    for field in (
        "runtime_vm_must_be_disposable",
        "rollback_or_destroy_required",
        "one_package_per_clean_snapshot",
    ):
        assert safety[field] is True


def test_validator_has_no_vm_or_package_execution_surface() -> None:
    text = SCRIPT.read_text(encoding="utf-8-sig")
    required = [
        "VM DRY-RUN READINESS",
        "vm_provider_not_available",
        "request-only dry run",
        "runtime entry gate",
        "synthetic_offline",
        "runtime_proof = $false",
        "network_activity_performed = $false",
        "launcher_execution_performed = $false",
        "target_mutation_performed = $false",
        "data_mutation_performed = $false",
    ]
    for fragment in required:
        assert fragment in text, f"missing VM readiness contract: {fragment}"

    forbidden = [
        r"\bStart-VM\b",
        r"\bNew-VM\b",
        r"\bCheckpoint-VM\b",
        r"\bRestore-VMSnapshot\b",
        r"\bStart-Process\b",
        r"\bInvoke-Command\b",
        r"\bNew-PSSession\b",
        r"\bTest-NetConnection\b",
        r"\bInvoke-WebRequest\b",
        r"VBoxManage(?:\.exe)?\s+startvm",
        r"vmrun(?:\.exe)?\s+start",
    ]
    for pattern in forbidden:
        assert not re.search(pattern, text, re.IGNORECASE), f"forbidden execution surface: {pattern}"


def test_validator_prints_matrix_and_emits_honest_json() -> None:
    completed = run_readiness(output_name="success")
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "VM DRY-RUN READINESS" in completed.stdout
    assert "[PASS] VM dry-run profile" in completed.stdout
    assert "[PASS] fixture dry-run journeys" in completed.stdout
    assert "[PASS] request-only dry run" in completed.stdout
    assert "[PASS] runtime entry gate" in completed.stdout
    assert re.search(r"\[(PASS|SKIP)\] optional VM provider smoke", completed.stdout)
    assert re.search(r"Result: \d+ passed / \d+ skipped / 0 failed", completed.stdout)

    result = load_result("success")
    validate_harness_result(result)
    provider = next(item for item in result["checks"] if item["name"] == "optional VM provider smoke")
    assert provider["required"] is False
    assert provider["status"] in {"PASS", "SKIP"}
    if provider["status"] == "SKIP":
        assert provider["detail"] == "vm_provider_not_available"


def test_missing_profile_fails_clearly_and_still_emits_json() -> None:
    completed = run_readiness(
        "-ProfilePath",
        "harness/e2e/__missing_vm_dry_run_profile__.json",
        output_name="missing-profile",
    )
    assert completed.returncode != 0
    assert "[FAIL] required files - missing_required_path:" in completed.stdout
    result = load_result("missing-profile")
    validate_harness_result(result)
    assert result["counts"]["failed"] >= 1


if __name__ == "__main__":
    try:
        test_profile_is_closed_and_fail_safe()
        test_validator_has_no_vm_or_package_execution_surface()
        test_validator_prints_matrix_and_emits_honest_json()
        test_missing_profile_fails_clearly_and_still_emits_json()
    finally:
        shutil.rmtree(OUTPUT, ignore_errors=True)
