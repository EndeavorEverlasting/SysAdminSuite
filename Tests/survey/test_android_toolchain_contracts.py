#!/usr/bin/env python3
"""Bounded synthetic prerequisite and diagnostic propagation tests; no host proof."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE_ROOT = Path(os.environ.get("SAS_ANDROID_TOOLCHAIN_ENGINE_ROOT", str(ROOT)))
FIXTURES = ROOT / "Tests/Fixtures/android-toolchain"
SCRIPT = ENGINE_ROOT / "scripts/Invoke-SasAndroidToolchain.ps1"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def invoke(fixture, operation=None, role=None):
    shell = shutil.which("pwsh")
    assert shell, "PowerShell 7 required for executable fixture gate"
    expectation = load(fixture)["test_expectation"]
    with tempfile.TemporaryDirectory(prefix="sas-android-fixture-") as output:
        command = [shell, "-NoProfile", "-File", str(SCRIPT), "-FixturePath", str(fixture),
                   "-Operation", operation or expectation["operation"], "-NodeRole",
                   role or expectation["node_role"], "-OutputRoot", output]
        process = subprocess.run(command, capture_output=True, text=True, timeout=60)
        receipts = list(Path(output).glob("receipt-*.json"))
        assert len(receipts) == 1, (process.returncode, process.stdout, process.stderr)
        return process.returncode, load(receipts[0])


def test_fixture_privacy_and_coverage():
    required = {"healthy", "missing-jdk", "user-local-alias", "sdk-studio-disagreement",
                "duplicate-adb", "wrong-api", "disk-failure", "network-failure",
                "interrupted-install", "license-required", "elevation-required",
                "emulator-nonboot", "source-hash-missing", "role-mismatch",
                "disconnected-target"}
    assert {p.name.removesuffix(".fixture.json") for p in FIXTURES.glob("*.json")} >= required
    for path in FIXTURES.glob("*.json"):
        data = load(path)
        assert data["synthetic"] is True
        text = path.read_text()
        assert "CheeksMcClappeth" not in text and "C:\\Users" not in text


def test_prerequisites_and_synthetic_observations():
    schema = load(ENGINE_ROOT / "schemas/harness/android-toolchain-result.schema.json")
    for fixture in sorted(FIXTURES.glob("*.fixture.json")):
        expected = load(fixture)["test_expectation"]
        code, receipt = invoke(fixture)
        assert set(expected["reasons"]) <= set(receipt["reason_codes"]), fixture.name
        assert code == (2 if expected["reasons"] else 0), (fixture.name, receipt)
        assert receipt["result"] == ("BLOCK" if expected["reasons"] else "SUCCESS")
        assert set(receipt["proof"]) <= {"FIXTURE_ONLY"}, receipt
        if receipt["result"] == "SUCCESS":
            assert receipt["proof"] == ["FIXTURE_ONLY"], receipt
        assert receipt["checks"] == [] and receipt["source"] is None
        try:
            import jsonschema
        except ImportError:
            pass
        else:
            jsonschema.Draft202012Validator(schema).validate(receipt)


def test_fixture_cannot_apply_or_repair():
    for operation in ("Apply", "Repair"):
        code, receipt = invoke(FIXTURES / "healthy.fixture.json", operation)
        assert code == 2
        assert "FIXTURE_MUTATION_FORBIDDEN" in receipt["reason_codes"]
        assert not receipt["checks"] and not receipt["proof"]


def test_inventory_is_not_a_runtime_claim():
    code, receipt = invoke(FIXTURES / "missing-jdk.fixture.json", "Inventory")
    assert code == 0
    assert "MISSING_STANDALONE_JDK" in receipt["reason_codes"]
    assert receipt["proof"] == ["FIXTURE_ONLY"]


def test_host_authority_requires_independent_profile():
    """Execute the production pure authority gate, with no host or installer calls."""
    authority = {"schema_version": "sas-android-toolchain-host-authority/v1",
                 "status": "RESOLVED", "node_role": "ptop_lab",
                 "manufacturer": "SyntheticVendor", "model": "SyntheticLaptop",
                 "allowed_operations": ["Apply", "Repair"], "evidence_ref": "synthetic-operator"}
    equipment = {"Manufacturer": "SyntheticVendor", "Model": "SyntheticLaptop"}
    cases = [(authority, equipment, "Apply", "PASS")]
    for field, value in [("status", "UNKNOWN"), ("node_role", "other_role"),
                         ("evidence_ref", ""), ("allowed_operations", [])]:
        cases.append(({**authority, field: value}, equipment, "Apply", "PTOP_PROFILE_AUTHORITY_INVALID"))
    cases.append((authority, {**equipment, "Model": "OtherWorkstation"}, "Apply", "PTOP_EQUIPMENT_PROFILE_MISMATCH"))
    with tempfile.TemporaryDirectory(prefix="sas-authority-") as directory:
        fixture = Path(directory) / "cases.json"
        fixture.write_text(json.dumps(cases), encoding="utf-8")
        script = r"""
