#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import json

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api.low_noise_policy import explain_summary, get_profile, load_policy, render_profile_english

validate_policy = load_policy

def test_policy_contract() -> None:
    policy = validate_policy()
    assert policy["policy_version"] == "1.1"
    assert policy["guidance"]["probe_again_guidance"].startswith("Five probes are unnecessary")
    profiles = {profile["id"]: profile for profile in policy["profiles"]}
    assert profiles.keys() >= {"network_preflight", "keyports_cybernet_json", "web_reachability_only", "admin_surface_reachability", "serial_to_target_preflight"}
    assert profiles["network_preflight"]["ports"] == [135, 445, 3389, 9100]
    english = render_profile_english(policy, get_profile(policy, "network_preflight"))
    assert "limits TCP checks to ports 135, 445, 3389, 9100" in english
    assert "target mutation is forbidden" in english

    summary_english = explain_summary({
        "low_noise_profile": "network_preflight",
        "network_activity_performed": False,
        "target_count": 2,
        "ports_source": "canonical_default",
        "next_action": "Review the synthetic evidence.",
    }, policy)
    assert "This run did not perform network activity." in summary_english
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
