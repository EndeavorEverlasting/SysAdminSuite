#!/usr/bin/env python3
"""Contracts for deterministic AutoLogon routing without prompt-owned application logic."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / ".claude/skills/autologon-deployment/SKILL.md"
CAPABILITY_MANIFEST = ROOT / "harness/api/agent-capability-manifest.json"
ROUTING_MANIFEST = ROOT / "harness/api/agent-routing-manifest.json"
DEPLOYMENT_STATE = ROOT / "harness/api/deployment-state-registry.json"
COMMAND_REGISTRY = ROOT / "harness/api/harness-command-registry.json"
ARTIFACT_REGISTRY = ROOT / "harness/api/harness-artifact-registry.json"
WORKFLOW = ROOT / "harness/workflows/autologon-proof-contract-floor.yaml"
FIELD_CAPABILITY = ROOT / ".claude/capabilities/autologon-deployment-orchestration.md"
RUNTIME_CAPABILITY = ROOT / ".claude/capabilities/autologon-runtime-proof.md"

PLAN_SIGNALS = {"plan AutoLogon", "AutoLogon deployment plan"}
FIELD_SIGNALS = {"deploy AutoLogon", "AutoLogon as admin", "AutoLogon pilot"}
RUNTIME_SIGNALS = {"prove AutoLogon after reboot", "AutoLogon session access", "technician runtime proof"}
CAPABILITY_IDS = {"autologon-deployment-orchestration", "autologon-runtime-proof"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read(path: Path) -> str:
    require(path.is_file(), f"missing {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def by_id(items: list[dict]) -> dict[str, dict]:
    return {item["id"]: item for item in items}


def normalized(value: str) -> str:
    return " ".join(value.lower().split())


def exact_targets(request: str) -> set[str]:
    request_signal = normalized(request)
    return {
        item["target"]
        for item in load(ROUTING_MANIFEST)["triggers"]
        if request_signal in {normalized(signal) for signal in item["deterministic_task_signals"]}
    }


def test_activation_signals_and_manifest_contracts() -> None:
    routing = by_id(load(ROUTING_MANIFEST)["triggers"])
    plan = routing["autologon-plan-trigger"]
    field = routing["autologon-admin-deployment-trigger"]
    runtime = routing["autologon-runtime-proof-trigger"]
    require(set(plan["deterministic_task_signals"]) == PLAN_SIGNALS, "AutoLogon plan signals drifted")
    require(set(field["deterministic_task_signals"]) == FIELD_SIGNALS, "AutoLogon field signals drifted")
    require(set(runtime["deterministic_task_signals"]) == RUNTIME_SIGNALS, "AutoLogon runtime signals drifted")
    require((plan["target_type"], plan["target"]) == ("skill", "autologon-deployment"), "plan route drifted")
    require((field["target_type"], field["target"]) == ("capability", "autologon-deployment-orchestration"), "field route drifted")
    require((runtime["target_type"], runtime["target"]) == ("capability", "autologon-runtime-proof"), "runtime route drifted")
    for trigger in (plan, field, runtime):
        require(bool(trigger["required_inputs"]), f"{trigger['id']} missing required inputs")
        require(bool(trigger["outputs"]), f"{trigger['id']} missing outputs")
        require(bool(trigger["preconditions"]), f"{trigger['id']} missing preconditions")
        require(bool(trigger["guardrails"]), f"{trigger['id']} missing guardrails")
        require(bool(trigger["validators"]), f"{trigger['id']} missing validators")
        require(bool(trigger["owner"]), f"{trigger['id']} missing owner")
        require(bool(trigger["proof_ceiling"]), f"{trigger['id']} missing proof ceiling")
    require(field["priority"] == runtime["priority"] > plan["priority"], "AutoLogon route priorities drifted")


def test_exact_routes_separate_field_and_runtime_authority() -> None:
    for signal in PLAN_SIGNALS:
        require(exact_targets(signal) == {"autologon-deployment"}, f"wrong plan route for {signal}")
    for signal in FIELD_SIGNALS:
        require(exact_targets(signal) == {"autologon-deployment-orchestration"}, f"wrong field route for {signal}")
    for signal in RUNTIME_SIGNALS:
        require(exact_targets(signal) == {"autologon-runtime-proof"}, f"wrong runtime route for {signal}")
    require(exact_targets("technician runtime proof") != {"autologon-deployment-orchestration"}, "runtime routed to deployment")
    require(exact_targets("deploy AutoLogon") != {"autologon-runtime-proof"}, "deployment routed to runtime")


def test_collision_ambiguity_and_negative_routing_fail_closed() -> None:
    routing = load(ROUTING_MANIFEST)
    triggers = by_id(routing["triggers"])
    field = triggers["autologon-admin-deployment-trigger"]
    runtime = triggers["autologon-runtime-proof-trigger"]
    ambiguous = "deploy AutoLogon and prove AutoLogon after reboot"
    matching = [
        item for item in (field, runtime)
        if any(normalized(signal) in normalized(ambiguous) for signal in item["deterministic_task_signals"])
    ]
    require({item["target"] for item in matching} == CAPABILITY_IDS, "mixed deployment/runtime request did not collide")
    require(len({item["priority"] for item in matching}) == 1, "mixed request priorities no longer fail closed")
    require(routing["ambiguity_rules"]["equal_priority_conflict_resolution"] == "fail_closed_to_repository_sprint", "ambiguity policy drifted")
    for negative in (
        "install an ordinary package in the disposable VM",
        "collect an AutoLogon password",
        "run AutoLogon through WinRM",
        "prove package acceptance",
    ):
        require(not (exact_targets(negative) & {"autologon-deployment", *CAPABILITY_IDS}), f"unsafe route matched: {negative}")
    package_vm = triggers["package-vm-qualification-trigger"]
    require("AutoLogon excluded" in package_vm["guardrails"], "package VM no longer excludes AutoLogon")
    require(all("autologon" not in normalized(signal) for signal in package_vm["deterministic_task_signals"]), "package VM gained AutoLogon signal")


def test_skill_consumes_current_field_authorities_without_reimplementation() -> None:
    skill = read(SKILL)
    for path in (
        "harness/api/deployment-state-registry.json",
        "harness/api/harness-command-registry.json",
        "harness/api/harness-artifact-registry.json",
        "harness/workflows/cybernet-autologon-deployment-state.yaml",
        "Deploy-CybernetSoftware.cmd",
        "scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1",
        "Qualify-AutoLogonSystemPackage.cmd",
        "scripts/Invoke-SasAutoLogonSessionAccessProof.ps1",
        "scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1",
    ):
        require(path in skill, f"skill missing current authority {path}")
    for required in (
        "sas cybernet Deploy HOST",
        "sas autologon Remote HOST",
        "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING",
        "canonical_system_install_enabled=false",
        "restart-complete deployment artifact",
        "runtime proof a prerequisite that delays product deployment",
    ):
        require(required in skill, f"skill missing field contract marker: {required}")
    require("Do not route ordinary field deployment through `scripts/Invoke-SasAutoLogonDeployment.ps1`" in skill, "skill still permits blocked LocalSystem route")
    for implementation_detail in ("New-ScheduledTaskAction", "Register-ScheduledTask", "DefaultPassword =", "Start-Process"):
        require(implementation_detail not in skill, f"skill reimplements product behavior: {implementation_detail}")


def test_field_capability_matches_restart_complete_product_state() -> None:
    deployment_state = load(DEPLOYMENT_STATE)
    context = by_id(deployment_state["contexts"])["cybernet-autologon"]
    truth = context["current_product_truth"]
    commands = by_id(load(COMMAND_REGISTRY)["commands"])
    artifacts = by_id(load(ARTIFACT_REGISTRY)["artifacts"])
    capability = read(FIELD_CAPABILITY)

    require(truth["canonical_system_install_enabled"] is False, "SYSTEM block unexpectedly removed")
    require(truth["current_live_apply_lane"] == "kerberos_s4u_named_admin_then_restart", "field lane drifted")
    require(commands["autologon-remote"]["command"] == "sas autologon Remote HOST", "AutoLogon command drifted")
    require(commands["cybernet-software-deploy"]["command"] == "sas cybernet Deploy HOST", "Cybernet command drifted")
    require(artifacts["autologon-s4u-deployment-result"]["path"].endswith("autologon_s4u_deployment_result.json"), "AutoLogon artifact drifted")
    require(artifacts["cybernet-software-deployment-result"]["path"].endswith("cybernet_software_deployment_result.json"), "Cybernet artifact drifted")

    for marker in (
        "sas autologon Remote HOST",
        "sas cybernet Deploy HOST",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED",
        "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING",
        "current field AutoLogon lane is Kerberos/S4U named-admin execution followed by the required restart",
        "Do not route ordinary field deployment through `scripts/Invoke-SasAutoLogonDeployment.ps1`",
    ):
        require(marker in capability, f"deployment capability missing marker: {marker}")
    require("Runtime proof is optional higher-ceiling evidence after deployment" in capability, "runtime proof became a deployment prerequisite")


def test_runtime_capability_requires_correlated_restart_complete_evidence() -> None:
    runtime = read(RUNTIME_CAPABILITY)
    for marker in (
        "correlated restart-complete deployment artifact for the same target",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED",
        "TECHNICIAN_OBSERVED_LIVE_RUNTIME",
        "runtime_proof=true",
        "overall_success=true",
        "remote SMB offline/online restart observation is not a substitute",
        "Fixture results remain contract-only",
    ):
        require(marker in runtime, f"runtime capability missing marker: {marker}")
    require("does not initiate either action" not in runtime, "stale separate-reboot capability wording remains")


def test_capabilities_are_atomic_registered_and_owned() -> None:
    manifest = load(CAPABILITY_MANIFEST)
    capabilities = by_id(manifest["capabilities"])
    skills = by_id(manifest["skills"])
    require(CAPABILITY_IDS <= set(capabilities), "AutoLogon capabilities not registered")
    skill = skills["autologon-deployment"]
    require(CAPABILITY_IDS <= set(skill["capability_ids"]), "AutoLogon skill capability set drifted")
    linked = {
        Path(name).stem
        for name in re.findall(r"\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)", read(SKILL))
    }
    require(linked == set(skill["capability_ids"]), "skill links and manifest capability set disagree")
    for cap_id, path in (
        ("autologon-deployment-orchestration", FIELD_CAPABILITY),
        ("autologon-runtime-proof", RUNTIME_CAPABILITY),
    ):
        text = read(path)
        require(capabilities[cap_id]["default_network_activity"] is False, f"{cap_id} gained default network authority")
        require(capabilities[cap_id]["default_target_mutation"] is False, f"{cap_id} gained default mutation authority")
        require("## Contract" in text and "## Used by" in text, f"{cap_id} capability structure drifted")
        require(".claude/skills/autologon-deployment/SKILL.md" in text, f"{cap_id} lost owner skill")


def test_frozen_operations_remain_historical_not_field_completion_authority() -> None:
    workflow = read(WORKFLOW)
    for operation in (
        "autologon.plan", "autologon.admin_deploy", "autologon.state_proof",
        "autologon.session_access_proof", "autologon.technician_runtime_proof",
        "autologon.proof_receipt_ingest",
    ):
        require(f"id: {operation}" in workflow, f"frozen operation removed: {operation}")
    field = read(FIELD_CAPABILITY)
    runtime = read(RUNTIME_CAPABILITY)
    require("restart-complete" in field, "field capability lost restart completion")
    require("actual signed-in AutoLogon session" in runtime, "runtime capability lost actual-session requirement")
    require("Fixture results remain contract-only" in runtime, "runtime fixture boundary drifted")


def test_discovery_and_validation_wiring() -> None:
    require(".claude/skills/autologon-deployment/SKILL.md" in read(ROOT / "AGENTS.md"), "AGENTS routing missing AutoLogon skill")
    require(".claude/skills/autologon-deployment/SKILL.md" in read(ROOT / "CLAUDE.md"), "CLAUDE routing missing AutoLogon skill")
    require("test_autologon_agent_harness_contracts.py" in read(ROOT / "CODEBASE_MAP.md"), "codebase map missing contract")
    require("python3 Tests/survey/test_autologon_agent_harness_contracts.py" in read(ROOT / "tests/survey/run_offline_survey_tests.sh"), "offline floor missing contract")
    require("test_autologon_agent_harness_contracts.py" in read(ROOT / ".github/workflows/agent-instruction-contracts.yml"), "agent CI missing contract")


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon agent-harness contract groups")
