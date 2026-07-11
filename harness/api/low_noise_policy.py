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
        "freshness_policy", "retry_policy", "rate_policy",
        "edge_target_policy", "output_policy", "evidence_policy", "guidance", "profiles",
    }
    missing = required - data.keys()
    assert not missing, f"missing fields: {sorted(missing)}"
    assert data["schema_version"] == "sas-low-noise-policy/v1"
    assert 0 <= data["retry_policy"]["default_retries"] <= data["retry_policy"]["max_retries"]
    assert 0 < data["rate_policy"]["default_rate_cap"] <= data["rate_policy"]["max_rate_cap"]
    assert data["output_policy"]["survey_local_only"] is True
    assert data["evidence_policy"]["target_mutation"] == "never"
    required_guidance = {"low_noise_principle", "network_visibility_note", "probe_again_guidance", "fresh_evidence_guidance", "mystery_serial_guidance", "front_door_guidance", "packet_profile_guidance", "probe_selection_questions"}
    assert required_guidance <= data["guidance"].keys(), "canonical guidance is incomplete"
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


def render_profile_english(policy: dict[str, Any], profile: dict[str, Any]) -> str:
    ports = ", ".join(str(port) for port in profile["ports"])
    discovery = profile.get("host_discovery_mode", "none")
    return "\n".join([
        f"Low-noise policy {policy['policy_version']} selected profile {profile['id']}.",
        f"This profile exists to perform {profile['purpose'].lower()}.",
        f"It accepts targets only from {profile['target_source']} and limits TCP checks to ports {ports}.",
        f"Its rate cap is {profile['rate_cap']} with {profile['retries']} retries and host discovery mode {discovery}.",
        "Evidence remains local, target mutation is forbidden, and profile selection does not authorize execution.",
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
    if summary.get("next_action"):
        lines.extend(["", f"Next action: {summary['next_action']}"])
    return "\n".join(lines) + "\n"
