#!/usr/bin/env python3
"""Regression contracts for AutoLogon field path budget and canonical network gating."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"
STATE = ROOT / "scripts" / "SasAutoLogonOperatorState.psm1"
S4U = ROOT / "scripts" / "Invoke-SasAutoLogonS4URestartDeployment.ps1"
NETWORK_GUARD = ROOT / "scripts" / "SasNetworkGuard.psm1"
VPN_REPAIR = ROOT / "scripts" / "Repair-SasVpnDomainAuthNetworkGuardRuntime.ps1"
VPN_BOOTSTRAP = ROOT / "scripts" / "Enable-SasNorthwellVpnNetworkGuard.ps1"
GITIGNORE = ROOT / ".gitignore"


def main() -> None:
    onsite = ONSITE.read_text(encoding="utf-8")
    field = FIELD.read_text(encoding="utf-8")
    state = STATE.read_text(encoding="utf-8")
    s4u = S4U.read_text(encoding="utf-8")
    network_guard = NETWORK_GUARD.read_text(encoding="utf-8")
    vpn_repair = VPN_REPAIR.read_text(encoding="utf-8")
    vpn_bootstrap = VPN_BOOTSTRAP.read_text(encoding="utf-8")
    gitignore = GITIGNORE.read_text(encoding="utf-8")

    # The outer transaction remains the sole authority for protected-network admission.
    assert "Confirm-SasNorthwellNetwork.ps1" in field
    assert "Enable-SasNorthwellVpnNetworkGuard.ps1" not in onsite
    assert "Assert-SasAutoLogonProtectedNetwork" not in onsite

    # Refresh and field transactions import SasOperatorSession before AutoLogon state. The nested
    # state module must not force-reload that dependency and erase caller-visible helpers such as
    # Get-SasOperatorNetworkClassification, Read-SasOperatorSession, or Set-SasOperatorSessionValues.
    assert "Import-Module $sessionModule -ErrorAction Stop" in state
    assert "Import-Module $sessionModule -Force" not in state
    assert "must not force-reload SasOperatorSession" in state

    # Protected AutoLogon state bookkeeping consumes the Guest-staged seal identity rather than
    # invoking Git after the network transition. Git availability is not deployment authority.
    assert "function Get-SasAutoLogonPreparedRuntimeIdentity" in state
    assert "autologon-short-runtime.json" in state
    assert "prepared_commit" in state
    assert "git_invoked = $false" in state
    assert "repo_head=$runtimeIdentity.commit" in state
    assert "repo_branch=$runtimeIdentity.branch" in state
    assert "Get-SasRepoHead -RepoRoot $RepoRoot" not in state
    assert "& git" not in state

    # Live Windows DomainAuthenticated non-Wi-Fi authority must outrank the visible physical uplink.
    # A guest Wi-Fi label must not block an authenticated VPN/LAN path, and a changed VPN address
    # must not require regenerating an exact /32 allowlist.
    required_guard = (
        "SasNetworkGuardDomainAuthPrecedence",
        "live_domain_authenticated_non_wifi_v1",
        "Test-SasNorthwellDomainAuthenticatedEvidence",
        "NetworkCategory",
        "DomainAuthenticated",
        "Get-NetConnectionProfile",
        "Get-NetIPAddress",
        "wi-?fi|wireless|wlan",
        "Live Windows domain authentication is stronger than the physical uplink label",
        "domain_authenticated_interface=$alias;interface_index=$interfaceIndex;local_ip=$ip",
    )
    missing_guard = [marker for marker in required_guard if marker not in network_guard]
    assert not missing_guard, f"missing live VPN guard markers: {missing_guard}"
    assert "if (@($config.allowedLocalIpCidrs).Count -eq 0) { return $false }" not in network_guard

    domain_auth = network_guard.index("function Test-SasNorthwellDomainAuthenticatedEvidence")
    wired = network_guard.index("function Test-SasNorthwellWiredEvidence")
    live_call = network_guard.index("Test-SasNorthwellDomainAuthenticatedEvidence @liveEvidenceArgs", wired)
    config = network_guard.index("$config = Get-SasNetworkGuardConfig", wired)
    assert domain_auth < wired < live_call < config, "live DomainAuthenticated authority must be evaluated before optional allowlist config"

    # The legacy bootstrap may remain for compatibility, but the canonical guard no longer depends
    # on exact /32 policy for an already DomainAuthenticated VPN.
    for marker in ("DomainAuthenticated", "Get-NetConnectionProfile", "Get-NetIPAddress"):
        assert marker in vpn_bootstrap, f"VPN bootstrap lost compatibility marker: {marker}"

    for marker in (
        "sas-vpn-domain-auth-precedence-runtime-repair/v1",
        "VPN_DOMAIN_AUTH_PRECEDENCE_RUNTIME_REPAIR_APPLIED",
        "guest_wifi_may_coexist = $true",
        "exact_local_ip_allowlist_required_for_domain_authenticated_vpn = $false",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
    ):
        assert marker in vpn_repair, f"runtime VPN repair lost marker: {marker}"

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
