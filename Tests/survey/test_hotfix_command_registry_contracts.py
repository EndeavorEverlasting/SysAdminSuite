#!/usr/bin/env python3
"""Static contracts for approved field hotfix command manifests.

These tests keep QR-friendly field commands explicit, reviewable, and bounded.
They do not execute target-side commands.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = REPO_ROOT / "configs" / "hotfix-commands" / "cybernet-setup-completion-flag.json"
SCHEMA_PATH = REPO_ROOT / "schemas" / "harness" / "hotfix-command.schema.json"


def load_manifest() -> dict:
    assert MANIFEST_PATH.exists(), f"missing manifest: {MANIFEST_PATH}"
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def load_schema() -> dict:
    assert SCHEMA_PATH.exists(), f"missing schema: {SCHEMA_PATH}"
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def test_hotfix_command_schema_requires_operator_safe_fields() -> None:
    schema = load_schema()
    required = set(schema["required"])

    for key in [
        "command_id",
        "status",
        "risk_level",
        "requires_operator_confirmation",
        "intended_operator_position",
        "delivery_modes",
        "preconditions",
        "forbidden_use",
        "scan_instructions",
        "cmd_payload",
        "powershell_payload",
        "qr_payloads",
    ]:
        assert key in required

    assert schema["properties"]["requires_operator_confirmation"]["const"] is True
    assert "standing-at-target" in schema["properties"]["intended_operator_position"]["enum"]
    assert "silent-admin-push" not in schema["properties"]["delivery_modes"]["items"]["enum"]


def test_cybernet_setup_completion_manifest_is_versioned_and_operator_confirmed() -> None:
    manifest = load_manifest()

    assert manifest["schema_version"] == "1.0.0"
    assert manifest["command_id"] == "cybernet.setup.childcompletion.setup_exe_3"
    assert manifest["status"] == "approved-field-hotfix"
    assert manifest["version"] == "1.0.0"
    assert manifest["risk_level"] == "medium"
    assert manifest["requires_operator_confirmation"] is True
    assert manifest["intended_operator_position"] == "standing-at-target"


def test_cybernet_setup_completion_manifest_documents_field_preconditions() -> None:
    manifest = load_manifest()
    preconditions = "\n".join(manifest["preconditions"])
    scan_instructions = "\n".join(manifest["scan_instructions"])

    assert "physically standing in front of the target Cybernet" in preconditions
    assert "Windows setup restart/unexpected-error dialog" in preconditions
    assert "Shift+F10" in preconditions
    assert "Shift+F10" in scan_instructions
    assert "Scan the CMD QR payload" in scan_instructions


def test_cybernet_setup_completion_cmd_qr_payload_contains_only_the_confirmed_fix() -> None:
    manifest = load_manifest()
    payload = manifest["qr_payloads"]["cmd_shift_f10"]

    assert payload == manifest["cmd_payload"]
    assert "HKLM\\SYSTEM\\Setup\\Status\\ChildCompletion" in payload
    assert "/v setup.exe" in payload
    assert "/t REG_DWORD" in payload
    assert "/d 3" in payload
    assert "/f" in payload
    assert "shutdown /r /t 0" in payload
    assert len(payload) <= 140, "Shift+F10 QR payload should stay short enough to scan reliably"


def test_cybernet_setup_completion_registry_does_not_claim_admin_silent_execution() -> None:
    manifest = load_manifest()
    forbidden = "\n".join(manifest["forbidden_use"])
    delivery_modes = set(manifest["delivery_modes"])

    assert "Do not run silently from the admin box" in forbidden
    assert "admin-gui-qr-display" in delivery_modes
    assert "suite-clone-local-qr-generation" in delivery_modes
    assert "silent-admin-push" not in delivery_modes


def test_cybernet_setup_completion_manifest_has_no_public_or_secret_bearing_payload() -> None:
    manifest_text = MANIFEST_PATH.read_text(encoding="utf-8").lower()

    forbidden_fragments = [
        "password",
        "credential",
        "secret",
        "token",
        "http://",
        "https://",
        "northwell",
        "agilant",
        "togatech",
    ]

    for fragment in forbidden_fragments:
        assert fragment not in manifest_text, f"manifest should not contain {fragment!r}"
