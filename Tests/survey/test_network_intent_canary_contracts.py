#!/usr/bin/env python3
"""Static contracts for the universal network canary and bounded auto-transition layer."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INTENT = ROOT / "scripts" / "SasNetworkIntent.psm1"
WRAPPER = ROOT / "scripts" / "Invoke-SasNetworkAwareField.ps1"
INSTALLER = ROOT / "scripts" / "Install-SasUniversalFieldLauncher.ps1"
DOC = ROOT / "docs" / "UNIVERSAL_FIELD_PLATFORM.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_canary_names_required_and_current_network_before_execution() -> None:
    text = read(INTENT)
    for marker in (
        "=== NETWORK CANARY ===",
        "NETWORK REQUIRED:",
        "NETWORK PURPOSE:",
        "CURRENT NETWORK:",
        "CURRENT AUTHORITY:",
        "AUTO-SWITCH:",
        "InternetSync",
        "ProtectedNorthwell",
        "LocalOnly",
        "CommandSpecific",
    ):
        assert marker in text, marker


def test_network_intents_match_operator_workflows() -> None:
    text = read(WRAPPER)
    for marker in (
        "'refresh'",
        "$intent = 'InternetSync'",
        "'printer'",
        "$intent = 'ProtectedNorthwell'",
        "'clipboard' { $intent = 'LocalOnly' }",
        "'platform' { $intent = 'LocalOnly' }",
        "'network'",
        "'autologon'",
        "'cybernet'",
        "Enter-SasNetworkIntent",
        "Restore-SasNetworkIntent",
    ):
        assert marker in text, marker
    assert text.index("Enter-SasNetworkIntent") < text.index("& powershell.exe @childArgs") < text.index("Restore-SasNetworkIntent")


def test_invalid_or_incomplete_shapes_cannot_trigger_protected_switch() -> None:
    text = read(WRAPPER)
    for marker in (
        "Test-SasPrinterShapeForNetworkTransition",
        "if ($actualArgs.Count -eq 0) { $intent = 'InternetSync' }",
        "elseif ($actualArgs.Count -eq 1) { $intent = 'ProtectedNorthwell' }",
        "if ($actualArgs.Count -eq 2 -and",
        "if ($actualArgs.Count -ge 2 -and",
        "Invalid/incomplete shapes still flow to the canonical dispatcher",
    ):
        assert marker in text, marker
    assert "if ($actualArgs.Count -gt 2) { return $false }" in text
    assert "if ($modeSeen) { return $false }" in text
    assert "if ($offlineSeen) { return $false }" in text


def test_saved_wlan_switching_is_transactional_and_restored() -> None:
    text = read(INTENT)
    for marker in (
        "sas-network-intent-transition/v1",
        "sas-protected-wlan-bookmark/v1",
        "return-network.json",
        "protected-network.json",
        "SAVED_WLAN_PROFILE",
        "restore_required",
        "restore_profile",
        "Invoke-SasSavedWlanConnect",
        "NETWORK RESTORE:",
        "NETWORK RESTORED:",
        "SAS_NETWORK_RESTORE_FAILED",
    ):
        assert marker in text, marker
    assert "try { [void](Invoke-SasSavedWlanConnect -RepoRoot $RepoRoot -ProfileName ([string]$before.network_label)) } catch { }" in text
    assert "try { [void](Invoke-SasSavedWlanConnect -RepoRoot $RepoRoot -ProfileName ([string]$before.label)) } catch { }" in text


def test_saved_wlan_profile_proof_is_locale_independent() -> None:
    text = read(INTENT)
    for marker in (
        "function Test-SasSavedWlanProfile",
        "@('wlan','show','profile',",
        "native exit code as profile-existence proof",
        "Test-SasSavedWlanProfile -RepoRoot $RepoRoot -ProfileName $ProfileName",
    ):
        assert marker in text, marker
    for forbidden in (
        "All User Profile",
        "User Profile",
        "Get-SasSavedWlanProfiles",
        "wlan','show','profiles",
    ):
        assert forbidden not in text, forbidden


def test_protected_auto_entry_requires_paired_proven_wlan_bookmarks() -> None:
    text = read(INTENT)
    for marker in (
        "$sameGuest",
        "$null -ne $return",
        "$null -ne $protectedBookmark",
        "AUTO_SWITCHED_TO_PROTECTED_WAB",
        "SAS_NETWORK_TRANSITION_PROTECTED_REQUIRED",
    ):
        assert marker in text, marker
    paired = text.index("if ($sameGuest -and $null -ne $protectedBookmark)")
    connect = text.index("Invoke-SasSavedWlanConnect", paired)
    assert paired < connect


def test_network_sensitive_transactions_are_serialized_through_restore() -> None:
    text = read(WRAPPER)
    for marker in (
        "Global\\SysAdminSuite.NetworkIntent.v1",
        "$serializedIntent = $intent -in @('InternetSync','ProtectedNorthwell')",
        "$networkMutex.WaitOne(0)",
        "SAS_NETWORK_TRANSITION_BUSY",
        "BLOCKED_BY_CONCURRENT_NETWORK_TRANSACTION",
        "Restore-SasNetworkIntent",
        "$networkMutex.ReleaseMutex()",
        "$networkMutex.Dispose()",
    ):
        assert marker in text, marker
    lock = text.index("$networkMutex.WaitOne(0)")
    enter = text.index("Enter-SasNetworkIntent", lock)
    child = text.index("& powershell.exe @childArgs", enter)
    restore = text.index("Restore-SasNetworkIntent", child)
    release = text.index("$networkMutex.ReleaseMutex()", restore)
    assert lock < enter < child < restore < release


def test_vpn_and_hardwire_lifecycle_fail_closed_instead_of_guessing() -> None:
    text = (read(INTENT) + "\n" + read(WRAPPER)).lower()
    for marker in (
        "sas_network_transition_manual_vpn_required",
        "no repository-proven vpn client lifecycle adapter is installed",
        "sas_network_transition_manual_wired_required",
        "sysadminsuite did not guess or manipulate an unproven vpn client",
    ):
        assert marker in text, marker
    for forbidden in (
        "rasdial",
        "rasphone",
        "get-vpnconnection",
        "set-vpnconnection",
        "remove-vpnconnection",
        "disconnect-vpn",
        "connect-vpn",
        "get-credential",
        "password",
    ):
        assert forbidden not in text, forbidden


def test_network_transition_layer_is_controller_local_and_target_free() -> None:
    text = (read(INTENT) + "\n" + read(WRAPPER)).lower()
    for forbidden in (
        "invoke-command",
        "test-netconnection",
        "schtasks",
        "admin$",
        "c$\\",
        "printuientry",
        "add-printer",
    ):
        assert forbidden not in text, forbidden


def test_restore_failure_prevents_false_green_result() -> None:
    text = read(WRAPPER)
    for marker in (
        "$restoreFailed = $false",
        "$restoreFailed = $true",
        "NETWORK RESTORE REQUIRES OPERATOR ATTENTION",
        "if ($restoreFailed -and $childExit -eq 0) { $childExit = 1 }",
    ):
        assert marker in text, marker


def test_installer_validates_controller_dependencies_before_shim_install() -> None:
    text = read(INSTALLER)
    for marker in (
        "$sourceOperatorSession",
        "$sourceNetworkGuard",
        "$sourceBoundedNative",
        "scripts\\SasFieldPlatform.psm1",
        "scripts\\SasOperatorSession.psm1",
        "scripts\\SasNetworkGuard.psm1",
        "scripts\\SasBoundedNative.psm1",
        "current network-aware runtime dependency",
        "MACHINE_RUNTIME_REFRESH_REQUIRED",
    ):
        assert marker in text, marker


def test_installed_sas_enters_network_aware_wrapper() -> None:
    text = read(INSTALLER)
    for marker in (
        "Invoke-SasNetworkAwareField.ps1",
        "SasNetworkIntent.psm1",
        "$sourceNetworkAwareLauncher",
        "$sourceNetworkIntent",
        "$networkAwareLauncherDestination",
        "$networkIntentDestination",
        'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-SasNetworkAwareField.ps1" %*',
        "VPN lifecycle is not guessed",
    ):
        assert marker in text, marker


def test_documentation_contains_network_matrix_and_canary_rule() -> None:
    text = read(DOC)
    for marker in (
        "## Network canary and automatic return",
        "`sas refresh`",
        "GUEST / INTERNET",
        "PROTECTED NORTHWELL",
        "LOCAL / ANY",
        "`DomainAuthenticated` VPN",
        "saved WLAN",
        "VPN",
        "restore",
        "concurrent",
        "serialized",
    ):
        assert marker in text, marker


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: network intent canary contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
