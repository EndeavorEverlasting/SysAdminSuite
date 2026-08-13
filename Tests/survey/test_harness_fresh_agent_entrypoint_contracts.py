#!/usr/bin/env python3
"""Contracts for the fresh-agent operational harness front door."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
README = ROOT / "harness" / "README.md"
STATUS = ROOT / "docs" / "HARNESS_STATUS.md"

REQUIRED_TRACKED = (
    "AGENTS.md",
    "CODEBASE_MAP.md",
    "harness/README.md",
    "harness/api/operational-harness-manifest.json",
    "harness/api/harness-command-registry.json",
    "harness/api/harness-validator-registry.json",
    "harness/api/harness-artifact-registry.json",
    "harness/api/harness-outcome-registry.json",
    "harness/workflows/fresh-agent-intake.yaml",
    "harness/workflows/operational-harness-maintenance.yaml",
    "harness/workflows/operational-harness-publish.yaml",
    "harness/validators/validate-harness-registries.py",
    "harness/validators/validate-outcome-contracts.py",
    "harness/skills/harness-maintenance/SKILL.md",
    "harness/reports/render-harness-status.py",
    "docs/HARNESS_STATUS.md",
    ".githooks/pre-commit",
    ".githooks/pre-push",
    "scripts/install-local-harness-hooks.sh",
    "Tests/survey/test_operational_harness_completeness_contracts.py",
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing required harness file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8-sig")


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args],
        text=True,
        capture_output=True,
        check=False,
    )


def test_required_harness_floor_exists_and_is_tracked() -> None:
    for relative in REQUIRED_TRACKED:
        path = ROOT / relative
        assert path.is_file(), f"missing harness component: {relative}"
        result = git("ls-files", "--error-unmatch", relative)
        assert result.returncode == 0, f"untracked harness component: {relative}"


def test_fresh_agent_entrypoint_routes_without_replacing_governance() -> None:
    text = read(README)
    markers = (
        "repository-root governance authority remains `AGENTS.md`",
        "## Fresh-agent sequence",
        "api/agent-routing-manifest.json",
        "workflows/operational-harness-maintenance.yaml",
        "api/harness-validator-registry.json",
        "api/harness-artifact-registry.json",
        "api/harness-outcome-registry.json",
        "reports/render-harness-status.py",
        "## Known traps",
        "Do not modify `AGENTS.md`",
        "Do not change product/runtime behavior",
        "Do not commit generated run evidence",
        "## Artifact and handoff discipline",
        "## Proof ceiling",
    )
    for marker in markers:
        assert marker in text, f"fresh-agent entrypoint missing marker: {marker}"


def test_entrypoint_names_the_minimum_validator_floor() -> None:
    text = read(README)
    for command in (
        "python harness/validators/validate-harness-registries.py",
        "python harness/validators/validate-outcome-contracts.py",
        "python harness/validators/validate-deployment-state-contracts.py",
        "python Tests/survey/test_operational_harness_completeness_contracts.py",
        "python Tests/survey/test_local_harness_contracts.py",
        "git diff --check",
    ):
        assert command in text, f"missing harness validation command: {command}"


def test_operator_report_states_working_and_gaps() -> None:
    status = read(STATUS)
    assert "## Working" in status
    assert "## Known gaps and proof limits" in status
    assert "## Operator validation" in status
    assert "PASS: operational harness completeness" in status


def test_entrypoint_does_not_claim_live_product_proof() -> None:
    text = read(README).lower()
    assert "harness validation alone does not prove product behavior" in text
    assert "software deployment" in text
    assert "live runtime acceptance" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: harness fresh-agent entrypoint contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
