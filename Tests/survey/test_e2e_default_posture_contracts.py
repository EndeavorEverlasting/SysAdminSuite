#!/usr/bin/env python3
"""Contracts for SysAdminSuite's default end-to-end validation posture."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / "AGENTS.md"
DOCTRINE = ROOT / "docs" / "END_TO_END_TESTING_POSTURE.md"
CAPABILITY = ROOT / ".claude" / "capabilities" / "end-to-end-testing.md"
SKILL = ROOT / ".claude" / "skills" / "end-to-end-validation" / "SKILL.md"
SCOPED = ROOT / ".claude" / "skills" / "scoped-validation" / "SKILL.md"
PROFILES = ROOT / "harness" / "e2e" / "e2e-profiles.json"
SCHEMA = ROOT / "schemas" / "harness" / "e2e-validation-profiles.schema.json"
RUNNER = ROOT / "scripts" / "Invoke-SasEndToEndValidation.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "default-e2e-validation.yml"
MANIFEST = ROOT / "harness" / "api" / "agent-capability-manifest.json"
SOFTWARE_INSTALL_E2E = ROOT / "scripts" / "Invoke-SasSoftwareInstallE2E.ps1"
SOFTWARE_INSTALL_BUILD = (
    ROOT / "scripts" / "Build-SasSoftwareInstallFixtureExecutable.ps1"
)
SOFTWARE_INSTALL_OPERATOR = ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1"
SOFTWARE_INSTALL_DOC = ROOT / "docs" / "SOFTWARE_INSTALL_E2E.md"
SOFTWARE_INSTALL_FIXTURE_SOURCE = (
    ROOT / "Tests" / "fixtures" / "software-install" / "DummyInstaller.cs"
)
OLD_FIXTURE_CMD = (
    ROOT / "Tests" / "fixtures" / "software-install" / "fixture-installer.cmd"
)
OLD_FIXTURE_PS1 = (
    ROOT / "Tests" / "fixtures" / "software-install" / "fixture-installer.ps1"
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_default_posture_is_explicit_and_not_unit_only() -> None:
    agents = read(AGENTS)
    doctrine = read(DOCTRINE)
    assert "End-to-end proof is the default merge and release target" in agents
    assert "Unit tests alone are insufficient" in doctrine
    assert "fixture, synthetic, or loopback end-to-end journey" in doctrine
    assert "Never promote fixture or loopback E2E to live target proof" in doctrine
    assert ".claude/skills/end-to-end-validation/SKILL.md" in agents


def test_skill_and_capability_compose_the_posture() -> None:
    capability = read(CAPABILITY)
    skill = read(SKILL)
    scoped = read(SCOPED)
    assert "## Contract" in capability
    assert "## Used by" in capability
    assert "end-to-end-testing.md" in skill
    assert "proof-and-checkpointing.md" in skill
    assert "mutation-and-evidence-boundaries.md" in skill
    assert "end-to-end-testing.md" in scoped
    assert "targeted check" in scoped.lower()
    assert "end-to-end" in scoped.lower()


def test_profile_is_fail_closed_and_loopback_only() -> None:
    catalog = load(PROFILES)
    schema = load(SCHEMA)
    assert catalog["schema_version"] == "sas-e2e-profiles/v1"
    assert catalog["schema_path"] == schema["$id"]
    assert schema["additionalProperties"] is False
    assert catalog["posture"] == {
        "end_to_end_default_required": True,
        "unit_tests_sufficient_for_merge": False,
        "external_network_activity_default": False,
        "target_mutation_default": False,
        "tracked_runtime_evidence_allowed": False,
    }
    profiles = {p["id"]: p for p in catalog["profiles"]}
    journeys = {j["id"]: j for j in catalog["journeys"]}
    default = profiles[catalog["default_profile"]]
    assert len(default["journey_ids"]) >= 4
    assert set(default["journey_ids"]) <= set(journeys)
    for journey_id in default["journey_ids"]:
        journey = journeys[journey_id]
        assert journey["required"] is True
        assert journey["network_scope"] in {"none", "loopback-only"}
        assert journey["target_mutation"] is False
        assert (ROOT / journey["script"]).is_file()
    scripts = {j["script"] for j in journeys.values()}
    assert "scripts/validate-sysadmin-harness.ps1" in scripts
    assert "scripts/Invoke-SasSoftwareInstallE2E.ps1" in scripts
    assert "dashboard/test_relay_cancel_e2e.py" in scripts
    assert "dashboard/test_relay_abort_e2e.js" in scripts
    install_journey = journeys["software-install-fixture"]
    assert install_journey["network_scope"] == "none"
    assert install_journey["target_mutation"] is False
    assert install_journey["arguments"] == ["-OutputRoot", "{journey_output}"]


def test_runner_emits_gate_artifacts_and_proof_boundaries() -> None:
    text = read(RUNNER)
    for fragment in [
        "e2e_validation_matrix.txt",
        "e2e_validation_result.json",
        "fixture_or_loopback_e2e",
        "live_target_e2e=$false",
        "external_network_activity_performed",
        "target_mutation_performed",
        "missing runtime:",
        "Test-AllUnittestCasesSkipped",
        "Required E2E journey skipped all tests",
    ]:
        assert fragment in text, f"runner missing contract: {fragment}"
    forbidden = [
        r"Test-NetConnection",
        r"Resolve-DnsName",
        r"Invoke-WebRequest",
        r"\bnmap\b",
        r"\bnaabu\b",
        r"Enter-PSSession",
        r"Invoke-Command\s+-ComputerName",
    ]
    for pattern in forbidden:
        assert not re.search(pattern, text, re.IGNORECASE), (
            f"default runner contains target surface: {pattern}"
        )


def test_software_install_e2e_builds_executable_and_emits_deltas() -> None:
    e2e = read(SOFTWARE_INSTALL_E2E)
    build = read(SOFTWARE_INSTALL_BUILD)
    operator = read(SOFTWARE_INSTALL_OPERATOR)
    doc = read(SOFTWARE_INSTALL_DOC)
    fixture_source = read(SOFTWARE_INSTALL_FIXTURE_SOURCE)

    assert not OLD_FIXTURE_CMD.exists(), "legacy command-wrapper fixture must be removed"
    assert not OLD_FIXTURE_PS1.exists(), "legacy PowerShell fixture must be removed"
    assert not list(
        (ROOT / "Tests" / "fixtures" / "software-install").glob("*.exe")
    ), "generated installer binaries must not be committed"

    required_e2e_fragments = [
        "Invoke-SasSoftwareInstall.ps1",
        "Build-SasSoftwareInstallFixtureExecutable.ps1",
        "sysadminsuite-dummy-installer.exe",
        "Microsoft.PowerShell.Management\\Start-Process",
        "real_operator_wrapper_executed = $true",
        "real_installer_executable_executed",
        "generated_installer_executable",
        "generated_installer_sha256",
        "software_install_before.json",
        "software_install_after.json",
        "software_install_delta.json",
        "software_install_e2e_events.jsonl",
        "software_install_e2e_result.json",
        "Get-SasSoftwareInstallDelta",
        "AllowTargetMutation = $true",
        "dummy-installed.txt",
        "completed_count -ne 1",
        "repo_artifact_remaining_count",
        "run_started",
        "target_completed",
        "fixture-software-install-executable-e2e",
        "live_target_e2e = $false",
        "external_network_activity_performed = $false",
        "target_mutation_performed = $false",
        "added_count -ne 3",
    ]
    for fragment in required_e2e_fragments:
        assert fragment in e2e, f"software-install E2E missing contract: {fragment}"

    for fragment in [
        "csc.exe",
        "/target:exe",
        "/platform:anycpu",
        "Get-FileHash",
        "executable_sha256",
        "build_manifest_path",
        "generated",
        "never committed",
    ]:
        assert fragment in build, f"fixture executable build missing contract: {fragment}"

    for fragment in [
        "dummy_install_completed",
        "dummy_install_failed",
        "dummy-installed.txt",
        "manifest.json",
        "SysAdminSuite Fixture Package",
        "sysadminsuite-dummy-installer.exe",
        "target-root",
        "dummy-relative-path",
        "log-path",
        "EnsureUnderRoot",
        "parent traversal",
    ]:
        assert fragment in fixture_source, (
            f"dummy installer executable source missing behavior: {fragment}"
        )

    for fragment in [
        "New-PSSession -ComputerName $target",
        "Start-Process -FilePath $InstallerSource",
        "software_install_events.jsonl",
        "software_install_summary.json",
        "Write-SasInstallEvent",
    ]:
        assert fragment in operator, f"operator wrapper contract missing: {fragment}"

    for fragment in [
        "real software-install operator wrapper",
        "generated Windows executable",
        "dummy-installed.txt",
        "before and after snapshots",
        "added, changed, and removed delta",
        "installer-owned JSONL logging",
        "binary is not committed",
        "not live WinRM",
    ]:
        assert fragment in doc, f"software-install E2E doc missing: {fragment}"


def test_ci_executes_real_journeys_and_tracks_dependencies() -> None:
    workflow = read(WORKFLOW)
    assert "windows-latest" in workflow
    assert "pip install websockets jsonschema" in workflow
    assert "npm install --no-save --no-package-lock ws@8" in workflow
    assert "Tests\\survey\\test_software_install_harness_contracts.py" in workflow
    assert "Tests\\survey\\test_e2e_default_posture_contracts.py" in workflow
    assert "Invoke-SasEndToEndValidation.ps1" in workflow
    assert "e2e_validation_result.json" in workflow
    assert "software-install-fixture/**" in workflow
    assert "if-no-files-found: error" in workflow
    assert "persist-credentials: false" in workflow

    dependency_paths = [
        "dashboard/**",
        "scripts/SasRunContext.psm1",
        "scripts/Render-SasEnglishReport.ps1",
        "scripts/Invoke-SasHarnessContracts.ps1",
        "scripts/Invoke-SasSoftwareInstall.ps1",
        "scripts/Invoke-SasSoftwareInstallE2E.ps1",
        "scripts/Build-SasSoftwareInstallFixtureExecutable.ps1",
        "scripts/SasTargetIntake.psm1",
        "Tests/fixtures/software-install/**",
        "Tests/Pester/SoftwareInstallHarness.Tests.ps1",
        "Tests/survey/test_software_install_harness_contracts.py",
        "docs/SOFTWARE_INSTALL_E2E.md",
        "Tests/survey/test_one_command_harness_proof_contracts.py",
        "Tests/survey/test_run_context_contracts.py",
        "Tests/survey/test_local_harness_contracts.py",
        "survey/fixtures/english-log/**",
        "survey/workflows/**",
        "harness/api/sas-harness-api.json",
        "mcp/local/servers.json",
        ".githooks/**",
    ]
    for path in dependency_paths:
        assert workflow.count(path) >= 2, (
            "E2E workflow does not trigger for dependency in push and PR filters: "
            + path
        )


def test_agent_manifest_records_e2e_default() -> None:
    manifest = load(MANIFEST)
    posture = manifest["posture"]
    assert posture["end_to_end_default_required"] is True
    assert posture["unit_tests_sufficient_for_merge"] is False
    capabilities = {item["id"]: item for item in manifest["capabilities"]}
    skills = {item["id"]: item for item in manifest["skills"]}
    assert "end-to-end-testing" in capabilities
    assert "end-to-end-validation" in skills
    assert "end-to-end-testing" in skills["end-to-end-validation"]["capability_ids"]
    assert "end-to-end-testing" in skills["scoped-validation"]["capability_ids"]


def test_schema_validation_when_jsonschema_is_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load(PROFILES), load(SCHEMA))


def main() -> None:
    tests = [
        test_default_posture_is_explicit_and_not_unit_only,
        test_skill_and_capability_compose_the_posture,
        test_profile_is_fail_closed_and_loopback_only,
        test_runner_emits_gate_artifacts_and_proof_boundaries,
        test_software_install_e2e_builds_executable_and_emits_deltas,
        test_ci_executes_real_journeys_and_tracks_dependencies,
        test_agent_manifest_records_e2e_default,
        test_schema_validation_when_jsonschema_is_available,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} E2E default posture contracts")


if __name__ == "__main__":
    main()
