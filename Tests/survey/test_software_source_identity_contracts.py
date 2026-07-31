#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts" / "SasSoftwareSourceIdentity.psm1"
S4U = ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1"
HANDOFF = ROOT / "docs" / "handoff" / "autologon-s4u-field-hardening-2026-07-30.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


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


def test_field_handoff_preserves_alias_authority_and_verified_canonical_identity() -> None:
    text = read(HANDOFF).lower()
    for marker in (
        "software-source identity",
        "approved catalog alias remains the source authority",
        "canonical fqdn and approved alias share resolved address evidence",
        "canonical `cifs/<fqdn>` spn",
        "canonical unc identity",
        "no credentials or ticket bytes are collected",
    ):
        assert marker in text, marker


def test_s4u_consumes_durable_source_identity_then_ticket_before_canonical_source_read() -> None:
    text = read(S4U)
    module_import = text.index("SasSoftwareSourceIdentity.psm1")
    resolve = text.index("Resolve-SasCanonicalSoftwareSourceIdentity -ApprovedServer $package.source_server", module_import)
    overlap_gate = text.index("if (-not [bool]$sourceIdentity.address_overlap_verified)", resolve)
    ticket = text.index("$shareTicket = Request-SasS4UKerberosTicket -Spn ([string]$sourceIdentity.cifs_spn)", overlap_gate)
    ticket_gate = text.index("if (-not [bool]$shareTicket.issued)", ticket)
    canonical_root = text.index("$canonicalSourceRoot = ([string]$sourceIdentity.canonical_unc_root).TrimEnd('\\') + '\\'", ticket_gate)
    source_read = text.index("$sourcePath = $canonicalSourceRoot + $package.installer_relative_path", canonical_root)
    assert module_import < resolve < overlap_gate < ticket < ticket_gate < canonical_root < source_read
    assert "KERBEROS_S4U_SOFTWARE_SOURCE_IDENTITY_BLOCKED" in text
    assert "KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED" in text
    assert "$sourcePath = $package.source_root + $package.installer_relative_path" not in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: software source identity contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
