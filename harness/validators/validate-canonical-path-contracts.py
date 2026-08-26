#!/usr/bin/env python3
"""Dependency-free canonical path contract validator for SysAdminSuite."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/canonical-path-registry.json"
SCHEMA = ROOT / "schemas/harness/canonical-path-registry.schema.json"
WORKFLOW = ROOT / "harness/workflows/canonical-path-resolution.yaml"
FRESH = ROOT / "harness/workflows/fresh-agent-intake.yaml"
FRESHNESS = ROOT / "harness/workflows/repository-freshness-before-launch.yaml"
ROUTE = ROOT / "harness/workflows/operator-execution-route.yaml"
SKILL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"
MAP = ROOT / "harness/maps/CANONICAL_PATH_MAP.md"
REPORT = ROOT / "harness/reports/CANONICAL_PATH_STATUS.md"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/canonical-path-contracts.yml"

REQUIRED_TRACKED = (
    REGISTRY,
    SCHEMA,
    WORKFLOW,
    FRESH,
    FRESHNESS,
    ROUTE,
    SKILL,
    MAP,
    REPORT,
    PRE_COMMIT,
    PRE_PUSH,
    CI,
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing canonical path component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    registry = load(REGISTRY)
    schema = load(SCHEMA)

    assert registry["schema_version"] == "sas-canonical-path-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == registry["schema_version"]

    policy = registry["policy"]
    for key in (
        "remote_main_contains_sha_is_not_workstation_deployment_proof",
        "canonical_development_checkout_must_be_unique",
        "second_mutable_clone_is_forbidden",
        "preserve_unique_or_dirty_work",
        "parallel_writers_use_isolated_worktrees",
        "ephemeral_acquisition_checkout_never_becomes_canonical_by_existence",
        "production_use_path_requires_independent_currentness_proof",
        "operator_entrypoint_requires_independent_observation_proof",
    ):
        assert policy.get(key) is True, f"canonical path policy must fail closed: {key}"

    proof_ids = [item["id"] for item in registry["proof_states"]]
    expected_proofs = {
        "remote_default_contains_sha",
        "canonical_development_checkout_current",
        "production_use_path_current",
        "operator_entrypoint_observes_current",
    }
    assert set(proof_ids) == expected_proofs
    assert len(proof_ids) == len(set(proof_ids))

    profiles = {item["id"]: item for item in registry["profiles"]}
    assert {"windows-development", "windows-admin-box"} <= set(profiles)
    for profile in profiles.values():
        assert profile["canonical_development_checkout"]["template"] == "%USERPROFILE%\\Desktop\\Dev\\SysAdminSuite"
        assert profile["temporary_worktree_root"]["template"] == "%LOCALAPPDATA%\\SysAdminSuite\\worktrees"
        assert profile["canonical_development_checkout"]["template"] != profile["temporary_worktree_root"]["template"]
        assert any("closeout-entry-*" in item for item in profile["ephemeral_acquisition_patterns"])

    admin = profiles["windows-admin-box"]
    assert admin["production_use_path"]["applicable"] is True
    assert admin["production_use_path"]["template"] == "C:\\SASAL"
    assert admin["real_operator_entrypoint"]["authority"] == "harness/api/operator-execution-route-registry.json"
    assert admin["real_operator_entrypoint"]["production_runtime_entrypoint"] == "C:\\SASAL\\Bootstrap-SysAdminSuiteAutoLogon.cmd"
    development = profiles["windows-development"]
    assert development["production_use_path"]["applicable"] is False

    assert registry["operator_command_safety"]["powershell_if_else_must_be_one_paste_block"] is True
    consumers = set(registry["consumers"])
    for expected in (
        "harness/workflows/fresh-agent-intake.yaml",
        "harness/workflows/repository-freshness-before-launch.yaml",
        "harness/workflows/operator-execution-route.yaml",
        "harness/skills/canonical-path-resolution/SKILL.md",
        "harness/maps/CANONICAL_PATH_MAP.md",
        "harness/reports/CANONICAL_PATH_STATUS.md",
    ):
        assert expected in consumers
        assert (ROOT / expected).is_file(), f"canonical path consumer missing: {expected}"

    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: canonical-path-resolution",
        "ephemeral acquisition checkout never becomes canonical",
        "remote_default_contains_sha",
        "canonical_development_checkout_current",
        "production_use_path_current",
        "operator_entrypoint_observes_current",
        "one paste block",
    ):
        assert marker in workflow, f"canonical path workflow missing: {marker}"

    fresh = read(FRESH)
    freshness = read(FRESHNESS)
    route = read(ROUTE)
    for text, marker in (
        (fresh, "harness/api/canonical-path-registry.json"),
        (fresh, "harness/workflows/canonical-path-resolution.yaml"),
        (freshness, "harness/api/canonical-path-registry.json"),
        (route, "harness/api/canonical-path-registry.json"),
    ):
        assert marker in text, f"canonical path consumer not wired: {marker}"

    skill = read(SKILL)
    for marker in (
        "entire construct in one copy/paste block",
        "second submission attempts to invoke a command named `else`",
        "remote default contains SHA",
        "production/use path current",
    ):
        assert marker in skill, f"canonical path skill missing: {marker}"

    map_text = read(MAP)
    report = read(REPORT)
    for marker in (
        "%USERPROFILE%\\Desktop\\Dev\\SysAdminSuite",
        "%LOCALAPPDATA%\\SysAdminSuite\\worktrees",
        "C:\\SASAL",
        "closeout-entry-*",
        "standalone `else`",
    ):
        assert marker in map_text, f"canonical path map missing: {marker}"
    for marker in (
        "one machine-readable path owner",
        "four independent proof states",
        "standalone later `else`",
        "PASS: canonical path harness contracts",
    ):
        assert marker in report, f"canonical path report missing: {marker}"

    for hook in (PRE_COMMIT, PRE_PUSH):
        assert "validate-canonical-path-contracts.py" in read(hook), f"canonical path validator missing from {hook.name}"
    ci = read(CI)
    for marker in (
        "Canonical Path Contracts",
        "validate-canonical-path-contracts.py",
        "test_canonical_path_harness_completeness.py",
        "test_operational_harness_completeness_contracts.py",
        "git diff --check",
    ):
        assert marker in ci, f"canonical path CI missing: {marker}"

    combined = "\n".join(read(path) for path in (REGISTRY, WORKFLOW, SKILL, MAP, REPORT)).lower()
    for forbidden in ("pa_rperez26", "wpj075", "nslijhs.net"):
        assert forbidden not in combined, f"machine/live-target literal leaked into canonical path harness: {forbidden}"

    for path in REQUIRED_TRACKED:
        assert tracked(path), f"canonical path component is not tracked: {path.relative_to(ROOT)}"

    print("PASS: canonical path harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
