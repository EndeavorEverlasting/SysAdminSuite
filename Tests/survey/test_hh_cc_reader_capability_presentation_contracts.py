#!/usr/bin/env python3
"""Contracts for presentation projection + wireless capability factoring."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_capability_orchestrator import run_capability_program
from harness.api.hh_cc_reader_capability_presentation import (
    classify_presentation_delta,
    project_capability_views,
    visible_leak,
)
from harness.api.hh_cc_reader_wireless_capability import (
    classify_airviewer,
    classify_network_adb,
)


def test_android_le10_requires_usb_bootstrap() -> None:
    result = classify_network_adb(android_version=10, usb_adb_bootstrap_proved=False)
    assert result["result"] == "NOT_APPLICABLE"
    assert result["requires_prior_usb_adb"] is True
    assert result["usb_bypass"] is False


def test_android_ge11_wireless_pairing_attended() -> None:
    result = classify_network_adb(
        android_version=11,
        previously_paired_trusted=False,
        pairing_ui_available=True,
        operator_present=False,
    )
    assert result["result"] == "INCONCLUSIVE_ATTENDED_GATE"
    assert result["attended_required"] is True


def test_airviewer_attended_timeout_human_gate() -> None:
    result = classify_airviewer(mode="view", timed_out=True, operator_present=False)
    assert result["result"] == "INCONCLUSIVE_ATTENDED_GATE"
    assert result["human_gate"] is True


def test_airviewer_unattended_needs_provisioning() -> None:
    result = classify_airviewer(mode="unattended", unattended_provisioning_evidence=False)
    assert result["result"] == "AUTHORITY_GATE"


def test_presentation_projection_no_internal_leaks() -> None:
    program = run_capability_program(
        current_topology="LAB_READER_ON_NETWORK_OPERATOR_ABSENT",
        operator_presence="none",
        context={"paxstore_credentials_present": False},
    )
    projection = project_capability_views(program["ledger"])
    visible = json.dumps(projection["views"])
    assert "P00" not in visible
    assert "P01" not in visible
    assert "P04" not in visible
    assert "P82" not in visible
    assert "P95" not in visible
    assert "INCONCLUSIVE_ATTENDED_GATE" not in visible
    assert "PROVEN_NEGATIVE" not in visible
    assert "CREDENTIAL_GATE" not in visible
    assert "harness" not in visible.lower()
    assert visible_leak("Needs a short on-site approval") is None


def test_presentation_delta_material_closed_avenue() -> None:
    delta = classify_presentation_delta(
        event_type="newly_closed_avenue",
        result="PROVEN_NEGATIVE",
        previous_result="NOT_YET_TESTED",
    )
    assert delta["disposition"] == "PRESENTATION_DELTA_REQUIRED"


def test_presentation_delta_not_required_for_noise() -> None:
    delta = classify_presentation_delta(
        event_type=None,
        result="NOT_YET_TESTED",
        previous_result="NOT_YET_TESTED",
        reason_if_not="test noop",
    )
    assert delta["disposition"] == "PRESENTATION_DELTA_NOT_REQUIRED"


def test_rejects_stakeholder_serial_ip_leak() -> None:
    assert visible_leak("Reader at 192.168.1.68") is not None
    assert visible_leak("Serial 1240473751 observed") is not None
    assert visible_leak("Closed by evidence for this configuration.") is None


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for fn in tests:
        try:
            fn()
            print(f"PASS {fn.__name__}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"FAIL {fn.__name__}: {exc}")
    raise SystemExit(1 if failed else 0)
