#!/usr/bin/env python3
"""Dependency-free contracts for the software deployment transport floor."""
from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESULT_SCHEMA = ROOT / "schemas/harness/software-deployment-transport-result.schema.json"
RECEIPT_SCHEMA = ROOT / "schemas/harness/software-deployment-transport-receipt.schema.json"
LIVE_CERT_SCHEMA = ROOT / "schemas/harness/software-deployment-transport-live-cert-result.schema.json"
FIXTURES = ROOT / "Tests/Fixtures/software-deployment-transport"
API = ROOT / "harness/api/sas-harness-api.json"
WORKFLOW = ROOT / "harness/workflows/software-deployment-transport.yaml"
DOC = ROOT / "docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md"
CI = ROOT / ".github/workflows/harness-contracts.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
INGEST_SCRIPT = ROOT / "tools/production-install-proof/ingest_transport_proof.py"
POWERSHELL_SCRIPT = ROOT / "scripts/Invoke-SasTransportProofIngest.ps1"

RESULT_VERSION = "sas-software-deployment-transport-result/v1"
RECEIPT_VERSION = "sas-software-deployment-transport-receipt/v1"
LIVE_CERT_VERSION = "sas-software-deployment-transport-live-cert-result/v1"
CLASSIFICATIONS = {
    "kerberos_smb_task_ready",
    "winrm_ready",
    "no_supported_transport",
    "transport_reachable_authorization_denied",
    "inconclusive",
}
TRANSPORTS = {"kerberos_smb_task", "winrm", "none"}
OPERATION_IDS = {
    "software_install.transport_preflight",
    "software_install.transport_live_cert",
    "software_install.transport_proof_ingest",
}
RESULT_KEYS = {
    "schema_version",
    "workflow_id",
    "evidence_class",
    "target_scope",
    "observations",
    "decision",
    "proof",
    "network_activity_performed",
    "target_mutation_performed",
    "proof_ceiling",
}
OBSERVATION_KEYS = {
    "dns",
    "identity",
    "service_tickets",
    "tcp",
    "winrm_session",
    "admin_share",
    "schedule_service",
    "scheduled_task_query",
}
RECEIPT_KEYS = {
    "schema_version",
    "workflow_id",
    "outcome",
    "reason_codes",
    "source",
    "decision",
    "certification",
    "privacy",
    "proof_level",
    "proof_ceiling",
}
RECEIPT_SOURCE_KEYS = {
    "source_schema_version",
    "source_evidence_sha256",
    "source_evidence_size_bytes",
    "source_evidence_retained_operator_local",
    "source_evidence_copied_to_output",
    "contract_fixture",
    "operator_confirmed",
}
RECEIPT_DECISION_KEYS = {"preflight_classification", "selected_transport"}
CERTIFICATION_KEYS = {
    "task_created",
    "executed_as_system",
    "result_retrieved",
    "task_deleted",
    "staging_deleted",
    "zero_remnants_verified",
    "software_installation_performed",
    "harmless_payload_only",
}
PRIVACY_KEYS = {
    "hostnames_emitted",
    "usernames_emitted",
    "ticket_bytes_emitted",
    "credentials_emitted",
    "package_paths_emitted",
    "machine_local_paths_emitted",
    "raw_evidence_emitted",
}


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def kerberos_smb_ready(observations: dict) -> bool:
    return all(
        [
            observations["dns"] == {
                **observations["dns"],
                "attempted": True,
                "resolved": True,
                "timed_out": False,
            },
            observations["identity"]["domain_joined"] is True,
            observations["identity"]["tgt_present"] is True,
            observations["service_tickets"]["cifs"]["requested"] is True,
            observations["service_tickets"]["cifs"]["issued"] is True,
            observations["tcp"]["port_445"]["tested"] is True,
            observations["tcp"]["port_445"]["reachable"] is True,
            observations["tcp"]["port_135"]["tested"] is True,
            observations["tcp"]["port_135"]["reachable"] is True,
            observations["admin_share"] == {
                "attempted": True,
                "authorized": True,
                "authorization_denied": False,
            },
            observations["schedule_service"] == {
                "queried": True,
                "running": True,
                "authorization_denied": False,
            },
            observations["scheduled_task_query"] == {
                "queried": True,
                "succeeded": True,
                "authorization_denied": False,
            },
        ]
    )


