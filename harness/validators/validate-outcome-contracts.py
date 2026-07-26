#!/usr/bin/env python3
"""Dependency-free validator for outcome-driven harness execution contracts."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
OUTCOMES = ROOT / "harness/api/harness-outcome-registry.json"
DEPLOYMENT_STATES = ROOT / "harness/api/deployment-state-registry.json"
WORKFLOW = ROOT / "harness/workflows/outcome-driven-execution.yaml"
SKILL = ROOT / "harness/skills/outcome-driven-execution/SKILL.md"


def load(path: Path) -> dict:
    assert path.is_file(), f"missing outcome harness authority: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read(path: Path) -> str:
    assert path.is_file(), f"missing outcome harness component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def main() -> int:
    commands = load(COMMANDS)["commands"]
    artifacts = load(ARTIFACTS)["artifacts"]
    outcomes = load(OUTCOMES)
    deployment_states = load(DEPLOYMENT_STATES)

    assert outcomes["schema_version"] == "sas-harness-outcome-registry/v1"
    policy = outcomes["policy"]
    assert policy["requested_goal_required"] is True
    assert policy["validation_is_admission_not_completion"] is True
    assert policy["dry_run_must_emit_artifact"] is True
    assert "runtime_proven" in policy["allowed_terminal_outcomes"]
    for forbidden in (
        "tests_passed_only", "status_reported_only", "command_printed_only",
        "wait_for_next_chat", "operator_repeats_agent_work",
    ):
        assert forbidden in policy["forbidden_terminal_outcomes"], f"missing forbidden terminal outcome: {forbidden}"

    command_by_id = {item["id"]: item for item in commands}
    artifact_ids = {item["id"] for item in artifacts}
    contracts = outcomes["contracts"]
    contract_by_command = {item["command_id"]: item for item in contracts}
    assert len(contract_by_command) == len(contracts), "duplicate outcome contract command_id"
    assert set(contract_by_command) == set(command_by_id), "every canonical command must have exactly one outcome contract"

    admission_kinds = {"validate", "test", "build", "deploy-plan"}
    for command_id, command in command_by_id.items():
        contract = contract_by_command[command_id]
        artifact_id = contract["success_artifact_id"]
        if command["kind"] in admission_kinds:
            assert artifact_id, f"admission command must emit a registered artifact: {command_id}"
        if artifact_id is not None:
            assert artifact_id in artifact_ids, f"unknown success artifact for {command_id}: {artifact_id}"
        if command["kind"] == "deploy-plan":
            deploy_continuations = [c for c in contract["continuations"] if c["when_goal"] == "deploy"]
            assert deploy_continuations, f"deploy-plan lacks deploy continuation: {command_id}"
            assert all(c["same_turn"] is True for c in deploy_continuations)
        for continuation in contract["continuations"]:
            next_id = continuation["command_id"]
            assert next_id in command_by_id, f"unknown continuation command: {command_id} -> {next_id}"
            assert next_id != command_id, f"self-loop continuation is forbidden: {command_id}"
            assert continuation["same_turn"] is True, f"continuation must be same-turn: {command_id} -> {next_id}"
        assert contract["failure_outcome"] == "blocked_with_actionable_gate"

    # Keep the historical full-profile contract internally stable while proving the new
    # field-safe clinical-core chain independently. Deployment-state routing selects the
    # clinical-core command while canonical SYSTEM AutoLogon remains blocked.
    assert contract_by_command["cybernet-plan"]["continuations"][0]["command_id"] == "cybernet-apply"
    assert contract_by_command["cybernet-core-plan"]["continuations"][0]["command_id"] == "cybernet-core-deploy"
    assert contract_by_command["cybernet-core-deploy"]["success_outcome"] == "product_deployed"
    assert contract_by_command["cybernet-core-deploy"]["success_artifact_id"] == "cybernet-clinical-core-deployment-summary"
    assert contract_by_command["deployment-state-validate"]["success_outcome"] == "artifact_created"
    assert contract_by_command["deployment-state-validate"]["success_artifact_id"] == "deployment-state-validation-result"
    assert contract_by_command["autologon-remote"]["success_outcome"] == "product_deployed"
    assert contract_by_command["autologon-remote"]["success_artifact_id"] == "autologon-s4u-pilot-result"
    assert contract_by_command["autologon-runtime-proof"]["success_outcome"] == "runtime_proven"
    assert contract_by_command["autologon-runtime-proof"]["success_artifact_id"] == "autologon-technician-runtime-proof"

    context = next(item for item in deployment_states["contexts"] if item["id"] == "cybernet-autologon")
    assert deployment_states["policy"]["tests_are_admission_not_target_state"] is True
    assert deployment_states["policy"]["test_autologon_with_authorized_target_means_apply_pilot"] is True
    assert deployment_states["policy"]["deploy_plus_runtime_requires_apply_first"] is True
    assert context["current_product_truth"]["current_clinical_core_apply_command_id"] == "cybernet-core-deploy"
    clinical_core = next(item for item in context["states"] if item["id"] == "clinical_core_ready")
    assert clinical_core["command_id"] == "cybernet-core-deploy"
    assert clinical_core["artifact_id"] == "cybernet-clinical-core-deployment-summary"
    assert clinical_core["positive_classification"] == "CLINICAL_CORE_DEPLOYMENT_COMPLETED"

    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: outcome-driven-execution",
        "validators and dry runs as admission gates, not as the requested deliverable",
        "follow the registered continuation in the same agent turn",
        "do not ask the operator to rerun a command the agent can safely execute itself",
        "harness/api/deployment-state-registry.json", "runtime_proven", "blocked_with_actionable_gate",
    ):
        assert marker in workflow, f"outcome workflow missing marker: {marker}"

    skill = read(SKILL)
    for marker in (
        "## Trigger", "## Required inputs", "## Procedure", "## Forbidden stopping patterns",
        "## Expected outputs", "harness/api/harness-outcome-registry.json",
        "harness/api/deployment-state-registry.json",
        "Do not hand a safe executable continuation back to the operator", "test AutoLogon",
    ):
        assert marker in skill, f"outcome skill missing marker: {marker}"

    print("PASS: outcome-driven harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
