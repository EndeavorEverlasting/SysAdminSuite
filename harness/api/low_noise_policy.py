"""Local-only low-noise policy API shared by CLI, tests, and future MCP adapters."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY_PATH = ROOT / "Config" / "low-noise-policy.json"


def load_policy(path: Path = DEFAULT_POLICY_PATH) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    required = {
        "schema_version", "policy_version", "population_source_policy",
        "freshness_policy", "retry_policy", "live_probe_budget_policy", "rate_policy",
        "edge_target_policy", "output_policy", "evidence_policy", "guidance", "profiles",
    }
    missing = required - data.keys()
    assert not missing, f"missing fields: {sorted(missing)}"
    assert data["schema_version"] == "sas-low-noise-policy/v1"
    assert 0 <= data["retry_policy"]["default_retries"] <= data["retry_policy"]["max_retries"]
    assert data["live_probe_budget_policy"]["check_existing_evidence_before_probe"] is True
    assert data["live_probe_budget_policy"]["complete_match_required_for_reuse"] is True
    assert data["live_probe_budget_policy"]["partial_or_ambiguous_match_is_insufficient"] is True
    assert data["live_probe_budget_policy"]["prefer_existing_live_probe_evidence"] is True
    assert data["live_probe_budget_policy"]["max_live_probes_per_target_scope"] == 5
    assert data["live_probe_budget_policy"]["override_requires_recorded_lead_or_operator_reason"] is True
    assert 0 < data["rate_policy"]["default_rate_cap"] <= data["rate_policy"]["max_rate_cap"]
    assert data["output_policy"]["survey_local_only"] is True
    assert data["evidence_policy"]["target_mutation"] == "never"
    required_guidance = {
        "low_noise_principle",
        "network_visibility_note",
        "probe_again_guidance",
        "fresh_evidence_guidance",
        "probe_evidence_role_guidance",
        "evidence_reuse_guardrail",
        "complete_match_guidance",
        "live_probe_budget_guidance",
        "mystery_serial_guidance",
        "front_door_guidance",
        "packet_profile_guidance",
        "probe_selection_questions",
    }
    assert required_guidance <= data["guidance"].keys(), "canonical guidance is incomplete"
    assert "not population, identity" in data["guidance"]["probe_evidence_role_guidance"]
    assert "may contribute" in data["guidance"]["probe_evidence_role_guidance"]
    required_questions = {
        "Are all required data fields present?",
        "Is the match partial or ambiguous?",
        "Is the live probe result joined to approved source data instead of treated as proof by itself?",
        "Has this target/scope already reached the live probe budget?",
    }
    assert required_questions <= set(data["guidance"]["probe_selection_questions"]), "probe selection questions must guard evidence reuse"
    profiles = data["profiles"]
    ids = [profile["id"] for profile in profiles]
    assert profiles and len(ids) == len(set(ids)), "profiles must be nonempty with unique IDs"
    for profile in profiles:
        for field in ("id", "purpose", "target_source", "ports", "tcp_only", "rate_cap", "retries", "host_discovery_mode", "exclude_cdn", "silent_output", "machine_output", "local_evidence_only", "target_mutation"):
            assert field in profile, f"{profile.get('id', '<unknown>')} missing {field}"
        assert profile["ports"] and len(profile["ports"]) == len(set(profile["ports"])), f"{profile['id']} ports must be nonempty and unique"
        assert all(isinstance(port, int) and 1 <= port <= 65535 for port in profile["ports"]), f"{profile['id']} has invalid ports"
        assert 0 < profile["rate_cap"] <= data["rate_policy"]["max_rate_cap"]
        assert 0 <= profile["retries"] <= data["retry_policy"]["max_retries"]
        assert profile["target_mutation"] == "never"
        assert profile["tcp_only"] is True
        assert profile["local_evidence_only"] is True
        assert profile["machine_output"] in {"json", "text"}
    return data


def get_profile(policy: dict[str, Any], profile_id: str) -> dict[str, Any]:
    matches = [profile for profile in policy["profiles"] if profile["id"] == profile_id]
    if len(matches) != 1:
        raise ValueError(f"unknown or duplicated low-noise profile: {profile_id}")
    return dict(matches[0])


def decide_probe_from_evidence(policy: dict[str, Any], evidence: dict[str, Any]) -> dict[str, Any]:
    """Return the low-noise live-probe decision for one target/scope evidence record.

    Expected booleans are deliberately plain so Bash, PowerShell, reports, and future agents can
    share the same contract without importing a workflow-specific object model.
    """
    budget = policy["live_probe_budget_policy"]
    max_probes = int(budget["max_live_probes_per_target_scope"])
    probe_count = int(evidence.get("live_probe_count_for_target_scope", 0) or 0)
    override_recorded = bool(evidence.get("override_recorded"))

    if probe_count >= max_probes and not override_recorded:
        return {
            "decision": "block_live_probe",
            "reason": "live_probe_budget_exhausted",
            "max_live_probes_per_target_scope": max_probes,
        }

    if not evidence.get("existing_evidence_present"):
        return {
            "decision": "stage_live_probe",
            "reason": "no_existing_evidence",
            "max_live_probes_per_target_scope": max_probes,
        }

    insufficiencies: list[str] = []
    if not evidence.get("all_required_data_present"):
        insufficiencies.append("incomplete_existing_evidence")
    if evidence.get("partial_match") or evidence.get("ambiguous_match"):
        insufficiencies.append("partial_or_ambiguous_match")
    if evidence.get("stale"):
        insufficiencies.append("stale_existing_evidence")
    if evidence.get("wrong_approved_scope"):
        insufficiencies.append("wrong_approved_scope")
    if evidence.get("conflicting"):
        insufficiencies.append("conflicting_existing_evidence")

    if insufficiencies:
        return {
            "decision": "review_before_probe",
            "reason": "existing_evidence_insufficient",
            "insufficiencies": insufficiencies,
            "max_live_probes_per_target_scope": max_probes,
        }

    return {
        "decision": "reuse_existing_evidence",
        "reason": "complete_approved_evidence_present",
        "live_probe_evidence_preferred": bool(evidence.get("live_probe_evidence_present")),
    }


def render_profile_english(policy: dict[str, Any], profile: dict[str, Any]) -> str:
    ports = ", ".join(str(port) for port in profile["ports"])
    discovery = profile.get("host_discovery_mode", "none")
    return "\n".join([
        f"Low-noise policy {policy['policy_version']} selected profile {profile['id']}.",
        f"This profile exists to perform {profile['purpose'].lower()}.",
        f"It accepts targets only from {profile['target_source']} and limits TCP checks to ports {ports}.",
        f"Its rate cap is {profile['rate_cap']} with {profile['retries']} retries and host discovery mode {discovery}.",
        "Evidence remains local, target mutation is forbidden, and profile selection does not authorize execution.",
        policy["guidance"]["probe_evidence_role_guidance"],
        policy["guidance"]["evidence_reuse_guardrail"],
        policy["guidance"]["complete_match_guidance"],
        policy["guidance"]["live_probe_budget_guidance"],
    ])


def explain_summary(summary: dict[str, Any], policy: dict[str, Any]) -> str:
    profile_id = summary.get("low_noise_profile")
    if not profile_id:
        raise ValueError("summary missing low_noise_profile")
    profile = get_profile(policy, profile_id)
    activity = "did" if summary.get("network_activity_performed") else "did not"
    lines = [
        "# SysAdminSuite Low-Noise Explanation",
        "",
        render_profile_english(policy, profile),
        "",
        f"This run {activity} perform network activity.",
    ]
    if "target_count" in summary:
        lines.append(f"It evaluated {summary['target_count']} approved targets.")
    if "ports_source" in summary:
        lines.append(f"The effective ports came from {summary['ports_source']}.")
    if summary.get("evidence_reuse_decision"):
        lines.append(f"Evidence reuse decision: {summary['evidence_reuse_decision']}.")
    if summary.get("next_action"):
        lines.extend(["", f"Next action: {summary['next_action']}"])
    return "\n".join(lines) + "\n"
