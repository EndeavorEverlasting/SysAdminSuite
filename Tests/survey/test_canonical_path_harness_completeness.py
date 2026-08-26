#!/usr/bin/env python3
"""Completeness check for the canonical path harness seam."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE_PARAMETERS = ["os", "user", "onedrive_enabled", "desktop_dev_root"]
FILES = (
    "harness/api/canonical-path-registry.json",
    "schemas/harness/canonical-path-registry.schema.json",
    "harness/workflows/canonical-path-resolution.yaml",
    "harness/validators/validate-canonical-path-contracts.py",
    "harness/skills/canonical-path-resolution/SKILL.md",
    "harness/maps/CANONICAL_PATH_MAP.md",
    "harness/reports/CANONICAL_PATH_STATUS.md",
    ".github/workflows/canonical-path-contracts.yml",
)


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing canonical path harness component: {relative}"
    return path.read_text(encoding="utf-8-sig")


def tracked(relative: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", relative],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    for relative in FILES:
        read(relative)
        assert tracked(relative), f"canonical path harness component not tracked: {relative}"

    registry = json.loads(read("harness/api/canonical-path-registry.json"))
    schema = json.loads(read("schemas/harness/canonical-path-registry.schema.json"))
    manifest = json.loads(read("harness/api/operational-harness-manifest.json"))
    validators = json.loads(read("harness/api/harness-validator-registry.json"))
    assert registry["schema_version"] == "sas-canonical-path-registry/v1"
    assert schema["properties"]["schema_version"]["const"] == registry["schema_version"]
    assert registry["policy"]["second_mutable_clone_is_forbidden"] is True
    assert registry["policy"]["parallel_writers_use_isolated_worktrees"] is True
    assert registry["policy"]["profile_parameters_are_independent"] is True
    assert registry["policy"]["onedrive_toggle_does_not_choose_desktop_location"] is True
    assert registry["policy"]["desktop_dev_root_is_authoritative"] is True
    assert registry["policy"]["user_identity_is_runtime_data_not_tracked_fixture"] is True
    assert registry["profile_parameters"]["required"] == PROFILE_PARAMETERS
    assert len(registry["proof_states"]) == 4

    profiles = registry["profiles"]
    assert profiles
    for profile in profiles:
        assert profile["required_profile_parameters"] == PROFILE_PARAMETERS
        if profile["platform"] == "windows":
            assert profile["canonical_development_checkout"]["template"] == "{desktop_dev_root}\\SysAdminSuite"

    consumers = set(registry["consumers"])
    assert "scripts/validate-sysadmin-harness.ps1" in consumers
    assert ".github/workflows/one-command-harness-proof.yml" in consumers

    manifest_ids = {item["id"] for item in manifest["components"]}
    for component_id in (
        "canonical-path-registry",
        "canonical-path-schema",
        "canonical-path-workflow",
        "canonical-path-validator",
        "canonical-path-completeness",
        "canonical-path-skill",
        "canonical-path-map",
        "canonical-path-report",
        "canonical-path-ci",
    ):
        assert component_id in manifest_ids, f"canonical path component missing from operational manifest: {component_id}"
    path_component = next(item for item in manifest["components"] if item["id"] == "canonical-path-registry")
    assert path_component["kind"] == "path_registry"
    assert "python harness/validators/validate-canonical-path-contracts.py" in manifest["validation_commands"]

    validator_ids = {item["id"] for item in validators["validators"]}
    assert "canonical-path-contracts" in validator_ids
    canonical_validator = next(item for item in validators["validators"] if item["id"] == "canonical-path-contracts")
    assert canonical_validator["blocking"] is True
    assert canonical_validator["command"] == "python harness/validators/validate-canonical-path-contracts.py"

    fresh = read("harness/workflows/fresh-agent-intake.yaml")
    freshness = read("harness/workflows/repository-freshness-before-launch.yaml")
    route = read("harness/workflows/operator-execution-route.yaml")
    one_command = read("scripts/validate-sysadmin-harness.ps1")
    one_command_ci = read(".github/workflows/one-command-harness-proof.yml")
    pre_commit = read(".githooks/pre-commit")
    pre_push = read(".githooks/pre-push")

    for text in (fresh, freshness, route):
        assert "harness/api/canonical-path-registry.json" in text
    for text in (pre_commit, pre_push):
        assert "validate-canonical-path-contracts.py" in text
        assert "test_canonical_path_harness_completeness.py" in text
    for marker in ("canonical path profile", "onedrive_enabled", "desktop_dev_root"):
        assert marker in one_command
    for marker in ("harness/api/canonical-path-registry.json", "harness/validators/validate-canonical-path-contracts.py"):
        assert marker in one_command_ci

    print("PASS: canonical path harness completeness")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
