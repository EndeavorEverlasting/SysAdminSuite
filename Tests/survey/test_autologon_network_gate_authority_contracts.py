#!/usr/bin/env python3
"""Regression contract for canonical protected-network gate authority in AutoLogon."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"


def main() -> None:
    text = FIELD.read_text(encoding="utf-8-sig")

    gate_call = "& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate"
    classification = "$result.network_classification = 'PROTECTED_NORTHWELL'"
    resolution = "=== CANONICAL TARGET RESOLUTION ==="

    assert "Confirm-SasNorthwellNetwork.ps1" in text
    assert gate_call in text
    assert classification in text
    assert "canonical protected-network authority" in text
    assert "OK_NETWORK_POSTURE" in text
    assert "Get-SasOperatorNetworkClassification -RepoRoot $repoRoot" not in text
    assert text.index(gate_call) < text.index(classification) < text.index(resolution)

    print("PASS: AutoLogon network gate authority contracts")


if __name__ == "__main__":
    main()
