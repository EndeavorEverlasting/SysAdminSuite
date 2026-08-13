#!/usr/bin/env python3
"""Regression contracts for AutoLogon field path budget and canonical network gating."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"
S4U = ROOT / "scripts" / "Invoke-SasAutoLogonS4URestartDeployment.ps1"


def main() -> None:
    onsite = ONSITE.read_text(encoding="utf-8")
    field = FIELD.read_text(encoding="utf-8")
    s4u = S4U.read_text(encoding="utf-8")

    # The outer transaction is the sole authority for protected-network admission.
    assert "Confirm-SasNorthwellNetwork.ps1" in field
    assert "Enable-SasNorthwellVpnNetworkGuard.ps1" not in onsite
    assert "Assert-SasAutoLogonProtectedNetwork" not in onsite

    # Nested evidence must not depend on the caller's potentially long OneDrive checkout path.
    assert "SAS_AUTOLOGON_OUTPUT_ROOT" in field
    assert "SysAdminSuite\\field-runs\\autologon-deployment" in field
    assert "-OutputRoot $deploymentOutputRoot" in field
    assert "New-Item -ItemType Directory -Path $OutputRoot" in s4u

    print("PASS: AutoLogon field path/network regression contracts")


if __name__ == "__main__":
    main()
