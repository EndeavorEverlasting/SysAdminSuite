#!/usr/bin/env python3
"""Static contracts for the SysAdminSuite repository directory structure."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "REPO_DIRECTORY_STRUCTURE.md"
ENTER_SCRIPT = ROOT / "scripts" / "Enter-SysAdminSuite.ps1"
WORKTREE_SCRIPT = ROOT / "scripts" / "New-SysAdminSuiteWorktree.ps1"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_repo_directory_structure_doc_establishes_app_root_and_preamble():
    text = read(DOC)
    required = [
        "SysAdminSuite Repository Directory Structure",
        "app root",
        "checked-out `SysAdminSuite` repository directory",
        "Required command preamble",
        "Set-Location \"C:\\Users\\Cheex\\Desktop\\dev\\SysAdminSuite\\SysAdminSuite\"",
        ".\\scripts\\Enter-SysAdminSuite.ps1",
        "Do not give a command that starts with",
        "Canonical tracked directories",
        "Generated-output boundary",
        "Canonical run directory shape",
        "Windows log classifier locations",
        "Agent rule",
    ]
    for fragment in required:
        assert fragment in text, f"missing directory structure doctrine fragment: {fragment}"


def test_repo_directory_structure_emulates_blacksmith_guild_sibling_worktrees():
    text = read(DOC)
    required = [
        "Blacksmith Guild reference pattern",
        "C:\\Users\\Cheex\\Desktop\\dev\\Mods\\Bannerlord\\BlacksmithGuild",
        "C:\\Users\\Cheex\\Desktop\\dev\\Mods\\Bannerlord\\BlacksmithGuild-037a-validation",
        "C:\\Users\\Cheex\\Desktop\\dev\\Mods\\Bannerlord\\BlacksmithGuild-pr23",
        "C:\\Users\\Cheex\\Desktop\\dev\\Mods\\Bannerlord\\BlacksmithGuild-pr25-launcher-evidence",
        "C:\\Users\\Cheex\\Desktop\\dev\\Mods\\Bannerlord\\BlacksmithGuild-pr27-duration-guard",
        "SysAdminSuite equivalent pattern",
        "<dev-root>\\SysAdminSuite-pr<NUMBER>-<short-scope>",
        "C:\\Users\\Cheex\\Desktop\\dev\\SysAdminSuite\\SysAdminSuite-pr149-windows-log-classifier",
        "Worktree naming rules",
        "Creating a sibling worktree",
        "New-SysAdminSuiteWorktree.ps1",
    ]
    for fragment in required:
        assert fragment in text, f"missing sibling worktree contract: {fragment}"


def test_repo_directory_structure_doc_names_required_directories_and_output_boundaries():
    text = read(DOC)
    required_dirs = [
        "docs/",
        "harness/",
        "harness/taxonomy/",
        "mcp/local/",
        "schemas/harness/",
        "scripts/",
        "survey/",
        "survey/input/",
        "survey/output/",
        "targets/",
        "Tests/",
        "Tests/survey/",
        "tests/survey/",
        "runs/<workflow_id>/",
        "survey/output/<workflow>/<run_id>/",
    ]
    for fragment in required_dirs:
        assert fragment in text, f"missing required directory contract: {fragment}"

    for forbidden_runtime_artifact in ["*.evtx", "*.etl", "*.pcap", "*.pcapng", "credential-bearing exports"]:
        assert forbidden_runtime_artifact in text


def test_enter_script_moves_to_validated_repo_root_without_guessing_user_location():
    text = read(ENTER_SCRIPT)
    required = [
        "#Requires -Version 5.1",
        "[CmdletBinding()]",
        "[string]$RepoRoot",
        "[switch]$PassThru",
        "function Test-SasRepoRoot",
        "docs",
        "scripts",
        "survey",
        "harness",
        "Tests",
        "Resolve-Path -LiteralPath $RepoRoot",
        "Set-Location -LiteralPath $resolvedRoot",
        "Path does not look like the SysAdminSuite app root",
    ]
    for fragment in required:
        assert fragment in text, f"missing Enter-SysAdminSuite fragment: {fragment}"


def test_new_worktree_script_creates_named_sibling_from_repo_root():
    text = read(WORKTREE_SCRIPT)
    required = [
        "#Requires -Version 5.1",
        "[CmdletBinding(SupportsShouldProcess = $true)]",
        "[ValidatePattern('^SysAdminSuite-[A-Za-z0-9][A-Za-z0-9._-]*$')]",
        "[string]$Name",
        "[string]$Branch",
        "[string]$StartPoint = 'main'",
        "function Resolve-SasRepoRoot",
        "function Test-SasRepoRoot",
        "Split-Path -Parent $resolvedRoot",
        "Join-Path $parent $Name",
        "Worktree path already exists",
        "git worktree add -b $Branch $worktreePath $StartPoint",
    ]
    for fragment in required:
        assert fragment in text, f"missing New-SysAdminSuiteWorktree fragment: {fragment}"


if __name__ == "__main__":
    test_repo_directory_structure_doc_establishes_app_root_and_preamble()
    test_repo_directory_structure_emulates_blacksmith_guild_sibling_worktrees()
    test_repo_directory_structure_doc_names_required_directories_and_output_boundaries()
    test_enter_script_moves_to_validated_repo_root_without_guessing_user_location()
    test_new_worktree_script_creates_named_sibling_from_repo_root()