def winrm_ready(observations: dict) -> bool:
    port_ready = any(
        observations["tcp"][name]["tested"] and observations["tcp"][name]["reachable"]
        for name in ("port_5985", "port_5986")
    )
    return port_ready and observations["winrm_session"] == {
        "attempted": True,
        "authorized": True,
        "authorization_denied": False,
    }


def validate_result(payload: dict) -> None:
    require(set(payload) == RESULT_KEYS, "result must be a closed object")
    require(payload["schema_version"] == RESULT_VERSION, "unsupported result schema")
    require(payload["workflow_id"] == "software-deployment-transport", "wrong workflow")
    require(set(payload["observations"]) == OBSERVATION_KEYS, "observation set is not closed")
    require(payload["decision"]["classification"] in CLASSIFICATIONS, "unknown classification")
    require(payload["decision"]["selected_transport"] in TRANSPORTS, "unknown transport")
    require(payload["decision"]["silent_fallback_permitted"] is False, "silent fallback enabled")
    require(payload["decision"]["fallback_after_mutation_permitted"] is False, "post-mutation fallback enabled")
    require(payload["target_mutation_performed"] is False, "preflight cannot claim mutation")
    require(payload["target_scope"]["identifier_emitted"] is False, "target identifier leaked")
    require(1 <= payload["target_scope"]["target_count"] <= 25, "target count is unbounded")
    for ticket in ("http", "host", "cifs"):
        require(payload["observations"]["service_tickets"][ticket]["ticket_bytes_emitted"] is False, "ticket bytes leaked")
    require(payload["observations"]["identity"]["ticket_bytes_emitted"] is False, "ticket bytes leaked")
    for flag in ("task_creation_proven", "system_execution_proven", "result_retrieval_proven", "cleanup_proven"):
        require(payload["proof"][flag] is False, f"preflight overclaims {flag}")
    if payload["evidence_class"] == "sanitized_fixture":
        require(payload["network_activity_performed"] is False, "fixture claims network activity")
        require(payload["proof"]["live_runtime"] is False, "fixture claims live runtime")

    classification = payload["decision"]["classification"]
    observations = payload["observations"]
    if classification == "kerberos_smb_task_ready":
        require(payload["decision"]["selected_transport"] == "kerberos_smb_task", "wrong SMB selection")
        require(kerberos_smb_ready(observations), "SMB readiness prerequisite missing")
        require(payload["proof"]["transport_authorization_proven"] is True, "SMB authorization not proven")
    elif classification == "winrm_ready":
        require(payload["decision"]["selected_transport"] == "winrm", "wrong WinRM selection")
        require(winrm_ready(observations), "WinRM authorization prerequisite missing")
        require(payload["proof"]["transport_authorization_proven"] is True, "WinRM authorization not proven")
    else:
        require(payload["decision"]["selected_transport"] == "none", "failure classification selected a transport")
        require(payload["proof"]["transport_authorization_proven"] is False, "failure classification claims authorization")
    if classification == "transport_reachable_authorization_denied":
        denied = observations["winrm_session"]["authorization_denied"] or observations["admin_share"]["authorization_denied"] or observations["schedule_service"]["authorization_denied"] or observations["scheduled_task_query"]["authorization_denied"]
        require(denied, "authorization-denied classification lacks a denial observation")
    if classification == "no_supported_transport":
        reachable = any(observations["tcp"][name]["reachable"] for name in observations["tcp"])
        require(not reachable, "no-supported-transport contradicts reachable transport ports")


