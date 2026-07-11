#!/usr/bin/env python3
"""Dependency-free validator for the canonical low-noise policy document."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "Config" / "low-noise-policy.json"

def validate_policy(path: Path = POLICY_PATH) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    required = {"schema_version", "policy_version", "population_source_policy", "freshness_policy", "retry_policy", "rate_policy", "edge_target_policy", "output_policy", "evidence_policy", "profiles"}
    missing = required - data.keys()
    assert not missing, f"missing fields: {sorted(missing)}"
    assert data["schema_version"] == "sas-low-noise-policy/v1"
    assert 0 <= data["retry_policy"]["default_retries"] <= data["retry_policy"]["max_retries"]
    assert 0 < data["rate_policy"]["default_rate_cap"] <= data["rate_policy"]["max_rate_cap"]
    assert data["output_policy"]["survey_local_only"] is True
    assert data["evidence_policy"]["target_mutation"] == "never"
    profiles = data["profiles"]
    ids = [profile["id"] for profile in profiles]
    assert profiles and len(ids) == len(set(ids)), "profiles must be nonempty with unique IDs"
    for profile in profiles:
        for field in ("id", "purpose", "target_source", "ports", "rate_cap", "retries", "machine_output", "target_mutation"):
            assert field in profile, f"{profile.get('id', '<unknown>')} missing {field}"
        assert profile["ports"] and 0 < profile["rate_cap"] <= data["rate_policy"]["max_rate_cap"]
        assert profile["retries"] >= 0 and profile["target_mutation"] == "never"
        assert profile["local_evidence_only"] is True
        assert profile["machine_output"] in {"json", "text"}
    return data

if __name__ == "__main__":
    validate_policy()
    print(f"low-noise policy valid: {POLICY_PATH.relative_to(ROOT)}")
