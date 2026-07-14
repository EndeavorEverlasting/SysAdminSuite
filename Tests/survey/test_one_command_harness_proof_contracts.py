#!/usr/bin/env python3
"""Contracts for the one-command synthetic harness proof."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "validate-sysadmin-harness.ps1"
SCHEMA = ROOT / "schemas" / "harness" / "harness-proof-result.schema.json"
CONTRACT_RUNNER = ROOT / "scripts" / "Invoke-SasHarnessContracts.ps1"
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
    results = sorted((OUTPUT / output_name).rglob("harness_validation_result.json"))
    assert results, "validator did not emit harness_validation_result.json"
    return json.loads(results[-1].read_text(encoding="utf-8-sig"))


def validate_result_contract(result: dict[str, Any], schema: dict[str, Any]) -> None:
    required = set(schema["required"])
    assert required <= set(result), f"result missing schema fields: {sorted(required - set(result))}"
    if schema.get("additionalProperties") is False:
        assert set(result) <= set(schema["properties"]), "result contains undeclared top-level fields"

    assert result["schema_version"] == schema["properties"]["schema_version"]["const"]
    datetime.fromisoformat(result["generated_at"].replace("Z", "+00:00"))
    assert isinstance(result["repo_root"], str) and result["repo_root"]
    assert isinstance(result["branch"], str) and result["branch"]
    assert re.fullmatch(r"(?:[0-9a-f]{40}|unknown)", result["commit"])
    assert result["proof_level"] == "synthetic_offline"

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
        assert set(check) == {"status", "name", "detail", "required"}
        assert check["status"] in {"PASS", "SKIP", "FAIL"}
        assert isinstance(check["name"], str) and check["name"]
        assert isinstance(check["detail"], str)
        assert isinstance(check["required"], bool)

    expected_counts = {
        "passed": sum(check["status"] == "PASS" for check in checks),
        "skipped": sum(check["status"] == "SKIP" for check in checks),
        "failed": sum(check["status"] == "FAIL" for check in checks),
    }
    assert result["counts"] == expected_counts

    dependencies = result["dependencies"]
    assert isinstance(dependencies, dict)
    assert all(value is None or isinstance(value, str) for value in dependencies.values())

    artifacts = result["artifacts"]
    assert set(artifacts) == {"matrix", "json", "run_root", "artifact_registry"}
    assert isinstance(artifacts["matrix"], str) and artifacts["matrix"]
    assert isinstance(artifacts["json"], str) and artifacts["json"]
    assert artifacts["run_root"] is None or isinstance(artifacts["run_root"], str)
    assert artifacts["artifact_registry"] is None or isinstance(artifacts["artifact_registry"], str)


def test_validator_exists_parses_and_has_no_runtime_execution_surface() -> None:
    text = VALIDATOR.read_text(encoding="utf-8-sig")
    assert "APP HARNESS VALIDATION" in text
    assert "harness_validation_result.json" in text
    assert "synthetic_offline" in text
    assert "lsp_project_not_loaded" in text
    assert "cross-lane merge integrity" in text
    assert "test_windows_log_classifier_code.py" in text
    assert "git_bash_not_available" in text
    assert "'detached'" in text

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["properties"]["schema_version"]["const"] == "sas-harness-proof/v1"
    assert schema["properties"]["proof_level"]["const"] == "synthetic_offline"
    assert schema["properties"]["runtime_proof"]["const"] is False

    forbidden = [
        r"Start-Process",
        r"Invoke-Item",
        r"explorer\.exe",
        r"START-HERE-SysAdminSuite",
        r"Launch-SysAdminSuite",
        r"Test-NetConnection",
        r"Resolve-DnsName",
        r"Invoke-WebRequest",
        r"\bnmap\b",
        r"\bnaabu\b",
    ]
    for pattern in forbidden:
        assert not re.search(pattern, text, re.IGNORECASE), f"forbidden runtime surface in validator: {pattern}"

    validator_literal = str(VALIDATOR).replace("'", "''")
    parse_command = (
        "$t=$null;$e=$null;"
        f"[System.Management.Automation.Language.Parser]::ParseFile('{validator_literal}',[ref]$t,[ref]$e)|Out-Null;"
        "if($e.Count){$e|Out-String|Write-Error;exit 1}"
    )
    parse = subprocess.run(
        [
            powershell(),
            "-NoProfile",
            "-Command",
            parse_command,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert parse.returncode == 0, parse.stderr


def test_result_schema_is_wired_into_contract_runner_and_ci() -> None:
    contract_runner = CONTRACT_RUNNER.read_text(encoding="utf-8-sig")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "schemas/harness/harness-proof-result.schema.json" in contract_runner
    assert "harness-proof-result.schema.json" in workflow
    assert "Test-Json" in workflow


def test_validator_prints_matrix_emits_json_and_states_proof_boundary() -> None:
    completed = run_validator(output_name="success")
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "APP HARNESS VALIDATION" in completed.stdout
    assert "[PASS] required files" in completed.stdout
    assert "[SKIP] optional MCP symbol smoke - lsp_project_not_loaded" in completed.stdout
    assert re.search(r"Result: \d+ passed / \d+ skipped / 0 failed", completed.stdout)

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    result = newest_result("success")
    validate_result_contract(result, schema)
    assert result["counts"]["failed"] == 0
    assert any(item["status"] == "SKIP" for item in result["checks"])
    assert Path(result["artifacts"]["matrix"]).is_file()


def test_broken_required_path_fails_clearly_and_still_emits_valid_json() -> None:
    completed = run_validator(
        "-AdditionalRequiredPath",
        "__missing_required_validator__.ps1",
        output_name="required-failure",
    )
    assert completed.returncode != 0
    assert "[FAIL] required files - missing_required_path: __missing_required_validator__.ps1" in completed.stdout

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    result = newest_result("required-failure")
    validate_result_contract(result, schema)
    assert result["counts"]["failed"] >= 1


if __name__ == "__main__":
    try:
        test_validator_exists_parses_and_has_no_runtime_execution_surface()
        test_result_schema_is_wired_into_contract_runner_and_ci()
        test_validator_prints_matrix_emits_json_and_states_proof_boundary()
        test_broken_required_path_fails_clearly_and_still_emits_valid_json()
    finally:
        shutil.rmtree(OUTPUT, ignore_errors=True)
