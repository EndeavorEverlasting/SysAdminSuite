#!/usr/bin/env python3
"""Repository freshness contracts for the operational harness."""
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
REPORT = ROOT / "harness/reports/REPOSITORY_FRESHNESS_STATUS.md"


def read(path: Path) -> str:
    assert path.is_file(), path.relative_to(ROOT).as_posix()
    return path.read_text(encoding="utf-8-sig")


def tracked(path: Path) -> bool:
    relative = path.relative_to(ROOT).as_posix()
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", relative],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def test_freshness_workflow() -> None:
    text = read(WORKFLOW).lower()
    for marker in (
        "repository-freshness-before-launch",
        "fetching a remote ref does not update the checked-out branch or worktree",
        "missing path in a stale worktree is not evidence",
        "fast-forward-only",
        "isolated worktree",
        "fetched origin/main but continued executing an older local main",
        "alternate direct script invented",
    ):
        assert marker in text, marker


def test_fresh_agent_routes_before_reconstruction() -> None:
    text = read(FRESH).lower()
    freshness = "harness/workflows/repository-freshness-before-launch.yaml"
    canonical = "use the canonical command or workflow instead of reconstructing implementation details"
    assert freshness in text
    assert "fetching origin/main alone does not update local main" in text
    assert text.index(freshness) < text.index(canonical)


def test_front_door_and_skill_repeat_the_rule() -> None:
    for text in (read(README).lower(), read(SKILL).lower()):
        assert "repository-freshness-before-launch.yaml" in text
        assert "does not update" in text
        assert "stale" in text
        assert "fast-forward" in text
        assert "isolated worktree" in text


def test_manifest_tracks_required_freshness_components() -> None:
    manifest = json.loads(read(MANIFEST))
    components = {item["id"]: item for item in manifest["components"]}
    expected = {
        "repository-freshness-workflow": "harness/workflows/repository-freshness-before-launch.yaml",
        "repository-freshness-validator": "harness/validators/validate-repository-freshness-contracts.py",
        "repository-freshness-report": "harness/reports/REPOSITORY_FRESHNESS_STATUS.md",
    }
    for component_id, path in expected.items():
        item = components[component_id]
        assert item["path"] == path
        assert item["required"] is True
        assert item["tracked"] is True
        assert tracked(ROOT / path), path


def test_operator_report_records_incident_and_repair() -> None:
    text = read(REPORT).lower()
    for marker in (
        "fetching origin/main did not update local main",
        "missing launcher",
        "fast-forward-only",
        "isolated worktree",
        "do not invent an alternate deployment path",
        "remaining proof limits",
    ):
        assert marker in text, marker


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: repository freshness harness contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
