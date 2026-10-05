#!/usr/bin/env python3
"""Call-stack contracts for labeled version-domain classification."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_roundtrip import freeze_baseline, resolve_target_identity
from harness.api.hh_cc_reader_version_domain import (
    CAMPAIGN_TARGET,
    DOMAIN_EXPERIAN_CC,
    DOMAIN_PAYDROID,
    DOMAIN_SYNTHETIC_DEVICE_FIRMWARE,
    DOMAIN_UNRESOLVED,
    classify_current_firmware_observation,
    classify_labeled_observation,
    evaluate_baseline_transition_eligibility,
    evaluate_fixture_receipt,
    evaluate_version_domains,
)

FIXTURE_DIR = ROOT / "Tests/survey/fixtures/hh-cc-reader-version-domain"
FIXTURE_ORDER = (
    "P1-device-information-current-firmware.json",
    "P2-full-positive-control.json",
    "N1-unlabeled-value.json",
    "N2-target-masquerade.json",
    "N3-non-a80-device.json",
    "N4-package-catalog-confusion.json",
    "N5-application-confusion.json",
    "N6-unknown-source-surface.json",
    "N7-ambiguous-version-heading.json",
    "N8-stale-observation.json",
)


def test_paydroid_installed_firmware_labeled_bind() -> None:
    result = classify_labeled_observation(
        {
            "section": "Installed Firmware",
            "field_heading": "Installed Firmware",
            "value": "PX7A_A80_PayDroid_6.0.1_Taurus_V05.1.07T0_20181219",
        }
    )
    assert result["version_domain"] == DOMAIN_PAYDROID
    assert result["confidence"] == "LABELED_BIND"
    assert result["matches_campaign_target_value"] is False
    assert result["mutation_performed"] is False


def test_campaign_like_value_without_label_unresolved() -> None:
    result = classify_labeled_observation({"value": CAMPAIGN_TARGET})
    assert result["version_domain"] == DOMAIN_UNRESOLVED
    assert result["confidence"] == "UNRESOLVED"
    assert "label_required" in result["reasons"]
    assert result["similarity_mapping_rejected"] is True


def test_installed_apps_campaign_value_binds_experian_hypothesis_domain() -> None:
    result = classify_labeled_observation(
        {
            "section": "Installed Apps",
            "field_heading": "Version",
            "package_name": "PaymentSafe / Control Center",
            "value": "2.0.15.260410",
        }
    )
    assert result["version_domain"] == DOMAIN_EXPERIAN_CC
    assert result["confidence"] == "LABELED_BIND"


def test_push_app_target_binds_campaign_domain() -> None:
    evaluation = evaluate_version_domains(
        [
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
                "value": CAMPAIGN_TARGET,
            },
        ]
    )
    assert evaluation["campaign_target_domain_state"] == "BOUND"
    assert evaluation["campaign_target_version_domain"] == DOMAIN_EXPERIAN_CC
    assert DOMAIN_PAYDROID in evaluation["domains_present"]
    assert evaluation["deploy_eligible_on_domain_alone"] is False
    assert evaluation["sourcing_path"]["state"] == "MARKETPLACE_MEDIATED"


def test_numeric_similarity_alone_never_binds_campaign() -> None:
    evaluation = evaluate_version_domains([{"value": "2.0.15.260410"}, {"value": CAMPAIGN_TARGET}])
    assert evaluation["campaign_target_domain_state"] == "VERSION_DOMAIN_UNRESOLVED"
    assert evaluation["primary_observation"] is None


def _load_fixtures() -> list[dict]:
    fixtures: list[dict] = []
    for name in FIXTURE_ORDER:
        path = FIXTURE_DIR / name
        assert path.is_file(), f"missing fixture {path}"
        fixtures.append(json.loads(path.read_text(encoding="utf-8")))
    return fixtures


def test_synthetic_fixture_sensitivity_matrix() -> None:
    """Positive and negative synthetic fixtures prove classifier + baseline transition sensitivity."""
    receipts = [evaluate_fixture_receipt(item) for item in _load_fixtures()]
    failures = [item for item in receipts if not item["passed"]]
    assert not failures, json.dumps(failures, indent=2)

    negative_ids = {f"N{i}" for i in range(1, 9)}
    negatives = [item for item in receipts if item["fixture_id"] in negative_ids]
    assert len(negatives) == 8
    assert all(item["actual_classification"] != "CURRENT_FIRMWARE_BOUND" for item in negatives)
    assert all(item["actual_transition"] != "ALLOWED" for item in negatives)

    positives = [item for item in receipts if item["fixture_id"] in {"P1", "P2"}]
    assert all(item["actual_classification"] == "CURRENT_FIRMWARE_BOUND" for item in positives)
    assert all(item["actual_transition"] == "ALLOWED" for item in positives)
    assert all(item["actual_version_domain"] == DOMAIN_SYNTHETIC_DEVICE_FIRMWARE for item in positives)


def test_p1_baseline_eligibility_without_live_mutation() -> None:
    """Domain-bound synthetic current value may advance toward baseline; mutation stays false."""
    fixture = json.loads((FIXTURE_DIR / FIXTURE_ORDER[0]).read_text(encoding="utf-8"))
    observation = fixture["input"]
    classification = classify_current_firmware_observation(observation)
    transition = evaluate_baseline_transition_eligibility(classification, observation)
    assert classification["classification"] == "CURRENT_FIRMWARE_BOUND"
    assert transition["baseline_transition"] == "ALLOWED"

    identity_src = {
        "source_serial": "SYNTH-FIXTURE-P1",
        "source_name": "SyntheticKiosk4",
        "expected_mac": "AA-BB-CC-DD-EE-F1",
        "live_mac": "AA:BB:CC:DD:EE:F1",
        "live_ipv4": "192.0.2.50",
        "probe_mac_match": True,
        "identity_proof_state": "UNIQUE_TARGET_RESOLVED",
    }
    identity = resolve_target_identity(identity_src)
    baseline_observation = {
        **identity_src,
        "current_firmware_value": observation["value"],
        "firmware_version_domain": classification["version_domain"],
        "captured_at": observation["observed_at"],
    }
    baseline = freeze_baseline(baseline_observation, identity)
    assert baseline["mutation_authorized"] is False
    assert baseline["current_firmware_value"] == "FW.TEST.1"
    assert transition["baseline_transition"] == "ALLOWED"
    # Eligibility is proven without inventing target firmware or authorizing mutation.
    assert baseline["baseline_locked"] is False
    assert "target_firmware_value" in baseline["missing_fields"]


def _print_fixture_results_table() -> None:
    receipts = [evaluate_fixture_receipt(item) for item in _load_fixtures()]
    print("\nfixture_results:")
    print("| fixture_id | expected_classification | actual_classification | expected_transition | actual_transition | exit_status | passed |")
    print("|---|---|---|---|---|---|---|")
    for item in receipts:
        print(
            f"| {item['fixture_id']} | {item['expected_classification']} | {item['actual_classification']} | "
            f"{item['expected_transition']} | {item['actual_transition']} | {item['exit_status']} | {item['passed']} |"
        )


if __name__ == "__main__":
    tests = [
        test_paydroid_installed_firmware_labeled_bind,
        test_campaign_like_value_without_label_unresolved,
        test_installed_apps_campaign_value_binds_experian_hypothesis_domain,
        test_push_app_target_binds_campaign_domain,
        test_numeric_similarity_alone_never_binds_campaign,
        test_synthetic_fixture_sensitivity_matrix,
        test_p1_baseline_eligibility_without_live_mutation,
    ]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS: {test.__name__}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"FAIL: {test.__name__}: {exc}")
    _print_fixture_results_table()
    raise SystemExit(1 if failed else 0)
