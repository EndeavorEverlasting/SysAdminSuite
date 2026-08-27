#!/usr/bin/env python3
"""Contracts for canonical SysAdminSuite resolution from an arbitrary shell directory."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/canonical-path-registry.json"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
WORKFLOW = ROOT / "harness/workflows/canonical-path-resolution.yaml"
SKILL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"
RESOLVER = ROOT / "scripts/Resolve-SasCanonicalDevelopmentPath.ps1"
CI = ROOT / ".github/workflows/canonical-path-contracts.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing from-anywhere path surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def assert_registry_and_command_owner() -> None:
    registry = load(REGISTRY)
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert "scripts/Resolve-SasCanonicalDevelopmentPath.ps1" in registry["consumers"]

    commands = load(COMMANDS)
    matches = [item for item in commands["commands"] if item["id"] == "canonical-path-resolve"]
    assert len(matches) == 1, "canonical-path-resolve must be registered exactly once"
    command = matches[0]
    assert command["source_of_truth"] == "harness/api/canonical-path-registry.json"
    assert command["mutation"] == "repository_read_only"
    assert command["network"] is False
    assert command["command"] == (
        "pwsh -NoProfile -ExecutionPolicy Bypass -File "
        "scripts/Resolve-SasCanonicalDevelopmentPath.ps1 -RequireCheckout -AsJson"
    )


def assert_resolver_fails_closed_without_cwd_authority() -> None:
    text = read(RESOLVER)
    required = (
        "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)",
        "Join-Path $desktop 'Dev'",
        "Join-Path $desktopDev 'SysAdminSuite'",
        "OneDriveCommercial",
        "OneDriveConsumer",
        "TARGET_FOLDER_REDIRECTED",
        "ROOT_UNAVAILABLE",
        "MULTIPLE_ROOTS",
        "CANONICAL_DEVELOPMENT",
        "ISOLATED_WORKTREE",
        "EPHEMERAL_ACQUISITION",
        "CONFLICT_WRONG_REPOSITORY",
        "CONFLICT_NESTED_OR_WRONG_ROOT",
        "CANONICAL_PROVED",
        "current_directory_is_authority = $false",
        "Do not create a fallback clone elsewhere",
        "exit 3",
    )
    for marker in required:
        assert marker in text, f"resolver missing fail-closed/path-input marker: {marker}"

    forbidden = (
        "pa_rperez26",
        "CheeksMcClappeth",
        "git clone",
        "reset --hard",
        "Remove-Item",
        "%USERPROFILE%\\Desktop\\Dev\\SysAdminSuite",
    )
    for marker in forbidden:
        assert marker not in text, f"resolver contains forbidden machine-specific/destructive behavior: {marker}"


def assert_workflow_and_skill_block_the_original_failure() -> None:
    workflow = read(WORKFLOW)
    skill = read(SKILL)
    for text, label in ((workflow, "workflow"), (skill, "skill")):
        assert "current working directory" in text.lower(), f"{label} must classify CWD as evidence only"
        assert "git rev-parse --show-toplevel" in text, f"{label} must name the original bad bootstrap"
        assert "Resolve-SasCanonicalDevelopmentPath.ps1" in text, f"{label} must route to the tracked resolver"
        assert "fallback clone" in text.lower(), f"{label} must forbid fallback checkout creation"

    for marker in (
        "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)",
        "Join-Path (Join-Path $desktop 'Dev') 'SysAdminSuite'",
        "-RequireCheckout",
    ):
        assert marker in skill, f"skill is missing executable from-anywhere bootstrap: {marker}"


def assert_provider_fixture_is_wired() -> None:
    ci = read(CI)
    for marker in (
        "scripts/Resolve-SasCanonicalDevelopmentPath.ps1",
        "Tests/survey/test_canonical_path_from_anywhere_contracts.py",
        "windows-resolution:",
        "Start outside any Git repository",
        "Prove missing canonical checkout fails closed",
        "Prove explicit canonical checkout succeeds",
    ):
        assert marker in ci, f"canonical path CI missing provider proof marker: {marker}"


def main() -> int:
    assert_registry_and_command_owner()
    assert_resolver_fails_closed_without_cwd_authority()
    assert_workflow_and_skill_block_the_original_failure()
    assert_provider_fixture_is_wired()
    print("[PASS] canonical path registry owns one executable resolver command")
    print("[PASS] resolver uses Windows Known Folder/profile evidence and forbids cwd/fallback-clone authority")
    print("[PASS] workflow and skill explicitly block the original git-rev-parse bootstrap failure")
    print("[PASS] Windows provider fixtures prove from-anywhere missing and canonical checkout states")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
