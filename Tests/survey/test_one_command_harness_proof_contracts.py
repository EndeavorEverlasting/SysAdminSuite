#!/usr/bin/env python3
"""Contracts for the one-command synthetic harness proof."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "validate-sysadmin-harness.ps1"
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


def newest_result(output_name: str) -> dict:
    results = sorted((OUTPUT / output_name).rglob("harness_validation_result.json"))
    assert results, "validator did not emit harness_validation_result.json"
    return json.loads(results[-1].read_text(encoding="utf-8-sig"))


def test_validator_exists_parses_and_has_no_runtime_execution_surface() -> None:
    text = VALIDATOR.read_text(encoding="utf-8-sig")
    assert "APP HARNESS VALIDATION" in text
    assert "harness_validation_result.json" in text
    assert "synthetic_offline" in text
    assert "lsp_project_not_loaded" in text
    assert "cross-lane merge integrity" in text
    assert "test_windows_log_classifier_code.py" in text
    assert "git_bash_not_available" in text

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


def test_validator_prints_matrix_emits_json_and_states_proof_boundary() -> None:
    completed = run_validator(output_name="success")
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "APP HARNESS VALIDATION" in completed.stdout
    assert "[PASS] required files" in completed.stdout
    assert "[SKIP] optional MCP symbol smoke - lsp_project_not_loaded" in completed.stdout
    assert re.search(r"Result: \d+ passed / \d+ skipped / 0 failed", completed.stdout)

    result = newest_result("success")
    assert result["proof_level"] == "synthetic_offline"
    assert result["runtime_proof"] is False
    assert result["network_activity_performed"] is False
    assert result["launcher_execution_performed"] is False
    assert result["target_mutation_performed"] is False
    assert result["data_mutation_performed"] is False
    assert result["counts"]["failed"] == 0
    assert any(item["status"] == "SKIP" for item in result["checks"])
    assert Path(result["artifacts"]["matrix"]).is_file()


def test_broken_required_path_fails_clearly_and_still_emits_json() -> None:
    completed = run_validator(
        "-AdditionalRequiredPath",
        "__missing_required_validator__.ps1",
        output_name="required-failure",
    )
    assert completed.returncode != 0
    assert "[FAIL] required files - missing_required_path: __missing_required_validator__.ps1" in completed.stdout
    result = newest_result("required-failure")
    assert result["counts"]["failed"] >= 1


if __name__ == "__main__":
    try:
        test_validator_exists_parses_and_has_no_runtime_execution_surface()
        test_validator_prints_matrix_emits_json_and_states_proof_boundary()
        test_broken_required_path_fails_clearly_and_still_emits_json()
    finally:
        shutil.rmtree(OUTPUT, ignore_errors=True)
