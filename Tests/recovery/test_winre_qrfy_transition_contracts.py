#!/usr/bin/env python3
"""Contracts for the privacy-safe SystemRescue -> WinRE QRFY transition."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "recovery" / "windows" / "winre-qrfy-catalog.json"
WINDOWS_DOC = ROOT / "recovery" / "windows" / "README.md"
SYSTEMRESCUE_DOC = ROOT / "recovery" / "systemrescue" / "README.md"
START = ROOT / "START-HERE-WINDOWS-WORKSTATION-RECOVERY.md"
RUNNER = ROOT / "scripts" / "Test-SasWindowsRecoveryFloor.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load_catalog() -> dict:
    return json.loads(read(CATALOG))


def rendered_command(item: dict) -> str:
    command = item.get("command") or item.get("command_template")
    assert isinstance(command, str) and command.strip(), item.get("id")
    return command.replace("{drive}", "C")


def test_qrfy_catalog_is_short_read_only_and_shell_specific() -> None:
    catalog = load_catalog()
    assert catalog["transport"]["name"] == "QRFY"
    assert catalog["transport"]["default_max_chars"] == 240
    assert catalog["transport"]["commit_runtime_output"] is False
    assert catalog["environment_contract"]["detect_shell_before_command_selection"] is True
    assert catalog["environment_contract"]["cross_shell_command_reuse"] is False

    commands = catalog["commands"]
    assert {item["id"] for item in commands} >= {
        "shell_identity",
        "firmware_identity",
        "volume_inventory",
        "windows_hive_probe",
        "bitlocker_volume_probe",
        "device_presence_probe",
    }
    for item in commands:
        command = rendered_command(item)
        assert item["shell"] == "cmd.exe"
        assert item["risk"] == "read_only"
        assert len(command) <= catalog["transport"]["default_max_chars"], (item["id"], len(command))

    command_text = "\n".join(rendered_command(item).lower() for item in commands)
    for forbidden in (
        "chkdsk",
        "startuprepair",
        "reset this pc",
        "format ",
        "diskpart clean",
        "clean all",
        "manage-bde -off",
        "repair-bde",
        "bootrec",
    ):
        assert forbidden not in command_text, forbidden


def test_transition_blocks_repair_when_unlocked_volume_loses_backing_device() -> None:
    catalog = load_catalog()
    rules = {item["id"]: item for item in catalog["transition_rules"]}
    rule = rules["unlocked_volume_backing_device_missing"]
    assert rule["when"]["bitlocker_lock_status"] == "Unlocked"
    assert rule["when"]["directory_probe"] == "A device which does not exist was specified."
    assert rule["when"]["diskpart_physical_disk_rows"] == 0
    assert rule["classification"] == "backing_device_unavailable"
    assert rule["safe_next_command_id"] == "device_presence_probe"
    assert set(rule["forbidden_until_resolved"]) >= {
        "chkdsk",
        "startup_repair",
        "reset_this_pc",
        "format",
        "diskpart_clean",
        "reinstall",
    }
    assert "not proof" in rule["proof_boundary"].lower()


def test_systemrescue_handoff_preserves_source_and_backup_before_winre() -> None:
    handoff = load_catalog()["systemrescue_handoff"]
    assert "blockdev --setro" in handoff["source_ro_semantics"]
    assert "not by itself proof" in handoff["source_ro_semantics"].lower()
    required = "\n".join(handoff["required_before_winre"]).lower()
    for marker in ("image artifacts verified", "cleanly detached", "read-only state", "destination disconnected"):
        assert marker in required, marker
    gate = handoff["winre_write_gate"].lower()
    for marker in ("chkdsk", "startup repair", "reset", "formatting", "reinstall", "physical-device presence"):
        assert marker in gate, marker


def test_catalog_contains_no_personal_or_secret_runtime_evidence() -> None:
    text = read(CATALOG)
    lowered = text.lower()
    for forbidden in (
        "drive.google.com",
        "docs.google.com",
        "appdata\\local",
        "c:\\users\\",
        "@gmail.com",
        "@outlook.com",
    ):
        assert forbidden not in lowered, forbidden
    assert not re.search(r"(?:\d{6}-){7}\d{6}", text), "BitLocker recovery key-like value must not be tracked"
    privacy = load_catalog()["privacy_contract"]
    assert all(value is False for key, value in privacy.items() if key.startswith("commit_") and isinstance(value, bool))


def test_owner_docs_and_canonical_floor_route_through_transition_contract() -> None:
    windows_doc = read(WINDOWS_DOC).lower()
    systemrescue_doc = read(SYSTEMRESCUE_DOC).lower()
    start = read(START).lower()
    runner = read(RUNNER).lower()

    for text in (windows_doc, systemrescue_doc, start):
        assert "qrfy" in text
        assert "winre-qrfy-catalog.json" in text
    for marker in ("backing_device_unavailable", "a device which does not exist was specified", "do not run chkdsk"):
        assert marker in windows_doc, marker
    for marker in ("blockdev --setro", "not" , "controller"):
        assert marker in systemrescue_doc, marker
    assert "test_winre_qrfy_transition_contracts.py" in runner


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: WinRE QRFY transition contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
