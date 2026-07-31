#!/usr/bin/env python3
"""Contracts for the local-only double-click return from protected Wi-Fi."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Return-SasOperatorToPreviousNetwork.ps1"
CMD = ROOT / "Switch-Back-To-Previous-Network.cmd"
REFRESH = ROOT / "scripts" / "Refresh-SasOperatorCommand.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_double_click_surface_calls_only_repo_owned_local_network_return() -> None:
    text = read(CMD)
    assert 'set "SCRIPT_DIR=%~dp0"' in text
    assert '"%SCRIPT_DIR%scripts\\Return-SasOperatorToPreviousNetwork.ps1"' in text
    assert "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass" in text
    assert "pause" in text.lower()
    assert "exit /b" in text.lower()
    for forbidden in ("schtasks", "\\\\", "shutdown", "WPJ", "ADMIN$"):
        assert forbidden.lower() not in text.lower(), forbidden


def test_refresh_records_a_dedicated_guest_return_network_bookmark() -> None:
    text = read(REFRESH)
    for marker in (
        "return-network.json",
        "sas-operator-return-network/v1",
        "Get-SasOperatorNetworkClassification -RepoRoot $fieldReady",
        "$currentNetwork.classification -ne 'GUEST_INTERNET'",
        "label=[string]$currentNetwork.label",
        "target_contact_performed=$false",
        "target_mutation_performed=$false",
        "secret_material_collected=$false",
        "RETURN NETWORK: $($currentNetwork.label)",
    ):
        assert marker in text, marker
    bookmark = text.index("$returnBookmark=[pscustomobject]")
    next_network = text.index("$nextNetwork=if", bookmark)
    assert bookmark < next_network


def test_return_prefers_dedicated_bookmark_and_has_legacy_fallback() -> None:
    text = read(SCRIPT)
    for marker in (
        "return-network.json",
        "sas-operator-return-network/v1",
        "$bookmarkSource='return-network.json'",
        "$bookmarkSource -eq 'none'",
        "last_network_classification",
        "last_network_label",
        "$previousClassification -ne 'GUEST_INTERNET'",
        "Test-SasNorthwellWifiSsid -Ssid $previousLabel",
        "not a saved Windows WLAN profile",
        "SAS_OPERATOR_RETURNED_TO_PREVIOUS_NETWORK",
    ):
        assert marker in text, marker
    dedicated = text.index("Test-Path -LiteralPath $returnBookmarkPath")
    fallback = text.index("last_network_classification", dedicated)
    assert dedicated < fallback


def test_return_uses_only_saved_profile_and_bounded_local_netsh() -> None:
    text = read(SCRIPT)
    for marker in (
        "SasBoundedNative.psm1",
        "Invoke-SasBoundedNative -FilePath $netsh -Arguments @('wlan','show','profiles')",
        "Invoke-SasBoundedNative -FilePath $netsh -Arguments @('wlan','connect'",
        "NativeTimeoutSeconds",
        "TransitionTimeoutSeconds",
        "Get-SasCurrentWifiSsid",
        "current_network_classification='GUEST_INTERNET'",
        "current_network_label=$previousLabel",
    ):
        assert marker in text, marker
    for forbidden in (
        "key=clear",
        "keymaterial",
        "password",
        "credential",
        "Get-Credential",
        "Test-NetConnection",
        "Invoke-Command",
    ):
        assert forbidden.lower() not in text.lower(), forbidden


def test_return_is_explicitly_target_free_and_contains_no_live_literals() -> None:
    text = (read(SCRIPT) + "\n" + read(CMD)).lower()
    assert "target contact: no" in text
    assert "target mutation: no" in text
    assert "no target was contacted or mutated" in text
    for forbidden in ("wpj075opr046", "pa_rperez26", "nslijhs-wab"):
        assert forbidden not in text, forbidden


def test_refresh_requires_network_return_surface_in_every_field_ready_checkout() -> None:
    text = read(REFRESH)
    assert "Switch-Back-To-Previous-Network.cmd" in text
    assert "scripts\\Return-SasOperatorToPreviousNetwork.ps1" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: operator network return contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
