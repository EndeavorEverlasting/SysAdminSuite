#!/usr/bin/env python3
"""Validate desired deployment-state contracts against current product truths."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/deployment-state-registry.json"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
OUTCOMES = ROOT / "harness/api/harness-outcome-registry.json"
APPROVED = ROOT / "configs/software-packages/approved-apps.json"
SETS = ROOT / "configs/software-packages/windows-native-package-sets.json"
WORKFLOW = ROOT / "harness/workflows/cybernet-autologon-deployment-state.yaml"
SKILL = ROOT / "harness/skills/cybernet-autologon-deployment-state/SKILL.md"
S4U = ROOT / "scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1"
S4U_DEPLOY = ROOT / "scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1"
FULL_DEPLOY = ROOT / "scripts/Invoke-SasCybernetSoftwareDeployment.ps1"
RUNTIME = ROOT / "scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1"


def load(path: Path) -> dict:
    assert path.is_file(), f"missing deployment-state authority: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read(path: Path) -> str:
    assert path.is_file(), f"missing deployment-state component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def one(items: list[dict], key: str, value: str) -> dict:
    matches = [item for item in items if str(item.get(key, "")) == value]
    assert len(matches) == 1, f"expected exactly one {key}={value}, found {len(matches)}"
    return matches[0]


def main() -> int:
    registry = load(REGISTRY)
    commands = load(COMMANDS)["commands"]
    artifacts = load(ARTIFACTS)["artifacts"]
    outcomes = load(OUTCOMES)["contracts"]
    approved = load(APPROVED)
    package_sets = load(SETS)

    assert registry["schema_version"] == "sas-deployment-state-registry/v1"
    policy = registry["policy"]
    for key in (
        "resolve_desired_state_before_commands",
        "tests_are_admission_not_target_state",
        "transport_live_cert_is_admission_only",
        "fixture_proof_is_admission_only",
        "do_not_reinstall_verified_core_apps",
        "runtime_only_does_not_imply_deployment_authority",
        "deploy_plus_runtime_requires_apply_first",
        "test_autologon_with_authorized_target_means_apply_pilot",
        "live_cert_with_autologon_or_cybernet_apply_intent_means_deployment_chain",
        "autologon_deployment_requires_restart",
        "runtime_proof_is_not_required_for_deployment_completion",
    ):
        assert policy[key] is True, f"deployment-state policy disabled: {key}"

    context = one(registry["contexts"], "id", "cybernet-autologon")
    truth = context["current_product_truth"]
    auto = one(approved["packages"], "id", "autologon")
    assert auto["install_enabled"] is True
    assert auto["canonical_system_install_enabled"] is False
    assert auto["canonical_system_qualification"]["status"] == "failed_runtime_validation"
    assert "AutoAdminLogon=1" in auto["canonical_system_qualification"]["blocked_reason"]
    assert truth["current_full_software_apply_command_id"] == "cybernet-software-deploy"
    assert truth["current_full_software_positive_status"] == "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED"
    assert truth["current_live_apply_command_id"] == "autologon-remote"
    assert truth["current_live_apply_positive_classification"] == "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED"
    assert truth["internal_pre_reboot_apply_classification"] == "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING"
    assert truth["autologon_must_be_last"] is True
    assert truth["autologon_restart_required"] is True

    sets = {item["id"]: item for item in package_sets["package_sets"]}
    core_ids = sets["cybernet-clinical-core"]["package_ids"]
    full_ids = sets["cybernet-clinical-workstation"]["package_ids"]
    assert core_ids == [
        "allscripts-eehr-shortcut-uai-2-2",
        "epic-downtime-guide-shortcut-1-0",
        "nuance-dragon-medical-one-2025",
        "hyland-fos-epic-integration-23-1-33-1000",
        "bca",
    ]
    assert full_ids[:-1] == core_ids
    assert full_ids[-1] == "autologon"
    assert sets["cybernet-autologon-only"]["package_ids"] == ["autologon"]

    command_ids = {item["id"] for item in commands}
    artifact_ids = {item["id"] for item in artifacts}
    outcome_by_command = {item["command_id"]: item for item in outcomes}
    for command_id in ("cybernet-software-deploy", "autologon-remote", "autologon-runtime-proof"):
        assert command_id in command_ids
    for artifact_id in ("cybernet-software-deployment-result", "autologon-s4u-deployment-result", "autologon-s4u-pilot-result", "autologon-technician-runtime-proof"):
        assert artifact_id in artifact_ids
    assert outcome_by_command["cybernet-software-deploy"]["success_artifact_id"] == "cybernet-software-deployment-result"
    assert outcome_by_command["autologon-remote"]["success_artifact_id"] == "autologon-s4u-deployment-result"

    intents = {item["id"]: item for item in context["intent_resolution"]}
    for intent_id in ("test-autologon", "live-cert-autologon", "deploy-autologon", "deploy-software", "deploy-and-runtime-proof", "runtime-proof-only", "complete-cybernet-profile"):
        assert intent_id in intents, f"missing deployment intent: {intent_id}"
    assert intents["test-autologon"]["goal_state"] == "autologon_restart_completed"
    assert intents["live-cert-autologon"]["goal_state"] == "autologon_restart_completed"
    assert intents["deploy-autologon"]["goal_state"] == "autologon_restart_completed"
    assert intents["deploy-software"]["goal_state"] == "cybernet_software_deployed"
    assert intents["runtime-proof-only"]["requires_prior_state"] == "autologon_restart_completed"

    states = {item["id"]: item for item in context["states"]}
    pre = states["autologon_pre_reboot_configured"]
    restart = states["autologon_restart_completed"]
    software = states["cybernet_software_deployed"]
    runtime = states["autologon_runtime_proven"]
    assert pre["terminal"] is False
    assert pre["positive_classification"] == "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING"
    assert restart["terminal"] is True
    assert restart["positive_classification"] == "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED"
    assert restart["artifact_id"] == "autologon-s4u-deployment-result"
    assert software["positive_classification"] == "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED"
    assert software["ordering"] == ["clinical_core_ready", "autologon_pre_reboot_configured", "autologon_restart_completed"]
    assert runtime["requires_state"] == "autologon_restart_completed"

    s4u = read(S4U)
    assert "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING" in s4u
    assert "Start-Process -FilePath ([string]$config.installer_path)" in s4u

    deploy = read(S4U_DEPLOY)
    for marker in (
        "Invoke-SasAutoLogonKerberosS4UPilot.ps1",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "shutdown.exe /r /t",
        "restart_offline_observed",
        "restart_online_observed",
        "runtime_proof_required_for_deployment_completion = $false",
    ):
        assert marker in deploy, f"restart-complete AutoLogon deployment drifted: {marker}"

    full = read(FULL_DEPLOY)
    for marker in (
        "Invoke-SasCybernetClinicalCoreDeployment.ps1",
        "Invoke-SasAutoLogonS4URestartDeployment.ps1",
        "AutoLogon must be the final software step",
        "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED",
    ):
        assert marker in full, f"full Cybernet deployment drifted: {marker}"

    runtime_script = read(RUNTIME)
    for marker in ("runtime-proof-summary.json", "TECHNICIAN_OBSERVED_LIVE_RUNTIME", "runtime_proof", "overall_success"):
        assert marker in runtime_script

    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: cybernet-autologon-deployment-state",
        "test AutoLogon as a real one-target apply pilot",
        "transport live certification remains admission only",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED",
        "runtime proof does not delay deployment completion",
    ):
        assert marker in workflow, f"deployment-state workflow missing: {marker}"

    skill = read(SKILL)
    for marker in (
        "## Trigger", "## Critical artifacts", "## Forbidden stopping patterns",
        "sas autologon Remote HOST", "sas cybernet Deploy HOST",
        "AutoLogon is last", "restart", "runtime proof", "hours of live searching",
    ):
        assert marker in skill, f"deployment-state skill missing: {marker}"

    forbidden = "\n".join(context["forbidden_substitutions"])
    for marker in ("deployment_planned", "FIXTURE_PASS", "KERBEROS_S4U_FIXTURE_READY", "LIVE CERT PASS", "REBOOT_PROOF_PENDING", "runtime proof as a prerequisite", "six-package LocalSystem"):
        assert marker in forbidden, f"missing forbidden deployment substitute: {marker}"

    print("PASS: deployment-state harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
