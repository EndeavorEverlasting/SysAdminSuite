#!/usr/bin/env python3
"""Static contracts for bounded verification of an approved saved-profile Wi-Fi switch."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GATE = ROOT / "scripts" / "Confirm-SasNorthwellNetwork.ps1"


def main() -> None:
    text = GATE.read_text(encoding="utf-8")
    required = (
        "Wait-SasApprovedSavedProfileTransition",
        "Get-SasActiveWifiConnectionProfile",
        "Test-SasUsableWifiConnectivity",
        "Test-SasStableNetworkLabel",
        "confirmed_saved_profile_network_transition",
        "direct_approved_network_label",
        "$previousNetworkLabel = [string]$posture.observed_wifi_network_label",
        "enterprise Wi-Fi authentication to stabilize",
        "approved network transition could not be verified",
        "$script:confirmedApprovedProfile = $profile",
        "switch_verification = $script:switchVerification",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
    )
    missing = [marker for marker in required if marker not in text]
    assert not missing, f"missing switch-verification contract markers: {missing}"
    assert "Start-Sleep -Seconds 3" not in text
    assert "Start-Sleep -Seconds 2" in text
    print("PASS: approved saved-profile transition verification contracts")


if __name__ == "__main__":
    main()
