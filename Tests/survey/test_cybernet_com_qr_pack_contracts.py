#!/usr/bin/env python3
"""Static contracts for the Cybernet COM-port QR pack.

The pack gives field technicians scannable CMD snippets through the Field Hotfixes GUI.
These tests validate structure and safety boundaries only; they do not execute snippets.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PACK_PATH = REPO_ROOT / "configs" / "hotfix-command-packs" / "cybernet-com-port-repair.pack.json"
RUNNER_PATH = REPO_ROOT / "scripts" / "Start-CybernetComPortQrPack.ps1"
LAUNCHER_PATH = REPO_ROOT / "Run-CybernetComPortQrPack.cmd"
AUTOFIX_LAUNCHER_PATH = REPO_ROOT / "Run-CybernetComPortAutoFix.cmd"
DOC_PATH = REPO_ROOT / "docs" / "field-hotfixes" / "cybernet-com-port-qr-pack.md"
FIELD_HOTFIX_GUI_PATH = REPO_ROOT / "GUI" / "Start-FieldHotfixesGui.ps1"


def load_pack() -> dict:
    assert PACK_PATH.exists(), f"missing Cybernet COM QR pack: {PACK_PATH}"
    return json.loads(PACK_PATH.read_text(encoding="utf-8"))


def test_cybernet_com_qr_pack_has_ordered_scannable_snippets() -> None:
    pack = load_pack()
    sequence = pack["sequence"]

    assert pack["pack_id"] == "cybernet.com_port_qr_pack"
    assert pack["entrypoint"] == "Run-CybernetComPortQrPack.cmd"
    assert pack["autofix_entrypoint"] == "Run-CybernetComPortAutoFix.cmd"
    assert pack["operator_position"] == "standing-at-target"
    assert len(sequence) == 12
    assert [item["step"] for item in sequence] == [f"{i:02d}" for i in range(1, 13)]

    required_keys = {
        "step",
        "title",
        "command_id",
        "risk_level",
        "cmd_payload",
        "powershell_payload",
        "expected_result",
        "operator_note",
    }
    for item in sequence:
        assert required_keys.issubset(item), f"missing keys in step {item}"
        assert item["command_id"].startswith("cybernet.com.")
        assert item["risk_level"] in {"low", "medium"}
        assert len(item["cmd_payload"]) <= 200
        assert len(item["powershell_payload"]) <= 260


def test_cybernet_com_qr_pack_contains_the_required_field_workflow() -> None:
    pack = load_pack()
    payloads = "\n".join(item["cmd_payload"] for item in pack["sequence"])

    expected_fragments = [
        r"mkdir C:\Temp\CybernetCOM",
        r"HKLM\HARDWARE\DEVICEMAP\SERIALCOMM",
        r"pnputil /enum-devices /class Ports",
        r"pnputil /enum-devices /class MultiPortSerial",
        "set devmgr_show_nonpresent_devices=1 && start devmgmt.msc",
        r"reg export \"HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter\"",
        r"reg add \"HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter\" /v ComDB",
        "shutdown /r /t 0",
        "serialcomm-after.txt",
        "ports-after.txt",
        r"explorer C:\Temp\CybernetCOM",
        "Run-CybernetComPortAutoFix.cmd",
    ]

    for fragment in expected_fragments:
        assert fragment in payloads, f"missing workflow fragment: {fragment}"


def test_cybernet_com_qr_pack_payloads_are_local_only() -> None:
    pack = load_pack()
    all_text = json.dumps(pack, sort_keys=True)
    forbidden_fragments = [
        "Invoke-Command",
        "New-PSSession",
        "Enter-PSSession",
        "Copy-Item -ToSession",
        "http://",
        "https://",
        "password",
        "credential",
        "secret",
        "token",
    ]

    for fragment in forbidden_fragments:
        assert fragment not in all_text, f"COM QR pack must not include {fragment!r}"

    assert "No silent remote execution" in all_text
    assert "No admin-box target mutation" in all_text
    assert "No SmartLynx or final app install" in all_text


def test_cybernet_com_qr_pack_runner_builds_temporary_field_hotfix_manifest() -> None:
    assert RUNNER_PATH.exists(), f"missing runner: {RUNNER_PATH}"
    assert FIELD_HOTFIX_GUI_PATH.exists(), f"missing Field Hotfixes GUI: {FIELD_HOTFIX_GUI_PATH}"
    content = RUNNER_PATH.read_text(encoding="utf-8")

    assert "cybernet-com-port-repair.pack.json" in content
    assert "Start-FieldHotfixesGui.ps1" in content
    assert "SysAdminSuite\\CybernetComQrPack" in content
    assert "ConvertTo-Json -Depth 8" in content
    assert "cmd_shift_f10" in content
    assert "powershell_console" in content
    assert "standing-at-target" in content
    assert "Do not run silently from the admin box" in content

    forbidden_fragments = [
        "Invoke-Command",
        "New-PSSession",
        "Enter-PSSession",
        "Copy-Item -ToSession",
        "Register-ScheduledTask",
    ]
    for fragment in forbidden_fragments:
        assert fragment not in content, f"runner must not include {fragment}"


def test_cybernet_com_qr_pack_launcher_and_outline_exist() -> None:
    assert LAUNCHER_PATH.exists(), f"missing launcher: {LAUNCHER_PATH}"
    assert AUTOFIX_LAUNCHER_PATH.exists(), f"missing AutoFix launcher: {AUTOFIX_LAUNCHER_PATH}"
    assert DOC_PATH.exists(), f"missing outline: {DOC_PATH}"

    launcher = LAUNCHER_PATH.read_text(encoding="utf-8")
    outline = DOC_PATH.read_text(encoding="utf-8")

    assert "Start-CybernetComPortQrPack.ps1" in launcher
    assert "Run-CybernetComPortQrPack.cmd" in outline
    assert "Run-CybernetComPortAutoFix.cmd" in outline
    assert "COM3 to COM1" in outline
    assert "COM4 to COM2" in outline
    assert "Run automated COM AutoFix" in outline
    assert "No silent remote execution" in outline
    assert "C:\\Temp\\CybernetCOM" in outline
