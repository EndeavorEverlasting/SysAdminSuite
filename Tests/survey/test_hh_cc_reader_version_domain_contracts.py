#!/usr/bin/env python3
"""Call-stack contracts for labeled version-domain classification."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_version_domain import (
    CAMPAIGN_TARGET,
    DOMAIN_EXPERIAN_CC,
    DOMAIN_PAYDROID,
    DOMAIN_UNRESOLVED,
    classify_labeled_observation,
    evaluate_version_domains,
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
