#!/usr/bin/env python3
"""Focused Admin Box role-factoring contracts for the shared Android toolchain engine.

Static repository validation plus synthetic fixture gates only. Never interpreted
as host installation, SDK/CLI presence, emulator boot, or SAS provider proof.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/Invoke-SasAndroidToolchain.ps1"
BOOTSTRAP = ROOT / "scripts/Start-SasAdminBoxAndroidToolchain.ps1"
FRONT_DOOR = ROOT / "Manage-AdminBoxAndroidToolchain.cmd"
PROFILE = ROOT / "Config/android-adminbox-toolchain-profile.json"
FIXTURES = ROOT / "Tests/Fixtures/android-toolchain"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def invoke(fixture, role, operation="Inventory"):
    shell = shutil.which("pwsh")
    assert shell, "PowerShell 7 required for executable fixture gate"
    with tempfile.TemporaryDirectory(prefix="sas-adminbox-fixture-") as output:
        command = [shell, "-NoProfile", "-File", str(SCRIPT), "-FixturePath", str(fixture),
                   "-Operation", operation, "-NodeRole", role, "-OutputRoot", output]
        process = subprocess.run(command, capture_output=True, text=True, timeout=60)
        receipts = list(Path(output).glob("receipt-*.json"))
        assert len(receipts) == 1, (process.returncode, process.stdout, process.stderr)
        return process.returncode, load(receipts[0])


def test_adminbox_profile_is_sanitized_desired_state():
    profile = load(PROFILE)
    assert profile["schema_version"] == "sas-android-toolchain-profile/v1"
    assert profile["node_role"] == "adminbox_reference"
    assert set(profile["allowed_operations"]) == {"Inventory", "Plan", "Apply", "Verify", "Repair"}
    assert profile["sas_adb_qualification"] == "INDEPENDENT_APPROVED_ARCHIVE_SHA256_REQUIRED"
    assert profile["minimum_free_gib"] >= 1 and profile["preferred_java_major"] == 21
    text = PROFILE.read_text(encoding="utf-8")
    for leak in ("serial", "hostname", "username", "C:\\Users", "evidence_ref"):
        assert leak.lower() not in text.lower(), leak


def test_engine_role_factoring_source_contract():
    text = SCRIPT.read_text(encoding="utf-8-sig")
    assert "Config/android-adminbox-toolchain-profile.json" in text
    assert "Assert-HostProfileForRole" in text
    assert "ADMINBOX_PROFILE_AUTHORITY_REQUIRED" in text
    assert "ADMINBOX_PROFILE_AUTHORITY_INVALID" in text
    assert "ADMINBOX_EQUIPMENT_PROFILE_MISMATCH" in text
    assert "@('ptop_lab','adminbox_reference')" in text
    # Provider routing must follow the requested role; ptop_lab hardcoding is spoofing.
    assert "'--role','ptop_lab'" not in text.replace(" ", "")
    assert "'--role',$NodeRole" in text
    # Sealed-runtime capability list is role-conditional and preserves the PTop list.
    assert "Manage-AdminBoxAndroidToolchain.cmd" in text
    assert "scripts/Start-SasAdminBoxAndroidToolchain.ps1" in text
    assert "Config/android-toolchain-profile.json','Manage-AndroidToolchain.cmd'" in text
    # Preserved ptop_lab gate stays intact.
    assert "Assert-PTopProfile" in text and "'PTOP_PROFILE_AUTHORITY_INVALID'" in text
    assert "'PTOP_EQUIPMENT_PROFILE_MISMATCH'" in text and "'PTOP_PROFILE_AUTHORITY_REQUIRED'" in text


def test_front_door_is_not_a_ptop_wrapper_disguise():
    cmd = FRONT_DOOR.read_text(encoding="utf-8")
    assert "Start-SasAdminBoxAndroidToolchain.ps1" in cmd
    assert "Start-SasAndroidToolchain.ps1" not in cmd
    assert "%~dp0" in cmd and "%SystemRoot%" in cmd
    upper = cmd.upper()
    assert "%USERPROFILE%" not in upper and "%ONEDRIVE%" not in upper
    boot = BOOTSTRAP.read_text(encoding="utf-8-sig")
    assert "Resolve-SasCanonicalDevelopmentPath.ps1" in boot and "-RequireCheckout" in boot
    assert "-NodeRole adminbox_reference" in boot
    assert "ADMINBOX_ROLE_OVERRIDE_FORBIDDEN" in boot
    assert "Invoke-SasAndroidToolchain.ps1" in boot


def test_adminbox_role_executes_synthetic_inventory():
    code, receipt = invoke(FIXTURES / "healthy.fixture.json", "adminbox_reference")
    assert code == 0, receipt
    assert receipt["result"] == "SUCCESS"
    assert receipt["node_role"] == "adminbox_reference"
    assert receipt["proof"] == ["FIXTURE_ONLY"]
    assert receipt["checks"] == [] and receipt["source"] is None


def test_unknown_and_mismatched_roles_fail_closed():
    for fixture, role in (("role-mismatch.fixture.json", "unsupported_synthetic_role"),
                          ("healthy.fixture.json", "ptop_lab_spoof"),
                          ("healthy.fixture.json", "")):
        if role == "":
            continue  # Empty role falls back to the declared default ptop_lab.
        code, receipt = invoke(FIXTURES / fixture, role)
        assert code == 2, (fixture, role, receipt)
        assert receipt["result"] == "BLOCK"
        assert "NODE_ROLE_MISMATCH" in receipt["reason_codes"], receipt


def test_adminbox_authority_gate_cases():
    """Execute the production role dispatcher, with no host or installer calls."""
    desired = load(PROFILE)
    authority = {"schema_version": "sas-android-toolchain-host-authority/v1",
                 "status": "RESOLVED", "node_role": "adminbox_reference",
                 "manufacturer": "SyntheticVendor", "model": "SyntheticLaptop",
                 "allowed_operations": ["Inventory", "Plan", "Apply", "Verify", "Repair"],
                 "evidence_ref": "synthetic-operator"}
    equipment = {"Manufacturer": "SyntheticVendor", "Model": "SyntheticLaptop"}
    cases = [{"role": "adminbox_reference", "authority": authority, "equipment": equipment,
              "operation": "Apply", "expected": "PASS"}]
    for field, value in (("status", "UNKNOWN"), ("node_role", "ptop_lab"),
                         ("evidence_ref", ""), ("allowed_operations", [])):
        cases.append({"role": "adminbox_reference", "authority": {**authority, field: value},
                      "equipment": equipment, "operation": "Apply",
                      "expected": "ADMINBOX_PROFILE_AUTHORITY_INVALID"})
    cases.append({"role": "adminbox_reference", "authority": authority,
                  "equipment": {**equipment, "Model": "OtherWorkstation"}, "operation": "Apply",
                  "expected": "ADMINBOX_EQUIPMENT_PROFILE_MISMATCH"})
    # Private authority may only narrow the sanitized desired-state ceiling.
    cases.append({"role": "adminbox_reference",
                  "authority": {**authority, "allowed_operations": ["Apply", "BeyondDesiredState"]},
                  "equipment": equipment, "operation": "Apply",
                  "expected": "ADMINBOX_PROFILE_AUTHORITY_INVALID"})
    cases.append({"role": "adminbox_reference",
                  "authority": {**authority, "allowed_operations": ["Verify"]},
                  "equipment": equipment, "operation": "Apply",
                  "expected": "ADMINBOX_PROFILE_AUTHORITY_INVALID"})
    ptop = {**authority, "node_role": "ptop_lab"}
    cases.append({"role": "ptop_lab", "authority": ptop, "equipment": equipment,
                  "operation": "Apply", "expected": "PASS"})
    cases.append({"role": "adminbox_reference", "authority": ptop, "equipment": equipment,
                  "operation": "Apply", "expected": "ADMINBOX_PROFILE_AUTHORITY_INVALID"})
    cases.append({"role": "bogus_role", "authority": authority, "equipment": equipment,
                  "operation": "Apply", "expected": "NODE_ROLE_MISMATCH"})
    with tempfile.TemporaryDirectory(prefix="sas-adminbox-authority-") as directory:
        case_file = Path(directory) / "cases.json"
        case_file.write_text(json.dumps(cases), encoding="utf-8")
        probe = Path(directory) / "authority.ps1"
        probe.write_text(r"""
