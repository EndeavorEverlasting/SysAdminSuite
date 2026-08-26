#!/usr/bin/env python3
"""Completeness check for the canonical path harness seam."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
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
    assert len(registry["proof_states"]) == 4

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
    pre_commit = read(".githooks/pre-commit")
    pre_push = read(".githooks/pre-push")

    for text in (fresh, freshness, route):
        assert "harness/api/canonical-path-registry.json" in text
    for text in (pre_commit, pre_push):
        assert "validate-canonical-path-contracts.py" in text
        assert "test_canonical_path_harness_completeness.py" in text

    print("PASS: canonical path harness completeness")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
