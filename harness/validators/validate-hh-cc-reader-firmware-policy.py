#!/usr/bin/env python3
"""Validate the H&H CC-reader firmware decision policy.

This contract makes the client inventory's ``Active Outdated`` signal durable
without promoting it beyond its evidence ceiling. It preserves the two observed
client-accepted firmware candidates, selects the highest numeric accepted
candidate as the default planning target, keeps the older accepted version's
ambiguity open, and blocks silent target substitution or firmware mutation
without authoritative estate-specific package/update evidence. It also prevents a recurring discovery defect: unknown ownership must not terminate investigation before the supported update-mechanism families are dispositioned. It further owns the PROVEN_PATH acceptance record and read-only estate checklist seams used by the executable estate-authority evaluator.
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "harness/api/hh-cc-reader-firmware-policy.json"
SCHEMA = ROOT / "schemas/harness/hh-cc-reader-firmware-policy.schema.json"
ESTATE_EVALUATOR = ROOT / "harness/api/hh_cc_reader_estate_authority.py"
ESTATE_TEST = ROOT / "Tests/survey/test_hh_cc_reader_estate_authority_contracts.py"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
HH_DOC = ROOT / "docs/HH_CC_READER_NETSTAT_BASELINE.md"
REMOTE_DOC = ROOT / "docs/HH_CC_READER_REMOTE_OPERATIONS_PROGRAM.md"
FIELD_SKILL = ROOT / ".claude/skills/field-workflow/SKILL.md"
CODEBASE_MAP = ROOT / "CODEBASE_MAP.md"
TEST = ROOT / "Tests/survey/test_hh_cc_reader_firmware_policy_contracts.py"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
OFFLINE = ROOT / "tests/survey/run_offline_survey_tests.sh"
CI = ROOT / ".github/workflows/hh-cc-reader-firmware-policy-contracts.yml"

VERSION = re.compile(r"^\d+(?:\.\d+)+$")
NETWORK_IMPORT = re.compile(
    r"(?m)^\s*(?:import|from)\s+(?:urllib|socket|requests|http|asyncio|ftplib|telnetlib)\b"
)
PROVIDER_MARKERS = (
    "drive" + ".google.com",
    "docs" + ".google.com",
    "Google" + " Drive",
    "One" + "Drive",
    "Drop" + "box",
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing H&H firmware policy component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def version_key(value: str) -> tuple[int, ...]:
    assert VERSION.fullmatch(value), f"non-numeric dotted firmware version: {value!r}"
    return tuple(int(part) for part in value.split("."))


def test_schema_and_scope() -> None:
    policy = load(POLICY)
    schema = load(SCHEMA)
    assert policy["schema_version"] == "sas-hh-cc-reader-firmware-policy/v1"
    assert policy["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"] == policy["schema_version"]
    assert schema["properties"]["scope"]["properties"]["source_field"]["const"] == "Active Outdated"
    assert schema["properties"]["selection"]["properties"]["rule"]["const"] == "highest_numeric_observed_client_accepted_candidate"
    gate_schema = schema["properties"]["gates"]["properties"]
    assert set(gate_schema) == set(policy["gates"])
    assert all(item.get("const") is True for item in gate_schema.values())
    assert set(schema["required"]) <= set(policy)
    mechanism_schema = schema["properties"]["mechanism_discovery"]
    assert mechanism_schema["properties"]["strategy"]["const"] == "mechanism_first_before_human_escalation"
    assert set(mechanism_schema["properties"]["rules"]["properties"]) == set(policy["mechanism_discovery"]["rules"])
    assert all(item.get("const") is True for item in mechanism_schema["properties"]["rules"]["properties"].values())
    assert policy["scope"]["organization"] == "NYC Health + Hospitals"
    assert policy["scope"]["device_family"] == "PAX A80"
    assert policy["scope"]["source_field"] == "Active Outdated"
    site = policy["site_resolution"]
    assert site["fleet_planning_scope"] == "organization-wide candidate only"
    assert site["default_site_state"] == "DISCOVERY_REQUIRED"
    assert site["execution_target_state"] == "UNRESOLVED_UNTIL_SITE_AND_MANAGEMENT_AUTHORITY"
    assert all(value is True for value in site["rules"].values())
    try:
        import jsonschema  # type: ignore
    except ImportError:
        pass
    else:
        jsonschema.Draft202012Validator(schema).validate(policy)


def test_client_field_semantics() -> None:
    policy = load(POLICY)
    semantics = policy["source_field_semantics"]
    assert "requiring remediation" in semantics["yes"]
    assert "client-accepted baseline evidence" in semantics["no"]
    ceiling = semantics["authority_ceiling"]
    for marker in (
        "Client estate classification evidence only",
        "vendor-global latest firmware",
        "package availability",
        "management entitlement",
        "update authorization",
    ):
        assert marker in ceiling, f"authority ceiling lost marker: {marker}"


def test_candidate_set_and_default_selection() -> None:
    policy = load(POLICY)
    candidates = policy["observed_client_accepted_candidates"]
    versions = [item["version"] for item in candidates]
    assert set(versions) == {"2.0.14.221110", "2.0.15.260522"}
    assert len(versions) == len(set(versions))
    assert all("Active Outdated is No" in item["basis"] for item in candidates)
    default_target = policy["selection"]["default_target"]
    assert policy["selection"]["rule"] == "highest_numeric_observed_client_accepted_candidate"
    assert policy["selection"]["scope"] == "fleet_planning_candidate_only"
    assert default_target == max(versions, key=version_key)
    default_rows = [item for item in candidates if item["status"] == "default_target_candidate"]
    assert len(default_rows) == 1
    assert default_rows[0]["version"] == default_target == "2.0.15.260522"


def test_older_accepted_version_ambiguity_stays_open() -> None:
    policy = load(POLICY)
    old = next(item for item in policy["observed_client_accepted_candidates"] if item["version"] == "2.0.14.221110")
    assert old["status"] == "accepted_candidate"
    assert old["ambiguity"] and "numerically older" in old["ambiguity"]
    ambiguity = next(item for item in policy["ambiguities"] if item["version"] == "2.0.14.221110")
    assert ambiguity["state"] == "OPEN"
    assert "why" in ambiguity["question"].lower()
    assert "classification current" in ambiguity["question"].lower()
    for marker in ("Do not discard", "relabel it as outdated", "management-plane clarification"):
        assert marker in ambiguity["handling"], f"older-version ambiguity lost marker: {marker}"


def test_mutation_and_supersession_gates() -> None:
    policy = load(POLICY)
    assert all(value is True for value in policy["gates"].values())
    supersession = policy["selection"]["supersession_requires"]
    joined = "\n".join(supersession)
    for marker in ("H&H estate-specific", "client source revision", "explicit operator target change"):
        assert marker in joined, f"supersession gate missing: {marker}"
    assert policy["gates"]["do_not_treat_active_outdated_no_as_vendor_latest"] is True
    assert policy["gates"]["do_not_silently_substitute_target"] is True
    assert policy["gates"]["site_context_required_before_firmware_mutation"] is True
    assert policy["gates"]["fleet_default_is_not_site_execution_authority"] is True
    assert policy["gates"]["authoritative_package_mapping_required_before_firmware_mutation"] is True
    assert policy["gates"]["supported_update_method_required_before_firmware_mutation"] is True
    assert policy["gates"]["controlled_pilot_required_before_repeatable_rollout"] is True



def test_mechanism_first_update_path_exhaustion() -> None:
    policy = load(POLICY)
    mechanism = policy["mechanism_discovery"]
    assert mechanism["strategy"] == "mechanism_first_before_human_escalation"
    assert mechanism["human_escalation"].startswith("fallback_only_after_supported_mechanisms")
    assert mechanism["required_dispositions"] == [
        "PROVEN_PATH",
        "NOT_APPLICABLE",
        "CREDENTIAL_GATE",
        "EVIDENCE_GAP",
    ]
    candidates = mechanism["candidate_order"]
    assert [item["id"] for item in candidates] == [
        "payment-fusion-control-center",
        "paxstore-ota-push",
        "terminal-tms-pull",
        "provider-auto-update",
    ]
    assert [item["priority"] for item in candidates] == [1, 2, 3, 4]
    assert [item["evidence_rank"] for item in candidates] == [
        "STRONGEST_ESTATE_MATCH",
        "STRONGEST_DELIVERY_MATCH",
        "FALLBACK",
        "FALLBACK",
    ]
    assert [item["disposition"] for item in candidates] == [
        "CREDENTIAL_GATE",
        "CREDENTIAL_GATE",
        "NOT_APPLICABLE",
        "CREDENTIAL_GATE",
    ]
    assert candidates[1]["role"] == "firmware_delivery_mechanism"
    assert "Readonly Firmware List + Terminal Management" in candidates[1]["next_discriminator"]
    assert "Full/write/push privileges are not required for discovery" in candidates[1]["next_discriminator"]
    assert "Automatic terminal updating" in candidates[3]["evidence_basis"]
    assert "IngEstate" in candidates[3]["evidence_basis"]
    assert "platform capability alone" in candidates[3]["next_discriminator"]
    joined = "\n".join(item["next_discriminator"] for item in candidates)
    for marker in ("CREDENTIAL_GATE", "PAXSTORE", "NTMS", "automatic update"):
        assert marker in joined, f"mechanism-first discriminator lost marker: {marker}"
    rules = mechanism["rules"]
    assert all(rules.values())
    assert rules["management_surface_and_delivery_mechanism_are_separate_discriminators"] is True
    assert rules["exhaust_supported_mechanisms_before_human_escalation"] is True
    assert rules["human_owner_confirmation_is_not_a_primary_discriminator"] is True
    assert rules["credential_gate_names_exact_surface_and_missing_access"] is True
    assert rules["do_not_mutate_reader_to_discover_management_path"] is True


def test_proven_path_acceptance_and_readonly_checklist() -> None:
    policy = load(POLICY)
    acceptance = policy["proven_path_acceptance"]
    checklist = policy["readonly_estate_checklist"]
    assert acceptance["from_disposition"] == "CREDENTIAL_GATE"
    assert acceptance["to_disposition"] == "PROVEN_PATH"
    assert acceptance["required_access_state"] == "PROVEN_ACCESS"
    assert acceptance["eligible_mechanism_ids"] == [
        "payment-fusion-control-center",
        "paxstore-ota-push",
        "provider-auto-update",
    ]
    assert acceptance["ineligible_mechanism_ids"] == ["terminal-tms-pull"]
    assert len(acceptance["required_packet_fields"]) == 7
    assert "MANAGEMENT_OWNER" in acceptance["required_packet_fields"]
    assert "POST_UPDATE_ACCEPTANCE" in acceptance["required_packet_fields"]
    assert all(acceptance["rules"].values())
    assert acceptance["rules"]["mutation_remains_unauthorized_after_proven_path"] is True
    assert acceptance["rules"]["package_absence_is_conflict_not_silent_substitution"] is True
    assert acceptance["rules"]["current_firmware_value_must_be_recorded"] is True
    assert acceptance["rules"]["package_visibility_unknown_cannot_promote"] is True
    assert "PROVEN_PATH" in acceptance["completion_gate"]
    assert "ACCESS_STATE" in acceptance["completion_gate"]
    assert "recorded sanitized firmware" in acceptance["completion_gate"]
    assert "UNKNOWN" in acceptance["completion_gate"]
    assert "does not authorize" in acceptance["proof_ceiling"].lower()
    assert "pilot" in acceptance["proof_ceiling"].lower()
    assert checklist["lane"] == "P5_management_plane_discovery"
    for action in ("push", "assign", "activate", "approve", "reset", "write"):
        assert action in checklist["forbidden_actions"], f"checklist lost forbidden action: {action}"
    assert "Readonly Firmware List + Terminal Management" in checklist["minimum_role_by_surface"]["paxstore-ota-push"]
    assert "IngEstate" in checklist["minimum_role_by_surface"]["payment-fusion-control-center"] or (
        "automatic-update" in checklist["minimum_role_by_surface"]["payment-fusion-control-center"]
    )
    assert len(checklist["items"]) == 12
    assert [item["order"] for item in checklist["items"]] == list(range(1, 13))
    assert all(item["required"] is True for item in checklist["items"])
    assert checklist["items"][0]["id"] == "confirm-authorized-readonly-session"
    assert checklist["items"][-1]["id"] == "emit-sanitized-authority-packet"
    assert ESTATE_EVALUATOR.is_file()
    assert ESTATE_TEST.is_file()
    evaluator = read(ESTATE_EVALUATOR)
    for marker in (
        "evaluate_proven_path_transition",
        "DISCOVERY_MUTATION_FORBIDDEN",
        "PROVEN_PATH_ACCEPTANCE_SATISFIED",
        "package_conflict",
        "mutation_authorized",
        "CURRENT_FIRMWARE_VALUE_REQUIRED",
        "current_firmware_observed_value",
    ):
        assert marker in evaluator, f"estate evaluator lost marker: {marker}"
    estate_tests = read(ESTATE_TEST)
    assert "test_unknown_package_visibility_with_reason_stays_at_credential_gate" in estate_tests
    assert "test_firmware_boolean_without_value_cannot_promote" in estate_tests


def test_bindings_and_agent_guidance() -> None:
    policy = load(POLICY)
    for binding in policy["bindings"]:
        text = read(ROOT / binding["path"])
        for marker in binding["required_markers"]:
            assert marker in text, f"binding {binding['path']} lost marker: {marker}"
    skill = read(FIELD_SKILL)
    assert "## H&H CC-reader firmware decision gate" in skill
    assert "machine policy is the source of truth" in skill
    section = skill.split("## H&H CC-reader firmware decision gate", 1)[1].split("## ", 1)[0]
    assert "harness/api/hh-cc-reader-firmware-policy.json" in section
    assert "Active Outdated" in section
    assert "site/hospital" in section
    assert "PROVEN_PATH acceptance" in section
    for candidate in policy["observed_client_accepted_candidates"]:
        assert candidate["version"] not in section, "field skill must not duplicate current firmware values"
    assert policy["selection"]["default_target"] not in section, "field skill must read target from policy"
    doc = read(HH_DOC)
    assert "## Client inventory firmware evidence" in doc
    assert "2.0.14.221110" in doc
    assert "2.0.15.260522" in doc
    assert "PROVEN_PATH acceptance record" in doc
    assert "Read-only estate evidence checklist" in doc
    remote = read(REMOTE_DOC)
    assert "PROVEN_PATH acceptance record" in remote
    assert "Read-only estate evidence checklist" in remote
    assert "hh_cc_reader_estate_authority.py" in remote


def test_harness_wiring() -> None:
    validators = load(VALIDATORS)["validators"]
    entry = next((item for item in validators if item["id"] == "hh-cc-reader-firmware-policy-contracts"), None)
    assert entry is not None, "validator registry missing H&H firmware policy contract"
    assert entry["command"] == "python harness/validators/validate-hh-cc-reader-firmware-policy.py"
    assert entry["blocking"] is True
    for required in (
        "harness/api/hh-cc-reader-firmware-policy.json",
        "schemas/harness/hh-cc-reader-firmware-policy.schema.json",
        "harness/api/hh_cc_reader_estate_authority.py",
        "Tests/survey/test_hh_cc_reader_estate_authority_contracts.py",
        "Tests/survey/test_hh_cc_reader_estate_authority_launcher_contracts.py",
        "Evaluate-HHCCReaderEstateAuthority.cmd",
        "docs/HH_CC_READER_NETSTAT_BASELINE.md",
        "docs/HH_CC_READER_REMOTE_OPERATIONS_PROGRAM.md",
        ".claude/skills/field-workflow/SKILL.md",
    ):
        assert required in entry["scope"], f"validator scope missing: {required}"
    components = {item["id"]: item for item in load(MANIFEST)["components"]}
    expected = {
        "hh-cc-reader-firmware-policy": "harness/api/hh-cc-reader-firmware-policy.json",
        "hh-cc-reader-firmware-policy-schema": "schemas/harness/hh-cc-reader-firmware-policy.schema.json",
        "hh-cc-reader-firmware-policy-validator": "harness/validators/validate-hh-cc-reader-firmware-policy.py",
        "hh-cc-reader-firmware-policy-contracts": "Tests/survey/test_hh_cc_reader_firmware_policy_contracts.py",
        "hh-cc-reader-estate-authority-evaluator": "harness/api/hh_cc_reader_estate_authority.py",
        "hh-cc-reader-estate-authority-contracts": "Tests/survey/test_hh_cc_reader_estate_authority_contracts.py",
        "hh-cc-reader-estate-authority-evaluate-launcher": "Evaluate-HHCCReaderEstateAuthority.cmd",
        "hh-cc-reader-estate-authority-launcher-contracts": "Tests/survey/test_hh_cc_reader_estate_authority_launcher_contracts.py",
    }
    for component_id, path in expected.items():
        assert component_id in components, f"manifest missing component: {component_id}"
        assert components[component_id]["path"] == path
    validator_name = "validate-hh-cc-reader-firmware-policy.py"
    estate_test = "test_hh_cc_reader_estate_authority_contracts.py"
    launcher_test = "test_hh_cc_reader_estate_authority_launcher_contracts.py"
    for path in (PRE_COMMIT, PRE_PUSH, OFFLINE, CI):
        text = read(path)
        assert validator_name in text, f"firmware policy validator not wired: {path.relative_to(ROOT)}"
        assert estate_test in text, f"estate-authority contracts not wired: {path.relative_to(ROOT)}"
    assert launcher_test in read(OFFLINE), "estate-authority launcher contracts not wired into offline floor"
    assert launcher_test in read(CI), "estate-authority launcher contracts not wired into CI"
    assert "Evaluate-HHCCReaderEstateAuthority.cmd" in read(CI)
    assert TEST.relative_to(ROOT).as_posix() in read(OFFLINE)
    assert "harness/api/hh-cc-reader-firmware-policy.json" in read(CODEBASE_MAP)
    assert "hh_cc_reader_estate_authority.py" in read(CODEBASE_MAP)
    assert "Evaluate-HHCCReaderEstateAuthority.cmd" in read(CODEBASE_MAP)


def test_offline_and_live_data_boundaries() -> None:
    targets = (POLICY, SCHEMA, Path(__file__), TEST, ESTATE_EVALUATOR, ESTATE_TEST, HH_DOC, REMOTE_DOC, FIELD_SKILL)
    joined = "\n".join(read(path) for path in targets)
    for marker in PROVIDER_MARKERS:
        assert marker not in joined, f"provider-specific marker leaked: {marker}"
    # Remote-ops program retains documented TEST-NET launcher examples; keep IPv4/MAC
    # fail-closed on the estate-authority and policy surfaces that must stay identifier-free.
    identity_surfaces = (POLICY, SCHEMA, Path(__file__), TEST, ESTATE_EVALUATOR, ESTATE_TEST, FIELD_SKILL)
    identity_joined = "\n".join(read(path) for path in identity_surfaces)
    assert not re.search(r"(?i)\b(?:\d{1,3}\.){3}\d{1,3}\b", identity_joined), "IPv4 literal not needed in firmware policy"
    assert not re.search(r"(?i)\b(?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2}\b", identity_joined), "MAC literal not needed in firmware policy"
    for path in (Path(__file__), TEST, ESTATE_EVALUATOR, ESTATE_TEST):
        assert not NETWORK_IMPORT.search(read(path)), f"network import in offline firmware contract: {path.name}"


def test_components_are_tracked() -> None:
    for path in (
        POLICY,
        SCHEMA,
        Path(__file__),
        TEST,
        ESTATE_EVALUATOR,
        ESTATE_TEST,
        HH_DOC,
        REMOTE_DOC,
        FIELD_SKILL,
        CODEBASE_MAP,
        PRE_COMMIT,
        PRE_PUSH,
        OFFLINE,
        CI,
    ):
        assert tracked(path), f"H&H firmware policy component is not tracked: {path.relative_to(ROOT)}"


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: H&H CC-reader firmware policy contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
