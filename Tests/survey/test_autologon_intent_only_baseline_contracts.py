#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "scripts" / "SasAutoLogonBaselinePolicy.psm1"
S4U = ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1"
HANDOFF = ROOT / "docs" / "handoff" / "autologon-s4u-field-hardening-2026-07-30.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_policy_accepts_only_unconfigured_or_exact_inert_intent_only_state() -> None:
    text = read(POLICY)
    for marker in (
        "Test-SasAutoLogonFirstInstallBaseline",
        "$status -eq 'not_configured'",
        "$status -ne 'intent_only'",
        "$intent -eq 'Autologon_YES'",
        "$autoAdminLogon.Trim() -in @('','0','0x0')",
        "IsNullOrWhiteSpace($defaultUser)",
        "IsNullOrWhiteSpace($defaultDomain)",
        "IsNullOrWhiteSpace($forceAutoLogon)",
        "IsNullOrWhiteSpace($autoLogonCount)",
        "-not $passwordPresent",
        "-not $expectedUserMatch",
        "$installed.Count -ne 0",
    ):
        assert marker in text, marker


def test_policy_never_collects_or_serializes_password_value() -> None:
    text = read(POLICY)
    assert "default_password_present" in text
    for forbidden in (
        "DefaultPassword).",
        "default_password_value",
        "password_value_collected = $true",
        "credential_collected = $true",
    ):
        assert forbidden.lower() not in text.lower(), forbidden


def test_current_s4u_guard_is_the_integration_point() -> None:
    text = read(S4U)
    assert "function Test-SasS4UCleanBaseline" in text
    assert "KERBEROS_S4U_DIRTY_BASELINE" in text
    assert "Do not reinstall blindly" in text


def test_field_handoff_records_intent_only_baseline_boundary() -> None:
    text = read(HANDOFF).lower()
    assert "dirty autologon baseline" in text or "dirty baseline" in text
    assert "baseline_snapshot.json" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon intent-only baseline contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
