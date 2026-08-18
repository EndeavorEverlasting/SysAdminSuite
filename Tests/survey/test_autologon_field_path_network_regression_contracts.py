#!/usr/bin/env python3
"""Regression contracts for AutoLogon field path budget and canonical network gating."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"
S4U = ROOT / "scripts" / "Invoke-SasAutoLogonS4URestartDeployment.ps1"
NETWORK_GUARD = ROOT / "scripts" / "SasNetworkGuard.psm1"
VPN_BOOTSTRAP = ROOT / "scripts" / "Enable-SasNorthwellVpnNetworkGuard.ps1"
GITIGNORE = ROOT / ".gitignore"


def main() -> None:
    onsite = ONSITE.read_text(encoding="utf-8")
    field = FIELD.read_text(encoding="utf-8")
    s4u = S4U.read_text(encoding="utf-8")
    network_guard = NETWORK_GUARD.read_text(encoding="utf-8")
    vpn_bootstrap = VPN_BOOTSTRAP.read_text(encoding="utf-8")
    gitignore = GITIGNORE.read_text(encoding="utf-8")

    # The outer transaction remains the sole authority for protected-network admission.
    assert "Confirm-SasNorthwellNetwork.ps1" in field
    assert "Enable-SasNorthwellVpnNetworkGuard.ps1" not in onsite
    assert "Assert-SasAutoLogonProtectedNetwork" not in onsite

    # A successful canonical network-gate process is itself the transaction's protected-network
    # authority. Do not perform a second caller-scope classification after state-module imports:
    # that redundant lookup can disappear when SasOperatorSession is force-reloaded in module scope.
    gate_call = "& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate"
    gate_classification = "$result.network_classification = 'PROTECTED_NORTHWELL'"
    target_resolution = "=== CANONICAL TARGET RESOLUTION ==="
    assert gate_call in field
    assert "canonical protected-network authority" in field
    assert "OK_NETWORK_POSTURE" in field
    assert gate_classification in field
    assert "Get-SasOperatorNetworkClassification -RepoRoot $repoRoot" not in field
    assert field.index(gate_call) < field.index(gate_classification) < field.index(target_resolution)

    # VPN bootstrap and canonical guard must agree on the authority model: an active
    # DomainAuthenticated non-Wi-Fi interface plus an exact allowlisted local IP.
    required_guard = (
        "Test-SasNorthwellDomainAuthenticatedEvidence",
        "NetworkCategory",
        "DomainAuthenticated",
        "Get-NetConnectionProfile",
        "Get-NetIPAddress",
        "allowedLocalIpCidrs",
        "Test-SasIpInCidr",
        "wi-?fi|wireless|wlan",
    )
    missing_guard = [marker for marker in required_guard if marker not in network_guard]
    assert not missing_guard, f"missing live VPN guard markers: {missing_guard}"
    for marker in ("DomainAuthenticated", "Get-NetConnectionProfile", "Get-NetIPAddress", "allowedLocalIpCidrs", "/32"):
        assert marker in vpn_bootstrap, f"VPN bootstrap lost authority marker: {marker}"

    # Every target-facing AutoLogon action must re-enter a stable short physical worktree.
    required = (
        "$fieldRuntimeRoot = 'C:\\SASAL'",
        "Invoke-SasAutoLogonShortRuntime",
        "worktree add --detach",
        "checkout --detach",
        "--git-common-dir",
        "status --porcelain",
        "Refusing to overwrite or clean it automatically",
        "$env:SAS_REPO_ROOT = $SourceRepoRoot",
        "-and -not $isShortRuntime",
        "& powershell.exe @childArgs",
        "exit $LASTEXITCODE",
    )
    missing = [marker for marker in required if marker not in onsite]
    assert not missing, f"missing short-runtime markers: {missing}"

    # The stable short runtime must keep live evidence in the repository's already-ignored runs root.
    assert "$fieldOutputRoot = Join-Path $repoRoot 'runs'" in onsite
    assert "-OutputRoot $fieldOutputRoot" in onsite
    assert "runs/" in gitignore

    # The inner engine still owns normal result creation; no proof gate is weakened.
    assert "New-Item -ItemType Directory -Path $runRoot,$evidenceRoot -Force" in s4u
    assert "autologon_s4u_deployment_result.json" in s4u
    assert "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" in field

    # Conservative path model for the longest currently registered nested field chain.
    representative = (
        r"C:\SASAL\runs\autologon-field-deployment-20260813-212232-6f78044c"
        r"\deployment\autologon-s4u-deployment-20260813-212244-8b335f50"
        r"\s4u\autologon-kerberos-s4u-20260813-212250-8b335f50"
        r"\preflight\software_deployment_transport_preflight_result.json"
    )
    assert len(representative) < 250, len(representative)

    print("PASS: AutoLogon field path/network regression contracts")


if __name__ == "__main__":
    main()
