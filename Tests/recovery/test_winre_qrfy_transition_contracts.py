#!/usr/bin/env python3
"""Contracts for the privacy-safe SystemRescue -> WinRE QRFY transition."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "recovery" / "windows" / "winre-qrfy-catalog.json"
TRANSITION_DOC = ROOT / "recovery" / "windows" / "WINRE_QRFY_TRANSITION.md"
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


def test_qrfy_catalog_is_short_shell_specific_and_never_explicitly_writes() -> None:
    catalog = load_catalog()
    assert catalog["transport"]["name"] == "QRFY"
    assert catalog["transport"]["default_max_chars"] == 240
    assert catalog["transport"]["commit_runtime_output"] is False
    assert catalog["environment_contract"]["detect_shell_before_command_selection"] is True
    assert catalog["environment_contract"]["cross_shell_command_reuse"] is False

    preservation = catalog["preservation_contract"]
    assert preservation["linux_blockdev_ro_persists_across_reboot"] is False
    assert preservation["winre_commands_are_media_write_blocker"] is False
    assert preservation["default_winre_claim"] == "no_explicit_write_command"
    assert preservation["device_presence_before_volume_access"] is True
    assert "hardware/controller write protection" in preservation["strict_preservation_requires"]

    commands = catalog["commands"]
    assert {item["id"] for item in commands} >= {
        "shell_identity",
        "firmware_identity",
        "volume_inventory",
        "device_presence_probe",
        "bitlocker_status_probe",
        "volume_guid_probe",
        "windows_hive_probe",
        "directory_probe",
    }
    for item in commands:
        command = rendered_command(item)
        assert item["shell"] == "cmd.exe"
        assert item["risk"] in {"metadata_only", "volume_access_gated", "filesystem_access_gated"}
        assert len(command) <= catalog["transport"]["default_max_chars"], (item["id"], len(command))
        if item["risk"] != "metadata_only":
            assert item.get("requires_source_write_protection") is True, item["id"]

    metadata_commands = "\n".join(
        rendered_command(item).lower() for item in commands if item["risk"] == "metadata_only"
    )
    for forbidden in ("dir ", "manage-bde", "mountvol", "fsutil", "chkdsk"):
        assert forbidden not in metadata_commands, forbidden

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


def test_retained_volume_without_physical_disk_blocks_volume_access_and_repair() -> None:
    catalog = load_catalog()
    rules = {item["id"]: item for item in catalog["transition_rules"]}
    rule = rules["retained_volume_without_physical_disk"]
    assert rule["when"]["diskpart_physical_disk_rows"] == 0
    assert rule["when"]["diskpart_volume_rows_minimum"] == 1
    assert rule["classification"] == "backing_device_unavailable"
    assert rule["safe_next_command_id"] == "device_presence_probe"
    assert set(rule["forbidden_until_resolved"]) >= {
        "source_volume_access",
        "chkdsk",
        "startup_repair",
        "reset_this_pc",
        "format",
        "diskpart_clean",
        "reinstall",
    }
    assert "not proof" in rule["proof_boundary"].lower()

    supporting = rules["unlocked_volume_device_missing_supporting_evidence"]
    assert supporting["when"]["bitlocker_lock_status"] == "Unlocked"
    assert supporting["when"]["directory_probe_result"] == "A device which does not exist was specified."
    assert "do not reproduce" in supporting["collection_gate"].lower()
    assert "write protection" in supporting["collection_gate"].lower()


def test_systemrescue_handoff_preserves_backup_and_does_not_overclaim_winre_ro() -> None:
    catalog = load_catalog()
    handoff = catalog["systemrescue_handoff"]
    assert "blockdev --setro" in handoff["source_ro_semantics"]
    assert "not by itself proof" in handoff["source_ro_semantics"].lower()
    required = "\n".join(handoff["required_before_winre"]).lower()
    for marker in ("image artifacts verified", "cleanly detached", "read-only state", "destination disconnected"):
        assert marker in required, marker
    assert "does not survive reboot" in handoff["winre_preservation_limit"].lower()
    assert "not a media write blocker" in handoff["winre_preservation_limit"].lower()
    gate = handoff["winre_write_gate"].lower()
    for marker in ("source-volume access", "physical-device presence", "hardware/controller protection"):
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
    transition = read(TRANSITION_DOC).lower()
    normalized_transition = transition.replace("**", "")
    start = read(START).lower()
    runner = read(RUNNER).lower()

    for text in (transition, start):
        assert "qrfy" in text
        assert "winre-qrfy-catalog.json" in text
    for marker in (
        "backing_device_unavailable",
        "a device which does not exist was specified",
        "do not run chkdsk",
        "blockdev --setro",
        "not by itself proof",
        "terminal photo",
        "does not survive",
        "not the same thing as a media write blocker",
        "requires_source_write_protection=true",
    ):
        assert marker in normalized_transition, marker
    assert "winre_qrfy_transition.md" in start
    assert "test_winre_qrfy_transition_contracts.py" in runner


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: WinRE QRFY transition contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
