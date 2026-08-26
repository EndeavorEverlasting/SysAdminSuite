#!/usr/bin/env python3
"""Contracts for the one-command synthetic harness and VM dry-run proof."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "Invoke-SasVmDryRunHarnessProof.ps1"
BASE_VALIDATOR = ROOT / "scripts" / "validate-sysadmin-harness.ps1"
VM_VALIDATOR = ROOT / "scripts" / "Test-SasVmDryRunReadiness.ps1"
VM_PROFILE = ROOT / "harness" / "e2e" / "vm-dry-run-readiness.json"
CANONICAL_PATH = ROOT / "harness" / "api" / "canonical-path-registry.json"
CANONICAL_VALIDATOR = ROOT / "harness" / "validators" / "validate-canonical-path-contracts.py"
PROMPTS = ROOT / "docs" / "prompts.json"
SCHEMA = ROOT / "schemas" / "harness" / "harness-proof-result.schema.json"
VM_SCHEMA = ROOT / "schemas" / "harness" / "vm-dry-run-readiness.schema.json"
WORKFLOW = ROOT / ".github" / "workflows" / "one-command-harness-proof.yml"
OUTPUT = ROOT / "survey" / "output" / "harness-proof-contract"


def powershell() -> str:
    command = shutil.which("pwsh") or shutil.which("powershell.exe") or shutil.which("powershell")
    assert command, "PowerShell runtime required for synthetic harness proof contracts"
    return command


def run_validator(*extra: str, output_name: str) -> subprocess.CompletedProcess[str]:
    output_root = OUTPUT / output_name
    return subprocess.run(
        [
            powershell(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(VALIDATOR),
            "-OutputRoot",
            str(output_root),
            *extra,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def newest_result(output_name: str) -> dict[str, Any]:
    result = OUTPUT / output_name / "harness_validation_result.json"
    assert result.is_file(), "validator did not emit top-level harness_validation_result.json"
    return json.loads(result.read_text(encoding="utf-8-sig"))


def prompt_p11() -> dict[str, Any]:
    prompts = json.loads(PROMPTS.read_text(encoding="utf-8-sig"))
    matches = [item for item in prompts if item.get("id") == "P11"]
    assert len(matches) == 1, "canonical Prompt Kit registry must contain exactly one P11"
    return matches[0]


def validate_result_contract(result: dict[str, Any], schema: dict[str, Any]) -> None:
    required = set(schema["required"])
    assert required <= set(result), f"result missing schema fields: {sorted(required - set(result))}"
    assert set(result) <= set(schema["properties"]), "result contains undeclared top-level fields"

    assert result["schema_version"] == schema["properties"]["schema_version"]["const"]
    datetime.fromisoformat(result["generated_at"].replace("Z", "+00:00"))
    assert isinstance(result["repo_root"], str) and result["repo_root"]
    assert isinstance(result["branch"], str) and result["branch"]
    assert re.fullmatch(r"(?:[0-9a-f]{40}|unknown)", result["commit"])
    assert result["proof_level"] == "synthetic_offline"
    assert result["final_status"] in {"PASS", "FAIL"}

    for field in (
        "runtime_proof",
        "network_activity_performed",
        "launcher_execution_performed",
        "target_mutation_performed",
        "data_mutation_performed",
    ):
        assert result[field] is False, f"{field} must remain false for synthetic proof"

    checks = result["checks"]
    assert isinstance(checks, list) and checks
    for check in checks:
        assert set(check) == {"status", "name", "detail", "required", "disposition"}
        assert check["status"] in {"PASS", "SKIP", "FAIL"}
        assert check["disposition"] in {"required", "optional", "environment_blocked", "inapplicable"}
        assert isinstance(check["name"], str) and check["name"]
        assert isinstance(check["detail"], str)
        assert isinstance(check["required"], bool)
        if check["required"]:
            assert check["disposition"] == "required"
            assert check["status"] != "SKIP", "required SKIP must fail closed before final receipt"

    expected_counts = {
        "passed": sum(check["status"] == "PASS" for check in checks),
        "skipped": sum(check["status"] == "SKIP" for check in checks),
        "failed": sum(check["status"] == "FAIL" for check in checks),
    }
    assert result["counts"] == expected_counts
    assert result["final_status"] == ("PASS" if expected_counts["failed"] == 0 else "FAIL")

    dependencies = result["dependencies"]
    assert isinstance(dependencies, dict)
    assert all(value is None or isinstance(value, str) for value in dependencies.values())

    validators = result["validator_set"]
    assert isinstance(validators, list) and validators
    assert "harness/validators/validate-canonical-path-contracts.py" in validators
    assert "scripts/Test-SasVmDryRunReadiness.ps1" in validators
    assert "scripts/Invoke-SasVmDryRunHarnessProof.ps1" in validators

    profile = result["profile"]
    assert set(profile) == {
        "machine_profile", "os", "user", "onedrive_enabled", "desktop_dev_root", "canonical_development_checkout"
    }
    assert profile["os"] in {"windows", "linux", "macos"}
    assert isinstance(profile["onedrive_enabled"], bool)
    assert profile["desktop_dev_root"]
    assert profile["canonical_development_checkout"]

    p11 = prompt_p11()
    prompt_owner = result["prompt_owner"]
    assert prompt_owner == {
        "id": p11["id"],
        "name": p11["name"],
        "purpose": p11["sprintRole"],
        "registry_path": "docs/prompts.json",
    }

    artifacts = result["artifacts"]
    assert set(artifacts) == {"matrix", "json", "run_root", "artifact_registry"}
    assert isinstance(artifacts["matrix"], str) and artifacts["matrix"]
    assert isinstance(artifacts["json"], str) and artifacts["json"]
    assert artifacts["run_root"] is None or isinstance(artifacts["run_root"], str)
    assert artifacts["artifact_registry"] is None or isinstance(artifacts["artifact_registry"], str)


def test_validator_exists_parses_and_has_no_runtime_execution_surface() -> None:
    for path in (VALIDATOR, BASE_VALIDATOR, VM_VALIDATOR, VM_PROFILE, CANONICAL_PATH, CANONICAL_VALIDATOR, PROMPTS, SCHEMA, VM_SCHEMA):
        assert path.is_file(), f"missing one-command proof surface: {path.relative_to(ROOT)}"

    text = VALIDATOR.read_text(encoding="utf-8-sig")
    base_text = BASE_VALIDATOR.read_text(encoding="utf-8-sig")
    vm_text = VM_VALIDATOR.read_text(encoding="utf-8-sig")
    for marker in (
        "APP HARNESS VALIDATION",
        "harness_validation_result.json",
        "synthetic_offline",
        "Test-SasVmDryRunReadiness.ps1",
        "VM dry run:",
        "required proof unavailable",
        "final_status",
        "prompt_owner",
        "validator_set",
    ):
        assert marker in text, f"composed validator missing: {marker}"
    for marker in (
        "harness/api/canonical-path-registry.json",
        "canonical path profile",
        "onedrive_enabled",
        "desktop_dev_root",
        "docs/prompts.json",
        "P11",
    ):
        assert marker in base_text, f"base validator missing profile/prompt contract: {marker}"
    for marker in ("vm_provider_not_available", "request-only dry run", "runtime entry gate"):
        assert marker in vm_text

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["properties"]["schema_version"]["const"] == "sas-harness-proof/v1"
    assert schema["properties"]["proof_level"]["const"] == "synthetic_offline"
    assert schema["properties"]["runtime_proof"]["const"] is False
    for field in ("final_status", "validator_set", "profile", "prompt_owner"):
        assert field in schema["properties"]

    vm_profile = json.loads(VM_PROFILE.read_text(encoding="utf-8"))
    assert vm_profile["proof_class"] == "synthetic_offline_vm_readiness"
    assert vm_profile["proof_ceiling"] == "readiness_only_no_vm_started"
    assert vm_profile["safety"]["readiness_validator_starts_vm"] is False
    assert vm_profile["safety"]["readiness_validator_executes_real_package"] is False
    assert vm_profile["safety"]["autologon_allowed"] is False

    forbidden = [
        r"\bStart-VM\b", r"\bNew-VM\b", r"\bCheckpoint-VM\b", r"\bRestore-VMSnapshot\b",
        r"\bStart-Process\b", r"\bInvoke-Item\b", r"explorer\.exe", r"START-HERE-SysAdminSuite",
        r"Launch-SysAdminSuite", r"\bTest-NetConnection\b", r"\bResolve-DnsName\b", r"\bInvoke-WebRequest\b",
        r"\bnmap\b", r"\bnaabu\b", r"VBoxManage(?:\.exe)?\s+startvm", r"vmrun(?:\.exe)?\s+start",
    ]
    combined = text + "\n" + base_text + "\n" + vm_text
    for pattern in forbidden:
        assert not re.search(pattern, combined, re.IGNORECASE), f"forbidden runtime surface: {pattern}"

    for script in (VALIDATOR, BASE_VALIDATOR, VM_VALIDATOR):
        literal = str(script).replace("'", "''")
        parse_command = (
            "$t=$null;$e=$null;"
            f"[System.Management.Automation.Language.Parser]::ParseFile('{literal}',[ref]$t,[ref]$e)|Out-Null;"
            "if($e.Count){$e|Out-String|Write-Error;exit 1}"
        )
        parse = subprocess.run(
            [powershell(), "-NoProfile", "-Command", parse_command], cwd=ROOT, text=True, capture_output=True, check=False
        )
        assert parse.returncode == 0, parse.stderr


def test_result_schemas_and_canonical_command_are_wired_into_ci() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "Invoke-SasVmDryRunHarnessProof.ps1" in workflow
    assert "test_vm_dry_run_readiness_contracts.py" in workflow
    assert "test_one_command_harness_proof_contracts.py" in workflow
    assert "harness/api/canonical-path-registry.json" in workflow
    assert "harness/validators/validate-canonical-path-contracts.py" in workflow
    assert "docs/prompts.json" in workflow
    assert "harness-proof-result.schema.json" in workflow
    assert "vm-dry-run-readiness.schema.json" in workflow
    assert "Test-Json" in workflow
    assert workflow.count("Invoke-SasVmDryRunHarnessProof.ps1 -OutputRoot") == 1, "CI must invoke one canonical composed validator command"


def test_validator_prints_matrix_emits_json_and_states_proof_boundary() -> None:
    completed = run_validator(output_name="success")
    assert completed.returncode == 0, completed.stdout + completed.stderr
    p11 = prompt_p11()
    assert "APP HARNESS VALIDATION" in completed.stdout
    assert "[PASS] required files" in completed.stdout
    assert "[PASS] canonical path profile" in completed.stdout
    assert f"Prompt: {p11['id']} | {p11['name']} | {p11['sprintRole']}" in completed.stdout
    assert "[PASS] VM dry run: VM dry-run profile" in completed.stdout
    assert "[PASS] VM dry run: fixture dry-run journeys" in completed.stdout
    assert "[PASS] VM dry run: request-only dry run" in completed.stdout
    assert "[PASS] VM dry run: runtime entry gate" in completed.stdout
    assert "[SKIP] optional MCP symbol smoke - lsp_project_not_loaded" in completed.stdout
    assert re.search(r"\[(PASS|SKIP)\] VM dry run: optional VM provider smoke", completed.stdout)
    assert re.search(r"Result: \d+ passed / \d+ skipped / 0 failed", completed.stdout)
    assert "Final status: PASS" in completed.stdout

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    result = newest_result("success")
    validate_result_contract(result, schema)
    assert result["counts"]["failed"] == 0
    assert result["final_status"] == "PASS"
    assert any(item["status"] == "SKIP" for item in result["checks"])
    assert all(not (item["required"] and item["status"] == "SKIP") for item in result["checks"])
    assert Path(result["artifacts"]["matrix"]).is_file()


def test_onedrive_toggle_does_not_choose_desktop_dev_root() -> None:
    explicit_dev = OUTPUT / "profile-override" / "explicit-desktop" / "Dev"
    completed = run_validator(
        "-OneDriveEnabled", "true",
        "-DesktopDevRoot", str(explicit_dev),
        output_name="profile-override",
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    result = newest_result("profile-override")
    profile = result["profile"]
    assert profile["onedrive_enabled"] is True
    assert Path(profile["desktop_dev_root"]).resolve() == explicit_dev.resolve()
    assert Path(profile["canonical_development_checkout"]).resolve() == (explicit_dev / "SysAdminSuite").resolve()


def test_broken_required_path_fails_clearly_and_still_emits_valid_json() -> None:
    completed = run_validator(
        "-AdditionalRequiredPath", "__missing_required_validator__.ps1", output_name="required-failure"
    )
    assert completed.returncode != 0
    assert "[FAIL] required files - missing_required_path: __missing_required_validator__.ps1" in completed.stdout

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    result = newest_result("required-failure")
    validate_result_contract(result, schema)
    assert result["counts"]["failed"] >= 1
    assert result["final_status"] == "FAIL"


if __name__ == "__main__":
    try:
        test_validator_exists_parses_and_has_no_runtime_execution_surface()
        test_result_schemas_and_canonical_command_are_wired_into_ci()
        test_validator_prints_matrix_emits_json_and_states_proof_boundary()
        test_onedrive_toggle_does_not_choose_desktop_dev_root()
        test_broken_required_path_fails_clearly_and_still_emits_valid_json()
    finally:
        shutil.rmtree(OUTPUT, ignore_errors=True)
