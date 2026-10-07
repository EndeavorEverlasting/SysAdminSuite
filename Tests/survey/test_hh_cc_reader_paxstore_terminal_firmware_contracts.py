#!/usr/bin/env python3
"""Contracts for PAXSTORE terminal firmware adapter (fail-closed mutation)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_paxstore_terminal_firmware import (
    post_verify,
    preview_firmware_push,
    push_firmware,
    push_history,
    resolve_firmware_candidate,
    task_status,
)
from harness.api.hh_cc_reader_paxstore_terminal_observe import observe_terminal_by_sn

FIXTURES = ROOT / "Tests/survey/fixtures/hh-cc-reader-paxstore-firmware"
SERIAL = "1240473751"
MAC = "C840523C93BA"
FM = "A80_PayDroid_target_fixture"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_terminal_observe_via_reuse() -> None:
    result = observe_terminal_by_sn(
        serial_no=SERIAL,
        expected_mac=MAC,
        fixture_payload=load("observe-success.json"),
    )
    assert result["access_state"] == "OBSERVED"
    assert result["current_firmware_value"]
    assert result["mutation_performed"] is False


def test_preview_success_path() -> None:
    result = preview_firmware_push(
        serial_no=SERIAL,
        fm_name=FM,
        expected_mac=MAC,
        observe_fixture=load("observe-success.json"),
        candidate_fixture=load("candidate-resolved.json"),
        history_fixture={"businessCode": 0, "data": {"list": []}},
    )
    assert result["operation"] == "PREVIEW"
    assert result["mutation_authorized"] is False
    assert result["mutation_gate"] == "LIVE_MUTATION_REFUSED_BY_DEFAULT"
    assert result["candidate"]["access_state"] == "RESOLVED"


def test_push_history() -> None:
    result = push_history(
        serial_no=SERIAL,
        fixture_payload=load("history-pending-active.json"),
    )
    assert result["access_state"] == "OBSERVED"
    assert len(result["tasks"]) == 2
    assert {t["status_family"] for t in result["tasks"]} >= {"pending", "active"}


def test_task_status() -> None:
    result = task_status(task_id="t-active", fixture_payload=load("task-status-active.json"))
    assert result["access_state"] == "OBSERVED"
    assert result["task"]["status_family"] == "active"


def test_auth_unavailable() -> None:
    result = preview_firmware_push(
        serial_no=SERIAL,
        fm_name=FM,
        expected_mac=MAC,
        environ={},
    )
    assert result["access_state"] == "CREDENTIAL_GATE"
    assert result["mutation_performed"] is False


def test_terminal_not_found() -> None:
    result = preview_firmware_push(
        serial_no=SERIAL,
        fm_name=FM,
        observe_fixture=load("terminal-not-found.json"),
    )
    assert result["access_state"] == "TERMINAL_NOT_FOUND"


def test_firmware_not_found() -> None:
    result = resolve_firmware_candidate(
        fm_name=FM,
        model_name="A80",
        fixture=load("candidate-not-found.json"),
    )
    assert result["access_state"] == "FIRMWARE_NOT_FOUND"


def test_firmware_not_online() -> None:
    result = resolve_firmware_candidate(
        fm_name="A80_PayDroid_offline",
        model_name="A80",
        fixture=load("candidate-not-online.json"),
    )
    assert result["access_state"] == "FIRMWARE_NOT_ONLINE"


def test_model_mismatch() -> None:
    result = resolve_firmware_candidate(
        fm_name="A920_only_package",
        model_name="A80",
        fixture=load("candidate-model-mismatch.json"),
    )
    assert result["access_state"] == "FIRMWARE_MODEL_MISMATCH"


def test_same_version_pending() -> None:
    result = preview_firmware_push(
        serial_no=SERIAL,
        fm_name=FM,
        observe_fixture=load("observe-success.json"),
        candidate_fixture=load("candidate-resolved.json"),
        history_fixture=load("history-pending-active.json"),
    )
    assert result["mutation_gate"] == "SAME_FIRMWARE_PENDING"


def test_same_version_active() -> None:
    result = preview_firmware_push(
        serial_no=SERIAL,
        fm_name="A80_PayDroid_other",
        observe_fixture=load("observe-success.json"),
        candidate_fixture={
            "businessCode": 0,
            "data": {
                "fmName": "A80_PayDroid_other",
                "compatibleModels": ["A80"],
                "online": True,
            },
        },
        history_fixture=load("history-pending-active.json"),
    )
    assert result["mutation_gate"] == "SAME_FIRMWARE_TASK_ACTIVE"


def test_live_mutation_refused_by_default() -> None:
    result = push_firmware(serial_no=SERIAL, fm_name=FM, allow_mutation=False)
    assert result["access_state"] == "LIVE_MUTATION_REFUSED_BY_DEFAULT"
    assert result["mutation_performed"] is False


def test_post_verify_compare() -> None:
    result = post_verify(
        serial_no=SERIAL,
        intended_fm_name="A80_PayDroid_fixture_firmware_name_NOT_CAMPAIGN_TARGET",
        expected_mac=MAC,
        observe_fixture=load("observe-success.json"),
    )
    assert result["matches_intended"] is True
    assert result["mutation_performed"] is False


def test_no_secret_in_preview_receipt() -> None:
    result = preview_firmware_push(
        serial_no=SERIAL,
        fm_name=FM,
        observe_fixture=load("observe-success.json"),
        candidate_fixture=load("candidate-resolved.json"),
        history_fixture={"businessCode": 0, "data": {"list": []}},
        environ={
            "SAS_PAXSTORE_API_KEY": "KEY",
            "SAS_PAXSTORE_API_SECRET": "SECRETVALUE",
        },
    )
    blob = json.dumps(result)
    assert "SECRETVALUE" not in blob
    assert "api_secret" not in blob.lower() or "[REDACTED]" in blob


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
