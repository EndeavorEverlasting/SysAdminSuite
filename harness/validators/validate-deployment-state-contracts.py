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
    ):
        assert policy[key] is True, f"deployment-state policy disabled: {key}"

    context = one(registry["contexts"], "id", "cybernet-autologon")
    truth = context["current_product_truth"]
    assert context["target_profile"] == "cybernet"
    assert context["target_count"] == 1

    auto = one(approved["packages"], "id", "autologon")
    assert auto["install_enabled"] is True
    assert auto["canonical_system_install_enabled"] is False
    assert auto["canonical_system_qualification"]["status"] == "failed_runtime_validation"
    assert "AutoAdminLogon=1" in auto["canonical_system_qualification"]["blocked_reason"]
    assert truth["autologon_install_enabled"] is True
    assert truth["canonical_system_install_enabled"] is False
    assert truth["canonical_system_qualification_status"] == "failed_runtime_validation"
    assert truth["current_live_apply_command_id"] == "autologon-remote"
    assert truth["current_live_apply_positive_classification"] == "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING"
    assert truth["full_profile_local_system_autologon_must_not_be_used_as_a_substitute"] is True

    sets = {item["id"]: item for item in package_sets["package_sets"]}
    assert sets["cybernet-clinical-core"]["package_ids"] == [
        "allscripts-eehr-shortcut-uai-2-2",
        "epic-downtime-guide-shortcut-1-0",
        "nuance-dragon-medical-one-2025",
        "hyland-fos-epic-integration-23-1-33-1000",
        "bca",
    ]
    assert sets["cybernet-autologon-only"]["package_ids"] == ["autologon"]
    assert sets["cybernet-clinical-workstation"]["package_ids"][-1] == "autologon"
    assert context["package_sets"]["clinical_core"] == "cybernet-clinical-core"
    assert context["package_sets"]["autologon_only"] == "cybernet-autologon-only"

    command_ids = {item["id"] for item in commands}
    artifact_ids = {item["id"] for item in artifacts}
    outcome_by_command = {item["command_id"]: item for item in outcomes}
    assert "autologon-remote" in command_ids
    assert "autologon-runtime-proof" in command_ids
    assert "autologon-s4u-pilot-result" in artifact_ids
    assert "autologon-technician-runtime-proof" in artifact_ids
    assert outcome_by_command["autologon-remote"]["success_artifact_id"] == "autologon-s4u-pilot-result"
    assert outcome_by_command["autologon-runtime-proof"]["success_artifact_id"] == "autologon-technician-runtime-proof"

    intents = {item["id"]: item for item in context["intent_resolution"]}
    for intent_id in ("test-autologon", "live-cert-autologon", "deploy-autologon", "deploy-and-runtime-proof", "runtime-proof-only", "complete-cybernet-profile"):
        assert intent_id in intents, f"missing deployment intent: {intent_id}"
    assert intents["test-autologon"]["requires_apply"] is True
    assert intents["live-cert-autologon"]["requires_apply"] is True
    assert intents["deploy-and-runtime-proof"]["goal_state"] == "autologon_runtime_proven"
    assert intents["runtime-proof-only"]["requires_apply"] is False
    assert intents["runtime-proof-only"]["requires_prior_state"] == "autologon_pre_reboot_configured"

    states = {item["id"]: item for item in context["states"]}
    pre = states["autologon_pre_reboot_configured"]
    runtime = states["autologon_runtime_proven"]
    cybernet = states["cybernet_profile_autologon_runtime_proven"]
    assert pre["command_id"] == "autologon-remote"
    assert pre["artifact_id"] == "autologon-s4u-pilot-result"
    assert pre["positive_classification"] == "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING"
    assert runtime["requires_state"] == "autologon_pre_reboot_configured"
    assert runtime["requires_separate_attended_reboot"] is True
    assert runtime["requires_direct_automatic_sign_in_observation"] is True
    assert runtime["command_id"] == "autologon-runtime-proof"
    assert runtime["artifact_id"] == "autologon-technician-runtime-proof"
    assert runtime["positive_classification"] == "TECHNICIAN_OBSERVED_LIVE_RUNTIME"
    assert cybernet["ordering"] == ["clinical_core_ready", "autologon_pre_reboot_configured", "autologon_runtime_proven"]

    forbidden = "\n".join(context["forbidden_substitutions"])
    for marker in ("deployment_planned", "FIXTURE_PASS", "KERBEROS_S4U_FIXTURE_READY", "LIVE CERT PASS", "exit code 0", "six-package LocalSystem"):
        assert marker in forbidden, f"missing forbidden deployment substitute: {marker}"

    s4u = read(S4U)
    for marker in (
        "Configure AutoLogon remotely through Kerberos SMB and a passwordless S4U scheduled task.",
        "Start-Process -FilePath ([string]$config.installer_path)",
        "autologon_kerberos_s4u_pilot_result.json",
        "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING",
    ):
        assert marker in s4u, f"S4U product truth drifted: {marker}"

    runtime_script = read(RUNTIME)
    for marker in ("runtime-proof-summary.json", "TECHNICIAN_OBSERVED_LIVE_RUNTIME", "runtime_proof", "overall_success"):
        assert marker in runtime_script, f"runtime proof truth drifted: {marker}"

    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: cybernet-autologon-deployment-state",
        "test AutoLogon as a real one-target apply pilot",
        "transport live certification remains admission only",
        "use command id autologon-remote",
        "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING",
        "run command id autologon-runtime-proof",
        "do not run the six-package LocalSystem Cybernet set as a substitute",
    ):
        assert marker in workflow, f"deployment-state workflow missing: {marker}"

    skill = read(SKILL)
    for marker in (
        "## Trigger",
        "## Critical artifacts",
        "## Forbidden stopping patterns",
        "sas autologon Remote HOST",
        "do not reinstall them merely to reach AutoLogon",
        "TECHNICIAN_OBSERVED_LIVE_RUNTIME",
        "hours of live searching",
    ):
        assert marker in skill, f"deployment-state skill missing: {marker}"

    print("PASS: deployment-state harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
