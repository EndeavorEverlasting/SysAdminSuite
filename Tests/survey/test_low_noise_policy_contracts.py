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
    assert {profile["id"] for profile in policy["profiles"]} >= {"keyports_cybernet_json", "web_reachability_only", "admin_surface_reachability", "serial_to_target_preflight"}

if __name__ == "__main__":
    test_policy_contract()
    print("low-noise policy contracts passed")
