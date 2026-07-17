#!/usr/bin/env python3
"""Contracts for the authorized disposable-VM package execution lane."""
from __future__ import annotations
import hashlib, json, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/Invoke-SasPackageDisposableVmRun.ps1"
SCHEMA = ROOT / "schemas/harness/package-vm-execution-result.schema.json"
OPERATION = ROOT / "harness/api/package-vm-execution-skill.json"
WORKFLOW = ROOT / "harness/workflows/package-vm-execution.yaml"
DOC = ROOT / "docs/PACKAGE_VM_EXECUTION.md"
CAPABILITY = ROOT / ".claude/capabilities/package-vm-execution.md"
SKILL = ROOT / ".claude/skills/package-vm-execution/SKILL.md"
ROUTING = ROOT / "harness/api/package-vm-execution-routing.json"
PROFILE = ROOT / "Tests/Fixtures/package-vm-execution/ready-profile.fixture.json"
INSTALLER = ROOT / "Tests/Fixtures/package-vm-execution/fixture-installer.payload"
ACCEPTANCE = ROOT / "Tests/Fixtures/package-vm-execution/acceptance.fixture.ps1"
RESULT_FIXTURE = ROOT / "Tests/Fixtures/package-vm-execution/package-vm-execution.fixture.json"
CI = ROOT / ".github/workflows/package-static-analysis.yml"
OFFLINE = ROOT / "tests/survey/run_offline_survey_tests.sh"

def load(path: Path):
    assert path.is_file(), f"missing: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8"))

def test_operation_and_workflow_are_separate_authorized_lane():
    operation = load(OPERATION)["operation"]
    assert operation["id"] == "package_analysis.vm_execute"
    assert operation["mode"] == "operator_execute"
    assert operation["network_activity"] is False
    assert operation["target_mutation"] is True
    assert operation["mutation_scope"] == "disposable_guest_only"
    assert operation["package_execution"] is True
    assert operation["package_execution_scope"] == "disposable_guest_only"
    assert operation["vm_start"] is True
    for marker in ("admin_box_package_execution_forbidden", "checkpoint_restore_before_and_after", "physical_workstation_validation_remains_separate"):
        assert marker in operation["guardrails"]
    routing = load(ROUTING)
    assert routing["triggers"][0]["target"] == "package_analysis.vm_execute"
    assert routing["ambiguity_rules"]["explicit_execution_request_required"] is True
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "mode: operator_execute" in workflow
    assert "mutation_scope: disposable_guest_only" in workflow
    assert "No package execution on the admin box" in workflow
    assert "Advance only a passing package" in workflow

def test_result_schema_and_fixture_are_closed_and_honest():
    schema, result = load(SCHEMA), load(RESULT_FIXTURE)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] is False
    assert result["proof"]["fixture_mode"] is True
    assert result["proof"]["vm_started"] is False
    assert result["proof"]["package_executed_in_guest"] is False
    assert result["proof"]["package_executed_on_host"] is False
    assert result["proof"]["physical_workstation_validated"] is False
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(result, schema)

def test_ready_fixture_binds_exact_package_hash_and_safe_guest():
    profile = load(PROFILE)
    assert hashlib.sha256(INSTALLER.read_bytes()).hexdigest() == profile["package_selector"]["source_sha256"]
    assert profile["decision"] == {"status":"ready_for_authorized_vm_run","blockers":[],"vm_started":False,"package_executed":False}
    guest = profile["guest"]
    assert guest["provider"] == "hyper_v" and guest["network_mode"] == "disconnected"
    assert guest["host_execution_forbidden"] is True
    assert guest["autologon_allowed"] is False
    assert guest["shared_clipboard_allowed"] is False
    assert guest["shared_folders_allowed"] is False

def test_powershell_entrypoint_enforces_real_runtime_boundaries():
    text = SCRIPT.read_text(encoding="utf-8")
    required = [
        "validate_vm_qualification_profile.py", "ready_for_authorized_vm_run", "Get-FileHash",
        "Get-VMNetworkAdapter", "Get-VMSnapshot", "Restore-VMSnapshot", "Start-VM", "Stop-VM",
        "New-PSSession -VMName", "Copy-Item -LiteralPath $InstallerPath", "-ToSession $session",
        "Start-Process -FilePath $Installer", "package_executed_on_host=$false",
        "physical_workstation_validated=$false", "autologon_performed=$false", "AllowVmMutation",
        "Guest-staged package hash mismatch", "checkpoint_revert"
    ]
    for marker in required:
        assert marker in text, marker
    assert "Start-Process -FilePath $InstallerPath" not in text
    assert "Connect-VMNetworkAdapter" not in text
    assert "Set-VMNetworkAdapter" not in text
    assert "Enable-VMIntegrationService" not in text
    assert "DefaultPassword" not in text

def test_docs_keep_vm_and_physical_proof_separate():
    combined = (DOC.read_text(encoding="utf-8") + CAPABILITY.read_text(encoding="utf-8") + SKILL.read_text(encoding="utf-8")).lower()
    for marker in ("admin box", "powerShell direct".lower(), "disconnected", "clean checkpoint", "physical-workstation", "autologon", "credentials"):
        assert marker in combined, marker
    assert "qualified in a disposable vm and eligible for a controlled physical pilot" in combined

def test_documentation_commands_are_copy_safe():
    data = DOC.read_bytes()
    assert not any(byte < 32 and byte not in (9, 10, 13) for byte in data)
    text = data.decode("utf-8")
    assert r".\Tests\Fixtures\package-vm-execution\ready-profile.fixture.json" in text
    assert r".\Tests\Fixtures\package-vm-execution\fixture-installer.payload" in text
    assert r".\Tests\Fixtures\package-vm-execution\acceptance.fixture.ps1" in text

def test_ci_and_offline_runner_are_wired():
    ci = CI.read_text(encoding="utf-8")
    offline = OFFLINE.read_text(encoding="utf-8")
    assert "test_package_vm_execution_contracts.py" in ci
    assert "Invoke-SasPackageDisposableVmRun.ps1" in ci
    assert "package-vm-execution-result.schema.json" in ci
    assert "test_package_vm_execution_contracts.py" in offline

def test_fixture_mode_executes_when_pwsh_is_available():
    pwsh = shutil.which("pwsh")
    if not pwsh:
        return
    output_root = ROOT / "survey/output/package-vm-execution-contract"
    if output_root.exists():
        shutil.rmtree(output_root)
    completed = subprocess.run([
        pwsh, "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(SCRIPT),
        "-QualificationProfilePath", str(PROFILE), "-InstallerPath", str(INSTALLER),
        "-VmName", "SAS-FIXTURE-VM", "-CheckpointName", "clean",
        "-AcceptanceScriptPath", str(ACCEPTANCE), "-OutputRoot", str(output_root), "-FixtureMode"
    ], cwd=ROOT, text=True, capture_output=True, check=False)
    assert completed.returncode == 0, completed.stdout + completed.stderr
    results = list(output_root.glob("*/package_vm_execution_result.json"))
    assert len(results) == 1
    result = load(results[0])
    assert result["execution"]["status"] == "fixture_only"
    assert result["proof"]["vm_started"] is False
    assert result["proof"]["package_executed_in_guest"] is False
    shutil.rmtree(output_root)

def main():
    tests = [value for name,value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test(); print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} package VM execution contract groups")

if __name__ == "__main__":
    main()
