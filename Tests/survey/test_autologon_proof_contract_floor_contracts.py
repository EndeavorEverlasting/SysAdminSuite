#!/usr/bin/env python3
"""Dependency-free contracts for the frozen AutoLogon proof floor."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "schemas" / "harness"
FIXTURE_DIR = ROOT / "Tests" / "Fixtures" / "autologon-contract-floor"
API_PATH = ROOT / "harness" / "api" / "sas-harness-api.json"
ARTIFACT_TYPES_PATH = ROOT / "harness" / "api" / "autologon-artifact-types.json"
WORKFLOW_PATH = ROOT / "harness" / "workflows" / "autologon-proof-contract-floor.yaml"
DOC_PATH = ROOT / "docs" / "AUTOLOGON_PROOF_CONTRACT_FLOOR.md"
CI_PATH = ROOT / ".github" / "workflows" / "autologon-proof-contract-floor.yml"
OFFLINE_RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"

SCHEMAS = {
    "sas-autologon-deployment-result/v1": "autologon-deployment-result.schema.json",
    "sas-autologon-final-step-gate-result/v1": "autologon-final-step-gate-result.schema.json",
    "sas-autologon-state-proof-result/v1": "autologon-state-proof-result.schema.json",
    "sas-autologon-session-access-proof/v2": "autologon-session-access-proof.schema.json",
    "sas-autologon-technician-runtime-proof/v2": "autologon-technician-runtime-proof.schema.json",
    "sas-autologon-proof-source-evidence/v1": "autologon-proof-source-evidence.schema.json",
    "sas-autologon-proof-receipt/v1": "autologon-proof-receipt.schema.json",
}

OPERATION_IDS = {
    "autologon.plan",
    "autologon.admin_deploy",
    "autologon.state_proof",
    "autologon.session_access_proof",
    "autologon.technician_runtime_proof",
    "autologon.proof_receipt_ingest",
}

RECEIPT_KEYS = {
    "schema_version",
    "source_evidence_sha256",
    "source_evidence_size_bytes",
    "classification",
    "proof_level",
    "reason_codes",
    "operator_confirmed",
    "privacy_status",
}

FIXTURE_NAMES = {
    "deployment-success.fixture.json",
    "deployment-failure.fixture.json",
    "final-gate-success.fixture.json",
    "final-gate-failure.fixture.json",
    "state-success.fixture.json",
    "state-failure.fixture.json",
    "session-success.fixture.json",
    "session-failure.fixture.json",
    "runtime-success.fixture.json",
    "runtime-failure.fixture.json",
    "source-success.fixture.json",
    "source-failure.fixture.json",
    "receipt-success.fixture.json",
    "receipt-failure.fixture.json",
}


class ContractError(ValueError):
    pass


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> Any:
    return json.loads(read(path))


def fail(path: str, message: str) -> None:
    raise ContractError(f"{path}: {message}")


def type_matches(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "null":
        return value is None
    raise ContractError(f"unsupported schema type in dependency-free validator: {expected}")


def validate_instance(value: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema and value != schema["const"]:
        fail(path, f"expected const {schema['const']!r}, got {value!r}")
    if "enum" in schema and value not in schema["enum"]:
        fail(path, f"value {value!r} is outside the closed enum")

    expected_type = schema.get("type")
    if expected_type is not None:
        choices = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(type_matches(value, item) for item in choices):
            fail(path, f"expected type {choices}, got {type(value).__name__}")

    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            fail(path, "string is shorter than minLength")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            fail(path, "string is longer than maxLength")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            fail(path, f"string does not match {schema['pattern']!r}")

    if isinstance(value, int) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            fail(path, "number is below minimum")
        if "maximum" in schema and value > schema["maximum"]:
            fail(path, "number is above maximum")

    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            fail(path, "array is shorter than minItems")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            fail(path, "array is longer than maxItems")
        if schema.get("uniqueItems"):
            rendered = [json.dumps(item, sort_keys=True) for item in value]
            if len(rendered) != len(set(rendered)):
                fail(path, "array items are not unique")
        if "items" in schema:
            for index, item in enumerate(value):
                validate_instance(item, schema["items"], f"{path}[{index}]")

    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [name for name in required if name not in value]
        if missing:
            fail(path, f"missing required properties: {', '.join(missing)}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            unknown = sorted(set(value) - set(properties))
            if unknown:
                fail(path, f"additional properties are forbidden: {', '.join(unknown)}")
        for name, property_schema in properties.items():
            if name in value:
                validate_instance(value[name], property_schema, f"{path}.{name}")

    for item in schema.get("allOf", []):
        validate_instance(value, item, path)

    if "if" in schema:
        try:
            validate_instance(value, schema["if"], path)
            matched = True
        except ContractError:
            matched = False
        branch = schema.get("then") if matched else schema.get("else")
        if branch is not None:
            validate_instance(value, branch, path)


def walk_schema(schema: Any, path: str = "$") -> None:
    if isinstance(schema, list):
        for index, item in enumerate(schema):
            walk_schema(item, f"{path}[{index}]")
        return
    if not isinstance(schema, dict):
        return
    if "$ref" in schema:
        fail(path, "external or local references are not used in the frozen dependency-free floor")
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        for item in types:
            type_matches(None if item == "null" else {}, item) if item in {"object", "null"} else None
    if "properties" in schema and not isinstance(schema["properties"], dict):
        fail(path, "properties must be an object")
    if "required" in schema:
        if not isinstance(schema["required"], list) or len(schema["required"]) != len(set(schema["required"])):
            fail(path, "required must be a unique array")
    if schema.get("type") == "object" and schema.get("additionalProperties") is not False:
        fail(path, "every typed object in the frozen floor must be closed")
    for key in ("properties", "items", "allOf", "if", "then", "else"):
        if key in schema:
            walk_schema(schema[key], f"{path}.{key}")


def test_json_parsing_and_schema_self_validation() -> None:
    seen_versions: set[str] = set()
    for version, filename in SCHEMAS.items():
        path = SCHEMA_DIR / filename
        schema = load(path)
        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
        assert schema["$id"] == f"schemas/harness/{filename}"
        assert schema["type"] == "object"
        assert schema["additionalProperties"] is False
        assert schema["properties"]["schema_version"]["const"] == version
        assert version not in seen_versions, f"duplicate schema version: {version}"
        seen_versions.add(version)
        walk_schema(schema)


def test_sanitized_success_and_failure_fixtures_validate() -> None:
    paths = sorted(FIXTURE_DIR.glob("*.fixture.json"))
    assert {path.name for path in paths} == FIXTURE_NAMES
    schemas = {version: load(SCHEMA_DIR / filename) for version, filename in SCHEMAS.items()}
    for path in paths:
        payload = load(path)
        version = payload.get("schema_version")
        assert version in schemas, f"unknown fixture schema: {path.name}: {version}"
        validate_instance(payload, schemas[version])


def test_intentionally_invalid_fixtures_are_rejected() -> None:
    schemas = {version: load(SCHEMA_DIR / filename) for version, filename in SCHEMAS.items()}
    invalid_paths = sorted(FIXTURE_DIR.glob("*.invalid.json"))
    assert {path.name for path in invalid_paths} == {
        "deployment-overclaim.invalid.json",
        "receipt-private-field.invalid.json",
    }
    for path in invalid_paths:
        payload = load(path)
        try:
            validate_instance(payload, schemas[payload["schema_version"]])
        except ContractError:
            pass
        else:
            raise AssertionError(f"invalid fixture was accepted: {path.name}")


def test_operation_ids_are_unique_frozen_and_fail_closed() -> None:
    api = load(API_PATH)
    operations = api["operations"]
    ids = [item["id"] for item in operations]
    assert len(ids) == len(set(ids)), "harness API contains duplicate operation IDs"
    assert OPERATION_IDS <= set(ids)
    by_id = {item["id"]: item for item in operations}
    assert by_id["autologon.plan"]["network_activity"] is False
    assert by_id["autologon.plan"]["target_mutation"] is False
    deploy = by_id["autologon.admin_deploy"]
    assert deploy["network_activity"] is True and deploy["target_mutation"] is True
    assert "Canonical_Kerberos_SMB_scheduled_task_front_door_required" in deploy["guardrails"]
    assert "No_direct_legacy_WinRM_delegation" in deploy["guardrails"]
    state = by_id["autologon.state_proof"]
    assert state["target_mutation"] is False
    ingest = by_id["autologon.proof_receipt_ingest"]
    assert ingest["mode"] == "local_transform"
    assert ingest["network_activity"] is False and ingest["target_mutation"] is False


def test_artifact_registry_and_run_context_contracts_are_closed() -> None:
    manifest = load(ARTIFACT_TYPES_PATH)
    assert manifest["schema_version"] == "sas-autologon-artifact-types/v1"
    run_context = manifest["run_context"]
    assert run_context["module_path"] == "scripts/SasRunContext.psm1"
    assert run_context["schema_version"] == "sas-run-context/v1"
    assert run_context["artifact_registry_schema"] == "schemas/harness/artifact-registry.schema.json"
    assert set(run_context["required_files"]) == {
        "context.json", "artifact_registry.json", "summary.json", "operator_handoff.txt"
    }
    artifacts = manifest["artifact_types"]
    ids = [item["id"] for item in artifacts]
    filenames = [item["filename"] for item in artifacts]
    assert len(ids) == len(set(ids)) == 7
    assert len(filenames) == len(set(filenames)) == 7
    assert all(item["register_in_artifact_registry"] is True for item in artifacts)
    for item in artifacts:
        assert (ROOT / item["schema_path"]).is_file()
    public = [item for item in artifacts if item["privacy_class"] == "public_safe"]
    assert [item["id"] for item in public] == ["autologon_proof_receipt"]


def recursive_keys(value: Any) -> set[str]:
    keys: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            keys.add(key.lower())
            keys.update(recursive_keys(child))
    elif isinstance(value, list):
        for item in value:
            keys.update(recursive_keys(item))
    return keys


def test_privacy_and_secret_field_rejection() -> None:
    valid_paths = sorted(FIXTURE_DIR.glob("*.fixture.json"))
    forbidden_keys = {
        "defaultpassword", "password", "target_hostname", "hostname", "computer_name",
        "username", "account_name", "package_path", "software_share_root",
        "installer_relative_path", "machine_local_path", "raw_evidence",
    }
    for path in valid_paths:
        payload = load(path)
        assert not (recursive_keys(payload) & forbidden_keys), f"private key in {path.name}"
        text = json.dumps(payload).lower()
        for pattern in (r"[a-z]:\\\\users\\\\", r"/home/[a-z0-9._-]+", r"\\\\\\\\[^\\\\\s]+\\\\(?:admin\$|packages)"):
            assert re.search(pattern, text) is None, f"machine-local/private value in {path.name}"

    receipt_schema = load(SCHEMA_DIR / SCHEMAS["sas-autologon-proof-receipt/v1"])
    assert set(receipt_schema["required"]) == RECEIPT_KEYS
    assert set(receipt_schema["properties"]) == RECEIPT_KEYS
    for path in FIXTURE_DIR.glob("receipt-*.fixture.json"):
        assert set(load(path)) == RECEIPT_KEYS


def test_fixture_proof_ceilings_never_promote_live_runtime() -> None:
    live_true_fields = {
        "network_activity_performed",
        "target_mutation_performed",
        "task_created",
        "executed_as_system",
        "installer_executed",
        "current_token_access_proven",
        "reboot_observed",
        "automatic_sign_in_observed",
        "session_access_proven",
        "application_started",
        "application_ready",
        "technician_behavior_observed",
        "application_behavior_proven",
        "canonical_transport_used",
        "deployment_succeeded",
    }

    def inspect(value: Any, path: Path) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key in live_true_fields:
                    assert child is False, f"fixture overclaims {key}: {path.name}"
                inspect(child, path)
        elif isinstance(value, list):
            for item in value:
                inspect(item, path)

    for path in FIXTURE_DIR.glob("*.fixture.json"):
        payload = load(path)
        if payload["schema_version"] == "sas-autologon-proof-receipt/v1":
            assert payload["classification"] != "acceptance_proven"
            assert payload["proof_level"] != "operator_accepted_runtime"
            continue
        if payload.get("evidence_class") == "sanitized_fixture":
            inspect(payload, path)
            assert "fixture" in payload["classification"]
            assert payload["proof_level"] == "sanitized_fixture_contract"


def test_workflow_migration_ledger_and_ci_registration() -> None:
    workflow = read(WORKFLOW_PATH)
    for marker in (
        "contract_status: frozen_v1",
        "scripts/SasRunContext.psm1",
        "harness/api/autologon-artifact-types.json",
        "canonical_transport_refactor_pending",
        "source evidence in place",
        "never copy source evidence",
    ):
        assert marker in workflow

    doc = read(DOC_PATH)
    existing_versions = {
        "sas-autologon-deployment-summary/v1",
        "sas-autologon-state-snapshot/v1",
        "sas-autologon-state-delta/v1",
        "sas-autologon-state-delta-run/v1",
        "sas-autologon-state-delta-summary/v1",
        "sas-autologon-state-delta-operator-state/v1",
        "sas-autologon-file-access-snapshot/v1",
        "sas-autologon-file-access-delta/v1",
        "sas-autologon-file-access-run/v1",
        "sas-autologon-file-access-summary/v1",
        "sas-autologon-session-access-proof/v1",
        "sas-autologon-technician-runtime-config/v1",
        "sas-autologon-technician-runtime-proof/v1",
    }
    for version in existing_versions:
        assert version in doc, f"existing emission missing from ledger: {version}"
    assert "No `schema_version`; `gate_version` is `1.0.0`" in doc
    assert "No existing public contract is renamed in place." in doc

    test_path = "Tests/survey/test_autologon_proof_contract_floor_contracts.py"
    assert test_path in read(CI_PATH)
    assert f"python3 {test_path}" in read(OFFLINE_RUNNER)


def test_optional_jsonschema_validation_when_available() -> None:
    try:
        import jsonschema  # type: ignore
    except ImportError:
        return
    schemas = {version: load(SCHEMA_DIR / filename) for version, filename in SCHEMAS.items()}
    for schema in schemas.values():
        jsonschema.Draft202012Validator.check_schema(schema)
    for path in FIXTURE_DIR.glob("*.fixture.json"):
        payload = load(path)
        jsonschema.Draft202012Validator(schemas[payload["schema_version"]]).validate(payload)
    for path in FIXTURE_DIR.glob("*.invalid.json"):
        payload = load(path)
        assert not jsonschema.Draft202012Validator(schemas[payload["schema_version"]]).is_valid(payload)


def main() -> None:
    tests = [
        test_json_parsing_and_schema_self_validation,
        test_sanitized_success_and_failure_fixtures_validate,
        test_intentionally_invalid_fixtures_are_rejected,
        test_operation_ids_are_unique_frozen_and_fail_closed,
        test_artifact_registry_and_run_context_contracts_are_closed,
        test_privacy_and_secret_field_rejection,
        test_fixture_proof_ceilings_never_promote_live_runtime,
        test_workflow_migration_ledger_and_ci_registration,
        test_optional_jsonschema_validation_when_available,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon proof contract-floor checks")


if __name__ == "__main__":
    main()
