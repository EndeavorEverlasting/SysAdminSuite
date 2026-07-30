#!/usr/bin/env python3
"""Regression contract for the portable launcher's Windows drive-path regex."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts" / "SasPortableLauncher.ps1"


def test_windows_drive_regex_escapes_the_literal_backslash() -> None:
    text = LAUNCHER.read_text(encoding="utf-8-sig")
    good = "$isLocalDrivePath = $RepoRoot -match '^[A-Za-z]:\\\\'"
    bad = "$isLocalDrivePath = $RepoRoot -match '^[A-Za-z]:\\'"
    assert good in text
    assert bad not in text.replace(good, "")


def test_repo_backed_commands_share_the_corrected_path_helper() -> None:
    text = LAUNCHER.read_text(encoding="utf-8-sig")
    assert text.count("Invoke-SasPortableRepoCommand -RepoRoot $repoRoot") >= 4
    for command in (
        "Find-SasEvidence.cmd",
        "Probe-CybernetSoftware.cmd",
        "Run-AutoLogonOnsite.cmd",
        "Deploy-CybernetSoftware.cmd",
    ):
        assert command in text


if __name__ == "__main__":
    test_windows_drive_regex_escapes_the_literal_backslash()
    test_repo_backed_commands_share_the_corrected_path_helper()
    print("PASS: portable launcher drive regex contracts (2 groups)")
