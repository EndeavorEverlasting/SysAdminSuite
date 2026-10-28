#!/usr/bin/env python3
"""Offline contracts for Windows Setup -> UEFI/BIOS technician access.

Does not reboot or modify firmware. These fixtures protect the OOBE context,
CMD-first launcher, QR payload, model fallback, and result-proof distinction.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "configs/hotfix-commands/windows-setup-uefi-bios.json"
LAUNCHER = ROOT / "Open-WindowsSetupBios.cmd"
GUI = ROOT / "GUI/Start-FieldHotfixesGui.ps1"
GUIDE = ROOT / "docs/field/WINDOWS-SETUP-UEFI-BIOS.md"
ENTRY = ROOT / "START-HERE-WINDOWS-SETUP-BIOS.md"
SKILL = ROOT / ".claude/skills/field-workflow/SKILL.md"

def test_manifest_is_versioned_and_does_not_mutate_settings():
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert m["schema_version"] == "1.0.0"
    assert m["command_id"] == "windows.setup.uefi_bios_reentry"
    assert m["requires_operator_confirmation"] is True
    assert m["intended_operator_position"] == "standing-at-target"
    assert m["cmd_payload"] == m["qr_payloads"]["cmd_shift_f10"] == "shutdown /r /fw /t 0"
    assert m["powershell_payload"] == m["qr_payloads"]["powershell_console"] == "shutdown.exe /r /fw /t 0"
    assert len(m["cmd_payload"]) <= 140
    for bad in ["reg add", "bcdedit", "diskpart", "format ", "Invoke-Command", "northwell", "ida g", "nyc h+h"]:
        assert bad.lower() not in MANIFEST.read_text(encoding="utf-8").lower()

def test_cmd_launcher_reuses_gui_without_restarting_support_pc():
    s = LAUNCHER.read_text(encoding="utf-8")
    assert "%~dp0" in s
    assert "Run-FieldHotfixesGui.cmd" in s
    assert "-ManifestPath" in s
    assert "windows-setup-uefi-bios.json" in s
    assert "shutdown" not in s.lower()
    assert "powershell.exe" not in s.lower()  # owned by pre-existing shared GUI launcher

def test_technician_guide_distinguishes_oobe_from_desktop_and_verifies_bios():
    guide = GUIDE.read_text(encoding="utf-8")
    entry = ENTRY.read_text(encoding="utf-8")
    for needle in ["Shift + F10", "Shift + Fn + F10", "shutdown /r /fw /t 0", "F2", "QCM1250", "BIOS_OBSERVED", "RESTART_ONLY"]:
        assert needle in guide
    assert "No desktop required" in entry
    assert "Windows Settings" in entry
    assert "Open-WindowsSetupBios.cmd" in guide and "Open-WindowsSetupBios.cmd" in entry
    assert "Cybernet setup-error completion-flag" in guide

def test_agent_route_and_generic_qr_instructions_are_discoverable():
    skill = SKILL.read_text(encoding="utf-8")
    gui = GUI.read_text(encoding="utf-8")
    assert "WINDOWS-SETUP-UEFI-BIOS.md" in skill
    assert "Open-WindowsSetupBios.cmd" in skill
    assert "Shift+F10" in skill
    assert "scan_instructions" in gui
    assert "cybernet.setup.childcompletion.setup_exe_3" in gui  # backwards compatible old label
