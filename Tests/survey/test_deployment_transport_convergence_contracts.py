#!/usr/bin/env python3
"""Dependency-free contracts for the deployment transport convergence floor."""
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HANDOFF = ROOT / "docs/handoff/deployment-transport-convergence.md"
INDEX = ROOT / "docs/launch-and-doc-index.md"
TRANSPORT_DOC = ROOT / "docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md"
SMB_DOC = ROOT / "docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md"
TUTORIAL = ROOT / "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md"
MANIFEST_DOC = ROOT / "docs/AUTHORIZED_DEPLOYMENT_MANIFEST.md"
BASH_CONTROLLER = ROOT / "bash/apps/sas-install-apps.sh"
API = ROOT / "harness/api/sas-harness-api.json"
E2E = ROOT / "harness/e2e/e2e-profiles.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing convergence authority: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_preservation_and_pr_ledgers_are_complete() -> None:
    handoff = read(HANDOFF)
    for sprint in ("P01", "P02", "P03", "P04", "P05", "P06", "P07"):
        assert f"| {sprint} " in handoff, f"missing preservation entry: {sprint}"
    for pr in (
        "#151", "#177", "#180", "#229", "#232", "#233", "#234", "#237",
        "#238", "#242", "#243", "#244", "#246", "#247", "#248", "#249", "#250",
    ):
        assert f"| {pr} |" in handoff, f"missing PR disposition: {pr}"
    assert "Merged on `main`" in handoff
    assert "#237 | closed, not merged" in handoff
    assert "#238 | closed, not merged" in handoff
    assert "Raw evidence was not committed" in handoff
    assert "live receipt continuity remains blocked" not in handoff


def test_public_safe_receipt_continuity_is_recorded() -> None:
    handoff = read(HANDOFF)
    transport = read(TRANSPORT_DOC)
    digest = "b84911668ec92d1f1285d2a603aa93fd1a8344e9725e0a1ab643b22a6d841a8b"
    for marker in (
        "live_cert_pass",
        "live_transport_execution_and_cleanup",
        "execution_and_cleanup_proven",
        digest,
        "1598",
        "privacy clean: `true`",
    ):
        assert marker in handoff, f"missing public-safe receipt marker: {marker}"
    assert digest in transport


def test_canonical_authorities_and_staging_boundaries_are_explicit() -> None:
    handoff = read(HANDOFF)
    transport = read(TRANSPORT_DOC)
    for marker in (
        "schemas/harness/software-deployment-transport-result.schema.json",
        "schemas/harness/software-deployment-transport-receipt.schema.json",
        "schemas/harness/software-deployment-transport-live-cert-result.schema.json",
        "scripts/Invoke-SasTransportProofIngest.ps1",
        "scripts/SasSoftwareDeploymentAdapter.psm1",
        "scripts/Invoke-SasValidatedSoftwareDeployment.ps1",
        "scripts/Invoke-SasSoftwareInstall.ps1",
        "bash/apps/sas-install-apps.sh",
        "harness/e2e/e2e-profiles.json",
    ):
        assert marker in handoff, f"missing canonical authority: {marker}"
    for root in (
        r"C:\ProgramData\SysAdminSuite\SoftwareInstall\<run_id>",
        r"C:\ProgramData\SysAdminSuite\AppInstall\<run_id>",
        r"C:\ProgramData\SysAdminSuite\TransportLiveCert\<run_id>",
    ):
        assert root in handoff and root in transport, f"missing staging boundary: {root}"
    assert "Neither adapter may inspect, reuse, or delete the other adapter's staging root" in transport


def test_legacy_and_primary_terminology_is_not_contradictory() -> None:
    controller = read(BASH_CONTROLLER).lower()
    smb_doc = read(SMB_DOC).lower()
    tutorial = read(TUTORIAL).lower()
    manifest_doc = read(MANIFEST_DOC).lower()
    assert "compatibility wrapper for the canonical powershell validated-deployment front" in controller
    assert "--request mode does not require --allow-legacy" in controller
    assert "legacy deployment lane" not in controller
    assert "guarded fallback" not in smb_doc
    assert "canonical winrm lane" not in smb_doc
    assert "legacy-lane" not in tutorial
    assert "only remote-install implementation" not in manifest_doc
    for text in (smb_doc, tutorial):
        assert "compatibility-controller gate" in text
        assert "--allow-legacy" in text
    assert "does not consume the transport decision" in manifest_doc
    handoff = read(HANDOFF)
    assert "Consumes P02 decisions for `Auto` and `SmbScheduledTask`" in handoff
    assert "WinRM-specific until it consumes" not in handoff
    assert controller.count('request_path=""') == 1
    assert controller.count('canonical_transport="winrm"') == 1


def test_frozen_operations_and_e2e_authority_remain_registered() -> None:
    api = json.loads(read(API))
    operation_ids = {item["id"] for item in api["operations"]}
    assert {
        "software_install.transport_preflight",
        "software_install.transport_live_cert",
        "software_install.transport_proof_ingest",
        "software_install.operator_execute",
    } <= operation_ids
    e2e = json.loads(read(E2E))
    journeys = {item["id"] for item in e2e["journeys"]}
    assert "software-install-fixture" in journeys
    assert "software-install-validated-finalization" in journeys
    assert "software-install-smb-task-fixture" in journeys
    default = next(item for item in e2e["profiles"] if item["id"] == "default")
    assert "software-install-smb-task-fixture" in default["journey_ids"]
    smb_journey = next(item for item in e2e["journeys"] if item["id"] == "software-install-smb-task-fixture")
    assert smb_journey["script"] == "Tests/bash/test_smb_scheduled_task_install_contracts.sh"

    workflow = read(ROOT / "harness/workflows/software-deployment-transport.yaml")
    assert "implementation_status: implemented_harmless_smb_live_cert" in workflow
    assert "application_entrypoint: scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1" in workflow
    assert "implementation_status: implemented_p07" in workflow
    assert "application_entrypoint: scripts/Invoke-SasTransportProofIngest.ps1" in workflow


def test_convergence_docs_are_indexed_and_public_safe() -> None:
    index = read(INDEX)
    handoff = read(HANDOFF)
    assert "docs/handoff/deployment-transport-convergence.md" in index
    assert "docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md" in index
    for forbidden in (
        "source_evidence_path",
        "target_hostname",
        "operator_username",
        "ticket_bytes",
        "credential_value",
        "raw_evidence",
    ):
        assert forbidden not in handoff.lower(), f"private receipt field leaked: {forbidden}"


def main() -> None:
    tests = [
        test_preservation_and_pr_ledgers_are_complete,
        test_public_safe_receipt_continuity_is_recorded,
        test_canonical_authorities_and_staging_boundaries_are_explicit,
        test_legacy_and_primary_terminology_is_not_contradictory,
        test_frozen_operations_and_e2e_authority_remain_registered,
        test_convergence_docs_are_indexed_and_public_safe,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} deployment transport convergence contract groups")


if __name__ == "__main__":
    main()
