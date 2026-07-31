from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Enable-SasNorthwellVpnNetworkGuard.ps1"


def read() -> str:
    return SCRIPT.read_text(encoding="utf-8")


def test_vpn_bootstrap_avoids_windows_powershell_generic_list_binder_trap() -> None:
    text = read()
    assert "System.Collections.Generic.List" not in text
    assert "$addresses = @()" in text
    assert "$profileEvidence = @()" in text
    assert "$addresses += $cidr" in text
    assert "$profileEvidence += [pscustomobject]" in text


def test_vpn_bootstrap_requires_domain_authenticated_non_wifi_posture() -> None:
    text = read()
    assert "DomainAuthenticated" in text
    assert "InterfaceAlias" in text
    assert "wi-?fi|wireless|wlan" in text
    assert "No active Windows DomainAuthenticated network profile" in text


def test_vpn_bootstrap_authorizes_only_exact_current_ipv4_addresses() -> None:
    text = read()
    assert "+ '/32'" in text
    assert "allowedLocalIpCidrs = $addresses" in text
    assert "allowedGatewayCidrs = @()" in text
    assert "allowedDnsServerCidrs = @()" in text
    assert "allowedWindowsDomains = @()" in text


def test_vpn_bootstrap_activates_exact_policy_for_current_process() -> None:
    text = read()
    assert "$env:SAS_NETWORK_GUARD_CONFIG = $configPath" in text
    assert "process_environment_config_activated = $true" in text
    assert "Activated SAS_NETWORK_GUARD_CONFIG for this PowerShell process." in text


def test_vpn_bootstrap_is_local_only_and_emits_structured_success() -> None:
    text = read()
    assert "SAS_VPN_NETWORK_GUARD_READY" in text
    assert "target_contact_performed = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "secret_material_collected = $false" in text


if __name__ == "__main__":
    test_vpn_bootstrap_avoids_windows_powershell_generic_list_binder_trap()
    test_vpn_bootstrap_requires_domain_authenticated_non_wifi_posture()
    test_vpn_bootstrap_authorizes_only_exact_current_ipv4_addresses()
    test_vpn_bootstrap_activates_exact_policy_for_current_process()
    test_vpn_bootstrap_is_local_only_and_emits_structured_success()
    print("VPN network guard bootstrap contracts passed")
