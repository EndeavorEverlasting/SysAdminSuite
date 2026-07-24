#!/usr/bin/env python3
"""Field-regression fixture contracts for the portable on-site operator flow."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "Tests" / "survey" / "fixtures" / "portable-onsite-runtime-regression.txt"


def main() -> None:
    text = FIXTURE.read_text(encoding="utf-8")
    expected = {
        "AUTOLOGON_SINGLE_REQUEST=qualification-request.local.json",
        "NETSH_SSID=unknown",
        "CONNECTION_PROFILE_NAME=NSLIJHS-WAB",
        "CONNECTION_PROFILE_INTERFACE_ALIAS=Wi-Fi",
        "EXPECTED_NETWORK_CLASSIFICATION=OK_NETWORK_POSTURE",
        "NUMERIC_SWITCH_CHOICE=1",
        "LETTER_SWITCH_CHOICE=S",
        "CANCEL_CHOICE=Q",
        "SWITCH_BASELINE_LABEL=NORTHWELL-GUEST",
        "SWITCH_APPROVED_PROFILE=NSLIJHS-WAB(WPA2)",
        "SWITCH_INTERMEDIATE_LABEL=Identifying...",
        "SWITCH_STABLE_WINDOWS_LABEL=nslijhs.net",
        "SWITCH_EXPECTED_EVIDENCE_SOURCE=confirmed_saved_profile_network_transition",
    }
    missing = sorted(marker for marker in expected if marker not in text)
    assert not missing, f"missing portable runtime regression markers: {missing}"
    print("PASS: portable on-site runtime fixture")


if __name__ == "__main__":
    main()
