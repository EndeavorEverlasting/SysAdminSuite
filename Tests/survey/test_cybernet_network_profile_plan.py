#!/usr/bin/env python3
"""Static contract for the multi-environment Cybernet posture plan."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / "docs" / "plans" / "cybernet-network-posture-profiles.plan.md"


def test_profile_plan_is_explicit_and_fail_closed() -> None:
    text = PLAN.read_text(encoding="utf-8")
    for fragment in (
        "corporate_wab",
        "approved_lan",
        "approved_vpn",
        "unknown",
        "Profile selection is an explicit toggle",
        "profile_id",
        "guard_configured",
        "network_activity_performed",
        "target_mutation_performed",
        "raw-evidence artifact references",
        "Human console status belongs on the host",
        "unknown` and failed evidence remain fail-closed",
        "No profile may collect secrets",
    ):
        assert fragment in text, f"missing profile-plan contract: {fragment}"


if __name__ == "__main__":
    test_profile_plan_is_explicit_and_fail_closed()
    print("cybernet network profile plan contracts passed")