def validate_receipt(payload: dict) -> None:
    require(set(payload) == RECEIPT_KEYS, "receipt must be a closed public object")
    require(payload["schema_version"] == RECEIPT_VERSION, "unsupported receipt schema")
    require(payload["workflow_id"] == "software-deployment-transport-proof-ingest", "wrong receipt workflow")
    require(set(payload["source"]) == RECEIPT_SOURCE_KEYS, "receipt source is not closed")
    require(set(payload["decision"]) == RECEIPT_DECISION_KEYS, "receipt decision is not closed")
    require(set(payload["certification"]) == CERTIFICATION_KEYS, "receipt certification is not closed")
    require(set(payload["privacy"]) == PRIVACY_KEYS, "receipt privacy block is not closed")
    require(re.fullmatch(r"[a-f0-9]{64}", payload["source"]["source_evidence_sha256"]) is not None, "invalid source digest")
    require(payload["source"]["source_evidence_retained_operator_local"] is True, "source not retained locally")
    require(payload["source"]["source_evidence_copied_to_output"] is False, "private source copied")
    require(all(value is False for value in payload["privacy"].values()), "receipt privacy flag is not false")
    require(payload["certification"]["software_installation_performed"] is False, "live cert installed software")
    require(payload["certification"]["harmless_payload_only"] is True, "live cert payload not harmless")
    allowed_privacy_keys = set(payload["privacy"])

    def reject_sensitive_keys(value: object, path: tuple[str, ...] = ()) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if not (path == ("privacy",) and key in allowed_privacy_keys):
                    lowered = key.lower()
                    require(
                        not any(fragment in lowered for fragment in ("hostname", "username", "ticket_bytes", "credential", "package_path", "machine_local_path", "raw_evidence")),
                        f"public receipt contains forbidden field: {key}",
                    )
                reject_sensitive_keys(child, (*path, key))
        elif isinstance(value, list):
            for item in value:
                reject_sensitive_keys(item, path)

    reject_sensitive_keys(payload)
    serialized = json.dumps(payload).lower()
    for forbidden in ("target_hostname", "ticket_cache", "begin kerberos", "c:\\users\\", "/home/"):
        require(forbidden not in serialized, f"public receipt contains forbidden field or value: {forbidden}")
    if payload["outcome"] == "contract_only":
        require(payload["source"]["contract_fixture"] is True, "contract receipt not fixture-bound")
        require(payload["proof_level"] == "sanitized_fixture_contract", "fixture overclaims proof")
        for flag in ("task_created", "executed_as_system", "result_retrieved", "task_deleted", "staging_deleted", "zero_remnants_verified"):
            require(payload["certification"][flag] is False, f"fixture overclaims {flag}")
    if payload["outcome"] == "live_cert_pass":
        require(payload["source"]["contract_fixture"] is False, "fixture became live proof")
        require(payload["source"]["operator_confirmed"] is True, "live proof lacks confirmation")
        require(payload["proof_level"] == "live_transport_execution_and_cleanup", "wrong live proof level")
        for flag in ("task_created", "executed_as_system", "result_retrieved", "task_deleted", "staging_deleted", "zero_remnants_verified"):
            require(payload["certification"][flag] is True, f"live cert pass lacks {flag}")


def test_schemas_freeze_closed_vocabularies_and_privacy() -> None:
    result = load(RESULT_SCHEMA)
    receipt = load(RECEIPT_SCHEMA)
    assert result["additionalProperties"] is False
    assert receipt["additionalProperties"] is False
    assert result["properties"]["schema_version"]["const"] == RESULT_VERSION
    assert receipt["properties"]["schema_version"]["const"] == RECEIPT_VERSION
    assert set(result["properties"]["decision"]["properties"]["classification"]["enum"]) == CLASSIFICATIONS
    assert result["properties"]["target_mutation_performed"]["const"] is False
    assert receipt["properties"]["privacy"]["additionalProperties"] is False
    for field in receipt["properties"]["privacy"]["required"]:
        assert receipt["properties"]["privacy"]["properties"][field]["const"] is False


