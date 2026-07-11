#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import json

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api.low_noise_policy import (
    decide_probe_from_evidence,
    explain_summary,
    get_profile,
    load_policy,
    render_profile_english,
)

validate_policy = load_policy

def test_policy_contract() -> None:
    policy = validate_policy()
    assert policy["policy_version"] == "1.1"
    assert policy["guidance"]["probe_again_guidance"].startswith("Five probes are unnecessary")
    assert policy["live_probe_budget_policy"]["max_live_probes_per_target_scope"] == 5
    assert policy["live_probe_budget_policy"]["check_existing_evidence_before_probe"] is True
    assert policy["live_probe_budget_policy"]["complete_match_required_for_reuse"] is True
    assert policy["live_probe_budget_policy"]["partial_or_ambiguous_match_is_insufficient"] is True
    assert policy["guidance"]["evidence_reuse_guardrail"].startswith("If all required data is already present")
    assert "Partial matches" in policy["guidance"]["complete_match_guidance"]
    assert "stop at five total live probes" in policy["guidance"]["live_probe_budget_guidance"]

    profiles = {profile["id"]: profile for profile in policy["profiles"]}
    assert profiles.keys() >= {"network_preflight", "keyports_cybernet_json", "web_reachability_only", "admin_surface_reachability", "serial_to_target_preflight"}
    assert profiles["network_preflight"]["ports"] == [135, 445, 3389, 9100]
    english = render_profile_english(policy, get_profile(policy, "network_preflight"))
    assert "limits TCP checks to ports 135, 445, 3389, 9100" in english
    assert "target mutation is forbidden" in english
    assert "do not probe again by default" in english
    assert "Partial matches, ambiguous matches" in english
    assert "stop at five total live probes" in english

    complete_evidence = decide_probe_from_evidence(policy, {
        "existing_evidence_present": True,
        "all_required_data_present": True,
        "live_probe_evidence_present": True,
        "live_probe_count_for_target_scope": 1,
    })
    assert complete_evidence["decision"] == "reuse_existing_evidence"
    assert complete_evidence["reason"] == "complete_approved_evidence_present"
    assert complete_evidence["live_probe_evidence_preferred"] is True

    partial_evidence = decide_probe_from_evidence(policy, {
        "existing_evidence_present": True,
        "all_required_data_present": False,
        "partial_match": True,
        "live_probe_count_for_target_scope": 1,
    })
    assert partial_evidence["decision"] == "review_before_probe"
    assert partial_evidence["reason"] == "existing_evidence_insufficient"
    assert "incomplete_existing_evidence" in partial_evidence["insufficiencies"]
    assert "partial_or_ambiguous_match" in partial_evidence["insufficiencies"]

    exhausted_budget = decide_probe_from_evidence(policy, {
        "existing_evidence_present": True,
        "all_required_data_present": False,
        "live_probe_count_for_target_scope": 5,
    })
    assert exhausted_budget["decision"] == "block_live_probe"
    assert exhausted_budget["reason"] == "live_probe_budget_exhausted"

    override_budget = decide_probe_from_evidence(policy, {
        "existing_evidence_present": True,
        "all_required_data_present": False,
        "live_probe_count_for_target_scope": 5,
        "override_recorded": True,
    })
    assert override_budget["decision"] == "review_before_probe"

    summary_english = explain_summary({
        "low_noise_profile": "network_preflight",
        "network_activity_performed": False,
        "target_count": 2,
        "ports_source": "canonical_default",
        "evidence_reuse_decision": "reuse_existing_evidence",
        "next_action": "Review the synthetic evidence.",
    }, policy)
    assert "This run did not perform network activity." in summary_english
    assert "Evidence reuse decision: reuse_existing_evidence." in summary_english
    assert "Next action: Review the synthetic evidence." in summary_english

    cli = subprocess.run([
        sys.executable, "-m", "harness.api.low_noise_cli", "profile",
        "--id", "network_preflight", "--format", "json",
    ], cwd=ROOT, check=True, capture_output=True, text=True)
    assert json.loads(cli.stdout)["id"] == "network_preflight"

    preflight = (ROOT / "survey" / "sas-network-preflight.ps1").read_text(encoding="utf-8-sig")
    for fragment in ("Get-SasLowNoiseProfile", "New-SasLowNoiseContextObject", "PolicyProfile = 'network_preflight'", "explicit_subset_override", "may narrow but not broaden", "low_noise_profile", "ports_source"):
        assert fragment in preflight, f"network preflight missing canonical profile contract: {fragment}"

    bash_planner = (ROOT / "survey" / "sas-target-reduction-plan.sh").read_text(encoding="utf-8-sig")
    assert "from harness.api.low_noise_policy import load_policy" in bash_planner
    assert '"policy_version": "1.0"' not in bash_planner

if __name__ == "__main__":
    test_policy_contract()
    print("low-noise policy contracts passed")
