#!/usr/bin/env python3
"""Contracts for port-fallback decision schema, fixtures, routing, and authority boundaries."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SCHEMA = ROOT / "schemas/harness/port-fallback-decision.schema.json"
FIXTURE_ROOT = ROOT / "Tests/Fixtures/port-fallback-decision"
ROUTING = ROOT / "harness/api/agent-routing-manifest.json"
LOW_NOISE_POLICY = ROOT / "Config/low-noise-policy.json"
NAABU_PROFILES = ROOT / "survey/naabu_profiles.json"
DOCTRINE = ROOT / "docs/LOW_NOISE_SURVEY_DOCTRINE.md"
ENGLISH_CONTRACT = ROOT / "docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md"
SKILL = ROOT / ".claude/skills/survey-low-noise/SKILL.md"
RUNNER = ROOT / "Tests/survey/run_offline_survey_tests.sh"
CI_WORKFLOW = ROOT / ".github/workflows/survey-doctrine.yml"
PESTER_TEST = ROOT / "Tests/Pester/SasLowNoisePolicy.Tests.ps1"
PROFILE_SYNC_TEST = ROOT / "Tests/bash/test_naabu_profile_sync.sh"
LOW_NOISE_MODULE = ROOT / "scripts/SasLowNoisePolicy.psm1"

VALID_FIXTURES = [
    "default-ok.fixture.json",
    "web-only-fallback.fixture.json",
    "approval-required.fixture.json",
    "untested-review.fixture.json",
]

INVALID_FIXTURES = [
    "invalid-conflicting-decision.fixture.json",
    "invalid-missing-gate.fixture.json",
    "invalid-narrowed-default-identity.fixture.json",
    "invalid-untested-as-filtered.fixture.json",
    "invalid-unknown-decision.fixture.json",
]

CANONICAL_DECISIONS = {
    "default_ok",
    "web_only_fallback",
    "approved_subnet_host_discovery_required",
    "udp_justification_required",
    "all_ports_denied_without_explicit_gate",
    "review_required",
}


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path):
    return json.loads(read(path))


def test_schema_exists_and_is_valid_json_schema() -> None:
    schema = load(SCHEMA)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == "schemas/harness/port-fallback-decision.schema.json"
    assert schema["additionalProperties"] is False
    assert "schema_version" in schema["required"]
    assert "decision" in schema["required"]
    assert "recommended_profile_id" in schema["required"]
    assert "approval_required" in schema["required"]
    assert "required_gate" in schema["required"]
    assert "network_activity_performed" in schema["required"]
    assert "target_mutation_performed" in schema["required"]
    assert "reason" in schema["required"]
    assert "next_action" in schema["required"]
    assert "proof_level" in schema["required"]

    decision_enum = schema["properties"]["decision"]["enum"]
    assert set(decision_enum) == CANONICAL_DECISIONS, f"decision enum mismatch: {set(decision_enum) ^ CANONICAL_DECISIONS}"

    gate_enum = schema["properties"]["required_gate"]["enum"]
    assert "" in gate_enum, "required_gate must include empty string for no-gate decisions"
    assert "approved_subnet_scope" in gate_enum
    assert "udp_justification" in gate_enum
    assert "explicit_all_ports_gate" in gate_enum

    proof_enum = schema["properties"]["proof_level"]["enum"]
    for level in ("contract", "fixture", "harness_routing", "static_pester", "fixture_e2e", "live_packets", "operator_acceptance"):
        assert level in proof_enum


def test_valid_fixtures_match_schema() -> None:
    schema = load(SCHEMA)
    for fname in VALID_FIXTURES:
        fixture_path = FIXTURE_ROOT / fname
        fixture = load(fixture_path)
        assert fixture["schema_version"] == "sas-port-fallback-decision/v1", f"{fname}: wrong schema_version"
        assert fixture["decision"] in CANONICAL_DECISIONS, f"{fname}: unknown decision {fixture['decision']}"
        assert fixture["network_activity_performed"] is False, f"{fname}: fixture must not claim network activity"


def test_default_ok_fixture_has_no_gate() -> None:
    fixture = load(FIXTURE_ROOT / "default-ok.fixture.json")
    assert fixture["decision"] == "default_ok"
    assert fixture["approval_required"] is False
    assert fixture["required_gate"] == ""
    assert fixture["recommended_profile_id"] == ""
    assert fixture["open_default_port_target_count"] > 0


def test_web_only_fallback_fixture_recommends_web_profile() -> None:
    fixture = load(FIXTURE_ROOT / "web-only-fallback.fixture.json")
    assert fixture["decision"] == "web_only_fallback"
    assert fixture["recommended_profile_id"] == "web_reachability_only_json"
    assert fixture["web_only_reachable_count"] > 0
    assert fixture["admin_surface_reachable_count"] == 0


def test_approval_required_fixture_has_gate() -> None:
    fixture = load(FIXTURE_ROOT / "approval-required.fixture.json")
    assert fixture["decision"] == "approved_subnet_host_discovery_required"
    assert fixture["approval_required"] is True
    assert fixture["required_gate"] == "approved_subnet_scope"
    assert fixture["recommended_profile_id"] == "host_discovery_web_syn_txt"


def test_untested_review_fixture_counts_all_untested() -> None:
    fixture = load(FIXTURE_ROOT / "untested-review.fixture.json")
    assert fixture["decision"] == "review_required"
    assert fixture["untested_target_count"] == 3
    assert fixture["tested_target_count"] == 0
    assert fixture["recommended_profile_id"] == ""


def test_invalid_conflicting_decision_detected() -> None:
    fixture = load(FIXTURE_ROOT / "invalid-conflicting-decision.fixture.json")
    assert fixture["decision"] == "web_only_fallback"
    assert fixture["open_default_port_target_count"] == 3
    assert fixture["admin_surface_reachable_count"] == 3
    assert "contradictory" in fixture["reason"].lower() or "contradicting" in fixture["reason"].lower() or "Decision says" in fixture["reason"]


def test_invalid_missing_gate_detected() -> None:
    fixture = load(FIXTURE_ROOT / "invalid-missing-gate.fixture.json")
    assert fixture["decision"] == "approved_subnet_host_discovery_required"
    assert fixture["required_gate"] == ""
    assert fixture["recommended_profile_id"] == "host_discovery_web_syn_txt"


def test_invalid_narrowed_default_identity_detected() -> None:
    fixture = load(FIXTURE_ROOT / "invalid-narrowed-default-identity.fixture.json")
    assert fixture["profile_source"] == "canonical_default"
    assert len(fixture["effective_ports"]) == 2
    assert fixture["effective_ports"] != [80, 443, 135, 445, 3389, 5985, 5986]
    assert "narrowed" in fixture["reason"].lower() or "custom" in fixture["reason"].lower()


def test_invalid_untested_as_filtered_detected() -> None:
    fixture = load(FIXTURE_ROOT / "invalid-untested-as-filtered.fixture.json")
    assert fixture["untested_target_count"] == 0
    assert fixture["silent_on_default_profile_count"] == 3
    assert "untested" in fixture["reason"].lower()


def test_invalid_unknown_decision_detected() -> None:
    fixture = load(FIXTURE_ROOT / "invalid-unknown-decision.fixture.json")
    assert fixture["decision"] not in CANONICAL_DECISIONS


def test_valid_fixtures_enforce_count_consistency() -> None:
    for fname in VALID_FIXTURES:
        fixture = load(FIXTURE_ROOT / fname)
        tested = fixture["tested_target_count"]
        untested = fixture["untested_target_count"]
        assert tested + untested == fixture["target_count"], (
            f"{fname}: tested ({tested}) + untested ({untested}) != target ({fixture['target_count']})"
        )

        open_default = fixture["open_default_port_target_count"]
        silent = fixture["silent_on_default_profile_count"]
        assert open_default + silent == tested, (
            f"{fname}: open_default ({open_default}) + silent ({silent}) != tested ({tested})"
        )


def test_trigger_survey_low_noise_contains_port_fallback_signals() -> None:
    routing = load(ROUTING)
    survey_trigger = None
    for t in routing["triggers"]:
        if t["id"] == "survey-low-noise-trigger":
            survey_trigger = t
            break
    assert survey_trigger is not None, "survey-low-noise-trigger missing from routing manifest"

    signals = survey_trigger["deterministic_task_signals"]
    required_signals = [
        "port fallback",
        "blocked default ports",
        "network preflight fallback",
        "Cybernet key-port fallback",
    ]
    for sig in required_signals:
        assert sig in signals, f"missing port-fallback signal: {sig}"

    assert survey_trigger["target_type"] == "skill"
    assert survey_trigger["target"] == "survey-low-noise"
    assert survey_trigger["guardrails"][0] == "no blind probing"


def test_skill_retains_capability_dependencies() -> None:
    skill_text = read(SKILL)
    assert "language-runtime-selection" in skill_text
    assert "mutation-and-evidence-boundaries" in skill_text
    assert "proof-and-checkpointing" in skill_text


def test_authority_matrix_in_doctrine() -> None:
    doctrine_text = read(DOCTRINE)
    assert "authority matrix" in doctrine_text.lower() or "authority boundary" in doctrine_text.lower()
    assert "Config/low-noise-policy.json" in doctrine_text
    assert "survey/naabu_profiles.json" in doctrine_text
    assert "port-fallback-decision.schema.json" in doctrine_text


def test_9100_port_decision_documented() -> None:
    doctrine_text = read(DOCTRINE)
    assert "9100" in doctrine_text, "doctrine must document the 9100 port decision"
    policy = load(LOW_NOISE_POLICY)
    preflight = [p for p in policy["profiles"] if p["id"] == "network_preflight"][0]
    assert 9100 in preflight["ports"], "network_preflight profile must retain port 9100"


def test_english_contract_contains_port_fallback_sections() -> None:
    english_text = read(ENGLISH_CONTRACT)
    assert "port fallback" in english_text.lower()
    assert "default_ok" in english_text
    assert "web_only_fallback" in english_text
    assert "review_required" in english_text


def test_naabu_profile_sync_test_consumes_canonical_data() -> None:
    sync_text = read(PROFILE_SYNC_TEST)
    assert "keyports_cybernet_json" in sync_text
    assert "80,443,135,445,3389,5985,5986" in sync_text


def test_low_noise_module_remains_provider_not_decision_engine() -> None:
    module_text = read(LOW_NOISE_MODULE)
    assert "Get-SasLowNoisePolicy" in module_text
    assert "Get-SasLowNoiseProfile" in module_text
    assert "New-SasLowNoiseContextObject" in module_text
    assert "Export-ModuleMember" in module_text


def test_runner_includes_new_tests() -> None:
    runner_text = read(RUNNER)
    assert "test_port_fallback_decision_contracts" in runner_text


def test_ci_workflow_references_new_tests() -> None:
    wf_text = read(CI_WORKFLOW)
    assert "test_port_fallback_decision_contracts" in wf_text
    assert "test_naabu_profile_sync" in wf_text


def test_no_duplicate_skill_created() -> None:
    duplicate_paths = list((ROOT / ".claude/skills").glob("**/SKILL.md"))
    skill_ids = []
    for p in duplicate_paths:
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        skill_ids.append(rel)
    low_noise_skills = [s for s in skill_ids if "low-noise" in s.lower()]
    assert len(low_noise_skills) == 1, f"found {len(low_noise_skills)} low-noise skills: {low_noise_skills}"


if __name__ == "__main__":
    test_schema_exists_and_is_valid_json_schema()
    test_valid_fixtures_match_schema()
    test_default_ok_fixture_has_no_gate()
    test_web_only_fallback_fixture_recommends_web_profile()
    test_approval_required_fixture_has_gate()
    test_untested_review_fixture_counts_all_untested()
    test_invalid_conflicting_decision_detected()
    test_invalid_missing_gate_detected()
    test_invalid_narrowed_default_identity_detected()
    test_invalid_untested_as_filtered_detected()
    test_invalid_unknown_decision_detected()
    test_valid_fixtures_enforce_count_consistency()
    test_trigger_survey_low_noise_contains_port_fallback_signals()
    test_skill_retains_capability_dependencies()
    test_authority_matrix_in_doctrine()
    test_9100_port_decision_documented()
    test_english_contract_contains_port_fallback_sections()
    test_naabu_profile_sync_test_consumes_canonical_data()
    test_low_noise_module_remains_provider_not_decision_engine()
    test_no_duplicate_skill_created()
    print("port-fallback decision contracts passed")
