#!/usr/bin/env python3
"""P95 contracts for additive, site-selectable H&H firmware protocols."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_protocols import (  # noqa: E402
    CONTRACT,
    FirmwareProtocolError,
    dispatch_protocol_observation,
    load_protocol_contract,
    select_and_dispatch,
    select_firmware_protocols,
)

from harness.api.hh_cc_reader_version_domain import (  # noqa: E402
    evaluate_version_domains,
    observations_from_ui_capture,
)

LAUNCHER = ROOT / "Select-HHCCReaderFirmwareProtocol.cmd"
COMMAND_REGISTRY = ROOT / "harness/api/harness-command-registry.json"
CAPTURE_TEMPLATE = ROOT / "docs/examples/hh-cc-reader-kiosk4-version-evidence-capture.template.json"
FIELD_GUIDE = ROOT / "docs/HH_CC_READER_KIOSK4_LOCAL_ACCESS_FIELD_GUIDE.md"


def proven_site(
    *,
    profile_id: str = "synthetic-hh-site-a",
    site_id: str = "synthetic-site-a",
    preference_order: list[str] | None = None,
    disabled_protocols: list[str] | None = None,
) -> dict:
    return {
        "profile_id": profile_id,
        "organization_id": "health-and-hospitals",
        "scope_type": "site_override",
        "status": "PROVEN",
        "profile_authority_ref": "PRIVATE_PROFILE_RECEIPT:synthetic",
        "site_id": site_id,
        "preference_order": preference_order or [],
        "disabled_protocols": disabled_protocols or [],
    }


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
        self.assertTrue(contract["invariants"]["protocols_are_additive_not_mutually_destructive"])
        self.assertTrue(contract["invariants"]["paxstore_is_default_fallback_not_global_default"])
        self.assertTrue(contract["invariants"]["unknown_or_unproven_site_profile_blocks_mutation_readiness"])
        self.assertTrue(contract["invariants"]["observation_dispatch_never_performs_mutation"])
        self.assertTrue(contract["invariants"]["artifact_acquisition_is_independent_from_observation_and_deployment_transport"])
        self.assertTrue(contract["invariants"]["public_search_absence_is_not_global_package_absence"])
        self.assertTrue(contract["invariants"]["paxstore_presentation_completeness_cannot_block_firmware_execution"])
        self.assertTrue(contract["invariants"]["observation_refresh_does_not_wait_for_artifact_acquisition"])
        self.assertEqual(contract["observation_refresh_policy"]["state"], "REPEATABLE_INDEPENDENT_LANE")
        self.assertIn("BEFORE_CONTROLLED_MUTATION", contract["observation_refresh_policy"]["required_triggers"])
        self.assertIn("AFTER_CONTROLLED_MUTATION", contract["observation_refresh_policy"]["required_triggers"])
        self.assertEqual(
            contract["dendritic_execution_model"]["axes"],
            ["OBSERVE_CURRENT_STATE", "ACQUIRE_FIRMWARE_ARTIFACT_OR_PROVIDER_DELIVERY", "SELECT_DEPLOYMENT_TRANSPORT"],
        )
        self.assertEqual(contract["artifact_acquisition"]["sources"]["public_web_research"]["role"], "DISCOVERY_ONLY")
        self.assertEqual(contract["artifact_acquisition"]["sources"]["paxstore_firmware_list"]["role"], "FALLBACK_OR_CORROBORATION")
        self.assertEqual(contract["protocols"]["paxstore_reseller_push"]["operational_tier"], "LAST_RESORT_OR_CORROBORATION")
        self.assertEqual(contract["protocols"]["pax_partner_paydroid_tool"]["operational_tier"], "LAB_ONLY")

    def test_version_evidence_capture_template_is_classifier_native_and_fail_closed(self) -> None:
        contract = load_protocol_contract()
        capture_contract = contract["version_evidence_capture_contract"]
        template = json.loads(CAPTURE_TEMPLATE.read_text(encoding="utf-8"))

        self.assertEqual(template["schema"], capture_contract["schema_version"])
        self.assertEqual(template["capture_state"], capture_contract["default_capture_state"])
        self.assertEqual(template["labeled_observations"], [])
        self.assertIsNone(template["identity_binding_reference"])
        self.assertNotIn("current_firmware_value", template)
        self.assertFalse(template["mutation_authorized"])
        self.assertEqual(
            capture_contract["classifier_required_observation_fields"],
            ["section", "field_heading", "value"],
        )

        observations = observations_from_ui_capture(template)
        self.assertEqual(observations, [])
        evaluation = evaluate_version_domains(observations)
        self.assertIsNone(evaluation["primary_observation"])
        self.assertEqual(evaluation["campaign_target_domain_state"], "VERSION_DOMAIN_UNRESOLVED")

    def test_version_evidence_capture_filled_shape_flows_directly_to_classifier(self) -> None:
        template = json.loads(CAPTURE_TEMPLATE.read_text(encoding="utf-8"))
        template["capture_state"] = "LABELED_OBSERVATION_CAPTURED"
        template["source_surface"] = "synthetic-read-only-version-screen"
        template["navigation_path"] = ["Settings", "About", "Software"]
        template["observed_at"] = "2099-01-01T00:00:00Z"
        template["identity_binding_reference"] = "PRIVATE_SYNTHETIC_IDENTITY_REF"
        template["labeled_observations"] = [
            {
                "section": "Installed Firmware",
                "field_heading": "Installed Firmware",
                "value": "PX7A_A80_PayDroid_fixture_NOT_CAMPAIGN",
                "package_name": None,
                "package_id": None,
                "install_time": None,
            }
        ]

        observations = observations_from_ui_capture(template)
        self.assertEqual(len(observations), 1)
        evaluation = evaluate_version_domains(observations)
        self.assertIsNotNone(evaluation["primary_observation"])
        self.assertEqual(evaluation["primary_observation"]["confidence"], "LABELED_BIND")
        self.assertFalse(evaluation["mutation_performed"])

    def test_field_guide_uses_classifier_native_capture_keys(self) -> None:
        guide = FIELD_GUIDE.read_text(encoding="utf-8")
        self.assertNotIn("section_heading\nfield_label\ndisplayed_value", guide)
        self.assertIn("section\nfield_heading\nvalue", guide)

    def test_presentation_showcase_cannot_promote_technical_state(self) -> None:
        contract = load_protocol_contract()
        showcase = contract["presentation_showcase_contract"]
        self.assertTrue(contract["invariants"]["presentation_is_projection_not_authority"])
        self.assertTrue(contract["invariants"]["version_evidence_capture_defaults_fail_closed"])
        self.assertTrue(contract["invariants"]["presentation_projection_never_promotes_technical_evidence"])
        self.assertTrue(showcase["rules"]["presentation_is_not_a_technical_authority"])
        self.assertTrue(showcase["rules"]["downstream_presentation_cannot_select_protocol_or_authorize_mutation"])
        self.assertEqual(showcase["state_projection"]["BASELINE_LOCKED"]["typed_state"], "PROVEN")
        self.assertEqual(
            showcase["state_projection"]["AWAITING_FIELD_OBSERVATION"]["typed_state"],
            "BLOCKED_EVIDENCE",
        )

    def test_capture_contract_key_drift_fails_closed(self) -> None:
        payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
        payload["version_evidence_capture_contract"]["classifier_required_observation_fields"] = [
            "section_heading",
            "field_label",
            "displayed_value",
        ]
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad-capture-contract.json"
            bad.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(FirmwareProtocolError, "classifier_keys_invalid"):
                load_protocol_contract(bad)

    def test_showcase_contract_cannot_drop_no_promotion_rule(self) -> None:
        payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
        payload["presentation_showcase_contract"]["rules"][
            "successful_visual_narrative_must_not_promote_unproven_runtime_state"
        ] = False
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad-showcase-contract.json"
            bad.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(FirmwareProtocolError, "presentation_showcase_rule_missing"):
                load_protocol_contract(bad)

    def test_malformed_contract_root_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.json"
            bad.write_text("[]\n", encoding="utf-8")
            with self.assertRaisesRegex(FirmwareProtocolError, "root_must_be_object"):
                load_protocol_contract(bad)

    def test_default_ranking_prefers_control_center_then_tms_without_dropping_fallbacks(self) -> None:
        result = select_firmware_protocols({
            "site_profile": proven_site(),
            "evidence_signals": [
                "EXPERIAN_CONTROL_CENTER_PRESENT",
                "TMS_ENDPOINT_CONFIGURED",
                "PAXSTORE_TERMINAL_PRESENT",
            ],
            "authority_signals": [],
            "proven_gates": [],
        })
        self.assertEqual(result["selection_state"], "EVIDENCED_PROTOCOL_SELECTED")
        self.assertEqual(result["primary_protocol"], "experian_control_center")
        self.assertEqual(result["evidenced_fallback_protocols"], ["provider_tms_ntms", "paxstore_reseller_push"])
        self.assertEqual(result["candidate_count"], 5)
        self.assertTrue(result["site_profile_proven"])
        self.assertFalse(result["mutation_authorized"])

    def test_site_profile_can_prefer_tms_over_control_center(self) -> None:
        result = select_firmware_protocols({
            "site_profile": proven_site(preference_order=["provider_tms_ntms", "experian_control_center"]),
            "evidence_signals": ["EXPERIAN_CONTROL_CENTER_PRESENT", "TMS_TID_PRESENT"],
        })
        self.assertEqual(result["primary_protocol"], "provider_tms_ntms")
        self.assertEqual(result["evidenced_fallback_protocols"], ["experian_control_center"])
        self.assertEqual(result["candidate_count"], 5)

    def test_paxstore_remains_production_capable_fallback_when_only_evidenced_path(self) -> None:
        result = select_firmware_protocols({
            "site_profile": proven_site(),
            "evidence_signals": ["PAXSTORE_ADMINISTRATOR_CENTER_PRESENT"],
        })
        self.assertEqual(result["primary_protocol"], "paxstore_reseller_push")
        row = next(item for item in result["candidates"] if item["protocol_id"] == "paxstore_reseller_push")
        self.assertEqual(row["operational_tier"], "LAST_RESORT_OR_CORROBORATION")
        self.assertEqual(row["observation_state"], "EVIDENCED")

    def test_lab_only_tool_never_auto_promotes_to_production_primary(self) -> None:
        result = select_firmware_protocols({
            "site_profile": proven_site(),
            "evidence_signals": ["PAYDROID_TOOL_AVAILABLE"],
            "authority_signals": ["PARTNER_LAB_MUTATION_AUTHORIZED"],
            "proven_gates": ["BASELINE_LOCKED", "RESTORE_PATH_PROVED", "CONTROLLED_LAB_TARGET"],
        })
        self.assertEqual(result["selection_state"], "ONLY_LAB_PROTOCOL_EVIDENCED")
        self.assertIsNone(result["primary_protocol"])
        lab = next(item for item in result["candidates"] if item["protocol_id"] == "pax_partner_paydroid_tool")
        self.assertEqual(lab["observation_state"], "LAB_ONLY_EVIDENCED")
        self.assertEqual(lab["mutation_readiness"], "ELIGIBLE_FOR_SEPARATE_MUTATION_DECISION")
        self.assertFalse(result["mutation_authorized"])

    def test_missing_or_unproven_site_profile_blocks_mutation_readiness(self) -> None:
        base = {
            "evidence_signals": ["TMS_ENDPOINT_CONFIGURED"],
            "authority_signals": ["TMS_UPDATE_AUTHORIZED"],
            "proven_gates": ["BASELINE_LOCKED", "RESTORE_PATH_PROVED"],
        }
        missing = select_firmware_protocols(base)
        tms = next(item for item in missing["candidates"] if item["protocol_id"] == "provider_tms_ntms")
        self.assertFalse(missing["site_profile_proven"])
        self.assertEqual(tms["mutation_readiness"], "BLOCKED_SITE_PROFILE")

        unproven = select_firmware_protocols({
            **base,
            "site_profile": {**proven_site(), "status": "DISCOVERY_REQUIRED"},
        })
        tms = next(item for item in unproven["candidates"] if item["protocol_id"] == "provider_tms_ntms")
        self.assertEqual(tms["mutation_readiness"], "BLOCKED_SITE_PROFILE")

        proven = select_firmware_protocols({**base, "site_profile": proven_site()})
        tms = next(item for item in proven["candidates"] if item["protocol_id"] == "provider_tms_ntms")
        self.assertEqual(tms["mutation_readiness"], "ELIGIBLE_FOR_SEPARATE_MUTATION_DECISION")
        self.assertFalse(proven["mutation_authorized"])

    def test_site_policy_disables_without_erasing_protocol(self) -> None:
        result = select_firmware_protocols({
            "site_profile": proven_site(disabled_protocols=["provider_tms_ntms"]),
            "evidence_signals": ["TMS_ENDPOINT_CONFIGURED", "PAXSTORE_TERMINAL_PRESENT"],
        })
        self.assertEqual(result["primary_protocol"], "paxstore_reseller_push")
        disabled = next(item for item in result["candidates"] if item["protocol_id"] == "provider_tms_ntms")
        self.assertEqual(disabled["observation_state"], "DISABLED_BY_SITE_POLICY")
        self.assertIn("provider_tms_ntms", result["preserved_protocols"])

    def test_unknown_protocol_or_wrong_organization_fails_closed(self) -> None:
        with self.assertRaisesRegex(FirmwareProtocolError, "unknown_protocol"):
            select_firmware_protocols({
                "site_profile": proven_site(preference_order=["invented_transport"]),
                "evidence_signals": [],
            })
        with self.assertRaisesRegex(FirmwareProtocolError, "wrong_organization"):
            select_firmware_protocols({
                "site_profile": {**proven_site(), "organization_id": "northwell-health"},
                "evidence_signals": [],
            })

    def test_dispatch_consumes_primary_protocol_and_never_mutates(self) -> None:
        result = select_and_dispatch({
            "site_profile": proven_site(),
            "evidence_signals": ["PAXSTORE_TERMINAL_PRESENT"],
        })
        self.assertEqual(result["selection"]["primary_protocol"], "paxstore_reseller_push")
        dispatch = result["dispatch"]
        self.assertEqual(dispatch["dispatch_state"], "READONLY_OBSERVATION_READY")
        self.assertEqual(dispatch["protocol_id"], "paxstore_reseller_push")
        self.assertEqual(dispatch["front_door"], "Observe-HHCCReaderPaxstoreTerminal.cmd")
        self.assertFalse(dispatch["mutation_authorized"])
        self.assertIn("without submitting", dispatch["next_action"])

    def test_dispatch_without_evidenced_production_protocol_routes_to_discovery(self) -> None:
        selection = select_firmware_protocols({"evidence_signals": []})
        dispatch = dispatch_protocol_observation(selection)
        self.assertEqual(dispatch["dispatch_state"], "NO_PRODUCTION_PROTOCOL_SELECTED")
        self.assertEqual(dispatch["mode"], "READONLY_DISCOVERY")
        self.assertFalse(dispatch["mutation_authorized"])

    def test_windows_front_door_is_tracked_and_propagates_exit_code(self) -> None:
        text = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn("hh_cc_reader_firmware_protocols.py", text)
        self.assertIn(" dispatch --input ", text)
        self.assertIn("exit /b %ERRORLEVEL%", text)
        self.assertIn("Protocol selection NEVER authorizes firmware mutation.", text)

    def test_launcher_is_registered_as_read_only_command(self) -> None:
        registry = json.loads(COMMAND_REGISTRY.read_text(encoding="utf-8"))
        row = next(
            item for item in registry["commands"]
            if item["id"] == "hh-cc-reader-firmware-protocol-select"
        )
        self.assertEqual(row["source_of_truth"], "Select-HHCCReaderFirmwareProtocol.cmd")
        self.assertEqual(row["mutation"], "none")
        self.assertFalse(row["network"])

    def test_contract_file_is_valid_json(self) -> None:
        payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(payload["selection_schema"], "sas-hh-cc-reader-firmware-protocol-selection/v1")


if __name__ == "__main__":
    unittest.main()
