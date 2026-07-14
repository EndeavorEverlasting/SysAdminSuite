#!/usr/bin/env python3
"""Static contracts for authorized deployment package intake."""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "New-SasAuthorizedDeploymentManifest.ps1"
FIXTURE = ROOT / "Tests" / "fixtures" / "deployment" / "authorized-package-intake.fixture.txt"
DOC = ROOT / "docs" / "AUTHORIZED_DEPLOYMENT_MANIFEST.md"
WORKFLOW = ROOT / ".github" / "workflows" / "authorized-deployment-manifest-contracts.yml"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_intake_surfaces_exist() -> None:
    for path in (SCRIPT, FIXTURE, DOC, WORKFLOW):
        assert path.exists(), f"missing package-intake surface: {path}"
    assert hashlib.sha256(FIXTURE.read_bytes()).hexdigest() != "0" * 64


def test_package_truth_is_captured_before_manifest_release() -> None:
    content = read(SCRIPT)
    required = (
        "Get-SasApprovedPackageRoots",
        "approved_software_sources",
        "Resolve-SasPackagePath",
        "Get-FileHash -LiteralPath $packageReadPath -Algorithm SHA256",
        "Get-AuthenticodeSignature -FilePath $packageReadPath",
        "signature_status",
        "signer_thumbprint",
        "product_version",
        "file_version",
        "InstallerArgumentsReference",
        "manifest_ready_for_review",
    )
    for fragment in required:
        assert fragment in content, f"missing package-truth contract: {fragment}"


def test_intake_is_bounded_and_never_contacts_targets() -> None:
    content = read(SCRIPT)
    required = (
        "[ValidateRange(1, 25)]",
        "Unique target count",
        "Assert-SasApprovedInputPath",
        "Invalid target hostname",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
        "maximum_25_unique_targets",
    )
    for fragment in required:
        assert fragment in content, f"missing bounded intake contract: {fragment}"

    forbidden = (
        "New-PSSession",
        "Invoke-Command",
        "Copy-Item -ToSession",
        "Start-Process",
        "New-Service",
        "Register-ScheduledTask",
        "New-ScheduledTask",
        "CurrentVersion\\Run",
        "shell:startup",
        "Clear-EventLog",
        "wevtutil cl",
        "-Credential",
        "DefaultPassword",
    )
    lowered = content.lower()
    for fragment in forbidden:
        assert fragment.lower() not in lowered, f"forbidden package-intake behavior: {fragment}"


def test_whatif_and_fixture_modes_are_offline() -> None:
    content = read(SCRIPT)
    assert "if ($WhatIfPreference)" in content
    assert "package_share_contact_performed = $false" in content
    assert "files_written = $false" in content
    assert "[switch]$FixtureMode" in content
    assert "authorized-package-intake.fixture.txt" in content
    assert "source_kind = $sourceKind" in content
    assert "synthetic_fixture" in content

    whatif_index = content.index("if ($WhatIfPreference)")
    package_read_index = content.index("Test-Path -LiteralPath $packageReadPath")
    assert whatif_index < package_read_index, "WhatIf must return before package access"


def test_manifest_output_matches_adapter_contract() -> None:
    content = read(SCRIPT)
    required = (
        "authorized-deployment-manifest.json",
        "TargetHostname = $target",
        "PackageName = $PackageName",
        "SoftwareShareRoot = $normalizedRoot",
        "InstallerRelativePath",
        "ExpectedSha256 = $hash",
        "InstallerArguments = @($InstallerArguments)",
        "InstallMode = $InstallMode",
        "RequestReference = $RequestReference",
        "ChangeReference = $ChangeReference",
        "TicketReference = $TicketReference",
    )
    for fragment in required:
        assert fragment in content, f"missing generated-manifest contract: {fragment}"


def test_docs_and_ci_expose_the_intake_flow() -> None:
    doc = read(DOC)
    workflow = read(WORKFLOW)
    for fragment in (
        "Package intake",
        "New-SasAuthorizedDeploymentManifest.ps1",
        "InstallerArgumentsReference",
        "package-intake-summary.json",
        "does not contact target workstations",
    ):
        assert fragment in doc, f"missing package-intake runbook fragment: {fragment}"
    assert "test_authorized_package_intake_contracts.py" in workflow
    assert "New-SasAuthorizedDeploymentManifest.ps1" in workflow
    assert "FixtureMode" in workflow


if __name__ == "__main__":
    test_intake_surfaces_exist()
    test_package_truth_is_captured_before_manifest_release()
    test_intake_is_bounded_and_never_contacts_targets()
    test_whatif_and_fixture_modes_are_offline()
    test_manifest_output_matches_adapter_contract()
    test_docs_and_ci_expose_the_intake_flow()
    print("PASS: 6 authorized package intake contracts")
