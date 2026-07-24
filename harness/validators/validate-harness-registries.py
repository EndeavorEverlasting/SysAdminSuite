#!/usr/bin/env python3
"""Dependency-free integrity validator for the operational harness registries."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
MANIFEST_SCHEMA = ROOT / "schemas/harness/operational-harness-manifest.schema.json"
VALIDATOR_SCHEMA = ROOT / "schemas/harness/harness-validator-registry.schema.json"
COMMAND_SCHEMA = ROOT / "schemas/harness/harness-command-registry.schema.json"
ARTIFACT_SCHEMA = ROOT / "schemas/harness/harness-artifact-registry.schema.json"
FRESH_AGENT = ROOT / "harness/workflows/fresh-agent-intake.yaml"
SKILL = ROOT / "harness/skills/harness-maintenance.md"
STATUS = ROOT / "docs/HARNESS_STATUS.md"
RENDERER = ROOT / "harness/reports/render-harness-status.py"


def load(path: Path) -> dict:
    assert path.is_file(), f"missing harness registry: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read(path: Path) -> str:
    assert path.is_file(), f"missing harness component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def tracked(relative: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", relative],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def require_unique(items: list[dict], label: str) -> None:
    ids = [str(item.get("id", "")).strip() for item in items]
    assert all(ids), f"{label} contains an empty id"
    assert len(ids) == len(set(ids)), f"{label} contains duplicate ids"


def test_manifest_components() -> None:
    manifest = load(MANIFEST)
    assert manifest["schema_version"] == "sas-operational-harness-manifest/v1"
    require_unique(manifest["components"], "operational harness components")
    for component in manifest["components"]:
        path = str(component["path"])
        assert (ROOT / path).is_file(), f"manifest component missing: {path}"
        if component.get("tracked", False):
            assert tracked(path), f"manifest component is not tracked: {path}"
        assert str(component.get("validation", "")).strip(), f"component missing validation: {component['id']}"


def test_registry_schema_authorities() -> None:
    expected = {
        MANIFEST_SCHEMA: "sas-operational-harness-manifest/v1",
        COMMAND_SCHEMA: "sas-harness-command-registry/v1",
        VALIDATOR_SCHEMA: "sas-harness-validator-registry/v1",
        ARTIFACT_SCHEMA: "sas-harness-artifact-registry/v1",
    }
    for path, version in expected.items():
        schema = load(path)
        assert schema["$schema"].endswith("draft/2020-12/schema"), f"schema draft mismatch: {path.name}"
        assert schema["properties"]["schema_version"]["const"] == version, f"schema version mismatch: {path.name}"
        relative = path.relative_to(ROOT).as_posix()
        assert tracked(relative), f"registry schema is not tracked: {relative}"


def test_validator_registry() -> None:
    registry = load(VALIDATORS)
    assert registry["schema_version"] == "sas-harness-validator-registry/v1"
    validators = registry["validators"]
    require_unique(validators, "validator registry")
    required = {
        "harness-registry-integrity",
        "operational-harness-completeness",
        "local-harness-contracts",
        "repository-text-policy-staged",
        "repository-text-policy-commit",
        "patch-whitespace",
        "offline-survey-floor",
        "pester-full",
        "managed-tests-release",
        "dashboard-publish",
    }
    assert required <= {item["id"] for item in validators}
    for item in validators:
        assert str(item.get("command", "")).strip(), f"validator command missing: {item['id']}"
        assert str(item.get("proof", "")).strip(), f"validator proof missing: {item['id']}"
        assert isinstance(item.get("scope"), list) and item["scope"], f"validator scope missing: {item['id']}"
        assert isinstance(item.get("blocking"), bool), f"validator blocking flag invalid: {item['id']}"


def test_command_registry() -> None:
    registry = load(COMMANDS)
    assert registry["schema_version"] == "sas-harness-command-registry/v1"
    commands = registry["commands"]
    require_unique(commands, "command registry")
    required = {
        "harness-validate",
        "harness-completeness",
        "offline-floor",
        "powershell-tests",
        "managed-tests",
        "dashboard-build",
        "dashboard-launch",
        "cybernet-plan",
        "cybernet-apply",
        "autologon-remote",
    }
    assert required <= {item["id"] for item in commands}
    for item in commands:
        assert str(item.get("command", "")).strip(), f"command text missing: {item['id']}"
        source = str(item.get("source_of_truth", "")).strip()
        assert source and (ROOT / source).is_file(), f"command source missing: {item['id']} -> {source}"
        assert item.get("mutation") in {
            "none",
            "repository_read_only",
            "repository_build_output_only",
            "local_runtime",
            "authorized_target_mutation",
        }, f"command mutation class invalid: {item['id']}"
        if item["mutation"] == "authorized_target_mutation":
            assert item.get("network") is True, f"target mutation must declare network activity: {item['id']}"


def test_fresh_agent_wiring() -> None:
    workflow = read(FRESH_AGENT)
    skill = read(SKILL)
    for marker in (
        "workflow_id: fresh-agent-intake",
        "read AGENTS.md without modifying it",
        "harness/api/harness-command-registry.json",
        "harness/api/harness-validator-registry.json",
        "harness/api/harness-artifact-registry.json",
        "harness/skills/harness-maintenance.md",
        "python harness/validators/validate-harness-registries.py",
        "git diff --check",
        "tools/New-SasSprintCapsule.ps1",
    ):
        assert marker in workflow, f"fresh-agent workflow missing: {marker}"
    for marker in (
        "## Trigger",
        "## Required inputs",
        "## Procedure",
        "## Expected outputs",
        "## Proof ceiling",
        "harness/workflows/fresh-agent-intake.yaml",
        "harness/api/harness-command-registry.json",
        "harness/api/harness-validator-registry.json",
        "Do not place harness-only procedures under `.claude/skills/`",
    ):
        assert marker in skill, f"harness-maintenance procedure missing: {marker}"


def test_artifact_and_report_wiring() -> None:
    registry = load(ARTIFACTS)
    require_unique(registry["artifacts"], "artifact registry")
    ids = {item["id"] for item in registry["artifacts"]}
    assert "harness-registry-validation-result" in ids
    assert "generated-harness-status-report" in ids
    renderer = read(RENDERER)
    assert "sas-harness-status-report/v1" in renderer
    assert "harness-validator-registry.json" in renderer
    assert "harness-command-registry.json" in renderer
    status = read(STATUS)
    assert "Harness registry integrity" in status
    assert "Fresh-agent intake" in status


def main() -> int:
    test_manifest_components()
    test_registry_schema_authorities()
    test_validator_registry()
    test_command_registry()
    test_fresh_agent_wiring()
    test_artifact_and_report_wiring()
    print("PASS: harness registry integrity")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
