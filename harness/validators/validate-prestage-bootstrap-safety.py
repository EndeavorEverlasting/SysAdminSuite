#!/usr/bin/env python3
"""Validate pre-stage AutoLogon bootstrap safety without changing product behavior."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAP = ROOT / "harness/maps/prestage-bootstrap-map.md"
WORKFLOW = ROOT / "harness/workflows/prestage-bootstrap-safety.yaml"
FRESHNESS = ROOT / "harness/workflows/repository-freshness-before-launch.yaml"
REGISTRY = ROOT / "harness/api/prestage-bootstrap-artifact-registry.json"
SCHEMA = ROOT / "schemas/harness/prestage-bootstrap-artifact-registry.schema.json"
SKILL = ROOT / "harness/skills/prestage-bootstrap-safety/SKILL.md"
REPORT = ROOT / "harness/reports/PRESTAGE_BOOTSTRAP_SAFETY_STATUS.md"
COMPLETENESS = ROOT / "Tests/survey/test_prestage_bootstrap_harness_completeness.py"
CI = ROOT / ".github/workflows/prestage-bootstrap-safety.yml"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
TARGET_RESOLVER = ROOT / "scripts/SasTargetNameResolution.psm1"
TARGET_TEST = ROOT / "Tests/Pester/TargetNameResolution.Tests.ps1"
NETWORK_GUARD = ROOT / "scripts/SasNetworkGuard.psm1"
S4U = ROOT / "scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1"
S4U_CONTRACT = ROOT / "Tests/survey/test_autologon_kerberos_s4u_contracts.py"


def read(path: Path) -> str:
    assert path.is_file(), f"missing pre-stage harness component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", rel],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def test_registry_and_schema() -> None:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    assert registry["schema_version"] == "sas-prestage-bootstrap-artifact-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == registry["schema_version"]
    artifacts = registry["artifacts"]
    ids = [item["id"] for item in artifacts]
    assert len(ids) == len(set(ids))
    required = {
        "prestage-bootstrap-map",
        "prestage-bootstrap-safety-status",
        "prestage-bootstrap-validation-result",
        "prestage-bootstrap-completeness-result",
        "target-name-resolution-strictmode-regression-result",
    }
    assert required <= set(ids)
    for item in artifacts:
        for field in ("path", "generator", "format", "tracked", "contains_live_data", "purpose"):
            assert field in item, f"artifact {item['id']} missing {field}"
        if item["contains_live_data"]:
            assert item["tracked"] is False


def test_map_and_workflow_route_freshness_before_field_diagnosis() -> None:
    mapping = read(MAP)
    for marker in (
        "harness/workflows/repository-freshness-before-launch.yaml",
        "scripts/SasNetworkGuard.psm1",
        "scripts/SasTargetNameResolution.psm1",
        "scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1",
        "Tests/Pester/TargetNameResolution.Tests.ps1",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "python harness/validators/validate-prestage-bootstrap-safety.py",
    ):
        assert marker in mapping, marker

    workflow = read(WORKFLOW).lower()
    freshness_marker = "harness/workflows/repository-freshness-before-launch.yaml"
    inspect_marker = "inspect scripts/sastargetnameresolution.psm1 read-only"
    assert freshness_marker in workflow
    assert inspect_marker in workflow
    assert workflow.index(freshness_marker) < workflow.index(inspect_marker)
    for marker in (
        "no stage 1 means do not attribute the failure to s4u task creation",
        "fetching a remote ref alone does not update the executing worktree",
        "product code is read-only in this harness lane",
        "target network contact and mutation remain forbidden",
        "stale-controller-code",
        "current-tree-regression-fails",
    ):
        assert marker in workflow, marker


def test_existing_freshness_workflow_routes_known_prestage_signature() -> None:
    text = read(FRESHNESS).lower()
    for marker in (
        "failure before stage 1",
        "strictmode",
        "prestage-bootstrap-safety.yaml",
        "prestage-bootstrap-safety/skill.md",
    ):
        assert marker in text, marker


def test_current_product_truth_contains_strictmode_fqdn_regression() -> None:
    resolver = read(TARGET_RESOLVER)
    assert "Set-StrictMode -Version 2.0" in resolver
    assert "if ($inputIsFqdn) {\n        $suffixes = @()\n    }" in resolver
    assert "if` expression that emits @()" in resolver or "if` expression that emits @()".replace("`", "") in resolver
    assert "suffix_candidate_count = $suffixes.Count" in resolver

    test = read(TARGET_TEST)
    for marker in (
        "Set-StrictMode -Version Latest",
        "resolves an already-canonical FQDN with zero suffix candidates under StrictMode",
        "$result.suffix_candidate_count | Should -Be 0",
    ):
        assert marker in test, marker


def test_prestage_dependency_surfaces_exist_and_remain_read_only_dependencies() -> None:
    for path in (NETWORK_GUARD, S4U, S4U_CONTRACT):
        assert path.is_file(), path.relative_to(ROOT)
    combined = (read(WORKFLOW) + read(SKILL) + read(REPORT)).lower()
    assert "do not patch product code" in combined or "do not edit product code" in combined
    assert "wpj075" not in combined
    assert "password=" not in combined


def test_hooks_ci_skill_report_and_completeness_are_wired() -> None:
    command = "validate-prestage-bootstrap-safety.py"
    completeness = "test_prestage_bootstrap_harness_completeness.py"
    for path in (PRE_COMMIT, PRE_PUSH, CI):
        text = read(path)
        assert command in text, path.relative_to(ROOT)
        assert completeness in text, path.relative_to(ROOT)

    skill = read(SKILL)
    for marker in (
        "## Trigger",
        "## Required inputs",
        "## Procedure",
        "## Failure handling",
        "## Expected outputs",
        "## Proof ceiling",
    ):
        assert marker in skill

    report = read(REPORT)
    for marker in (
        "## Working",
        "## Repaired operational boundary",
        "## Broken / blocked conditions",
        "## Missing proof",
        "## Operator next gate",
    ):
        assert marker in report


def test_required_components_are_tracked() -> None:
    for path in (
        MAP,
        WORKFLOW,
        FRESHNESS,
        REGISTRY,
        SCHEMA,
        SKILL,
        REPORT,
        Path(__file__),
        COMPLETENESS,
        CI,
        PRE_COMMIT,
        PRE_PUSH,
        TARGET_RESOLVER,
        TARGET_TEST,
    ):
        assert tracked(path), path.relative_to(ROOT).as_posix()


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: pre-stage bootstrap safety harness contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
