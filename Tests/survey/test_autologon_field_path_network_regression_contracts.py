#!/usr/bin/env python3
"""Regression contracts for AutoLogon field path budget and canonical network gating."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"
STATE = ROOT / "scripts" / "SasAutoLogonOperatorState.psm1"
S4U = ROOT / "scripts" / "Invoke-SasAutoLogonS4URestartDeployment.ps1"
TRANSPORT = ROOT / "scripts" / "Test-SasSoftwareDeploymentTransport.ps1"
S4U_STATUS = ROOT / "scripts" / "Get-SasAutoLogonS4URunStatus.ps1"
NETWORK_GUARD = ROOT / "scripts" / "SasNetworkGuard.psm1"
VPN_BOOTSTRAP = ROOT / "scripts" / "Enable-SasNorthwellVpnNetworkGuard.ps1"
GITIGNORE = ROOT / ".gitignore"


def main() -> None:
    onsite = ONSITE.read_text(encoding="utf-8")
    field = FIELD.read_text(encoding="utf-8")
    state = STATE.read_text(encoding="utf-8")
    s4u = S4U.read_text(encoding="utf-8")
    transport = TRANSPORT.read_text(encoding="utf-8")
    s4u_status = S4U_STATUS.read_text(encoding="utf-8")
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

    # The state module is a nested consumer of SasOperatorSession. It must not force-reload that
    # dependency and erase session helpers already exported into the field transaction's scope.
    assert "Import-Module $sessionModule -ErrorAction Stop" in state
    assert "Import-Module $sessionModule -Force" not in state
    assert "Do not force-reload it" in state
    assert "Get-SasObjectPropertyValue" in field

    # Protected AutoLogon operator-state bookkeeping consumes the already-sealed manifest identity
    # instead of invoking Git for HEAD/branch metadata after the network transition.
    assert "Get-SasAutoLogonPreparedRuntimeIdentity" in state
    assert "autologon-short-runtime.json" in state
    assert "prepared_commit" in state
    assert "git_invoked = $false" in state
    assert "repo_branch=$runtimeIdentity.branch" in state
    assert "repo_head=$runtimeIdentity.commit" in state
    assert "Get-SasRepoHead -RepoRoot $RepoRoot" not in state
    assert "& git" not in state

    # Transport preflight owns a complete SasRunContext tree. Nesting that workflow/run tree beneath
    # the already nested field/deployment/S4U run overflows the practical Windows PowerShell 5.1 path
    # budget. The preflight must compact an over-budget requested root back to the canonical short
    # repository runs root while returning its actual result_path to the S4U caller.
    overflow_request = (
        r"C:\SASAL\runs\autologon-field-deployment-99999999-999999-ffffffff"
        r"\deployment\autologon-s4u-deployment-99999999-999999-ffffffff"
        r"\s4u\autologon-kerberos-s4u-99999999-999999-ffffffff"
        r"\preflight\software-deployment-transport"
        r"\software-deployment-transport-99999999-999999-ffffffff\request.json"
    )
    compact_result = (
        r"C:\SASAL\runs\software-deployment-transport"
        r"\software-deployment-transport-99999999-999999-ffffffff"
        r"\artifacts\software_deployment_transport_result.json"
    )
    assert len(overflow_request) > 260, len(overflow_request)
    assert len(compact_result) < 240, len(compact_result)
    for marker in (
        "$transportWindowsPathBudget = 240",
        "Get-SasTransportProjectedArtifactPath",
        "TRANSPORT_OUTPUT_ROOT_COMPACTED",
        "$compactOutputRoot = Join-Path $repoRoot 'runs'",
        "Assert-SasLocalOutputRoot -OutputRoot $requestedOutputRoot -RepoRoot $repoRoot",
        "transport_preflight_link.json",
        "sas-software-deployment-transport-link/v1",
        "owner_link_path = $transportOwnerLinkPath",
    ):
        assert marker in transport, f"missing transport path-budget/link marker: {marker}"

    # Compaction must not make the transport evidence invisible to the S4U owner. The local status
    # observer follows only a canonical link whose result remains under <repo>/runs and has the exact
    # transport result filename; it never turns the pointer into network or target authority.
    for marker in (
        "transport_preflight_link.json",
        "sas-software-deployment-transport-link/v1",
        "$approvedTransportRoot = Join-Path $repoRoot 'runs'",
        "Test-SasStatusPathUnderRoot",
        "software_deployment_transport_result.json",
        "preflight_link_valid",
        "network_activity_performed_by_observer = $false",
        "target_mutation_performed_by_observer = $false",
    ):
        assert marker in s4u_status, f"missing S4U compact-link status marker: {marker}"

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

    # Conservative path model for the longest ordinary nested field artifact after transport
    # preflight is compacted into its own short run tree.
    representative = (
        r"C:\SASAL\runs\autologon-field-deployment-99999999-999999-ffffffff"
        r"\deployment\autologon-s4u-deployment-99999999-999999-ffffffff"
        r"\s4u\autologon-kerberos-s4u-99999999-999999-ffffffff"
        r"\evidence\s4u_probe_lifecycle.json"
    )
    assert len(representative) < 240, len(representative)

    print("PASS: AutoLogon field path/network regression contracts")


if __name__ == "__main__":
    main()
