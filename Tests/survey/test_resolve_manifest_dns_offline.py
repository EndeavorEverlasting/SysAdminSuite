#!/usr/bin/env python3
"""Offline tests for manifest DNS resolver classification rows."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "survey" / "sas-resolve-manifest-dns.py"


def load_module():
    spec = importlib.util.spec_from_file_location("sas_resolve_manifest_dns", MODULE_PATH)
    if not spec or not spec.loader:
        raise RuntimeError(f"could not load {MODULE_PATH}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


MOD = load_module()


def assert_classification_fields(row: dict[str, str]) -> None:
    missing = [field for field in MOD.CLASSIFICATION_FIELDS if field not in row]
    assert not missing, f"missing classification fields: {missing}"


def test_no_hostname_serial_row_classifies_target() -> None:
    rows = MOD.build_rows(
        [
            {
                "Serial": "CYB-SERIAL-OFFLINE-001",
                "DeviceType": "Cybernet",
                "Source": "synthetic_manifest.csv",
            }
        ],
        [],
    )
    assert len(rows) == 1
    row = rows[0]
    assert row["Status"] == "NO_HOSTNAME"
    assert row["DeviceRole"] == "target_workstation"
    assert row["RoleConfidence"] == "needs_review"
    assert row["IdentifierType"] == "Serial"
    assert row["CountsTowardCybernetPopulation"] == "Yes"
    assert_classification_fields(row)


def test_no_hostname_mac_row_requires_review_without_population_count() -> None:
    rows = MOD.build_rows(
        [
            {
                "MACAddress": "02:00:00:00:00:02",
                "IdentifierType": "MAC",
                "DeviceType": "Cybernet",
                "Source": "synthetic_manifest.csv",
            }
        ],
        [],
    )
    assert len(rows) == 1
    row = rows[0]
    assert row["Status"] == "NO_HOSTNAME"
    assert row["DeviceRole"] == "target_workstation"
    assert row["RoleConfidence"] == "needs_review"
    assert row["IdentifierType"] == "MAC"
    assert row["CountsTowardCybernetPopulation"] == "No"
    assert_classification_fields(row)


def test_dns_not_found_keeps_classification_fields() -> None:
    original_resolve_host = MOD.resolve_host
    try:
        MOD.resolve_host = lambda _host, _suffixes: ("DNS_NOT_FOUND", "", [], "", "synthetic")
        rows = MOD.build_rows(
            [
                {
                    "HostName": "SYN-NO-DNS-001",
                    "Serial": "CYB-SERIAL-OFFLINE-002",
                    "DeviceType": "Cybernet",
                    "Source": "synthetic_manifest.csv",
                }
            ],
            [],
        )
    finally:
        MOD.resolve_host = original_resolve_host

    assert len(rows) == 1
    row = rows[0]
    assert row["Status"] == "DNS_NOT_FOUND"
    assert row["HostName"] == "SYN-NO-DNS-001"
    assert row["Error"] == "synthetic"
    assert_classification_fields(row)


def main() -> int:
    tests = [
        test_no_hostname_serial_row_classifies_target,
        test_no_hostname_mac_row_requires_review_without_population_count,
        test_dns_not_found_keeps_classification_fields,
    ]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL {test.__name__}: {exc}", file=sys.stderr)
    if failed:
        print(f"{failed} test(s) failed", file=sys.stderr)
        return 1
    print(f"All {len(tests)} DNS resolver offline test(s) passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
