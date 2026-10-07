#!/usr/bin/env python3
"""Contracts for topology-aware capability orchestrator / ledger / attended window."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_capability_ledger import derive_metrics, redact_secrets
from harness.api.hh_cc_reader_capability_orchestrator import (
    build_attended_window_manifest,
    default_capability_catalog,
    run_capability_program,
    select_run_order,
)
from harness.api.hh_cc_reader_capability_topology import classify_measure_outcome


def test_confirmed_otg_no_enumeration_remains_closed() -> None:
    program = run_capability_program(
        current_topology="DESK_COMPUTER_AVAILABLE",
        operator_presence="none",
    )
    entry = next(
        e
        for e in program["ledger"]["entries"]
        if e["capability_id"] == "usb_otg_adb_current_config"
    )
    assert entry["latest_result"] == "PROVEN_NEGATIVE"
    assert "usb_otg_adb_current_config" not in program["executed_capability_ids"]


def test_human_prompt_timeout_is_attended_gate_not_negative() -> None:
    result = classify_measure_outcome(
        timed_out=True,
        human_prompt_possible=True,
        operator_present=False,
        definitive_negative=False,
    )
    assert result == "INCONCLUSIVE_ATTENDED_GATE"
    assert result != "PROVEN_NEGATIVE"


def test_independent_successor_runs_after_attended_gate() -> None:
    def measure(cap, ctx):
        if cap["capability_id"] == "airviewer_attended_view":
            return {
                "timed_out": True,
                "human_prompt_possible": True,
                "summary": "approval waiting",
            }
        if cap["capability_id"] == "repo_engineering":
            return {"positive": True, "summary": "ok"}
        if cap["capability_id"] in {
            "paxstore_terminal_observe",
            "paxstore_firmware_preview",
            "firmware_source_portability",
            "presentation_projection",
        }:
            return {"positive": True, "summary": "ok"}
        return {"not_yet": True}

    program = run_capability_program(
        current_topology="LAB_READER_ON_NETWORK_OPERATOR_ABSENT",
        operator_presence="none",
        measure=measure,
        context={"paxstore_credentials_present": True},
    )
    assert "airviewer_attended_view" in program["executed_capability_ids"]
    air = next(
        r for r in program["receipts"] if r["capability_id"] == "airviewer_attended_view"
    )
    assert air["result"] == "INCONCLUSIVE_ATTENDED_GATE"
    assert "repo_engineering" in program["executed_capability_ids"]
    assert "paxstore_terminal_observe" in program["executed_capability_ids"]
    assert program["program_terminated_early"] is False


def test_topology_missing_is_deferred_not_absent() -> None:
    program = run_capability_program(
        current_topology="DESK_COMPUTER_AVAILABLE",
        operator_presence="none",
    )
    same_net = next(
        e
        for e in program["ledger"]["entries"]
        if e["capability_id"] == "same_network_exact_target_probe"
    )
    assert same_net["latest_result"] == "DEFERRED_TOPOLOGY_UNAVAILABLE"


def test_operator_absent_no_interactive_retry_loop() -> None:
    program = run_capability_program(
        current_topology="DESK_COMPUTER_AVAILABLE",
        operator_presence="none",
        interactive_retry=True,
    )
    assert program["interactive_retry_allowed"] is False


def test_attended_window_collapses_multiple_gates() -> None:
    catalog = default_capability_catalog()
    results = {
        "airviewer_attended_view": {
            "result": "INCONCLUSIVE_ATTENDED_GATE",
            "receipt": {"summary": "view timeout"},
        },
        "android_ge11_wireless_pairing": {
            "result": "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
            "receipt": {"summary": "pairing UI"},
        },
    }
    manifest = build_attended_window_manifest(catalog, results)
    assert manifest["batch_count"] >= 1
    total = sum(len(b["experiments"]) for b in manifest["batches"])
    assert total >= 2


def test_high_cost_not_selected_while_lower_remains() -> None:
    catalog = default_capability_catalog()
    order = select_run_order(
        catalog,
        current_topology="ADMIN_BOX_RELOCATED_TO_LAB",
        operator_presence="required",
        prior_results={"usb_otg_adb_current_config": "PROVEN_NEGATIVE"},
        usb_adb_bootstrap_proved=False,
        android_version=10,
        airviewer_unattended_provisioned=False,
        new_usb_discriminator=False,
    )
    ids = [c["capability_id"] for c in order]
    if "same_network_exact_target_probe" in ids:
        # only allowed when no zero/low remain
        lower = [
            c
            for c in order
            if c["interruption_cost"] in {"zero", "low"}
            and c["capability_id"] != "same_network_exact_target_probe"
        ]
        assert not lower
    program = run_capability_program(
        current_topology="DESK_COMPUTER_AVAILABLE",
        operator_presence="none",
        context={"paxstore_credentials_present": True},
    )
    assert program["high_cost_selected_while_lower_remained"] is False
    assert "same_network_exact_target_probe" not in program["executed_capability_ids"]


def test_metrics_derived_from_ledger() -> None:
    program = run_capability_program(
        current_topology="DESK_COMPUTER_AVAILABLE",
        operator_presence="none",
        context={"paxstore_credentials_present": True},
    )
    metrics = program["metrics"]
    assert metrics["TOTAL_AVENUES_MODELED"] == len(program["ledger"]["entries"])
    assert metrics == derive_metrics(program["ledger"]["entries"])
    assert metrics["TOTAL_AVENUES_MODELED"] >= 10


def test_secret_hygiene_in_redaction() -> None:
    cleaned = redact_secrets(
        {"api_secret": "SUPERSECRET", "summary": "ok", "nested": {"token": "x"}}
    )
    assert cleaned["api_secret"] == "[REDACTED]"
    assert cleaned["nested"]["token"] == "[REDACTED]"
    assert "SUPERSECRET" not in json.dumps(cleaned)


def test_android_le10_network_adb_requires_usb_bootstrap() -> None:
    program = run_capability_program(
        current_topology="DUAL_TRANSPORT_ATTENDED",
        operator_presence="required",
        context={"usb_adb_bootstrap_proved": False, "android_version": 10},
    )
    entry = next(
        e for e in program["ledger"]["entries"] if e["capability_id"] == "android_le10_network_adb"
    )
    assert entry["latest_result"] == "NOT_APPLICABLE"


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
