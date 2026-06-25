#!/usr/bin/env python3
"""Offline tests for Cybernet tracker cleanup and revisit priority reports."""
from __future__ import annotations

import csv
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def write_csv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def test_cleanup_report_splits_tracker_cleanup_from_revisit_work() -> None:
    with tempfile.TemporaryDirectory() as tmp_raw:
        tmp = Path(tmp_raw)
        resolver = tmp / "resolver.csv"
        cleanup = tmp / "cleanup.csv"
        revisit = tmp / "revisit.csv"
        fields = [
            "input_identifier","target","source_row","device_type",
            "expected_hostname","expected_cybernet_serial","expected_neuron_serial","expected_mac",
            "resolved_hostname","resolved_serial","resolved_mac",
            "observed_hostname","observed_serial","observed_mac",
            "reachability_status","serial_probe_status","classification","follow_up_system",
            "probe_methods_attempted","probe_method_success","probe_confidence",
            "evidence_source","evidence_detail","identity_drift_status",
            "already_had_serial","already_had_mac","can_populate_serial","can_populate_mac",
            "log_status","notes","probed_at",
        ]
        write_csv(
            resolver,
            [
                {
                    "input_identifier": "CYB-SERIAL-100",
                    "target": "CYB-SERIAL-100",
                    "source_row": "100",
                    "device_type": "Cybernet",
                    "expected_hostname": "OLD-HOST",
                    "expected_cybernet_serial": "CYB-SERIAL-100",
                    "expected_neuron_serial": "",
                    "expected_mac": "",
                    "resolved_hostname": "NEW-HOST",
                    "resolved_serial": "CYB-SERIAL-100",
                    "resolved_mac": "AA:BB:CC:DD:EE:10",
                    "observed_hostname": "NEW-HOST",
                    "observed_serial": "CYB-SERIAL-100",
                    "observed_mac": "AA:BB:CC:DD:EE:10",
                    "reachability_status": "offline_identity",
                    "serial_probe_status": "IdentityCollected",
                    "classification": "identity_resolved",
                    "follow_up_system": "Tracker update",
                    "probe_methods_attempted": "manifest_match;identity_csv_lookup",
                    "probe_method_success": "identity_csv_match",
                    "probe_confidence": "medium",
                    "evidence_source": "identity_csv",
                    "evidence_detail": "offline fixture",
                    "identity_drift_status": "hostname_drift",
                    "already_had_serial": "yes",
                    "already_had_mac": "no",
                    "can_populate_serial": "no",
                    "can_populate_mac": "yes",
                    "log_status": "hostname_drift",
                    "notes": "Resolved hostname differs from tracker/input hostname",
                    "probed_at": "2026-06-25 00:00:00",
                },
                {
                    "input_identifier": "CYB-SERIAL-200",
                    "target": "CYB-SERIAL-200",
                    "source_row": "200",
                    "device_type": "Cybernet",
                    "expected_hostname": "CONFLICT-HOST",
                    "expected_cybernet_serial": "CYB-SERIAL-200",
                    "expected_neuron_serial": "",
                    "expected_mac": "",
                    "resolved_hostname": "CONFLICT-HOST",
                    "resolved_serial": "DIFFERENT-SERIAL",
                    "resolved_mac": "",
                    "observed_hostname": "CONFLICT-HOST",
                    "observed_serial": "DIFFERENT-SERIAL",
                    "observed_mac": "",
                    "reachability_status": "offline_identity",
                    "serial_probe_status": "IdentityCollected",
                    "classification": "manual_review",
                    "follow_up_system": "Tracker review",
                    "probe_methods_attempted": "manifest_match;identity_csv_lookup",
                    "probe_method_success": "manual_review_required",
                    "probe_confidence": "conflict",
                    "evidence_source": "identity_csv",
                    "evidence_detail": "offline fixture",
                    "identity_drift_status": "hostname_match",
                    "already_had_serial": "yes",
                    "already_had_mac": "no",
                    "can_populate_serial": "no",
                    "can_populate_mac": "no",
                    "log_status": "serial_conflict",
                    "notes": "Observed serial conflicts with tracker serial",
                    "probed_at": "2026-06-25 00:00:00",
                },
                {
                    "input_identifier": "CYB-SERIAL-300",
                    "target": "CYB-SERIAL-300",
                    "source_row": "300",
                    "device_type": "Cybernet",
                    "expected_hostname": "",
                    "expected_cybernet_serial": "CYB-SERIAL-300",
                    "expected_neuron_serial": "",
                    "expected_mac": "",
                    "resolved_hostname": "",
                    "resolved_serial": "",
                    "resolved_mac": "",
                    "observed_hostname": "",
                    "observed_serial": "",
                    "observed_mac": "",
                    "reachability_status": "not_checked",
                    "serial_probe_status": "not_checked",
                    "classification": "needs_ad_lookup",
                    "follow_up_system": "AD;Vision",
                    "probe_methods_attempted": "manifest_match;identity_csv_lookup",
                    "probe_method_success": "unresolved",
                    "probe_confidence": "none",
                    "evidence_source": "none",
                    "evidence_detail": "Identifier is not resolved by supplied evidence sources",
                    "identity_drift_status": "not_applicable",
                    "already_had_serial": "yes",
                    "already_had_mac": "no",
                    "can_populate_serial": "no",
                    "can_populate_mac": "no",
                    "log_status": "ad_probe_unavailable",
                    "notes": "No AD evidence supplied and no identity evidence found",
                    "probed_at": "2026-06-25 00:00:00",
                },
            ],
            fields,
        )

        run(
            [
                "bash",
                "survey/sas-build-cybernet-cleanup-report.sh",
                "--resolver-csv",
                str(resolver),
                "--output-cleanup",
                str(cleanup),
                "--output-revisit",
                str(revisit),
            ]
        )

        cleanup_rows = read_rows(cleanup)
        revisit_rows = read_rows(revisit)

        assert [row["CleanupStatus"] for row in cleanup_rows] == [
            "hostname_drift",
            "manual_review_required",
            "no_tracker_update",
        ]
        assert cleanup_rows[0]["RecommendedAction"] == "Update tracker hostname from OLD-HOST to NEW-HOST; keep serial as identity."
        assert cleanup_rows[1]["RecommendedAction"].startswith("Do not update tracker automatically")

        assert [row["PriorityBucket"] for row in revisit_rows] == [
            "P1_tracker_cleanup_only",
            "P0_manual_review",
            "P3_ad_vision_lookup_needed",
        ]
        assert revisit_rows[0]["RecommendedAction"].startswith("Update tracker hostname")
        assert revisit_rows[1]["Reason"] == "Serial/MAC conflict"
        assert revisit_rows[2]["RecommendedAction"] == "Check AD/Vision/tracker mapping before scheduling a physical revisit."


if __name__ == "__main__":
    test_cleanup_report_splits_tracker_cleanup_from_revisit_work()
    print("offline cybernet cleanup report tests passed")
