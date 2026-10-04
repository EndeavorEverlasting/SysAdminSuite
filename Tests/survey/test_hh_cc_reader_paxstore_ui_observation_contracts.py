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
    # Campaign package visible without labeled domain bind remains PARTIAL.
    assert result["package_mapping"]["state"] == "PARTIAL"
    assert result["package_mapping"]["campaign_target_domain_state"] == (
        "VERSION_DOMAIN_UNRESOLVED"
    )
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


def test_capture_serial_required_not_inferred_from_expected() -> None:
    result = ingest_ui_observation(
        {
            "mac": MAC,
            "installed_firmware": "A80_PayDroid_no_serial",
            "live_ipv4": "192.168.1.68",
        },
        expected_serial=SERIAL,
        expected_mac=MAC,
        freeze=True,
    )
    assert result["access_state"] == "IDENTITY_MISMATCH"
    assert "capture_missing_serial" in result["identity_rejection_reasons"]
    assert "baseline" not in result


def test_package_mapping_proven_requires_campaign_version() -> None:
    capture = load("success-installed-firmware.json")
    capture["target_package_version"] = "9.9.9.999999"
    result = ingest_ui_observation(capture, expected_serial=SERIAL, expected_mac=MAC)
    assert result["package_mapping"]["state"] == "PARTIAL"


def test_labeled_dual_domain_capture_binds_campaign_and_can_prove_package() -> None:
    capture = {
        "serial": SERIAL,
        "mac": MAC,
        "live_ipv4": "192.168.1.68",
        "labeled_observations": [
            {
                "section": "Installed Firmware",
                "field_heading": "Installed Firmware",
                "value": "PX7A_A80_PayDroid_fixture_NOT_CAMPAIGN",
            },
            {
                "section": "Push App",
                "field_heading": "Available Version",
                "package_name": "PaymentSafe",
                "package_id": "pkg-260522",
                "value": "2.0.15.260522",
            },
        ],
        "target_package_visible": "YES",
        "target_package_id": "pkg-260522",
        "target_package_version": "2.0.15.260522",
        "target_push_surface": "Push App",
        "current_package_restorable": "UNKNOWN",
    }
    result = ingest_ui_observation(capture, expected_serial=SERIAL, expected_mac=MAC, freeze=True)
    assert result["access_state"] == "OBSERVED"
    assert result["version_domain"] == "paydroid_os_build"
    assert result["version_domain_evaluation"]["campaign_target_domain_state"] == "BOUND"
    assert result["version_domain_evaluation"]["campaign_target_version_domain"] == (
        "experian_control_center_payment_package"
    )
    assert result["package_mapping"]["state"] == "PROVEN"
    assert result["baseline"]["state"] == "BASELINE_LOCKED"
