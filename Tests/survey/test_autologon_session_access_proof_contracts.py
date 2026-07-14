#!/usr/bin/env python3
"""Static contracts for the real AutoLogon-session access proof."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonSessionAccessProof.ps1"
DOC = ROOT / "docs" / "AUTOLOGON_SESSION_ACCESS_PROOF.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_entrypoint_and_runbook_exist() -> None:
    assert SCRIPT.exists()
    assert DOC.exists()


def test_real_current_identity_is_required_before_path_tests() -> None:
    content = read(SCRIPT)
    identity = "[System.Security.Principal.WindowsIdentity]::GetCurrent().Name"
    gate = "if (-not $identityMatch)"
    loop = "foreach ($literalPath in $validatedPaths)"
    assert identity in content
    assert gate in content
    assert content.index(gate) < content.rindex(loop)
    assert "SKIPPED_IDENTITY_MISMATCH" in content
    assert "IDENTITY_MISMATCH" in content


def test_paths_are_explicit_and_bounded() -> None:
    content = read(SCRIPT)
    required = (
        "[ValidateRange(1, 12)]",
        "Path count $($result.Count) exceeds MaxPaths",
        "WildcardPattern]::ContainsWildcardCharacters",
        "Path cannot contain parent traversal segments",
        "drive-rooted local/mapped path or a complete UNC share path",
    )
    for fragment in required:
        assert fragment in content, f"missing path boundary: {fragment}"


def test_live_directory_open_does_not_return_entry_names_or_file_contents() -> None:
    content = read(SCRIPT)
    assert "[System.IO.Directory]::EnumerateFileSystemEntries" in content
    assert "path_contents_recorded = $false" in content
    forbidden = (
        "Get-Content -LiteralPath $literalPath",
        "Select-Object -ExpandProperty Name",
        "directory_entries =",
        "file_contents =",
    )
    lowered = content.lower()
    for fragment in forbidden:
        assert fragment.lower() not in lowered


def test_write_probe_is_explicit_unique_non_overwriting_and_cleaned() -> None:
    content = read(SCRIPT)
    required = (
        "[switch]$AllowWriteProbe",
        ".sas-autologon-access-{0}.tmp",
        "[System.IO.FileMode]::CreateNew",
        "Remove-Item -LiteralPath $markerPath",
        "Create and immediately remove one uniquely named zero-byte access marker",
        "cleanup_succeeded",
    )
    for fragment in required:
        assert fragment in content, f"missing write/cleanup contract: {fragment}"
    assert "FileMode]::OpenOrCreate" not in content
    assert "FileMode]::Create" not in content.replace("FileMode]::CreateNew", "")


def test_retry_window_is_bounded_without_background_monitoring() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    assert "[ValidateRange(0, 5)]" in content
    assert "[ValidateRange(1, 30)]" in content
    assert "Start-Sleep -Seconds $RetryDelaySeconds" in content
    assert "no continuous monitoring or background retry process" in doc
    forbidden = ("while ($true)", "Register-ScheduledTask", "New-Service")
    for fragment in forbidden:
        assert fragment.lower() not in content.lower()


def test_no_credentials_impersonation_or_persistence() -> None:
    content = read(SCRIPT)
    required = (
        "credentials_collected = $false",
        "impersonation_used = $false",
        "persistence_created = $false",
    )
    for fragment in required:
        assert fragment in content
    forbidden = (
        "[pscredential]",
        "Get-Credential",
        "ConvertTo-SecureString",
        "WindowsImpersonationContext",
        "Register-ScheduledTask",
        "New-ScheduledTask",
        "New-Service",
        "CurrentVersion\\Run",
    )
    lowered = content.lower()
    for fragment in forbidden:
        assert fragment.lower() not in lowered, f"forbidden session-proof behavior: {fragment}"


def test_decisions_and_runtime_fixture_boundary_are_explicit() -> None:
    content = read(SCRIPT)
    for decision in (
        "SESSION_ACCESS_CONFIRMED",
        "SESSION_ACCESS_PARTIAL",
        "SESSION_ACCESS_FAILED",
        "IDENTITY_MISMATCH",
    ):
        assert decision in content
    assert "runtime_proof = (-not $FixtureMode -and $allConfirmed)" in content
    assert "fixture_mode = [bool]$FixtureMode" in content


def test_runbook_requires_real_session_application_and_share_proof() -> None:
    content = read(DOC)
    required = (
        "inside the real AutoLogon desktop session",
        "both share and NTFS enforcement",
        "real application read/write/save behavior",
        "mapped drive or UNC roundabout",
        "no leftover `.sas-autologon-access-*.tmp` marker",
    )
    for fragment in required:
        assert fragment in content, f"missing runtime gate: {fragment}"


def main() -> None:
    tests = [
        test_entrypoint_and_runbook_exist,
        test_real_current_identity_is_required_before_path_tests,
        test_paths_are_explicit_and_bounded,
        test_live_directory_open_does_not_return_entry_names_or_file_contents,
        test_write_probe_is_explicit_unique_non_overwriting_and_cleaned,
        test_retry_window_is_bounded_without_background_monitoring,
        test_no_credentials_impersonation_or_persistence,
        test_decisions_and_runtime_fixture_boundary_are_explicit,
        test_runbook_requires_real_session_application_and_share_proof,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon session access proof contracts")


if __name__ == "__main__":
    main()