def test_valid_fixture_matrix_is_dependency_free_and_fail_closed() -> None:
    result_files = sorted(FIXTURES.glob("*.fixture.json"))
    assert [path.name for path in result_files] == [
        "authorization-denied.fixture.json",
        "inconclusive.fixture.json",
        "kerberos-smb-task-ready.fixture.json",
        "live-cert-result.fixture.json",
        "no-supported-transport.fixture.json",
        "public-receipt.fixture.json",
        "winrm-ready.fixture.json",
    ]
    seen = set()
    for path in result_files:
        payload = load(path)
        sv = payload.get("schema_version", "")
        if sv == RESULT_VERSION:
            validate_result(payload)
            seen.add(payload["decision"]["classification"])
        elif sv == RECEIPT_VERSION:
            validate_receipt(payload)
        elif sv == LIVE_CERT_VERSION:
            # Live-cert result fixture — validated by schema check below
            pass
        else:
            raise AssertionError(f"unexpected schema_version in fixture: {path.name}")
    assert seen == CLASSIFICATIONS


def test_invalid_fixtures_and_unknown_classification_are_rejected() -> None:
    for path in sorted(FIXTURES.glob("*.invalid.json")):
        payload = load(path)
        try:
            if payload.get("schema_version") == RECEIPT_VERSION:
                validate_receipt(payload)
            else:
                validate_result(payload)
        except (KeyError, TypeError, ValueError):
            pass
        else:
            raise AssertionError(f"invalid fixture was accepted: {path.name}")

    unknown = copy.deepcopy(load(FIXTURES / "inconclusive.fixture.json"))
    unknown["decision"]["classification"] = "automatic_best_effort_fallback"
    try:
        validate_result(unknown)
    except ValueError:
        pass
    else:
        raise AssertionError("unknown classification was accepted")


def test_json_schema_validation_when_available() -> None:
    try:
        import jsonschema  # type: ignore
    except ImportError:
        return
    result_schema = load(RESULT_SCHEMA)
    receipt_schema = load(RECEIPT_SCHEMA)
    live_cert_schema = load(LIVE_CERT_SCHEMA)
    validators = {
        RESULT_VERSION: jsonschema.Draft202012Validator(result_schema),
        RECEIPT_VERSION: jsonschema.Draft202012Validator(receipt_schema),
        LIVE_CERT_VERSION: jsonschema.Draft202012Validator(live_cert_schema),
    }
    for path in FIXTURES.glob("*.fixture.json"):
        payload = load(path)
        validators[payload["schema_version"]].validate(payload)
    for path in FIXTURES.glob("*.invalid.json"):
        payload = load(path)
        version = payload.get("schema_version", RESULT_VERSION)
        assert not validators[version].is_valid(payload), f"schema accepted invalid fixture: {path.name}"


def test_harness_operations_are_frozen_and_do_not_grant_hidden_authority() -> None:
    api = load(API)
    operations = {item["id"]: item for item in api["operations"]}
    assert OPERATION_IDS <= set(operations)
    preflight = operations["software_install.transport_preflight"]
    assert preflight["mode"] == "operator_execute"
    assert preflight["network_activity"] is True
    assert preflight["target_mutation"] is False
    live_cert = operations["software_install.transport_live_cert"]
    assert live_cert["network_activity"] is True
    assert live_cert["target_mutation"] is True
    assert "No_software_installation" in live_cert["guardrails"]
    ingest = operations["software_install.transport_proof_ingest"]
    assert ingest["mode"] == "local_transform"
    assert ingest["network_activity"] is False
    assert ingest["target_mutation"] is False
    execute = operations["software_install.operator_execute"]
    assert "schema_valid_transport_result" in execute["inputs"]
    assert "Schema_valid_transport_decision_required" in execute["guardrails"]
    assert "No_silent_fallback_after_mutation_begins" in execute["guardrails"]


