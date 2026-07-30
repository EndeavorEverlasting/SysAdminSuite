#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts" / "SasSoftwareSourceIdentity.psm1"
S4U = ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1"
HANDOFF = ROOT / "docs" / "handoff" / "autologon-s4u-field-hardening-2026-07-30.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_canonical_source_identity_is_fail_closed() -> None:
    text = read(MODULE)
    for marker in (
        "Resolve-SasCanonicalSoftwareSourceIdentity",
        "[System.Net.Dns]::GetHostEntry($alias)",
        "[System.Net.Dns]::GetHostAddresses($canonical)",
        "$sharedAddresses.Count -eq 0",
        "address_overlap_verified = $true",
        "cifs_spn = ('CIFS/{0}' -f $canonical)",
        "canonical_unc_root = ('\\\\{0}\\' -f $canonical)",
        "credential_collected = $false",
        "ticket_bytes_emitted = $false",
        "target_mutation_performed = $false",
    ):
        assert marker in text, marker


def test_field_handoff_preserves_alias_vs_canonical_discovery() -> None:
    text = read(HANDOFF)
    for marker in (
        "SOFTWARE_SOURCE_KERBEROS_READY_FQDN_ONLY",
        "short CIFS ticket",
        "canonical FQDN",
        "same approved installer",
        "target mutation remained false",
    ):
        assert marker.lower() in text.lower(), marker


def test_s4u_still_requires_explicit_source_ticket_before_source_read() -> None:
    text = read(S4U)
    ticket = text.index("$shareTicket = Request-SasS4UKerberosTicket")
    ticket_gate = text.index("if (-not [bool]$shareTicket.issued)")
    source_read = text.index("$sourcePath = $package.source_root + $package.installer_relative_path")
    assert ticket < ticket_gate < source_read
    assert "KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: software source identity contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
