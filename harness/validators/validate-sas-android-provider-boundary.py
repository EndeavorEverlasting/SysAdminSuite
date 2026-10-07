#!/usr/bin/env python3
"""Validate the reusable SysAdminSuite AndroidProvider architecture contract."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = ROOT / "harness" / "api" / "sas-android-provider-boundary.v1.json"
DEFAULT_SCHEMA = ROOT / "schemas" / "harness" / "sas-android-provider-boundary.schema.json"

EXPECTED_ROLES = {"ptop_lab", "adminbox_reference", "technician_adminbox_field"}
EXPECTED_LIFECYCLE = [
    "RUNTIME_QUALIFIED",
    "HOST_SERVER_READY",
    "TARGET_ENUMERATED",
    "IDENTITY_BOUND",
    "SESSION_READY",
    "OPERATION_EXECUTED",
    "CLEANUP_PROVEN",
    "LEASE_RELEASED",
]
EXPECTED_MATURITY = ["M0", "M1", "M2", "M3", "M4", "M5"]


def load(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("contract root must be an object")
    return payload


def validate_schema(payload: dict[str, Any]) -> list[str]:
    schema = load(DEFAULT_SCHEMA)
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as exc:
        return [f"schema.invalid:{type(exc).__name__}"]
    validation_errors = sorted(
        Draft202012Validator(schema).iter_errors(payload),
        key=lambda item: [str(part) for part in item.absolute_path],
    )
    errors: list[str] = []
    for error in validation_errors:
        path = ".".join(str(part) for part in error.absolute_path) or "$"
        errors.append(f"schema.{path}:{error.validator}")
    return errors


def validate_contract(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = validate_schema(payload)
    if payload.get("schema_version") != "sas-android-provider-boundary/v1":
        errors.append("schema_version")
    if payload.get("status") != "IMPLEMENTED_CONTRACT":
        errors.append("status")

    arch = payload.get("architecture") if isinstance(payload.get("architecture"), dict) else {}
    if arch.get("management_plane") != "SysAdminSuite":
        errors.append("architecture.management_plane")
    if arch.get("provider") != "AndroidProvider":
        errors.append("architecture.provider")
    if arch.get("current_backend") != "adb_cli":
        errors.append("architecture.current_backend")
    rules = arch.get("rules") if isinstance(arch.get("rules"), dict) else {}
    for key in (
        "adb_is_transport_not_management_plane",
        "workloads_consume_provider_not_adb_binary",
        "provider_backend_is_replaceable",
        "device_identity_is_independent_of_transport",
        "capability_authority_and_proof_are_orthogonal",
        "cc_reader_firmware_is_workload_not_provider",
    ):
        if rules.get(key) is not True:
            errors.append(f"architecture.rules.{key}")

    roles = payload.get("node_roles")
    if not isinstance(roles, list):
        errors.append("node_roles")
        roles = []
    role_map = {r.get("id"): r for r in roles if isinstance(r, dict) and isinstance(r.get("id"), str)}
    if set(role_map) != EXPECTED_ROLES:
        errors.append("node_roles.ids")
    for role_id in ("adminbox_reference", "technician_adminbox_field"):
        role = role_map.get(role_id, {})
        if role.get("offline_execution_required") is not True:
            errors.append(f"node_roles.{role_id}.offline_execution_required")
        if role.get("public_internet_required_at_execution") is not False:
            errors.append(f"node_roles.{role_id}.public_internet_required_at_execution")

    bundle = payload.get("runtime_bundle") if isinstance(payload.get("runtime_bundle"), dict) else {}
    if bundle.get("components_are_one_qualified_bundle") is not True:
        errors.append("runtime_bundle.components_are_one_qualified_bundle")
    if bundle.get("deterministic_runtime_resolution") is not True:
        errors.append("runtime_bundle.deterministic_runtime_resolution")
    if bundle.get("competing_path_or_sdk_copies_are_reported") is not True:
        errors.append("runtime_bundle.competing_path_or_sdk_copies_are_reported")
    if bundle.get("field_network_fetch_allowed") is not False:
        errors.append("runtime_bundle.field_network_fetch_allowed")
    if not {"source","version","sha256","component_manifest","qualification_state","qualified_at"} <= set(bundle.get("required_metadata") or []):
        errors.append("runtime_bundle.required_metadata")

    host = payload.get("host_provider") if isinstance(payload.get("host_provider"), dict) else {}
    for key in ("single_android_provider_authority_per_host","node_unique_adb_key_material_required","shared_default_adb_private_key_forbidden"):
        if host.get(key) is not True:
            errors.append(f"host_provider.{key}")
    if host.get("adb_server_bind_scope") != "LOOPBACK_ONLY":
        errors.append("host_provider.adb_server_bind_scope")
    if host.get("adb_server_default_host") != "127.0.0.1":
        errors.append("host_provider.adb_server_default_host")
    if host.get("raw_remote_adb_server_export") != "FORBIDDEN_BY_DEFAULT":
        errors.append("host_provider.raw_remote_adb_server_export")

    identity = payload.get("device_identity") if isinstance(payload.get("device_identity"), dict) else {}
    for key in ("logical_identity_is_not_adb_serial","transport_aliases_are_evidence_not_identity","usb_and_tcp_aliases_for_same_device_must_collapse"):
        if identity.get(key) is not True:
            errors.append(f"device_identity.{key}")
    if identity.get("ambiguous_identity_result") != "BLOCK":
        errors.append("device_identity.ambiguous_identity_result")

    dims = payload.get("state_dimensions") if isinstance(payload.get("state_dimensions"), dict) else {}
    if dims.get("orthogonal") is not True:
        errors.append("state_dimensions.orthogonal")
    if dims.get("technical_capability") != ["UNKNOWN","UNAVAILABLE","AVAILABLE","READY"]:
        errors.append("state_dimensions.technical_capability")
    if dims.get("authority") != ["FORBIDDEN","READ_ONLY_ALLOWED","MUTATION_GATED","AUTHORIZED"]:
        errors.append("state_dimensions.authority")
    if dims.get("proof") != ["DESIGNED","REPOSITORY_VALIDATED","INTEGRATION_VALIDATED","LIVE_PROVEN"]:
        errors.append("state_dimensions.proof")

    ops = payload.get("operation_classes") if isinstance(payload.get("operation_classes"), dict) else {}
    if (ops.get("device_mutation") or {}).get("generic_provider_does_not_authorize") is not True:
        errors.append("operation_classes.device_mutation.generic_provider_does_not_authorize")
    if (ops.get("destructive_or_privilege_escalating") or {}).get("generic_provider_posture") != "FORBIDDEN":
        errors.append("operation_classes.destructive_or_privilege_escalating.generic_provider_posture")

    if payload.get("session_lifecycle") != EXPECTED_LIFECYCLE:
        errors.append("session_lifecycle")
    cleanup = payload.get("cleanup") if isinstance(payload.get("cleanup"), dict) else {}
    if cleanup.get("tcpip_transition_requires_return_to_usb_proof") is not True:
        errors.append("cleanup.tcpip_transition_requires_return_to_usb_proof")
    if cleanup.get("cleanup_failure_terminal_result") != "INCOMPLETE":
        errors.append("cleanup.cleanup_failure_terminal_result")
    if cleanup.get("cleanup_failure_never_promotes_success") is not True:
        errors.append("cleanup.cleanup_failure_never_promotes_success")

    public = payload.get("public_surface") if isinstance(payload.get("public_surface"), dict) else {}
    if public.get("raw_shell_is_not_a_technician_public_api") is not True:
        errors.append("public_surface.raw_shell_is_not_a_technician_public_api")
    if public.get("typed_operations_precede_raw_commands") is not True:
        errors.append("public_surface.typed_operations_precede_raw_commands")

    backends = payload.get("backend_roadmap") if isinstance(payload.get("backend_roadmap"), dict) else {}
    if (backends.get("adb_cli") or {}).get("state") != "CURRENT":
        errors.append("backend_roadmap.adb_cli")
    if (backends.get("adb_smart_socket_client") or {}).get("state") != "FUTURE_OPTION":
        errors.append("backend_roadmap.adb_smart_socket_client")
    if (backends.get("direct_adb_transport_client") or {}).get("disposition") != "REJECT_NOW":
        errors.append("backend_roadmap.direct_adb_transport_client")

    workload_boundary = payload.get("workload_boundary") if isinstance(payload.get("workload_boundary"), dict) else {}
    workload = workload_boundary.get("hh_cc_reader") if isinstance(workload_boundary.get("hh_cc_reader"), dict) else {}
    if workload.get("current_adapter") != "harness/api/hh_cc_reader_adb_control_plane.py":
        errors.append("workload_boundary.hh_cc_reader.current_adapter")
    if workload.get("kiosk4_usb_otg_finding_scope") != "CURRENT_KIOSK4_CONFIGURATION_ONLY":
        errors.append("workload_boundary.hh_cc_reader.kiosk4_usb_otg_finding_scope")

    security = payload.get("security") if isinstance(payload.get("security"), dict) else {}
    for key in ("secrets_never_tracked","live_device_identifiers_never_tracked","adb_private_keys_never_tracked","raw_adb_server_not_exposed_to_untrusted_networks","provider_support_never_implies_operation_authority"):
        if security.get(key) is not True:
            errors.append(f"security.{key}")

    maturity = payload.get("maturity_path")
    ids = [row.get("id") for row in maturity if isinstance(row, dict)] if isinstance(maturity, list) else []
    if ids != EXPECTED_MATURITY:
        errors.append("maturity_path")
    if not isinstance(payload.get("proof_ceiling"), str) or not payload["proof_ceiling"].strip():
        errors.append("proof_ceiling")
    return errors


def main(argv: list[str] | None = None) -> int:
    argv = argv or sys.argv[1:]
    path = Path(argv[0]) if argv else DEFAULT_CONTRACT
    try:
        errors = validate_contract(load(path))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}")
        return 1
    if errors:
        print("FAIL: sas AndroidProvider boundary: " + ", ".join(errors))
        return 1
    print("PASS: sas AndroidProvider boundary")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
