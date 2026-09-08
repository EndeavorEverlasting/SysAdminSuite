#!/usr/bin/env python3
"""Validate conservative Cybernet device-exclusion policy and pre-query rejection rules."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

try:
    import jsonschema  # type: ignore
except ImportError:
    jsonschema = None

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/cybernet-device-exclusion-registry.json"
SCHEMA = ROOT / "schemas/harness/cybernet-device-exclusion-registry.schema.json"
DOC = ROOT / "docs/CYBERNET_DEVICE_EXCLUSION_REGISTRY.md"
MAP = ROOT / "harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md"
WORKFLOW = ROOT / "harness/workflows/cybernet-hardware-identity-discovery.yaml"
TEST = ROOT / "Tests/survey/test_cybernet_hardware_identity_harness_completeness.py"
CI = ROOT / ".github/workflows/cybernet-hardware-identity-harness.yml"

TRACKED_SURFACES = (REGISTRY, SCHEMA, DOC, MAP, WORKFLOW, TEST, CI)


def read(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"missing Cybernet device-exclusion surface: {path.relative_to(ROOT).as_posix()}")
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def assert_tracked(path: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"Cybernet device-exclusion surface is not tracked: {path.relative_to(ROOT).as_posix()}")


def require_markers(path: Path, markers: tuple[str, ...]) -> None:
    text = read(path)
    for marker in markers:
        assert marker in text, f"{path.relative_to(ROOT)} missing marker: {marker}"


def main() -> None:
    for path in TRACKED_SURFACES:
        read(path)
        assert_tracked(path)

    data = load(REGISTRY)
    schema = load(SCHEMA)
    assert data["schema_version"] == "sas-cybernet-device-exclusion-registry/v1"
    assert data["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["properties"]["schema_version"]["const"] == data["schema_version"]
    if jsonschema is not None:
        jsonschema.Draft202012Validator(schema).validate(data)
        print("PASS: declared Draft 2020-12 Cybernet device-exclusion registry schema")
    else:
        print("PASS: dependency-free Cybernet device-exclusion registry shape (jsonschema unavailable locally)")

    tracking = data["tracking_policy"]
    assert tracking["tracked_registry_contains_live_entries"] is False
    assert tracking["live_entry_tracking"] == "local_untracked_or_approved_external_source"
    assert data["entries"] == [], "tracked exclusion registry must not contain live device entries"

    policy = data["decision_policy"]
    assert policy["default_action"] == "DO_NOT_EXCLUDE"
    assert policy["conflict_action"] == "REVIEW_REQUIRED_NO_AUTO_EXCLUSION"
    assert policy["positive_cybernet_evidence_action"] == "BLOCK_EXCLUSION_AND_ROUTE_TO_HARDWARE_IDENTITY"
    assert policy["before_network_signature_requires"] == "AUTHORITATIVE_NON_CYBERNET_CLASSIFICATION"
    assert policy["before_endpoint_metadata_requires"] == "AUTHORITATIVE_NON_CYBERNET_CLASSIFICATION"
    assert set(policy["before_hardware_metadata_allows"]) == {
        "AUTHORITATIVE_NON_CYBERNET_CLASSIFICATION",
        "CURRENT_WINDOWS_NON_CLIENT_PRODUCT_TYPE",
    }
    for key in (
        "weak_evidence_never_accumulates_to_reject",
        "corroborating_evidence_never_accumulates_to_reject",
        "strong_evidence_never_accumulates_to_reject_without_authority",
    ):
        assert policy[key] is True, f"{key} must remain true"
    for key in (
        "hostname_alone_can_reject",
        "software_presence_or_absence_can_reject",
        "subnet_alone_can_reject",
        "open_ports_alone_can_reject",
        "mac_oui_alone_can_reject",
        "network_signature_alone_can_reject",
        "new_active_query_for_exclusion_allowed",
    ):
        assert policy[key] is False, f"{key} must remain false"

    strengths = {item["id"]: item for item in data["evidence_strengths"]}
    assert set(strengths) == {"AUTHORITATIVE", "STRONG", "CORROBORATING", "WEAK", "CONFLICTING"}
    assert strengths["AUTHORITATIVE"]["auto_rejection_eligible"] is True
    for level in ("STRONG", "CORROBORATING", "WEAK", "CONFLICTING"):
        assert strengths[level]["auto_rejection_eligible"] is False

    evidence = {item["id"]: item for item in data["evidence_types"]}
    assert len(evidence) == len(data["evidence_types"]), "duplicate device-exclusion evidence id"

    non_authoritative = {
        "ad_operating_system_server_label",
        "existing_snmp_device_description",
        "existing_http_device_banner",
        "dhcp_vendor_class",
        "dns_ptr_or_role_label",
        "mac_oui_vendor",
        "hostname_role_pattern",
        "software_footprint",
        "software_absence",
        "open_tcp_port",
        "network_signature_135_445",
        "subnet_or_site_role_inference",
    }
    for evidence_id in non_authoritative:
        item = evidence[evidence_id]
        assert item["strength"] != "AUTHORITATIVE", f"{evidence_id} must not become authoritative"
        assert item["auto_rejection_stages"] == [], f"{evidence_id} must never auto-reject"

    for evidence_id in ("existing_snmp_device_description", "existing_http_device_banner"):
        assert evidence[evidence_id]["collection_policy"] == "REUSE_ONLY_NO_NEW_QUERY_FOR_EXCLUSION"

    product_type = evidence["current_windows_product_type_non_client"]
    assert product_type["strength"] == "AUTHORITATIVE"
    assert product_type["collection_policy"] == "EXISTING_REQUIRED_GATE_ONLY"
    assert product_type["auto_rejection_stages"] == ["BEFORE_HARDWARE_METADATA"]

    for evidence_id in (
        "approved_printer_inventory_record",
        "approved_network_controller_access_point_record",
        "approved_time_clock_inventory_record",
        "approved_cmdb_explicit_device_class",
        "approved_asset_inventory_explicit_device_class",
        "approved_endpoint_inventory_server_class",
    ):
        assert evidence[evidence_id]["strength"] == "AUTHORITATIVE"
        assert "BEFORE_ENDPOINT_METADATA" in evidence[evidence_id]["auto_rejection_stages"]

    classes = {item["id"]: item for item in data["device_classes"]}
    expected_classes = {
        "printer",
        "access_point",
        "time_clock",
        "server",
        "other_computer",
        "other_network_device",
        "other_non_cybernet_device",
    }
    assert set(classes) == expected_classes
    assert "cronus_clock" in classes["time_clock"]["aliases"]

    evidence_ids = set(evidence)
    for class_id, item in classes.items():
        for field in (
            "safe_pre_query_evidence_types",
            "safe_pre_hardware_evidence_types",
            "never_sufficient_evidence_types",
        ):
            unknown = set(item[field]) - evidence_ids
            assert not unknown, f"{class_id}.{field} references unknown evidence: {sorted(unknown)}"
        for evidence_id in item["safe_pre_query_evidence_types"]:
            assert evidence[evidence_id]["strength"] == "AUTHORITATIVE", (
                f"{class_id} pre-query exclusion must be authoritative: {evidence_id}"
            )
            assert "BEFORE_ENDPOINT_METADATA" in evidence[evidence_id]["auto_rejection_stages"], (
                f"{class_id} pre-query evidence lacks stage authority: {evidence_id}"
            )
        for evidence_id in item["never_sufficient_evidence_types"]:
            assert evidence[evidence_id]["strength"] != "AUTHORITATIVE", (
                f"{class_id} never-sufficient evidence became authoritative: {evidence_id}"
            )

    assert set(classes["other_computer"]["safe_pre_query_evidence_types"]) == {
        "prior_sas_confirmed_non_cybernet",
        "approved_hardware_reference_non_cybernet_match",
    }
    assert "approved_asset_inventory_explicit_device_class" in classes["other_computer"]["never_sufficient_evidence_types"]

    assert classes["server"]["safe_pre_hardware_evidence_types"] == [
        "current_windows_product_type_non_client"
    ]
    assert "ad_operating_system_server_label" in classes["server"]["never_sufficient_evidence_types"]
    assert "open_tcp_port" in classes["printer"]["never_sufficient_evidence_types"]
    assert "mac_oui_vendor" in classes["access_point"]["never_sufficient_evidence_types"]

    require_markers(DOC, (
        "# Cybernet Device Exclusion Registry",
        "BEFORE_NETWORK_SIGNATURE",
        "BEFORE_ENDPOINT_METADATA",
        "BEFORE_HARDWARE_METADATA",
        "Cronus clocks / time clocks",
        "Strong evidence does not become authoritative by counting",
        "generic `computer`, `desktop`, or `workstation` label is **not** enough",
        "does **not** authorize a new active query",
    ))
    require_markers(MAP, (
        "cybernet-device-exclusion-registry.json",
        "authoritative exclusion",
        "weak/corroborating/strong evidence never accumulates",
    ))
    require_markers(WORKFLOW, (
        "pre_query_exclusion",
        "harness/api/cybernet-device-exclusion-registry.json",
        "do not create new active queries solely to obtain exclusion evidence",
        "REVIEW_REQUIRED_NO_AUTO_EXCLUSION",
    ))
    require_markers(TEST, ("validate-cybernet-device-exclusion-registry.py",))
    require_markers(CI, (
        "cybernet-device-exclusion-registry.json",
        "cybernet-device-exclusion-registry.schema.json",
        "validate-cybernet-device-exclusion-registry.py",
        "CYBERNET_DEVICE_EXCLUSION_REGISTRY.md",
    ))

    for path in (REGISTRY, DOC, MAP, WORKFLOW):
        text = read(path)
        assert not re.search(r"\bW[A-Z]{2}\d{3}OPR\d+\b", text), (
            f"live-looking target hostname must not be committed in {path.relative_to(ROOT)}"
        )

    print("PASS: printers/APs/time clocks/servers/other devices require authoritative exclusion evidence")
    print("PASS: hostname/software/subnet/ports/OUI/network signature cannot auto-reject")
    print("PASS: strong/corroborating/weak evidence never accumulates into exclusion authority")
    print("PASS: server ProductType rejection is limited to the existing pre-hardware gate")
    print("PASS: tracked device-exclusion registry contains no live device entries")


if __name__ == "__main__":
    main()
