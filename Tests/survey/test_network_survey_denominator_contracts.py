#!/usr/bin/env python3
"""Dependency-free contracts for the network survey artifact denominator and adapter harness."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schemas" / "survey" / "network-survey-artifact-denominator.schema.json"
REGISTRY = ROOT / "survey" / "network_survey_artifact_adapters.json"
NORMALIZER = ROOT / "scripts" / "SasSurveyArtifactNormalizer.psm1"
VALIDATOR = ROOT / "scripts" / "Test-SasSurveyArtifactDenominator.ps1"
DELTA_MODULE = ROOT / "scripts" / "SasDeltaEvidenceCache.psm1"
PLANNER = ROOT / "survey" / "sas-delta-preflight-plan.ps1"
WRITER = ROOT / "scripts" / "Write-SasDeltaPreflightArtifacts.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "network-survey-delta-contracts.yml"
OFFLINE_RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"
DOC = ROOT / "docs" / "NETWORK_SURVEY_ARTIFACT_DENOMINATOR.md"
FIXTURES = (
    ROOT / "survey" / "fixtures" / "delta_denominator_requested.alias.sample.csv",
    ROOT / "survey" / "fixtures" / "delta_denominator_requested.sample.json",
    ROOT / "survey" / "fixtures" / "delta_denominator_targets.sample.txt",
    ROOT / "survey" / "fixtures" / "delta_denominator_evidence.network.sample.csv",
    ROOT / "survey" / "fixtures" / "delta_denominator_evidence.identity.sample.jsonl",
    ROOT / "survey" / "fixtures" / "delta_denominator_invalid.sample.csv",
)

ROW_REQUIRED = {
    "row_id", "record_role", "serial", "normalized_serial", "target", "normalized_target",
    "candidate_targets", "device_type", "site", "expected_prefix", "observed_at", "evidence_type",
    "evidence_strength_tier", "serial_identity_confirmed", "reachability_status", "open_ports",
    "resolved_address", "mac_address", "port", "port_status", "ad_candidate_status", "tracker_status",
    "source_file", "source_adapter", "source_values",
}


def read(path: Path) -> str:
    assert path.exists(), f"missing required surface: {path}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def test_denominator_surfaces_exist() -> None:
    for path in (SCHEMA, REGISTRY, NORMALIZER, VALIDATOR, DELTA_MODULE, PLANNER, WRITER, WORKFLOW, OFFLINE_RUNNER, DOC, *FIXTURES):
        assert path.exists(), f"missing denominator surface: {path}"


def test_schema_is_closed_versioned_and_role_aware() -> None:
    schema = load_json(SCHEMA)
    assert schema["$schema"].endswith("2020-12/schema")
    assert schema["additionalProperties"] is False
    assert schema["properties"]["contract_version"]["const"] == "1.0.0"
    assert set(schema["properties"]["artifact_role"]["enum"]) == {"requested_population", "evidence_snapshot"}
    row = schema["$defs"]["row"]
    assert row["additionalProperties"] is False
    assert set(row["required"]) == ROW_REQUIRED
    assert {"identity", "reachability", "negative_silent"}.issubset(set(row["properties"]["evidence_type"]["enum"]))
    assert any("anyOf" in rule for rule in row["allOf"]), "schema must require at least one denominator key"


def test_adapter_registry_covers_modular_formats_without_expanding_planner_aliases() -> None:
    registry = load_json(REGISTRY)
    schema = load_json(SCHEMA)
    assert registry["registry_version"] == "1.0.0"
    assert registry["denominator_contract_version"] == schema["properties"]["contract_version"]["const"]
    assert registry["denominator_schema"] == "schemas/survey/network-survey-artifact-denominator.schema.json"
    canonical = set(registry["canonical_fields"])
    coverage: dict[str, set[str]] = {"requested_population": set(), "evidence_snapshot": set()}
    ids: set[str] = set()
    for adapter in registry["adapters"]:
        assert adapter["id"] not in ids, f"duplicate adapter id: {adapter['id']}"
        ids.add(adapter["id"])
        coverage[adapter["role"]].update(adapter["formats"])
        assert set(adapter["mappings"]).issubset(canonical), f"adapter maps an undeclared canonical field: {adapter['id']}"
        assert adapter["detection"]["required_any"], f"adapter detection is empty: {adapter['id']}"
    assert coverage["requested_population"] == {"csv", "txt", "json", "jsonl"}
    assert coverage["evidence_snapshot"] == {"csv", "json", "jsonl"}
    downstream = read(DELTA_MODULE) + "\n" + read(PLANNER)
    for alias in ("Cybernet S/N", "Neuron S/N", "SerialNumber", "ExpectedHostname", "PingStatus"):
        assert alias not in downstream, f"source alias leaked beyond adapter boundary: {alias}"


def test_normalizer_uses_schema_as_operational_input_and_fails_closed() -> None:
    text = read(NORMALIZER)
    for fragment in (
        "network_survey_artifact_adapters.json", "network-survey-artifact-denominator.schema.json",
        "$Schema.required", "$Schema.'$defs'.row.required", "Select-SasSurveyArtifactAdapter",
        "Test-SasSurveyDenominatorPackage", "ARTIFACT_ROWS_REJECTED", "DENOMINATOR_KEY_MISSING",
        "TIMESTAMP_REQUIRED_FOR_FRESHNESS",
    ):
        assert fragment in text, f"normalizer missing enforcement fragment: {fragment}"
    assert re.search(r"network_activity_performed\s*=\s*\$false", text)
    assert re.search(r"target_mutation_performed\s*=\s*\$false", text)


def test_planner_normalizes_every_artifact_before_delta_logic() -> None:
    text = read(PLANNER) + "\n" + read(WRITER)
    assert text.index("Invoke-SasSurveyArtifactNormalization") < text.index("ConvertFrom-SasRequestedArtifactPackage")
    for fragment in (
        "artifact_intake_manifest.json", "normalized_artifacts", "all_artifacts_valid = $true",
        "normalized_artifact_paths", "validation_report_paths", "denominator_contract_version = '1.0.0'",
    ):
        assert fragment in text, f"planner/writer missing denominator provenance: {fragment}"
    plan_rows = read(ROOT / "scripts" / "Invoke-SasDeltaPreflightPlanRows.ps1")
    assert "PROBE_REQUIRD_STALE_EVIDENCE" not in plan_rows
    assert "PROBE_REQUIRED_STALE_EVIDENCE" in plan_rows


def test_normalizer_and_validator_are_packet_free() -> None:
    text = read(NORMALIZER) + "\n" + read(VALIDATOR)
    for fragment in ("Test-NetConnection", "Test-Connection -ComputerName", "Resolve-DnsName", "Invoke-Command -ComputerName", "naabu -", "nmap "):
        assert fragment not in text, f"artifact intake must remain packet-free: {fragment}"


def test_end_to_end_harness_covers_valid_mixed_formats_and_invalid_artifact() -> None:
    workflow = read(WORKFLOW)
    for fragment in (
        "Run denominator static contracts", "Run modular artifact denominator validation",
        "Run mixed-format denominator-to-delta end-to-end fixture", "Reject an artifact that cannot satisfy the denominator",
        "delta_denominator_requested.sample.json", "delta_denominator_evidence.network.sample.csv",
        "delta_denominator_evidence.identity.sample.jsonl", "delta_denominator_invalid.sample.csv",
        "artifact_intake_manifest.json", "canonical denominator contract",
    ):
        assert fragment in workflow, f"workflow missing end-to-end denominator coverage: {fragment}"
    assert "test_network_survey_denominator_contracts.py" in read(OFFLINE_RUNNER)


def test_fixtures_are_synthetic_and_cover_alias_json_jsonl_txt_and_rejection() -> None:
    combined = "\n".join(read(path) for path in FIXTURES)
    for serial in ("SN2001", "SN2002", "SN2003", "SN2004"):
        assert serial in combined
    assert "Cybernet S/N" in read(FIXTURES[0])
    assert "SerialNumber" in read(FIXTURES[1])
    assert "IdentityConfirmed" in read(FIXTURES[4])
    assert "missing serial target and candidate bridge" in read(FIXTURES[5])
    assert "northwell" not in combined.lower()


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} network survey denominator contracts")
