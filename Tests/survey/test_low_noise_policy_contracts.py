#!/usr/bin/env python3
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "validate-low-noise-policy.py"
spec = importlib.util.spec_from_file_location("low_noise_validator", VALIDATOR)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
validate_policy = module.validate_policy

def test_policy_contract() -> None:
    policy = validate_policy()
    assert policy["policy_version"] == "1.1"
    profiles = {profile["id"]: profile for profile in policy["profiles"]}
    assert profiles.keys() >= {"network_preflight", "keyports_cybernet_json", "web_reachability_only", "admin_surface_reachability", "serial_to_target_preflight"}
    assert profiles["network_preflight"]["ports"] == [135, 445, 3389, 9100]

    preflight = (ROOT / "survey" / "sas-network-preflight.ps1").read_text(encoding="utf-8-sig")
    for fragment in ("Get-SasLowNoiseProfile", "PolicyProfile = 'network_preflight'", "operator_subset", "may narrow but not broaden", "low_noise_profile", "ports_source"):
        assert fragment in preflight, f"network preflight missing canonical profile contract: {fragment}"

if __name__ == "__main__":
    test_policy_contract()
    print("low-noise policy contracts passed")
