#!/usr/bin/env python3
"""Dependency-free contracts for the SysAdminSuite AndroidProvider boundary."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "harness/api/sas-android-provider-boundary.v1.json"
VALIDATOR = ROOT / "harness/validators/validate-sas-android-provider-boundary.py"
HH_CONTROL = ROOT / "harness/api/hh_cc_reader_adb_control_plane.py"
HH_WORKFLOW = ROOT / "docs/HH_CC_READER_ADB_ADMIN_BOX_WORKFLOW.md"


def load_validator():
    spec = importlib.util.spec_from_file_location("sas_android_boundary_validator", VALIDATOR)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_contract_validator() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert load_validator().validate_contract(payload) == []



def test_schema_is_applied_and_nested_shape_fails_closed() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    missing_version = copy.deepcopy(payload)
    missing_version.pop("version")
    assert any(error.startswith("schema.") for error in load_validator().validate_contract(missing_version))

    unexpected_nested_key = copy.deepcopy(payload)
    unexpected_nested_key["host_provider"]["adb_server_bnid_scope"] = "LOOPBACK_ONLY"
    assert any(error.startswith("schema.host_provider") for error in load_validator().validate_contract(unexpected_nested_key))


def test_concrete_adb_server_host_must_be_loopback() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    payload["host_provider"]["adb_server_default_host"] = "0.0.0.0"
    errors = load_validator().validate_contract(payload)
    assert "host_provider.adb_server_default_host" in errors
    assert any(error.startswith("schema.host_provider.adb_server_default_host") for error in errors)


def test_malformed_workload_boundary_returns_failures_not_traceback() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    payload["workload_boundary"] = []
    errors = load_validator().validate_contract(payload)
    assert errors
    assert any(error.startswith("schema.workload_boundary") for error in errors)
    assert "workload_boundary.hh_cc_reader.current_adapter" in errors


def test_capability_authority_and_proof_remain_separate() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    dims = payload["state_dimensions"]
    assert dims["orthogonal"] is True
    assert "READY" in dims["technical_capability"]
    assert "AUTHORIZED" in dims["authority"]
    assert "LIVE_PROVEN" in dims["proof"]
    assert payload["operation_classes"]["device_mutation"]["generic_provider_does_not_authorize"] is True


def test_field_nodes_are_offline_first() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    roles = {r["id"]: r for r in payload["node_roles"]}
    for role_id in ("adminbox_reference", "technician_adminbox_field"):
        assert roles[role_id]["offline_execution_required"] is True
        assert roles[role_id]["public_internet_required_at_execution"] is False
    assert payload["runtime_bundle"]["field_network_fetch_allowed"] is False


def test_adb_server_stays_local_and_keys_are_not_shared() -> None:
    host = json.loads(CONTRACT.read_text(encoding="utf-8"))["host_provider"]
    assert host["adb_server_bind_scope"] == "LOOPBACK_ONLY"
    assert host["raw_remote_adb_server_export"] == "FORBIDDEN_BY_DEFAULT"
    assert host["node_unique_adb_key_material_required"] is True
    assert host["shared_default_adb_private_key_forbidden"] is True


def test_logical_device_identity_survives_transport_aliases() -> None:
    identity = json.loads(CONTRACT.read_text(encoding="utf-8"))["device_identity"]
    assert identity["logical_identity_is_not_adb_serial"] is True
    assert identity["usb_and_tcp_aliases_for_same_device_must_collapse"] is True
    assert identity["ambiguous_identity_result"] == "BLOCK"


def test_existing_hh_adapter_remains_scoped_and_fail_closed() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    code = HH_CONTROL.read_text(encoding="utf-8")
    workflow = HH_WORKFLOW.read_text(encoding="utf-8")
    assert payload["workload_boundary"]["hh_cc_reader"]["current_adapter"] == "harness/api/hh_cc_reader_adb_control_plane.py"
    assert "ADB is a transport beneath that plane, not the plane itself." in code
    assert "MUTATION_AUTHORIZED=false" in workflow
    assert "USB_OTG_ADB_CAPABILITY not a deployment transport in this configuration" in workflow
    assert payload["workload_boundary"]["hh_cc_reader"]["kiosk4_usb_otg_finding_scope"] == "CURRENT_KIOSK4_CONFIGURATION_ONLY"


def test_backend_maturity_requires_measurement_before_replacement() -> None:
    roadmap = json.loads(CONTRACT.read_text(encoding="utf-8"))["backend_roadmap"]
    assert roadmap["adb_cli"]["state"] == "CURRENT"
    assert roadmap["adb_smart_socket_client"]["state"] == "FUTURE_OPTION"
    assert "measured" in roadmap["adb_smart_socket_client"]["promotion_gate"].casefold()
    assert roadmap["direct_adb_transport_client"]["disposition"] == "REJECT_NOW"


TESTS = [
    test_contract_validator,
    test_schema_is_applied_and_nested_shape_fails_closed,
    test_concrete_adb_server_host_must_be_loopback,
    test_malformed_workload_boundary_returns_failures_not_traceback,
    test_capability_authority_and_proof_remain_separate,
    test_field_nodes_are_offline_first,
    test_adb_server_stays_local_and_keys_are_not_shared,
    test_logical_device_identity_survives_transport_aliases,
    test_existing_hh_adapter_remains_scoped_and_fail_closed,
    test_backend_maturity_requires_measurement_before_replacement,
]


if __name__ == "__main__":
    for test in TESTS:
        test()
    print(f"PASS: sas AndroidProvider boundary contracts ({len(TESTS)} groups)")
