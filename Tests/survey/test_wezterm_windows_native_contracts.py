#!/usr/bin/env python3
"""Dependency-free contract tests for the Windows-native WezTerm profile configuration."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "Config/wezterm-windows.lua.template"
MANAGER = ROOT / "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
LAUNCHER_PS = ROOT / "Launch-WorkstationWezTerm.ps1"
LAUNCHER_CMD = ROOT / "Launch-WorkstationWezTerm.cmd"
MAP = ROOT / "CODEBASE_MAP.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_wezterm_template_contract() -> None:
    text = read(TEMPLATE)
    assert "@SHELL_PATH@" in text, "template must contain SHELL_PATH placeholder"
    assert "@LAUNCH_MENU_ENTRIES@" in text, "template must contain LAUNCH_MENU_ENTRIES placeholder"
    assert "SplitHorizontal" in text, "template must contain safe horizontal split keybinding"
    assert "SplitVertical" in text, "template must contain safe vertical split keybinding"
    assert "Cheex" not in text, "template contains personal developer username 'Cheex'"


def test_wezterm_manager_safety_contract() -> None:
    text = read(MANAGER)
    assert "SupportsShouldProcess = $true" in text or "SupportsShouldProcess" in text, "manager must support ShouldProcess"
    assert "$PSCmdlet.ShouldProcess" in text, "manager must gate mutations behind ShouldProcess confirmation"
    assert "Action = 'Plan'" in text, "manager must default to Plan mode"
    assert "Plan" in text and "Apply" in text and "Rollback" in text, "manager must support Plan, Apply, and Rollback actions"
    assert "Cheex" not in text, "manager contains personal developer username 'Cheex'"


def test_launcher_contract() -> None:
    text_ps = read(LAUNCHER_PS)
    assert "wezterm" in text_ps.lower(), "launcher must reference wezterm"
    assert "Start-Process" in text_ps, "launcher must invoke process asynchronously"
    assert "Cheex" not in text_ps, "launcher contains personal developer username 'Cheex'"

    text_cmd = read(LAUNCHER_CMD)
    assert "powershell.exe" in text_cmd, "batch file wrapper must invoke powershell"
    assert "Launch-WorkstationWezTerm.ps1" in text_cmd, "batch file wrapper must call the script launcher"
    assert "Cheex" not in text_cmd, "batch wrapper contains personal developer username 'Cheex'"


def test_codebase_map_registration() -> None:
    codebase_map = read(MAP)
    assert "wezterm-windows.lua.template" in codebase_map, "CODEBASE_MAP.md must register the template"
    assert "Invoke-SasWezTermWindowsNativeProfile.ps1" in codebase_map, "CODEBASE_MAP.md must register the manager script"
    assert "Launch-WorkstationWezTerm.ps1" in codebase_map, "CODEBASE_MAP.md must register the launcher"


def main() -> None:
    tests = [
        test_wezterm_template_contract,
        test_wezterm_manager_safety_contract,
        test_launcher_contract,
        test_codebase_map_registration,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} WezTerm Windows-native profile contracts")


if __name__ == "__main__":
    main()
