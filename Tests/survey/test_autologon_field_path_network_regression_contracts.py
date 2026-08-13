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

    # The outer transaction remains the sole authority for protected-network admission.
    assert "Confirm-SasNorthwellNetwork.ps1" in field
    assert "Enable-SasNorthwellVpnNetworkGuard.ps1" not in onsite
    assert "Assert-SasAutoLogonProtectedNetwork" not in onsite

    # Long physical checkouts must re-enter an exact committed short worktree before field mutation.
    required = (
        "FieldPathThreshold",
        "Invoke-SasAutoLogonShortRuntime",
        "SysAdminSuite\\field-runtime\\autologon",
        "worktree add --detach",
        "rev-parse HEAD",
        "status --porcelain",
        "Short AutoLogon field runtime is dirty",
        "$env:SAS_REPO_ROOT = $SourceRepoRoot",
        "& powershell.exe @childArgs",
        "exit $LASTEXITCODE",
    )
    missing = [marker for marker in required if marker not in onsite]
    assert not missing, f"missing short-runtime markers: {missing}"

    # The inner engine still creates its result directory before first persistence; the short runtime
    # fixes the physical path budget rather than weakening or relocating product proof semantics.
    assert "New-Item -ItemType Directory -Path $runRoot,$evidenceRoot -Force" in s4u
    assert "autologon_s4u_deployment_result.json" in s4u

    print("PASS: AutoLogon field path/network regression contracts")


if __name__ == "__main__":
    main()