param($Engine,$Cases)
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Engine,[ref]$null,[ref]$null)
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-PTopProfile'},$true)
if(-not $function){throw 'PRODUCTION_AUTHORITY_GATE_MISSING'}
. ([scriptblock]::Create($function.Extent.Text))
foreach($case in (Get-Content $Cases -Raw|ConvertFrom-Json)){
 $actual='PASS'
 try{Assert-PTopProfile $case[0] $case[1] $case[2]}catch{$actual=$_.Exception.Message}
 if($actual -ne $case[3]){throw ('Authority sensitivity failure: '+$actual)}
}
"""
        probe = Path(directory) / "authority.ps1"
        probe.write_text(script, encoding="utf-8")
        process = subprocess.run([shutil.which("pwsh"), "-NoProfile", "-File", str(probe),
                                  str(SCRIPT), str(fixture)], capture_output=True, text=True, timeout=60)
        assert process.returncode == 0, (process.stdout, process.stderr)


def test_registry_wiring():
    def by_id(name, collection, key="id"):
        return {row[key]: row for row in load(ROOT / f"harness/api/{name}.json")[collection]}
    command = by_id("harness-command-registry", "commands")["android-toolchain"]
    assert command["source_of_truth"] == "scripts/Invoke-SasAndroidToolchain.ps1"
    artifact = by_id("harness-artifact-registry", "artifacts")["android-toolchain-result"]
    assert artifact["tracked"] is False and artifact["contains_live_data"] is True
    assert artifact["path"].startswith("survey/output/android-toolchain/")
    outcome = by_id("harness-outcome-registry", "contracts", "command_id")["android-toolchain"]
    assert outcome["success_artifact_id"] == "android-toolchain-result"
    assert outcome["failure_outcome"] == "blocked_with_actionable_gate"


def test_windows_powershell_owned_subprocess_exit():
    """Execute production process helper with real harmless children under PS5.1."""
    if os.name != "nt":
        return
    shell = str(Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe")
    with tempfile.TemporaryDirectory(prefix="sas process spaces ") as output:
        probe = Path(output) / "process.ps1"
        probe.write_text(r'''param($Engine,$OutputRoot)
$ErrorActionPreference='Stop';$fixture=$null;$TimeoutSeconds=10;$result=@{checks=@()}
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Engine,[ref]$null,[ref]$null)
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Bounded'},$true)
. ([scriptblock]::Create($function.Extent.Text))
Invoke-Bounded "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" @('-NoProfile','-Command','exit 0')|Out-Null
if($result.checks[-1].exit_code -ne 0){throw 'ZERO_EXIT_LOST'}
try{Invoke-Bounded "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" @('-NoProfile','-Command','exit 7');throw 'NONZERO_EXIT_ACCEPTED'}catch{if($_.Exception.Message -ne 'COMMAND_FAILED'){throw}}
if($result.checks[-1].exit_code -ne 7){throw 'NONZERO_EXIT_LOST'}
''', encoding="utf-8")
        process = subprocess.run([shell, "-NoProfile", "-File", str(probe), str(SCRIPT), output], capture_output=True, text=True, timeout=30)
        assert process.returncode == 0, (process.stdout, process.stderr)


if __name__ == "__main__":
    for name, function in sorted(globals().copy().items()):
        if name.startswith("test_") and callable(function):
            function()
            print(f"PASS: {name}")
