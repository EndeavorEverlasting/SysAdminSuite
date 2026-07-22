#!/usr/bin/env python3
"""Contracts for the canonical AutoLogon admin/runtime runbook and safe presenter."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNBOOK = ROOT / "docs" / "AUTOLOGON_DEPLOYMENT_WORKFLOW.md"
RUNTIME_DOC = ROOT / "docs" / "AUTOLOGON_TECHNICIAN_RUNTIME_PROOF.md"
PILOT = ROOT / "docs" / "AUTOLOGON_PHYSICAL_PILOT_CHECKLIST.md"
FLOOR = ROOT / "docs" / "AUTOLOGON_PROOF_CONTRACT_FLOOR.md"
INDEX = ROOT / "docs" / "launch-and-doc-index.md"
MAP = ROOT / "CODEBASE_MAP.md"
SCRIPT = ROOT / "scripts" / "Show-SasAutoLogonResult.ps1"
LAUNCHER = ROOT / "Inspect-LatestAutoLogon.cmd"
PESTER = ROOT / "Tests" / "Pester" / "AutoLogonCanonicalResultPresenter.Tests.ps1"
FIXTURE = ROOT / "Tests" / "Fixtures" / "autologon-result-inspector" / "deployment-success"
WORKFLOW = ROOT / ".github" / "workflows" / "autologon-canonical-e2e.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_runbook_uses_only_current_canonical_entrypoints_and_parameters() -> None:
    doc = read(RUNBOOK)
    deployment = read(ROOT / "scripts" / "Invoke-SasAutoLogonDeployment.ps1")
    implemented_surfaces = "\n".join(
        read(ROOT / path)
        for path in (
            "scripts/Invoke-SasAutoLogonDeployment.ps1",
            "scripts/Test-SasSoftwareDeploymentTransport.ps1",
            "scripts/Invoke-SasAutoLogonSessionAccessProof.ps1",
            "scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1",
            "scripts/Invoke-SasEndToEndValidation.ps1",
            "scripts/Show-SasAutoLogonResult.ps1",
        )
    )
    required = (
        "Invoke-SasAutoLogonDeployment.ps1",
        "Test-SasSoftwareDeploymentTransport.ps1",
        "Invoke-SasAutoLogonSessionAccessProof.ps1",
        "Start-SasAutoLogonTechnicianRuntimeProof.cmd",
        "Show-SasAutoLogonResult.ps1",
        "Inspect-LatestAutoLogon.cmd",
        "Invoke-SasEndToEndValidation.ps1",
        "-Profile autologon",
        "-TransportPreflightPath",
        "-InstallerSha256",
        "-AuthorizedBy",
        "-RequestReference",
        "-ChangeReference",
        "-TicketReference",
        "-AllowTargetMutation",
    )
    for marker in required:
        assert marker in doc, marker
    assert "installer_and_no_arguments_confirmed" in doc
    assert "Do not add switches to the AutoLogon executable" in doc
    for parameter in re.findall(r"(?<![A-Za-z0-9])-([A-Z][A-Za-z0-9]+)", doc):
        if parameter in {"NoProfile", "ExecutionPolicy", "File", "Profile", "OutputRoot", "PassThru", "Confirm", "Force"}:
            continue
        if parameter.startswith("Sas"):
            continue
        assert f"${parameter}" in implemented_surfaces or parameter == "WhatIf", (
            f"documented parameter is not implemented by a named surface: -{parameter}"
        )
    assert "Invoke-SasSoftwareInstall.ps1 `" not in doc
    assert "UncDirect" not in doc


def test_proof_stages_failure_review_and_rollback_are_explicit() -> None:
    doc = read(RUNBOOK)
    stages = [
        "Stage 1 — Plan only",
        "Stage 2 — Fixture proof",
        "Stage 3 — One-target administrator pilot",
        "Stage 4 — Post-install readiness",
        "Stage 5 — Reboot and automatic sign-in observation",
        "Stage 6 — Signed-in session access",
        "Stage 7 — Application behavior and acceptance",
    ]
    positions = [doc.index(stage) for stage in stages]
    assert positions == sorted(positions)
    for marker in (
        "Failure review: preserve, classify, then decide",
        "Rollback and recovery",
        "do not blindly retry",
        "does not implement an automated AutoLogon rollback",
        "final security-sensitive mutation",
        "Before snapshot",
        "final-step gate",
        "does not reboot",
    ):
        assert marker.lower() in doc.lower(), marker


def test_docs_are_public_safe_and_have_no_stale_dependency_language() -> None:
    combined = "\n".join(read(path) for path in ROOT.glob("docs/AUTOLOGON_*.md"))
    forbidden = (
        "nt2kwb972sms01",
        "PR #167",
        "PR #168",
        "PR #175",
        "remains stacked",
        "canonical transport refactor pending",
        "pending canonical transport refactor",
        "Restart-Computer",
    )
    for marker in forbidden:
        assert marker.lower() not in combined.lower(), marker
    assert "password values are never collected or committed" in read(RUNBOOK).lower()


def test_presenter_is_read_only_public_safe_and_fail_closed() -> None:
    script = read(SCRIPT)
    launcher = read(LAUNCHER)
    for marker in (
        "DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING",
        "FIXTURE_CONTRACT_PASS_ONLY",
        "PLAN_ONLY_NO_DEPLOYMENT",
        "EVIDENCE_INVALID",
        "CLEANUP_REVIEW_REQUIRED",
        "digest_continuity",
        "cleanup_failure_count",
        "repo_owned_remnant_count",
        "proof_ceiling",
        "identifiers_emitted",
        "exit $exitCode",
    ):
        assert marker in script, marker
    for forbidden in (
        "Test-NetConnection",
        "Invoke-Command -ComputerName",
        "Restart-Computer",
        "Start-Process explorer",
        "Write-Host \"Run",
        "Write-Host \"Account",
        "Write-Host \"Path",
    ):
        assert forbidden not in script, forbidden
    assert "Show-SasAutoLogonResult.ps1" in launcher
    assert "pwsh.exe" in launcher and "powershell.exe" in launcher
    assert "exit /b %SAS_EXIT_CODE%" in launcher


def test_fixture_digest_continuity_and_privacy_contract() -> None:
    artifacts = FIXTURE / "artifacts"
    source = artifacts / "autologon_proof_source_evidence.json"
    receipt = load(artifacts / "autologon_proof_receipt.json")
    assert receipt["source_evidence_sha256"] == hashlib.sha256(source.read_bytes()).hexdigest()
    assert receipt["source_evidence_size_bytes"] == source.stat().st_size
    deployment = load(artifacts / "autologon_deployment_result.json")
    summary = load(FIXTURE / "summary.json")
    assert deployment["target_scope"]["identifiers_emitted"] is False
    assert deployment["deployment"]["cleanup_verified"] is True
    assert deployment["deployment"]["zero_remnants_verified"] is True
    assert summary["cleanup_failure_count"] == 0
    assert summary["repo_artifact_remaining_count"] == 0
    forbidden_keys = {"hostname", "computer_name", "username", "account_name", "package_path", "raw_evidence"}

    def keys(value: object) -> set[str]:
        if isinstance(value, dict):
            return {str(k).lower() for k in value} | set().union(*(keys(v) for v in value.values()))
        if isinstance(value, list):
            return set().union(*(keys(v) for v in value)) if value else set()
        return set()

    for path in artifacts.glob("*.json"):
        assert not (keys(load(path)) & forbidden_keys), path.name

    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        return
    schema_by_name = {
        "autologon_deployment_result.json": "autologon-deployment-result.schema.json",
        "autologon_final_step_gate_result.json": "autologon-final-step-gate-result.schema.json",
        "autologon_state_proof_result.json": "autologon-state-proof-result.schema.json",
        "autologon_proof_source_evidence.json": "autologon-proof-source-evidence.schema.json",
        "autologon_proof_receipt.json": "autologon-proof-receipt.schema.json",
    }
    for artifact_name, schema_name in schema_by_name.items():
        Draft202012Validator(load(ROOT / "schemas" / "harness" / schema_name)).validate(load(artifacts / artifact_name))


def test_index_map_ci_and_windows_fixture_registration() -> None:
    for text in (read(INDEX), read(MAP)):
        for marker in ("AUTOLOGON_DEPLOYMENT_WORKFLOW.md", "Show-SasAutoLogonResult.ps1", "Inspect-LatestAutoLogon.cmd"):
            assert marker in text, marker
    workflow = read(WORKFLOW)
    assert "test_autologon_admin_runtime_runbook_contracts.py" in workflow
    assert "AutoLogonCanonicalResultPresenter.Tests.ps1" in workflow
    assert PESTER.is_file()


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon admin/runtime runbook contracts")


if __name__ == "__main__":
    main()
