#!/usr/bin/env python3
"""Completeness floor for the scoped pre-stage bootstrap harness."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPONENTS = {
    "map": "harness/maps/prestage-bootstrap-map.md",
    "workflow": "harness/workflows/prestage-bootstrap-safety.yaml",
    "artifact_registry": "harness/api/prestage-bootstrap-artifact-registry.json",
    "schema": "schemas/harness/prestage-bootstrap-artifact-registry.schema.json",
    "validator": "harness/validators/validate-prestage-bootstrap-safety.py",
    "skill": "harness/skills/prestage-bootstrap-safety/SKILL.md",
    "operator_report": "harness/reports/PRESTAGE_BOOTSTRAP_SAFETY_STATUS.md",
    "ci": ".github/workflows/prestage-bootstrap-safety.yml",
    "pre_commit": ".githooks/pre-commit",
    "pre_push": ".githooks/pre-push",
    "fresh_agent": "harness/workflows/fresh-agent-intake.yaml",
    "freshness_workflow": "harness/workflows/repository-freshness-before-launch.yaml",
}


def read(path: str) -> str:
    full = ROOT / path
    assert full.is_file(), f"missing pre-stage harness component: {path}"
    return full.read_text(encoding="utf-8-sig")


def tracked(path: str) -> None:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, f"untracked pre-stage harness component: {path}"


def test_all_components_exist_and_are_tracked() -> None:
    for path in COMPONENTS.values():
        read(path)
        tracked(path)


def test_artifact_registry_has_generation_and_naming_contracts() -> None:
    registry = json.loads(read(COMPONENTS["artifact_registry"]))
    assert registry["naming"]["tracked_report"] == COMPONENTS["operator_report"]
    assert "console output or CI log" in registry["naming"]["validation_result"]
    ids = {item["id"] for item in registry["artifacts"]}
    assert "prestage-bootstrap-validation-result" in ids
    assert "target-name-resolution-strictmode-regression-result" in ids


def test_hooks_and_ci_execute_scoped_checks_at_safe_boundaries() -> None:
    validator = "python3 harness/validators/validate-prestage-bootstrap-safety.py"
    completeness = "python3 Tests/survey/test_prestage_bootstrap_harness_completeness.py"
    pre_commit = read(COMPONENTS["pre_commit"])
    assert validator in pre_commit and completeness in pre_commit
    pre_push = read(COMPONENTS["pre_push"])
    exact_tip = pre_push.index("validate_freshness_tip() {")
    assert validator not in pre_push[:exact_tip]
    assert completeness not in pre_push[:exact_tip]
    assert validator in pre_push[exact_tip:]
    assert completeness in pre_push[exact_tip:]
    ci = read(COMPONENTS["ci"])
    assert "python harness/validators/validate-prestage-bootstrap-safety.py" in ci
    assert "python Tests/survey/test_prestage_bootstrap_harness_completeness.py" in ci
    assert "python -m pip install jsonschema" in ci
    assert "TargetNameResolution.Tests.ps1" in ci


def test_freshness_workflow_routes_to_scoped_harness() -> None:
    text = read(COMPONENTS["freshness_workflow"])
    assert "failure before stage 1" in text.lower()
    assert "harness/workflows/prestage-bootstrap-safety.yaml" in text
    assert "harness/skills/prestage-bootstrap-safety/SKILL.md" in text


def test_fresh_agent_routes_prestage_signature_before_field_rerun() -> None:
    text = read(COMPONENTS["fresh_agent"])
    assert "failure before stage 1" in text.lower()
    assert "StrictMode" in text
    assert "harness/workflows/repository-freshness-before-launch.yaml" in text
    assert "harness/workflows/prestage-bootstrap-safety.yaml" in text
    assert "harness/skills/prestage-bootstrap-safety/SKILL.md" in text
    assert "before any field rerun or S4U-task diagnosis" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: pre-stage bootstrap harness completeness ({len(tests)} groups)")


if __name__ == "__main__":
    main()
