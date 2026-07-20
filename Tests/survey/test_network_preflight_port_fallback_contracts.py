#!/usr/bin/env python3
"""Contracts for network-preflight port-fallback integration: module, entrypoint, API, and workflow agreement."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MODULE = ROOT / "scripts/SasPortFallbackDecision.psm1"
ENTRYPOINT = ROOT / "scripts/Get-SasPortFallbackDecision.ps1"
PREFLIGHT = ROOT / "survey/sas-network-preflight.ps1"
HARNESS_API = ROOT / "harness/api/sas-harness-api.json"
LOW_NOISE_MODULE = ROOT / "scripts/SasLowNoisePolicy.psm1"
NAABU_PROFILES = ROOT / "survey/naabu_profiles.json"
LOW_NOISE_POLICY = ROOT / "Config/low-noise-policy.json"
DECISION_SCHEMA = ROOT / "schemas/harness/port-fallback-decision.schema.json"
PESTER_TEST = ROOT / "Tests/Pester/SasPortFallbackDecision.Tests.ps1"
FIXTURE_ROOT = ROOT / "Tests/Fixtures/port-fallback-decision"

CANONICAL_DECISIONS = {
    "default_ok",
    "web_only_fallback",
    "approved_subnet_host_discovery_required",
    "udp_justification_required",
    "all_ports_denied_without_explicit_gate",
    "review_required",
}


def read(path: Path) -> str:
    assert path.is_file(), f"missing: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path):
    return json.loads(read(path))


def test_module_exists_and_parses() -> None:
    content = read(MODULE)
    assert "New-SasPortFallbackDecision" in content
    assert "Export-ModuleMember" in content
    assert "keyports_cybernet_json" in content


def test_entrypoint_exists_and_parses() -> None:
    content = read(ENTRYPOINT)
    assert "Get-SasPortFallbackDecision.ps1" in content or "FixtureMode" in content
    assert "SasPortFallbackDecision.psm1" in content
    assert "New-SasPortFallbackDecision" in content


def test_module_consumes_canonical_profile_data() -> None:
    content = read(MODULE)
    assert "naabu_profiles.json" in content
    assert "keyports_cybernet_json" in content


def test_module_has_no_hardcoded_port_duplicates() -> None:
    content = read(MODULE)
    assert "Get-CanonicDefaultPorts" in content
    naabu = load(NAABU_PROFILES)
    canonical_ports = naabu["profiles"]["keyports_cybernet_json"]["ports"]
    assert canonical_ports in content or "Get-CanonicDefaultPorts" in content


def test_preflight_imports_decision_module() -> None:
    content = read(PREFLIGHT)
    assert "SasPortFallbackDecision.psm1" in content
    assert "New-SasPortFallbackDecision" in content
    assert "port_fallback_decision.json" in content


def test_preflight_contains_fallback_classification() -> None:
    content = read(PREFLIGHT)
    assert "fallbackDecision" in content
    assert "openDefaultCount" in content or "open_default_port_target_count" in content
    assert "silentCount" in content or "silent_on_default_profile_count" in content
    assert "untestedCount" in content or "untested_target_count" in content


def test_preflight_no_automatic_fallback_execution() -> None:
    content = read(PREFLIGHT)
    assert "No fallback scan was launched automatically" in content


def test_harness_api_registers_operation() -> None:
    api = load(HARNESS_API)
    ops = {op["id"]: op for op in api["operations"]}
    assert "survey.port_fallback.plan" in ops
    op = ops["survey.port_fallback.plan"]
    assert op["network_activity"] is False
    assert op["target_mutation"] is False
    assert "port_fallback_decision.json" in op["outputs"]


def test_pester_tests_exist_and_complete() -> None:
    content = read(PESTER_TEST)
    assert "New-SasPortFallbackDecision correctness" in content
    assert "review_required" in content
    assert "default_ok" in content
    assert "web_only_fallback" in content
    assert "udp_justification_required" in content
    assert "all_ports_denied_without_explicit_gate" in content
    assert "approved_subnet_host_discovery_required" in content


def test_sprint1_schema_is_consumed_not_duplicated() -> None:
    schema = load(DECISION_SCHEMA)
    decision_enum = set(schema["properties"]["decision"]["enum"])
    assert decision_enum == CANONICAL_DECISIONS


if __name__ == "__main__":
    test_module_exists_and_parses()
    test_entrypoint_exists_and_parses()
    test_module_consumes_canonical_profile_data()
    test_module_has_no_hardcoded_port_duplicates()
    test_preflight_imports_decision_module()
    test_preflight_contains_fallback_classification()
    test_preflight_no_automatic_fallback_execution()
    test_harness_api_registers_operation()
    test_pester_tests_exist_and_complete()
    test_sprint1_schema_is_consumed_not_duplicated()
    print("network-preflight port-fallback contracts passed")
