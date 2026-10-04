#!/usr/bin/env python3
"""Call-stack contracts for PAXSTORE serial-bound installed-firmware observation."""
from __future__ import annotations

import hashlib
import hmac
import json
import sys
from pathlib import Path
from urllib.parse import parse_qsl, urlparse

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_paxstore_terminal_observe import (
    VERSION_DOMAIN,
    build_signed_get,
    observe_terminal_by_sn,
)

FIXTURES = ROOT / "Tests/survey/fixtures/hh-cc-reader-paxstore-terminal"
SERIAL = "1240473751"
MAC = "C840523C93BA"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_credential_gate_without_env() -> None:
    result = observe_terminal_by_sn(serial_no=SERIAL, expected_mac=MAC, environ={})
    assert result["access_state"] == "CREDENTIAL_GATE"
    assert result["network_contacted"] is False
    assert result["current_firmware_value"] is None
    assert result["mutation_performed"] is False


def test_fixture_success_maps_firmware_and_domain() -> None:
    result = observe_terminal_by_sn(
        serial_no=SERIAL,
        expected_mac=MAC,
        live_ipv4="192.168.1.68",
        fixture_payload=load("success-installed-firmware.json"),
        freeze=True,
    )
    assert result["access_state"] == "OBSERVED"
    assert result["identity_bound"] is True
    assert result["current_firmware_value"] == "A80_PayDroid_fixture_firmware_name_NOT_CAMPAIGN_TARGET"
    assert result["version_domain"] == VERSION_DOMAIN
    assert result["current_firmware_value"] != "2.0.15.260522"
    assert result["baseline"]["baseline_locked"] is True
    assert result["baseline"]["state"] == "BASELINE_LOCKED"
    assert result["identity_resolution"]["state"] == "UNIQUE_TARGET_RESOLVED"


def test_serial_mismatch_rejects() -> None:
    result = observe_terminal_by_sn(
        serial_no=SERIAL,
        expected_mac=MAC,
        fixture_payload=load("serial-mismatch.json"),
    )
    assert result["access_state"] == "IDENTITY_MISMATCH"
    assert result["identity_bound"] is False
    assert "serial_mismatch" in result["identity_rejection_reasons"]


def test_missing_firmware_field() -> None:
    result = observe_terminal_by_sn(
        serial_no=SERIAL,
        expected_mac=MAC,
        fixture_payload=load("missing-firmware.json"),
    )
    assert result["access_state"] == "FIRMWARE_FIELD_ABSENT"
    assert result["identity_bound"] is True
    assert result["current_firmware_value"] is None


def test_signed_query_matches_hmac_header() -> None:
    url, headers, query = build_signed_get(
        base_url="https://api.whatspos.com/p-market-api",
        api_key="KEY",
        api_secret="SECRET",
        serial_no=SERIAL,
        timestamp_ms=1_700_000_000_000,
    )
    expected = (
        hmac.new(b"SECRET", query.encode("utf-8"), hashlib.sha256).hexdigest().upper()
    )
    assert headers["signature"] == expected
    assert url.endswith("?" + query)
    params = dict(parse_qsl(urlparse(url).query, keep_blank_values=True))
    assert params["serialNo"] == SERIAL
    assert params["includeInstalledFirmware"] == "true"
    assert params["sysKey"] == "KEY"


def test_transport_injection_no_network_secret_leak() -> None:
    seen: dict[str, str] = {}

    def fake_transport(url: str, headers: dict[str, str]) -> dict:
        seen["url"] = url
        seen["signature"] = headers["signature"]
        return load("success-installed-firmware.json")

    result = observe_terminal_by_sn(
        serial_no=SERIAL,
        expected_mac=MAC,
        environ={
            "SAS_PAXSTORE_API_KEY": "KEY",
            "SAS_PAXSTORE_API_SECRET": "SECRET",
            "SAS_PAXSTORE_BASE_URL": "https://api.whatspos.com/p-market-api",
        },
        transport=fake_transport,
    )
    assert result["access_state"] == "OBSERVED"
    assert "SECRET" not in json.dumps(result)
    assert "includeInstalledFirmware=true" in seen["url"]
    assert seen["signature"]


def main() -> int:
    tests = [
        test_credential_gate_without_env,
        test_fixture_success_maps_firmware_and_domain,
        test_serial_mismatch_rejects,
        test_missing_firmware_field,
        test_signed_query_matches_hmac_header,
        test_transport_injection_no_network_secret_leak,
    ]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:  # noqa: BLE001 - contract runner
            failed += 1
            print(f"FAIL {test.__name__}: {exc}")
    print(f"{'PASSED' if failed == 0 else 'FAILED'} {len(tests) - failed}/{len(tests)}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
