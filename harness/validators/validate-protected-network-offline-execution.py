#!/usr/bin/env python3
"""Validate protected-network offline autonomy and the ScanSnap sealed-runtime seam."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "harness/contracts/protected-network-offline-execution.v1.json"
GOVERNANCE = ROOT / "AGENTS.md"
GUEST_DOC = ROOT / "docs/GUEST_SYNC_TO_PROTECTED_DEPLOYMENT.md"
SCAN_CMD = ROOT / "Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.cmd"
SCAN_PS1 = ROOT / "Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.ps1"
SCAN_MANIFEST = ROOT / "Config/SoftwareDeploy/ScanSnap/package.manifest.json"
ADAPTER = ROOT / "scripts/SasSoftwareDeploymentAdapter.psm1"
PREPARE = ROOT / "scripts/Prepare-SasAutoLogonShortRuntime.ps1"
SEAL = ROOT / "scripts/Test-SasAutoLogonRuntimeSeal.ps1"
HANDOFF = ROOT / "docs/handoff/SCANSNAP_RECOVERY_CURSOR_HANDOFF_20261007.md"
INTAKE = ROOT / "harness/workflows/fresh-agent-intake.yaml"
REGISTRY = ROOT / "harness/api/harness-validator-registry.json"
CI = ROOT / ".github/workflows/harness-contracts.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def require(text: str, marker: str, owner: str) -> None:
    assert marker in text, f"{owner} missing: {marker}"


def main() -> int:
    required = (
        CONTRACT, GOVERNANCE, GUEST_DOC, SCAN_CMD, SCAN_PS1, SCAN_MANIFEST,
        ADAPTER, PREPARE, SEAL, HANDOFF, INTAKE, REGISTRY, CI,
    )
    for path in required:
        assert tracked(path), f"component not tracked: {path.relative_to(ROOT)}"

    contract = json.loads(read(CONTRACT))
    assert contract["schema_version"] == "sas-protected-offline-execution/v1"
    assert contract["prompt_provenance"]["P00"]["name"] == "Governance Doctrine Installer"
    assert contract["prompt_provenance"]["P01"]["name"] == "Harness Infrastructure Builder"

    prep = contract["phases"]["internet_preparation"]
    protected = contract["phases"]["protected_execution"]
    doctrine = contract["doctrine"]
    scansnap = contract["scansnap"]

    assert prep["network_intent"] == "InternetSync"
    assert prep["target_contact_allowed"] is False
    assert "required_package_companion_files" in prep["required_outputs"]
    assert "offline_failure_continuation_logic" in prep["required_outputs"]

    assert protected["network_intent"] == "ProtectedNorthwell"
    assert protected["agent_runtime_may_be_required"] is False
    assert protected["public_internet_may_be_required"] is False
    assert protected["git_network_io_allowed"] is False
    assert protected["public_web_lookup_allowed"] is False
    assert protected["cloud_agent_provider_required"] is False
    assert protected["execution_must_be_self_contained"] is True
    assert protected["required_runtime_transport"] == "LOCAL_FILESYSTEM_ONLY"
    for marker in (
        "package_payload_available_locally",
        "package_companion_files_available_locally",
        "target_resolution_available_offline",
        "deployment_engine_available_offline",
        "failure_classification_available_offline",
        "same_transaction_continuation_available_offline",
        "independent_target_progress_preserved",
        "evidence_written_locally",
        "operator_recovery_available_offline",
    ):
        assert marker in protected["required_properties"], marker

    assert scansnap["live_transport_owner"] == "scripts/SasSoftwareDeploymentAdapter.psm1"
    assert scansnap["exact_fqdn_required_on_protected_routes"] is True
    assert scansnap["whatif_must_not_mutate_target"] is True
    assert scansnap["success_requires_validation_and_teardown"] is True
    assert doctrine["protected_execution_cannot_depend_on_chat_continuity"] is True
    assert doctrine["failure_is_a_local_continuation_state_not_a_chat_handoff"] is True

    governance = read(GOVERNANCE)
    for marker in (
        "Bounded sealed-runtime protected-window exception",
        "C:\\SASAL",
        "tracked repository-owned `.cmd` launcher",
        "exactly one canonical FQDN",
    ):
        require(governance, marker, "governance")

    guest = read(GUEST_DOC)
    for marker in (
        "Agent availability boundary",
        "assume the agent and public Internet are unavailable",
        "Do not switch to protected Northwell until the sealed runtime contains every package, script, validator, continuation path, and operator front door required",
        "LOCAL_FILESYSTEM_ONLY",
    ):
        require(guest, marker, "guest/protected runbook")

    prepare = read(PREPARE)
    require(prepare, "LOCAL_FILESYSTEM_ONLY", "runtime preparer")
    require(prepare, "runtime_remotes_removed", "runtime preparer")
    seal = read(SEAL)
    require(seal, "LOCAL_FILESYSTEM_ONLY", "runtime seal validator")
    require(seal, "runtime_remotes_removed", "runtime seal validator")

    cmd = read(SCAN_CMD)
    require(cmd, "Deploy-ScanSnap.ps1", "ScanSnap CMD front door")
    scan = read(SCAN_PS1)
    for marker in (
        "SasSoftwareDeploymentAdapter.psm1",
        "Invoke-SasSmbScheduledTaskDeployment",
        "SupportFilePaths",
        "Test-SasDeploymentFqdn",
        "WHATIF_IDENTITY_UNBOUND",
        "scansnap-home-executable",
        "Resolve-SasSmbDeploymentFinalizationStatus",
    ):
        require(scan, marker, "ScanSnap engine")
    for forbidden in ("function Invoke-RobocopyStage", "function New-RemoteInstallRunner", "function Invoke-RemoteSchtaskInstall"):
        assert forbidden not in scan, f"ScanSnap duplicate transport survived: {forbidden}"

    adapter = read(ADAPTER)
    for marker in (
        "SupportFilePaths",
        "supportHashesVerified",
        "WorkingDirectory = $workingDirectory",
        "Resolve-SasSmbDeploymentFinalizationStatus",
    ):
        require(adapter, marker, "canonical adapter")

    manifest = json.loads(read(SCAN_MANIFEST))
    assert str(manifest["DetectValue"]).endswith("PfuSshMain.exe")
    assert ".iss" in str(manifest["SilentArgs"]).lower()

    handoff = read(HANDOFF).lower()
    for marker in (
        "protected execution",
        "no public internet/agent/git dependency",
        "field whatif evidence",
    ):
        require(handoff, marker, "ScanSnap recovery handoff")

    intake = read(INTAKE)
    require(intake, "validate-protected-network-offline-execution.py", "fresh-agent intake")
    registry = read(REGISTRY)
    require(registry, "protected-network-offline-execution", "validator registry")
    ci = read(CI)
    require(ci, "validate-protected-network-offline-execution.py", "harness CI")
    require(ci, "protected-network-offline-execution.v1.json", "harness CI paths")

    print("PASS: P00 governance and P01 harness preserve protected offline autonomy")
    print("PASS: ScanSnap delegates live transport to the canonical deployment adapter")
    print("PASS: ScanSnap companion-file, FQDN, validation, teardown, and WhatIf gates are wired")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
