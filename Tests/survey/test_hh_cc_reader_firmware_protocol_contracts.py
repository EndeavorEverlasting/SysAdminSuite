#!/usr/bin/env python3
"""P95 contracts for additive, site-selectable H&H firmware protocols."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_protocols import (  # noqa: E402
    CONTRACT,
    FirmwareProtocolError,
    load_protocol_contract,
    select_firmware_protocols,
)


class FirmwareProtocolContracts(unittest.TestCase):
    def test_contract_preserves_five_additive_protocols(self) -> None:
        contract = load_protocol_contract()
        self.assertEqual(contract["status"], "IMPLEMENTED")
        self.assertEqual(
            contract["default_preference_order"],
            [
                "experian_control_center",
                "provider_tms_ntms",
                "provider_managed_automatic",
                "paxstore_reseller_push",
                "pax_partner_paydroid_tool",
            ],
        )
        self.assertEqual(set(contract["protocols"]), set(contract["default_preference_order"]))
        self.assertTrue(
            contract["invariants"]["protocols_are_additive_not_mutually_destructive"]
        )
        self.assertTrue(contract["invariants"]["paxstore_is_default_fallback_not_global_default"])
        self.assertEqual(
            contract["protocols"]["paxstore_reseller_push"]["operational_tier"],
            "LAST_RESORT_OR_CORROBORATION",
        )
        self.assertEqual(
            contract["protocols"]["pax_partner_paydroid_tool"]["operational_tier"],
            "LAB_ONLY",
        )

    def test_default_ranking_prefers_control_center_then_tms_without_dropping_fallbacks(self) -> None:
        result = select_firmware_protocols(
            {
                "site_profile_id": "synthetic-hospital-a",
                "evidence_signals": [
                    "EXPERIAN_CONTROL_CENTER_PRESENT",
                    "TMS_ENDPOINT_CONFIGURED",
                    "PAXSTORE_TERMINAL_PRESENT",
                ],
                "authority_signals": [],
                "proven_gates": [],
            }
        )
        self.assertEqual(result["selection_state"], "EVIDENCED_PROTOCOL_SELECTED")
        self.assertEqual(result["primary_protocol"], "experian_control_center")
        self.assertEqual(
            result["evidenced_fallback_protocols"],
            ["provider_tms_ntms", "paxstore_reseller_push"],
        )
        self.assertEqual(result["candidate_count"], 5)
        self.assertEqual(
            result["preserved_protocols"],
            [
                "experian_control_center",
                "provider_tms_ntms",
                "provider_managed_automatic",
                "paxstore_reseller_push",
                "pax_partner_paydroid_tool",
            ],
        )
        self.assertFalse(result["mutation_authorized"])

    def test_site_profile_can_prefer_tms_over_control_center(self) -> None:
        result = select_firmware_protocols(
            {
                "site_profile_id": "synthetic-hospital-b",
                "evidence_signals": [
                    "EXPERIAN_CONTROL_CENTER_PRESENT",
                    "TMS_TID_PRESENT",
                ],
                "preference_order": [
                    "provider_tms_ntms",
                    "experian_control_center",
                ],
            }
        )
        self.assertEqual(result["primary_protocol"], "provider_tms_ntms")
        self.assertEqual(result["evidenced_fallback_protocols"], ["experian_control_center"])
        self.assertEqual(result["candidate_count"], 5)

    def test_paxstore_remains_production_capable_fallback_when_it_is_the_only_evidenced_path(self) -> None:
        result = select_firmware_protocols(
            {
                "site_profile_id": "synthetic-hospital-c",
                "evidence_signals": ["PAXSTORE_ADMINISTRATOR_CENTER_PRESENT"],
            }
        )
        self.assertEqual(result["primary_protocol"], "paxstore_reseller_push")
        row = next(
            item for item in result["candidates"]
            if item["protocol_id"] == "paxstore_reseller_push"
        )
        self.assertEqual(row["operational_tier"], "LAST_RESORT_OR_CORROBORATION")
        self.assertEqual(row["observation_state"], "EVIDENCED")

    def test_lab_only_tool_never_auto_promotes_to_production_primary(self) -> None:
        result = select_firmware_protocols(
            {
                "site_profile_id": "synthetic-lab",
                "evidence_signals": ["PAYDROID_TOOL_AVAILABLE"],
                "authority_signals": ["PARTNER_LAB_MUTATION_AUTHORIZED"],
                "proven_gates": [
                    "BASELINE_LOCKED",
                    "RESTORE_PATH_PROVED",
                    "CONTROLLED_LAB_TARGET",
                ],
            }
        )
        self.assertEqual(result["selection_state"], "ONLY_LAB_PROTOCOL_EVIDENCED")
        self.assertIsNone(result["primary_protocol"])
        lab = next(
            item for item in result["candidates"]
            if item["protocol_id"] == "pax_partner_paydroid_tool"
        )
        self.assertEqual(lab["observation_state"], "LAB_ONLY_EVIDENCED")
        self.assertEqual(
            lab["mutation_readiness"],
            "ELIGIBLE_FOR_SEPARATE_MUTATION_DECISION",
        )
        self.assertFalse(result["mutation_authorized"])

    def test_mutation_readiness_separates_evidence_authority_and_live_gates(self) -> None:
        blocked = select_firmware_protocols(
            {
                "evidence_signals": ["TMS_ENDPOINT_CONFIGURED"],
                "authority_signals": [],
                "proven_gates": [],
            }
        )
        tms = next(
            item for item in blocked["candidates"]
            if item["protocol_id"] == "provider_tms_ntms"
        )
        self.assertEqual(tms["mutation_readiness"], "BLOCKED_AUTHORITY")
        self.assertEqual(tms["missing_authority_signals"], ["TMS_UPDATE_AUTHORIZED"])

        eligible = select_firmware_protocols(
            {
                "evidence_signals": ["TMS_ENDPOINT_CONFIGURED"],
                "authority_signals": ["TMS_UPDATE_AUTHORIZED"],
                "proven_gates": ["BASELINE_LOCKED", "RESTORE_PATH_PROVED"],
            }
        )
        tms = next(
            item for item in eligible["candidates"]
            if item["protocol_id"] == "provider_tms_ntms"
        )
        self.assertEqual(
            tms["mutation_readiness"],
            "ELIGIBLE_FOR_SEPARATE_MUTATION_DECISION",
        )
        self.assertFalse(eligible["mutation_authorized"])

    def test_site_policy_disables_without_erasing_protocol(self) -> None:
        result = select_firmware_protocols(
            {
                "evidence_signals": [
                    "TMS_ENDPOINT_CONFIGURED",
                    "PAXSTORE_TERMINAL_PRESENT",
                ],
                "disabled_protocols": ["provider_tms_ntms"],
            }
        )
        self.assertEqual(result["primary_protocol"], "paxstore_reseller_push")
        disabled = next(
            item for item in result["candidates"]
            if item["protocol_id"] == "provider_tms_ntms"
        )
        self.assertEqual(disabled["observation_state"], "DISABLED_BY_SITE_POLICY")
        self.assertIn("provider_tms_ntms", result["preserved_protocols"])

    def test_unknown_protocol_override_fails_closed(self) -> None:
        with self.assertRaisesRegex(FirmwareProtocolError, "unknown_protocol"):
            select_firmware_protocols(
                {
                    "evidence_signals": [],
                    "preference_order": ["invented_transport"],
                }
            )

    def test_contract_file_is_valid_json(self) -> None:
        payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(payload["selection_schema"], "sas-hh-cc-reader-firmware-protocol-selection/v1")


if __name__ == "__main__":
    unittest.main()