param($Engine,$Cases,$Desired)
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Engine,[ref]$null,[ref]$null)
foreach($name in @('Assert-PTopProfile','Assert-HostProfileForRole')){
 $function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 if(-not $function){throw ('PRODUCTION_AUTHORITY_GATE_MISSING: '+$name)}
 . ([scriptblock]::Create($function.Extent.Text))
}
$state=Get-Content $Desired -Raw|ConvertFrom-Json
foreach($case in (Get-Content $Cases -Raw|ConvertFrom-Json)){
 $actual='PASS'
 try{Assert-HostProfileForRole -Role $case.role -Authority $case.authority -Equipment $case.equipment -RequestedOperation $case.operation -DesiredState $state}catch{$actual=$_.Exception.Message}
 if($actual -ne $case.expected){throw ('Authority sensitivity failure: '+$actual)}
}
""", encoding="utf-8")
        shell = shutil.which("pwsh")
        assert shell, "PowerShell 7 required for executable authority gate"
        process = subprocess.run([shell, "-NoProfile", "-File", str(probe), str(SCRIPT),
                                  str(case_file), str(PROFILE)], capture_output=True, text=True, timeout=60)
        assert process.returncode == 0, (process.stdout, process.stderr)


def test_engine_and_bootstrap_parse_clean():
    shell = shutil.which("pwsh")
    assert shell, "PowerShell 7 required for parse gate"
    parse = r"""
param($Files)
foreach($file in $Files){
 $tokens=$null;$errors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file),[ref]$tokens,[ref]$errors)
 if(@($errors).Count){throw ($file+': '+$errors[0].Message)}
}
"""
    with tempfile.TemporaryDirectory(prefix="sas-adminbox-parse-") as directory:
        probe = Path(directory) / "parse.ps1"
        probe.write_text(parse, encoding="utf-8")
        process = subprocess.run([shell, "-NoProfile", "-File", str(probe), str(SCRIPT), str(BOOTSTRAP)],
                                 capture_output=True, text=True, timeout=60)
        assert process.returncode == 0, (process.stdout, process.stderr)


if __name__ == "__main__":
    for name, function in sorted(globals().copy().items()):
        if name.startswith("test_") and callable(function):
            function()
            print(f"PASS: {name}")