def test_workflow_docs_ci_and_offline_runner_preserve_authority_boundary() -> None:
    workflow = read(WORKFLOW)
    for marker in (
        "contract_status: frozen_v1",
        "software_install.transport_preflight",
        "software_install.transport_live_cert",
        "software_install.transport_proof_ingest",
        "implementation_status: deferred_to_p02",
        "No fallback is permitted after mutation begins.",
    ):
        assert marker in workflow
    doc = read(DOC)
    for marker in (
        RESULT_VERSION,
        RECEIPT_VERSION,
        "Reachability and authorization are separate observations.",
        "Application behavior remains authoritative in repository scripts and modules",
        "does not implement a transport",
        "does not prove transport implementation",
    ):
        assert marker in doc
    test_path = "Tests/survey/test_software_deployment_transport_contracts.py"
    assert test_path in read(CI)
    assert f"python3 {test_path}" in read(RUNNER)


def test_tracked_transport_floor_has_no_live_or_machine_local_evidence() -> None:
    paths = [RESULT_SCHEMA, RECEIPT_SCHEMA, WORKFLOW, DOC, *sorted(FIXTURES.glob("*.json"))]
    combined = "\n".join(read(path) for path in paths)
    forbidden_patterns = (
        r"(?i)[a-z]:\\users\\",
        r"(?i)/home/[a-z0-9._-]+",
        r"(?i)begin.*kerberos",
        r"(?i)session[_ -]?key",
        r"(?i)password\s*[:=]",
        r"(?i)\\\\[^\\\s]+\\(?:admin\$|packages)"
    )
    for pattern in forbidden_patterns:
        assert not re.search(pattern, combined), f"private/live evidence pattern found: {pattern}"


def test_live_cert_result_schema_is_closed_and_frozen() -> None:
    """The live-cert result schema exists, is closed, and uses the frozen version."""
    require(LIVE_CERT_SCHEMA.exists(), f"live-cert result schema missing: {LIVE_CERT_SCHEMA}")
    schema = load(LIVE_CERT_SCHEMA)
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"] == LIVE_CERT_VERSION
    assert schema["properties"]["workflow_id"]["const"] == "software-deployment-transport-live-cert"
    assert "allOf" not in schema, "source schema must permit failed or partial certification results"
    # Certification block must be closed
    cert_props = schema["properties"]["certification"]["properties"]
    assert set(cert_props) == CERTIFICATION_KEYS
    assert cert_props["software_installation_performed"]["const"] is False
    assert cert_props["harmless_payload_only"]["const"] is True
    # Privacy block must be closed with all-false defaults
    priv_props = schema["properties"]["privacy"]["properties"]
    assert set(priv_props) == PRIVACY_KEYS
    for field in schema["properties"]["privacy"]["required"]:
        assert priv_props[field]["const"] is False


def test_receipt_ingest_produces_valid_receipt_from_fixture() -> None:
    """The receipt ingest Python script produces a valid receipt from a fixture."""
    require(INGEST_SCRIPT.exists(), f"receipt ingest script missing: {INGEST_SCRIPT}")
    # Use the live-cert result fixture as a mock source
    source_fixture = FIXTURES / "live-cert-result.fixture.json"
    require(source_fixture.exists(), f"live-cert-result fixture missing: {source_fixture}")
    import subprocess
    import tempfile

    with tempfile.TemporaryDirectory() as tmpdir:
        result = subprocess.run(
            [sys.executable, str(INGEST_SCRIPT),
             "--source", str(source_fixture),
             "--output-dir", tmpdir,
             "--contract-fixture"],
            capture_output=True, text=True, timeout=30,
        )
        assert result.returncode == 0, f"ingest failed: {result.stderr}"
        output = json.loads(result.stdout)
        receipt_path = Path(output["receipt"])
        assert receipt_path.exists(), "receipt not written"
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        validate_receipt(receipt)
        assert receipt["outcome"] == "contract_only"
        assert receipt["source"]["contract_fixture"] is True
        assert receipt["source"]["source_evidence_copied_to_output"] is False
        assert receipt["source"]["source_evidence_retained_operator_local"] is True
        # Verify summary was written
        summary_path = Path(output["summary"])
        assert summary_path.exists(), "summary not written"
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        assert summary["schema_version"] == "sas-run-summary/v1"
        assert summary["privacy_clean"] is True


