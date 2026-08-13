#!/usr/bin/env python3
"""Dependency-free contracts for repository freshness before command selection."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / "harness/workflows/repository-freshness-before-launch.yaml"
FRESH = ROOT / "harness/workflows/fresh-agent-intake.yaml"
README = ROOT / "harness/README.md"
SKILL = ROOT / "harness/skills/harness-maintenance/SKILL.md"
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/harness-registry-integrity.yml"
REPORT = ROOT / "harness/reports/REPOSITORY_FRESHNESS_STATUS.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing freshness component: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(ROOT), *args], text=True, capture_output=True, check=False)


def assert_tracked(path: Path) -> None:
    relative = path.relative_to(ROOT).as_posix()
    result = git("ls-files", "--error-unmatch", relative)
    assert result.returncode == 0, f"untracked freshness component: {relative}"


def test_workflow_blocks_stale_checkout_inference() -> None:
    text = read(WORKFLOW)
    for marker in (
        "workflow_id: repository-freshness-before-launch",
        "fetching a remote ref does not update the checked-out branch or worktree",
        "a missing path in a stale worktree is not evidence",
        "fast-forward-only",
        "use an isolated worktree",
        "verify the expected path against the refreshed commit before inventing an alternate launcher",
        "fetched origin/main but continued executing an older local main",
        "alternate direct script invented before checking the expected path at the refreshed commit",
        "target_network_activity: false",
        "target_mutation: false",
    ):
        assert marker in text, f"freshness workflow missing marker: {marker}"


def test_fresh_agent_routes_to_freshness_before_command_reconstruction() -> None:
    text = read(FRESH)
    workflow_marker = "harness/workflows/repository-freshness-before-launch.yaml"
    canonical_marker = "use the canonical command or workflow instead of reconstructing implementation details"
    assert workflow_marker in text
    assert "missing locally" in text.lower()
    assert "fetching origin/main alone does not update local main" in text.lower()
    assert text.index(workflow_marker) < text.index(canonical_marker)


def test_front_door_and_skill_name_the_stale_main_trap() -> None:
    for text in (read(README).lower(), read(SKILL).lower()):
        assert "repository-freshness-before-launch.yaml" in text
        assert "fetching" in text and "does not update" in text
        assert "stale" in text
        assert "isolated worktree" in text
        assert "fast-forward" in text


def test_manifest_and_validator_registry_register_contract() -> None:
    component_by_id = {item["id"]: item for item in load(MANIFEST)["components"]}
    assert component_by_id["repository-freshness-workflow"]["path"] == "harness/workflows/repository-freshness-before-launch.yaml"
    assert component_by_id["repository-freshness-validator"]["path"] == "harness/validators/validate-repository-freshness-contracts.py"
    assert component_by_id["repository-freshness-report"]["path"] == "harness/reports/REPOSITORY_FRESHNESS_STATUS.md"
    validator_by_id = {item["id"]: item for item in load(VALIDATORS)["validators"]}
    item = validator_by_id["repository-freshness-contracts"]
    assert item["blocking"] is True
    assert item["command"] == "python harness/validators/validate-repository-freshness-contracts.py"


def test_hooks_and_ci_run_freshness_validator() -> None:
    command = "harness/validators/validate-repository-freshness-contracts.py"
    for path in (PRE_COMMIT, PRE_PUSH, CI):
        assert command in read(path), f"freshness validator not wired into {path.relative_to(ROOT).as_posix()}"


def test_operator_report_records_failure_and_repair() -> None:
    text = read(REPORT).lower()
    for marker in (
        "fetching origin/main did not update local main",
        "missing launcher",
        "fast-forward-only",
        "isolated worktree",
        "do not invent an alternate deployment path",
        "working",
        "repaired",
        "remaining proof limits",
    ):
        assert marker in text, f"freshness report missing marker: {marker}"


def test_all_new_components_are_tracked() -> None:
    for path in (WORKFLOW, Path(__file__), REPORT):
        assert_tracked(path)


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: repository freshness harness contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
