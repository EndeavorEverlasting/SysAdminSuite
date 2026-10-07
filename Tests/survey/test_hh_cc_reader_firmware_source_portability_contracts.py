#!/usr/bin/env python3
"""Contracts for firmware source/provenance + reader-to-reader portability."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_source_portability import evaluate_portability

FIXTURES = ROOT / "Tests/survey/fixtures/hh-cc-reader-firmware-portability"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_signed_full_ota() -> None:
    result = evaluate_portability(load("signed-full-ota.json"))
    assert result["artifact_class"] == "VENDOR_SIGNED_FULL_OTA"
    assert result["result"] == "PROVEN_REUSABLE_SIGNED_ARTIFACT"
    assert result["provenance"]["sha256_proves"] == "artifact_identity_not_trust"


def test_signed_incremental_source_build_match() -> None:
    result = evaluate_portability(load("signed-incremental-match.json"))
    assert result["artifact_class"] == "VENDOR_SIGNED_INCREMENTAL_OTA"
    assert result["result"] == "PROVEN_REUSABLE_FOR_SOURCE_BUILD_COHORT"
    assert result["portability"]["source_build_match"] is True


def test_signed_incremental_source_build_mismatch() -> None:
    result = evaluate_portability(load("signed-incremental-mismatch.json"))
    assert result["result"] == "PROVEN_NOT_PORTABLE"
    assert "incremental_source_build_mismatch" in result["reasons"]


def test_ab_payload_classification() -> None:
    result = evaluate_portability(load("ab-payload.json"))
    assert result["artifact_class"] == "ANDROID_AB_PAYLOAD"
    assert result["supported_apply_mechanism"] == "UPDATE_ENGINE_PAYLOAD"
    assert result["result"] == "INCONCLUSIVE_PRIVILEGE_REQUIRED"


def test_raw_partition_not_automatically_admitted() -> None:
    result = evaluate_portability(load("raw-partition.json"))
    assert result["artifact_class"] == "GENERIC_SYSTEM_PARTITION_IMAGE"
    assert result["result"] == "AUTHORITY_GATE"


def test_device_unique_security_state_excluded() -> None:
    result = evaluate_portability(load("security-state.json"))
    assert result["artifact_class"] == "SECURITY_OR_PAYMENT_STATE"
    assert result["result"] == "PROVEN_NOT_PORTABLE"
    assert result["device_unique_exclusion"]["clone_candidate_admitted"] is False
    assert "cloning unsafe" not in json.dumps(result).lower()


def test_torrent_hash_not_production_safe() -> None:
    result = evaluate_portability(load("torrent-hash-only.json"))
    assert result["result"] == "POLICY_REJECTED"
    assert result["provenance"]["sha256"]


def test_no_blanket_a80_assumption() -> None:
    result = evaluate_portability(load("signed-full-ota.json"))
    assert result["portability"]["all_a80_assumed_compatible"] is False
    assert result["portability"]["all_a80_assumed_incompatible"] is False


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