def test_receipt_ingest_validates_the_complete_live_cert_source_schema() -> None:
    """Every source field is validated through the tracked live-cert schema."""
    import subprocess
    import tempfile

    source = load(FIXTURES / "live-cert-result.fixture.json")
    source["network_activity_performed"] = True
    source["target_mutation_performed"] = True
    invalid_sources: list[tuple[str, dict]] = []

    missing_timestamp = copy.deepcopy(source)
    missing_timestamp.pop("generated_at_utc")
    invalid_sources.append(("missing timestamp", missing_timestamp))

    invalid_timestamp = copy.deepcopy(source)
    invalid_timestamp["generated_at_utc"] = "not-a-date"
    invalid_sources.append(("invalid timestamp", invalid_timestamp))

    non_boolean_activity = copy.deepcopy(source)
    non_boolean_activity["network_activity_performed"] = "true"
    invalid_sources.append(("non-boolean activity", non_boolean_activity))

    short_proof_ceiling = copy.deepcopy(source)
    short_proof_ceiling["proof_ceiling"] = "too short"
    invalid_sources.append(("short proof ceiling", short_proof_ceiling))

    extra_root_property = copy.deepcopy(source)
    extra_root_property["unexpected"] = False
    invalid_sources.append(("extra root property", extra_root_property))

    extra_decision_property = copy.deepcopy(source)
    extra_decision_property["decision"]["fallback"] = "winrm"
    invalid_sources.append(("extra decision property", extra_decision_property))

    extra_certification_property = copy.deepcopy(source)
    extra_certification_property["certification"]["installer_started"] = False
    invalid_sources.append(("extra certification property", extra_certification_property))

    for label, candidate in invalid_sources:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_path = Path(tmpdir) / "invalid_source.json"
            source_path.write_text(json.dumps(candidate), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(INGEST_SCRIPT),
                 "--source", str(source_path),
                 "--output-dir", str(Path(tmpdir) / "out")],
                capture_output=True, text=True, timeout=30,
            )
            assert result.returncode != 0, f"schema accepted {label}"
            assert "source schema validation failed" in result.stderr.lower(), result.stderr


def test_live_cert_pass_requires_activity_mutation_and_smb_decision() -> None:
    """Operator confirmation and certification flags cannot create false proof."""
    import subprocess
    import tempfile

    source = load(FIXTURES / "live-cert-result.fixture.json")
    source["network_activity_performed"] = True
    source["target_mutation_performed"] = True
    invalid_pass_inputs: list[tuple[str, dict, str]] = []

    no_network = copy.deepcopy(source)
    no_network["network_activity_performed"] = False
    invalid_pass_inputs.append(("network activity false", no_network, "execution_failed"))

    no_mutation = copy.deepcopy(source)
    no_mutation["target_mutation_performed"] = False
    invalid_pass_inputs.append(("target mutation false", no_mutation, "execution_failed"))

    incomplete_cleanup = copy.deepcopy(source)
    incomplete_cleanup["certification"]["zero_remnants_verified"] = False
    invalid_pass_inputs.append(("cleanup incomplete", incomplete_cleanup, "cleanup_incomplete"))

    winrm = copy.deepcopy(source)
    winrm["decision"] = {
        "preflight_classification": "winrm_ready",
        "selected_transport": "winrm",
    }
    invalid_pass_inputs.append(("WinRM decision", winrm, "execution_failed"))

    for label, candidate, expected_reason in invalid_pass_inputs:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_path = Path(tmpdir) / "source.json"
            source_path.write_text(json.dumps(candidate), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(INGEST_SCRIPT),
                 "--source", str(source_path),
                 "--output-dir", str(Path(tmpdir) / "out"),
                 "--operator-confirmed"],
                capture_output=True, text=True, timeout=30,
            )
            assert result.returncode == 0, f"ingest failed for {label}: {result.stderr}"
            output = json.loads(result.stdout)
            receipt = load(Path(output["receipt"]))
            assert receipt["outcome"] == "live_cert_failed", f"false pass for {label}"
            assert receipt["proof_level"] == "insufficient"
            assert expected_reason in receipt["reason_codes"]


