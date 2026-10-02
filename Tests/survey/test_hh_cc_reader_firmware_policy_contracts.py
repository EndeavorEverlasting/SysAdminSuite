#!/usr/bin/env python3
"""Focused recurrence contracts for the H&H CC-reader firmware decision policy."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "harness/api/hh-cc-reader-firmware-policy.json"
SCHEMA = ROOT / "schemas/harness/hh-cc-reader-firmware-policy.schema.json"
VALIDATOR = ROOT / "harness/validators/validate-hh-cc-reader-firmware-policy.py"
DOC = ROOT / "docs/HH_CC_READER_NETSTAT_BASELINE.md"
FIELD_SKILL = ROOT / ".claude/skills/field-workflow/SKILL.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing firmware policy component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def test_active_outdated_semantics_are_durable() -> None:
    policy = load(POLICY)
    assert policy["scope"]["source_field"] == "Active Outdated"
    assert "requiring remediation" in policy["source_field_semantics"]["yes"]
    assert "client-accepted baseline evidence" in policy["source_field_semantics"]["no"]
    assert policy["gates"]["do_not_treat_active_outdated_no_as_vendor_latest"] is True


def test_site_scope_fails_closed_before_execution_target() -> None:
    policy = load(POLICY)
    site = policy["site_resolution"]
    assert site["fleet_planning_scope"] == "organization-wide candidate only"
    assert site["default_site_state"] == "DISCOVERY_REQUIRED"
    assert site["execution_target_state"] == "UNRESOLVED_UNTIL_SITE_AND_MANAGEMENT_AUTHORITY"
    assert all(site["rules"].values())
    assert policy["selection"]["scope"] == "fleet_planning_candidate_only"
    assert policy["gates"]["site_context_required_before_firmware_mutation"] is True
    assert policy["gates"]["fleet_default_is_not_site_execution_authority"] is True


def test_current_client_accepted_candidates_are_exact() -> None:
    policy = load(POLICY)
    candidates = {item["version"]: item for item in policy["observed_client_accepted_candidates"]}
    assert set(candidates) == {"2.0.14.221110", "2.0.15.260522"}
    assert candidates["2.0.14.221110"]["status"] == "accepted_candidate"
    assert candidates["2.0.15.260522"]["status"] == "default_target_candidate"
    assert all("Active Outdated is No" in item["basis"] for item in candidates.values())


def test_default_is_highest_observed_client_accepted_candidate() -> None:
    policy = load(POLICY)
    versions = [item["version"] for item in policy["observed_client_accepted_candidates"]]
    assert policy["selection"]["rule"] == "highest_numeric_observed_client_accepted_candidate"
    assert policy["selection"]["scope"] == "fleet_planning_candidate_only"
    assert policy["selection"]["default_target"] == max(versions, key=key)
    assert policy["selection"]["default_target"] == "2.0.15.260522"


def test_older_accepted_version_cannot_be_erased_to_simplify_the_story() -> None:
    policy = load(POLICY)
    ambiguity = next(item for item in policy["ambiguities"] if item["version"] == "2.0.14.221110")
    assert ambiguity["state"] == "OPEN"
    assert "classification current" in ambiguity["question"].lower()
    assert "Do not discard" in ambiguity["handling"]
    assert "relabel it as outdated" in ambiguity["handling"]


def test_target_substitution_and_mutation_fail_closed() -> None:
    policy = load(POLICY)
    assert policy["gates"]["do_not_silently_substitute_target"] is True
    assert policy["gates"]["site_context_required_before_firmware_mutation"] is True
    assert policy["gates"]["fleet_default_is_not_site_execution_authority"] is True
    assert policy["gates"]["authoritative_package_mapping_required_before_firmware_mutation"] is True
    assert policy["gates"]["supported_update_method_required_before_firmware_mutation"] is True
    assert policy["gates"]["controlled_pilot_required_before_repeatable_rollout"] is True
    joined = "\n".join(policy["selection"]["supersession_requires"])
    assert "H&H estate-specific" in joined
    assert "client source revision" in joined
    assert "explicit operator target change" in joined



def test_mechanism_discovery_must_precede_human_escalation() -> None:
    policy = load(POLICY)
    mechanism = policy["mechanism_discovery"]
    assert mechanism["strategy"] == "mechanism_first_before_human_escalation"
    assert mechanism["required_dispositions"] == [
        "PROVEN_PATH",
        "NOT_APPLICABLE",
        "CREDENTIAL_GATE",
        "EVIDENCE_GAP",
    ]
    assert [item["id"] for item in mechanism["candidate_order"]] == [
        "payment-fusion-control-center",
        "paxstore-ota-push",
        "terminal-tms-pull",
        "provider-auto-update",
    ]
    assert [item["evidence_rank"] for item in mechanism["candidate_order"]] == [
        "STRONGEST_ESTATE_MATCH",
        "STRONGEST_DELIVERY_MATCH",
        "FALLBACK",
        "FALLBACK",
    ]
    assert [item["disposition"] for item in mechanism["candidate_order"]] == [
        "CREDENTIAL_GATE",
        "CREDENTIAL_GATE",
        "NOT_APPLICABLE",
        "CREDENTIAL_GATE",
    ]
    paxstore = mechanism["candidate_order"][1]
    auto_update = mechanism["candidate_order"][3]
    assert "Readonly Firmware List + Terminal Management" in paxstore["next_discriminator"]
    assert "Full/write/push privileges are not required for discovery" in paxstore["next_discriminator"]
    assert "Automatic terminal updating" in auto_update["evidence_basis"]
    assert "IngEstate" in auto_update["evidence_basis"]
    assert "platform capability alone" in auto_update["next_discriminator"]
    assert all(mechanism["rules"].values())
    assert mechanism["rules"]["exhaust_supported_mechanisms_before_human_escalation"] is True
    assert mechanism["rules"]["human_owner_confirmation_is_not_a_primary_discriminator"] is True
    assert "generic owner-identification request" in mechanism["candidate_order"][0]["next_discriminator"]


def test_proven_path_acceptance_and_readonly_checklist_are_owned() -> None:
    policy = load(POLICY)
    acceptance = policy["proven_path_acceptance"]
    checklist = policy["readonly_estate_checklist"]
    assert acceptance["from_disposition"] == "CREDENTIAL_GATE"
    assert acceptance["to_disposition"] == "PROVEN_PATH"
    assert acceptance["required_access_state"] == "PROVEN_ACCESS"
    assert "paxstore-ota-push" in acceptance["eligible_mechanism_ids"]
    assert "terminal-tms-pull" in acceptance["ineligible_mechanism_ids"]
    assert acceptance["rules"]["mutation_remains_unauthorized_after_proven_path"] is True
    assert acceptance["rules"]["package_absence_is_conflict_not_silent_substitution"] is True
    assert checklist["lane"] == "P5_management_plane_discovery"
    assert "push" in checklist["forbidden_actions"]
    assert len(checklist["items"]) == 12
    assert "Readonly Firmware List + Terminal Management" in checklist["minimum_role_by_surface"]["paxstore-ota-push"]


def test_docs_and_agent_lane_point_back_to_machine_policy() -> None:
    doc = read(DOC)
    skill = read(FIELD_SKILL)
    for marker in ("Active Outdated", "2.0.14.221110", "2.0.15.260522", "harness/api/hh-cc-reader-firmware-policy.json"):
        assert marker in doc, f"CC-reader baseline lost marker: {marker}"
    for marker in ("H&H CC-reader firmware decision gate", "Active Outdated", "site/hospital", "machine policy is the source of truth", "harness/api/hh-cc-reader-firmware-policy.json", "PROVEN_PATH acceptance"):
        assert marker in skill, f"field workflow lost marker: {marker}"
    for marker in ("PROVEN_PATH acceptance record", "Read-only estate evidence checklist"):
        assert marker in doc, f"CC-reader baseline lost marker: {marker}"
    section = skill.split("## H&H CC-reader firmware decision gate", 1)[1].split("## ", 1)[0]
    policy = load(POLICY)
    for candidate in policy["observed_client_accepted_candidates"]:
        assert candidate["version"] not in section, "field workflow duplicated a policy-owned firmware value"


def test_schema_matches_policy_version() -> None:
    policy = load(POLICY)
    schema = load(SCHEMA)
    assert schema["properties"]["schema_version"]["const"] == policy["schema_version"]
    assert schema["additionalProperties"] is False
    assert schema["properties"]["scope"]["properties"]["source_field"]["const"] == "Active Outdated"
    assert schema["properties"]["selection"]["properties"]["rule"]["const"] == policy["selection"]["rule"]
    assert set(schema["properties"]["gates"]["properties"]) == set(policy["gates"])
    assert all(item["const"] is True for item in schema["properties"]["gates"]["properties"].values())
    try:
        import jsonschema  # type: ignore
    except ImportError:
        pass
    else:
        jsonschema.Draft202012Validator(schema).validate(policy)


def test_validator_exists_and_names_the_recurrence_boundary() -> None:
    text = read(VALIDATOR)
    for marker in (
        "Active Outdated",
        "highest_numeric_observed_client_accepted_candidate",
        "2.0.14.221110",
        "2.0.15.260522",
        "do_not_silently_substitute_target",
    ):
        assert marker in text, f"validator lost recurrence marker: {marker}"


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for fn in tests:
        fn()
    print(f"PASS: H&H CC-reader firmware policy focused contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
