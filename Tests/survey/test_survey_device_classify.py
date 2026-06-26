#!/usr/bin/env python3
"""Offline unit tests for survey device classifier."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "survey" / "sas-survey-device-classify.py"


def load_module():
    import sys
    spec = importlib.util.spec_from_file_location("sas_survey_device_classify", MODULE_PATH)
    if not spec or not spec.loader:
        raise RuntimeError(f"could not load {MODULE_PATH}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


MOD = load_module()
classify_device = MOD.classify_device


def test_ap_reverse_dns():
    result = classify_device(
        hostname="NSUH-AP-12",
        reverse_dns_names="ap-nsuh-floor3.example.org",
        survey_lane="subnet_discovery",
        in_manifest=False,
    )
    assert result.device_role == "infrastructure_access_point"
    assert result.counts_toward_cybernet_population == "No"


def test_cybernet_manifest_workstation():
    result = classify_device(
        hostname="NSUH12WMH01",
        device_type="Cybernet",
        serial="CYB-SERIAL-001",
        identifier_type="Serial",
        survey_lane="cybernet_manifest",
        in_manifest=True,
    )
    assert result.device_role == "target_workstation"
    assert result.counts_toward_cybernet_population == "Yes"
    assert result.identifier_type == "Serial"
    assert result.survey_authority == "serial"


def test_printer_ports():
    result = classify_device(
        hostname="10.10.10.50",
        open_ports=["9100", "445"],
        survey_lane="subnet_discovery",
        in_manifest=False,
    )
    assert result.device_role == "infrastructure_print"
    assert result.counts_toward_cybernet_population == "No"


def test_discovery_only_subnet_lane():
    result = classify_device(
        hostname="MYSTERY-HOST",
        survey_lane="subnet_discovery",
        in_manifest=False,
    )
    assert result.device_role == "discovery_only"
    assert result.survey_authority == "subnet_inference_only"


def test_aruba_vendor_ap():
    result = classify_device(
        hostname="10.1.1.5",
        reverse_dns_names="wireless-controller",
        mac_vendor="Aruba Networks",
        survey_lane="subnet_discovery",
        in_manifest=False,
    )
    assert result.device_role == "infrastructure_access_point"


def test_classify_from_dns_row():
    row = {
        "HostName": "NSUH12WMH02",
        "DeviceType": "Cybernet",
        "Serial": "ABC123",
        "ReverseNames": "",
        "IdentifierType": "Serial",
    }
    out = MOD.classify_from_dns_row(row)
    assert out["SurveyLane"] == "cybernet_manifest"
    assert out["DeviceRole"] == "target_workstation"
    assert "DeviceRole" in out


def main() -> int:
    tests = [
        test_ap_reverse_dns,
        test_cybernet_manifest_workstation,
        test_printer_ports,
        test_discovery_only_subnet_lane,
        test_aruba_vendor_ap,
        test_classify_from_dns_row,
    ]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except AssertionError as exc:
            failed += 1
            print(f"FAIL {test.__name__}: {exc}", file=sys.stderr)
    if failed:
        print(f"{failed} test(s) failed", file=sys.stderr)
        return 1
    print(f"All {len(tests)} classifier tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
