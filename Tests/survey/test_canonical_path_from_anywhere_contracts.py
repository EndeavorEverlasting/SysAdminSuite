#!/usr/bin/env python3
"""Contracts for canonical SysAdminSuite resolution from an arbitrary shell directory."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/canonical-path-registry.json"
WORKFLOW = ROOT / "harness/workflows/canonical-path-resolution.yaml"
SKILL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"
RESOLVER = ROOT / "scripts/Resolve-SasCanonicalDevelopmentPath.ps1"
CI = ROOT / ".github/workflows/canonical-path-contracts.yml"


def read(path: Path) -> str:
    """Read a tracked contract surface using its repository encoding."""
    assert path.is_file(), f"missing from-anywhere path surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    """Load a tracked JSON contract after proving the file exists."""
    return json.loads(read(path))


def assert_registry_owns_resolver() -> None:
    """Keep the canonical-path registry as the sole durable path authority."""
    registry = load(REGISTRY)
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert "scripts/Resolve-SasCanonicalDevelopmentPath.ps1" in registry["consumers"]
    assert registry["policy"]["canonical_development_checkout_must_be_unique"] is True
    assert registry["policy"]["canonical_development_checkout_requires_git_io_health"] is True
    assert registry["policy"]["second_mutable_clone_is_forbidden"] is True
    assert registry["policy"]["desktop_dev_root_is_authoritative"] is True
    assert registry["policy"]["onedrive_toggle_does_not_choose_desktop_location"] is True
    safety = registry["operator_command_safety"]
    assert safety["powershell_if_else_must_be_one_paste_block"] is True
    assert safety["powershell_native_failure_must_abort_single_paste_block"] is True
    assert safety["next_command_must_not_require_unmerged_default_branch_artifact"] is True


def assert_resolver_fails_closed_without_cwd_authority() -> None:
    """Require Known Folder/profile evidence, Git I/O health, and no fallback authority."""
    text = read(RESOLVER)
    required = (
        "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)",
        "Join-Path $desktopKnownFolder 'Dev'",
        "Join-Path $desktopDev 'SysAdminSuite'",
        "desktop_known_folder = $desktopKnownFolder",
        "desktop_source = $desktopSource",
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
        "CONFLICT_REPARSE_POINT_UNINSPECTED",
        "CONFLICT_GIT_IO_UNHEALTHY",
        "status --porcelain=v1 --untracked-files=no --ignore-submodules=dirty",
        "canonical_git_io_health = $canonicalGitIoHealth",
        "CANONICAL_PROVED",
        "current_directory_is_authority = $false",
        "path_semantics = 'WINDOWS_CASE_INSENSITIVE_NORMALIZED_FULL_PATH'",
        "path_disposition = $pathDisposition",
        "canonical_checkout_reparse_state = $canonicalReparseState",
        "canonical_entrypoint_authority = $entrypointAuthority",
        "path_relation = $pathRelation",
        "exit 3",
    )
    for marker in required:
        assert marker in text, f"resolver missing fail-closed/path-input marker: {marker}"
    assert "do not create a fallback clone elsewhere" in text.lower()
    assert "evilgithub.com" not in text

    for disposition in (
        "'CANONICAL + PROVED'",
        "'NONCANONICAL + PRESERVE'",
        "'MISSING'",
        "'CONFLICT'",
        "'UNKNOWN'",
    ):
        assert disposition in text, f"resolver missing path disposition: {disposition}"

    forbidden = (
        "pa_rperez26",
        "CheeksMcClappeth",
        "git clone",
        "reset --hard",
        "Remove-Item",
        "%USERPROFILE%\\Desktop\\Dev\\SysAdminSuite",
        "$desktop = Split-Path -Parent $desktopDev",
    )
    for marker in forbidden:
        assert marker not in text, f"resolver contains forbidden machine-specific/destructive behavior: {marker}"


def assert_workflow_and_skill_block_the_recurrence() -> None:
    """Freeze the original cwd failure plus native-continuation and unmerged-helper recurrence."""
    workflow = read(WORKFLOW)
    skill = read(SKILL)
    for text, label in ((workflow, "workflow"), (skill, "skill")):
        assert "current working directory" in text.lower(), f"{label} must classify CWD as evidence only"
        assert "git rev-parse --show-toplevel" in text, f"{label} must name the original bad bootstrap"
        assert "fallback clone" in text.lower(), f"{label} must forbid fallback checkout creation"
        assert "git i/o" in text.lower(), f"{label} must require Git I/O health"
        assert "unmerged" in text.lower(), f"{label} must forbid default-branch dependence on unmerged helpers"

    for marker in (
        "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)",
        "& {",
        "$LASTEXITCODE",
        "status --porcelain=v1 --untracked-files=no --ignore-submodules=dirty",
        "native-command failures do not honor `$ErrorActionPreference`",
        "Never make an unmerged helper a prerequisite",
    ):
        assert marker.lower() in skill.lower(), f"skill is missing atomic recurrence-prevention marker: {marker}"


def assert_provider_fixture_is_wired() -> None:
    """Require real Windows CI proof for missing, wrong-repo, broken-I/O, and valid checkout states."""
    ci = read(CI)
    for marker in (
        "scripts/Resolve-SasCanonicalDevelopmentPath.ps1",
        "Tests/survey/test_canonical_path_from_anywhere_contracts.py",
        "windows-resolution:",
        "Start outside any Git repository",
        "Prove missing canonical checkout fails closed",
        "Prove wrong repository checkout fails closed",
        "Prove Git I/O unhealthy checkout fails closed",
        "Prove explicit canonical checkout succeeds",
        "CONFLICT_GIT_IO_UNHEALTHY",
        "canonical_git_io_health",
        "CONFLICT_WRONG_REPOSITORY",
        "Explicit DesktopDevRoot incorrectly replaced real Desktop Known Folder",
    ):
        assert marker in ci, f"canonical path CI missing provider proof marker: {marker}"


def main() -> int:
    """Execute the complete canonical path from-anywhere contract floor."""
    assert_registry_owns_resolver()
    assert_resolver_fails_closed_without_cwd_authority()
    assert_workflow_and_skill_block_the_recurrence()
    assert_provider_fixture_is_wired()
    print("[PASS] canonical path registry owns uniqueness, Git I/O health, and atomic/default-branch-safe handoffs")
    print("[PASS] resolver keeps actual Windows Desktop Known Folder distinct from an explicit Desktop Dev override")
    print("[PASS] resolver fails closed on cwd, OneDrive conflicts, wrong origin, reparse state, and Git I/O failure")
    print("[PASS] workflow and skill block the repeated native-continuation and unmerged-helper handoff defect")
    print("[PASS] Windows provider fixtures cover missing, wrong-repository, unhealthy-I/O, and canonical checkout states")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
