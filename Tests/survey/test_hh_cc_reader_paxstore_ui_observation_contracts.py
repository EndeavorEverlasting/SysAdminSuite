#!/usr/bin/env python3
"""Call-stack contracts for PAXSTORE Terminal Management UI observation ingest."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_paxstore_terminal_observe import VERSION_DOMAIN
from harness.api.hh_cc_reader_paxstore_ui_observation import (
    compare_ui_api_parity,
    ingest_ui_observation,
)

FIXTURES = ROOT / "Tests/survey/fixtures/hh-cc-reader-paxstore-ui"
SERIAL = "1240473751"
MAC = "C840523C93BA"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_ui_success_maps_firmware_and_freezes_baseline() -> None:
    result = ingest_ui_observation(
        load("success-installed-firmware.json"),
        expected_serial=SERIAL,
        expected_mac=MAC,
        freeze=True,
    )
    assert result["access_state"] == "OBSERVED"
    assert result["identity_bound"] is True
    assert result["current_firmware_value"] == (
        "A80_PayDroid_ui_fixture_firmware_name_NOT_CAMPAIGN_TARGET"
    )
    assert result["version_domain"] == VERSION_DOMAIN
    assert result["current_firmware_value"] != "2.0.15.260522"
    assert result["surface"] == "paxstore_terminal_ui_app_firmware"
    assert result["network_contacted"] is False
    assert result["mutation_performed"] is False
    assert result["package_mapping"]["state"] == "PROVEN"
    assert result["restore_disposition"]["current_package_restorable"] == "YES"
    assert result["baseline"]["baseline_locked"] is True
    assert result["baseline"]["state"] == "BASELINE_LOCKED"
    assert result["identity_resolution"]["state"] == "UNIQUE_TARGET_RESOLVED"


def test_ui_serial_mismatch_rejects() -> None:
    result = ingest_ui_observation(
        load("serial-mismatch.json"),
        expected_serial=SERIAL,
        expected_mac=MAC,
        freeze=True,
    )
    assert result["access_state"] == "IDENTITY_MISMATCH"
    assert result["identity_bound"] is False
    assert "serial_mismatch" in result["identity_rejection_reasons"]
    assert "baseline" not in result
    assert result["mutation_performed"] is False


def test_ui_missing_firmware_field() -> None:
    result = ingest_ui_observation(
        load("missing-firmware.json"),
        expected_serial=SERIAL,
        expected_mac=MAC,
        freeze=True,
    )
    assert result["access_state"] == "FIRMWARE_FIELD_ABSENT"
    assert result["identity_bound"] is True
    assert result["current_firmware_value"] is None
    assert "baseline" not in result
    assert result["package_mapping"]["state"] == "UNPROVEN"


def test_parity_pass_when_ui_and_api_agree() -> None:
    ui = ingest_ui_observation(
        load("success-installed-firmware.json"),
        expected_serial=SERIAL,
        expected_mac=MAC,
    )
    parity = compare_ui_api_parity(ui, load("api-receipt-matching.json"))
    assert parity["IDENTITY_PARITY"] == "PASS"
    assert parity["FIRMWARE_PARITY"] == "PASS"
    assert parity["overall"] == "PASS"
    assert parity["divergences"] == []


def test_parity_divergence_does_not_pick_winner() -> None:
    ui = ingest_ui_observation(
        load("success-installed-firmware.json"),
        expected_serial=SERIAL,
        expected_mac=MAC,
    )
    parity = compare_ui_api_parity(ui, load("api-receipt-firmware-divergence.json"))
    assert parity["IDENTITY_PARITY"] == "PASS"
    assert parity["FIRMWARE_PARITY"] == "FAIL"
    assert parity["overall"] == "DIVERGENCE"
    assert "installed_firmware" in parity["divergences"]
    assert "do not guess" in parity["resolution_rule"].lower()