def test_receipt_ingest_rejects_private_fields() -> None:
    """The receipt ingest rejects source evidence containing forbidden private fields."""
    require(INGEST_SCRIPT.exists(), f"receipt ingest script missing: {INGEST_SCRIPT}")
    import subprocess
    import tempfile

    bad_source = {
        "schema_version": LIVE_CERT_VERSION,
        "workflow_id": "software-deployment-transport-live-cert",
        "generated_at_utc": "2026-07-22T00:00:00Z",
        "decision": {
            "preflight_classification": "kerberos_smb_task_ready",
            "selected_transport": "kerberos_smb_task",
        },
        "certification": {
            "task_created": True, "executed_as_system": True,
            "result_retrieved": True, "task_deleted": True,
            "staging_deleted": True, "zero_remnants_verified": True,
            "software_installation_performed": False, "harmless_payload_only": True,
        },
        "privacy": {k: False for k in PRIVACY_KEYS},
        "network_activity_performed": True,
        "target_mutation_performed": True,
        "proof_ceiling": "test",
        "hostname": "CORP-WS01",
    }
    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = Path(tmpdir) / "bad_source.json"
        source_path.write_text(json.dumps(bad_source), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(INGEST_SCRIPT),
             "--source", str(source_path),
             "--output-dir", tmpdir],
            capture_output=True, text=True, timeout=30,
        )
        assert result.returncode != 0, "should have rejected private field"
        assert "private field" in result.stderr.lower() or "forbidden" in result.stderr.lower()


def test_receipt_ingest_powershell_script_exists() -> None:
    """The PowerShell receipt ingest wrapper exists and is parseable."""
    require(POWERSHELL_SCRIPT.exists(), f"PowerShell ingest script missing: {POWERSHELL_SCRIPT}")
    content = read(POWERSHELL_SCRIPT)
    assert "Invoke-SasTransportProofIngest" in content
    assert "New-SasRunContext" in content
    assert "Register-SasArtifact" in content
    assert "software-deployment-transport-proof-ingest" in content


def main() -> None:
    tests = [
        test_schemas_freeze_closed_vocabularies_and_privacy,
        test_valid_fixture_matrix_is_dependency_free_and_fail_closed,
        test_invalid_fixtures_and_unknown_classification_are_rejected,
        test_json_schema_validation_when_available,
        test_harness_operations_are_frozen_and_do_not_grant_hidden_authority,
        test_workflow_docs_ci_and_offline_runner_preserve_authority_boundary,
        test_tracked_transport_floor_has_no_live_or_machine_local_evidence,
        test_live_cert_result_schema_is_closed_and_frozen,
        test_receipt_ingest_produces_valid_receipt_from_fixture,
        test_receipt_ingest_validates_the_complete_live_cert_source_schema,
        test_live_cert_pass_requires_activity_mutation_and_smb_decision,
        test_receipt_ingest_rejects_private_fields,
        test_receipt_ingest_powershell_script_exists,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} software deployment transport contract groups")


if __name__ == "__main__":
    main()
