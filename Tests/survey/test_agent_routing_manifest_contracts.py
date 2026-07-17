#!/usr/bin/env python3
"""Contracts for deterministic repository task routing."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROUTING = ROOT / "harness/api/agent-routing-manifest.json"
SCHEMA = ROOT / "schemas/harness/agent-routing-manifest.schema.json"
CAPABILITIES = ROOT / "harness/api/agent-capability-manifest.json"
HARNESS_API = ROOT / "harness/api/sas-harness-api.json"
WORKFLOW_SPEC = ROOT / "harness/workflows/agent-sprint-capsule.yaml"
AGENTS = ROOT / "AGENTS.md"
CODEBASE_MAP = ROOT / "CODEBASE_MAP.md"
AI_ENTRYPOINT = ROOT / "docs/AI_HARNESS_ENTRYPOINT.md"
WORKFLOW = ROOT / ".github/workflows/agent-instruction-contracts.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path):
    return json.loads(read(path))


def test_schema_and_authority_paths() -> None:
    routing, schema = load(ROUTING), load(SCHEMA)
    assert routing["schema_version"] == "sas-agent-routing-manifest/v1"
    assert routing["schema_path"] == "schemas/harness/agent-routing-manifest.schema.json"
    assert routing["capability_manifest_path"] == "harness/api/agent-capability-manifest.json"
    assert routing["harness_api_path"] == "harness/api/sas-harness-api.json"
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == routing["schema_path"]
    assert schema["additionalProperties"] is False


def test_every_skill_has_one_deterministic_route() -> None:
    routing = load(ROUTING)
    skill_ids = {item["id"] for item in load(CAPABILITIES)["skills"]}
    routed = [item["target"] for item in routing["triggers"] if item["target_type"] == "skill"]
    assert set(routed) == skill_ids, f"skill routing drift: {sorted(set(routed) ^ skill_ids)}"
    assert len(routed) == len(set(routed)), f"skills have duplicate routes: {routed}"
    for trigger in routing["triggers"]:
        signals = trigger["deterministic_task_signals"]
        assert signals and len(signals) == len(set(signals))
        assert trigger["required_inputs"] and trigger["outputs"] and trigger["preconditions"]
        assert trigger["guardrails"] and trigger["validators"] and trigger["proof_ceiling"]
        for validator in trigger["validators"]:
            assert (ROOT / validator).is_file(), f"missing trigger validator: {validator}"


def test_primary_signals_are_unambiguous_and_safety_is_additive() -> None:
    routing = load(ROUTING)
    seen: dict[str, str] = {}
    for trigger in routing["triggers"]:
        for signal in trigger["deterministic_task_signals"]:
            normalized = " ".join(signal.lower().split())
            assert normalized not in seen, f"duplicate deterministic signal {signal!r}: {seen.get(normalized)} and {trigger['id']}"
            seen[normalized] = trigger["id"]
    live_guard = next(item for item in routing["triggers"] if item["target"] == "live-data-guard")
    assert live_guard["composition_mode"] == "additive" and live_guard["priority"] > 1
    assert routing["ambiguity_rules"] == {
        "explicit_user_lane_wins": True,
        "safety_guard_triggers_compose_additively": True,
        "equal_priority_conflict_resolution": "fail_closed_to_repository_sprint",
        "unknown_signal_fallback": "repository-sprint",
        "no_trigger_authorizes_mutation": True,
    }


def test_harness_operation_targets_exist_and_do_not_mutate() -> None:
    routing = load(ROUTING)
    operations = {item["id"]: item for item in load(HARNESS_API)["operations"]}
    operation_triggers = [item for item in routing["triggers"] if item["target_type"] == "harness_operation"]
    assert operation_triggers
    for trigger in operation_triggers:
        operation = operations[trigger["target"]]
        assert operation["network_activity"] is False
        assert operation["target_mutation"] is False
    assert "agent_sprint_capsule.generate" in operations
    assert "agent_routing.catalog.read" in operations


def test_package_and_handoff_routes_are_current() -> None:
    by_target = {item["target"]: item for item in load(ROUTING)["triggers"]}
    operations = {item["id"]: item for item in load(HARNESS_API)["operations"]}
    assert "package-static-analysis" in by_target
    assert "package semantic analysis" in [s.lower() for s in by_target["package-static-analysis"]["deterministic_task_signals"]]
    assert "package functionality analysis" in [s.lower() for s in by_target["package-static-analysis"]["deterministic_task_signals"]]
    assert "package_analysis.trust" in by_target
    assert "package trust policy" in [s.lower() for s in by_target["package_analysis.trust"]["deterministic_task_signals"]]
    assert set(by_target["package_analysis.trust"]["required_inputs"]) == set(operations["package_analysis.trust"]["inputs"])
    assert "package_analysis.vm_qualification_profile_validate" in by_target
    assert "package qualification profile" in [
        s.lower() for s in by_target["package_analysis.vm_qualification_profile_validate"]["deterministic_task_signals"]
    ]
    assert set(by_target["package_analysis.vm_qualification_profile_validate"]["required_inputs"]) == set(
        operations["package_analysis.vm_qualification_profile_validate"]["inputs"]
    )
    for operation_id in (
        "package_analysis.static",
        "package_analysis.semantic_enrich",
        "package_analysis.trust",
        "package_analysis.vm_qualification_profile_validate",
    ):
        assert operation_id in operations
        assert operations[operation_id]["network_activity"] is False
        assert operations[operation_id]["target_mutation"] is False
    assert (ROOT / "harness/workflows/package-analysis.yaml").is_file()
    capsule = by_target["agent_sprint_capsule.generate"]
    assert "final handoff compression" in [s.lower() for s in capsule["deterministic_task_signals"]]
    operation = operations["agent_sprint_capsule.generate"]
    assert set(capsule["required_inputs"]) == set(operation["inputs"])
    assert capsule["proof_ceiling"] == "schema, fixture, run-context, artifact-registration, and local handoff proof"


def test_workflow_and_discoverability_are_wired() -> None:
    workflow_text = read(WORKFLOW_SPEC)
    for marker in ("name:", "mode: local_transform", "network_activity: false", "target_mutation: false", "input_mapping:", "next_command: NextCommand", "phases:", "artifacts:", "validation:", "next_actions:"):
        assert marker in workflow_text
    assert "harness/api/agent-capability-manifest.json" in read(CODEBASE_MAP)
    for doc in (AGENTS, AI_ENTRYPOINT):
        text = read(doc)
        assert "harness/api/agent-routing-manifest.json" in text
        assert "tools/New-SasSprintCapsule.ps1" in text
    assert "python3 Tests/survey/test_agent_routing_manifest_contracts.py" in read(RUNNER)
    assert "python3 Tests/survey/test_agent_routing_manifest_contracts.py" in read(WORKFLOW)


def test_schema_validation_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load(ROUTING), load(SCHEMA))


def main() -> None:
    tests = [test_schema_and_authority_paths, test_every_skill_has_one_deterministic_route, test_primary_signals_are_unambiguous_and_safety_is_additive, test_harness_operation_targets_exist_and_do_not_mutate, test_package_and_handoff_routes_are_current, test_workflow_and_discoverability_are_wired, test_schema_validation_when_available]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} agent routing manifest contracts")


if __name__ == "__main__":
    main()
