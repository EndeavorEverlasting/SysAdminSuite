#!/usr/bin/env python3
"""Static contracts for the AutoLogon file-access posture lane."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonFileAccessPosture.ps1"
DOC = ROOT / "docs" / "AUTOLOGON_FILE_ACCESS_POSTURE.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_entrypoint_and_runbook_exist() -> None:
    assert SCRIPT.exists()
    assert DOC.exists()


def test_modes_targets_and_local_path_bounds_are_explicit() -> None:
    content = read(SCRIPT)
    required = (
        "[ValidateSet('Before', 'After', 'Assess')]",
        "[ValidateRange(1, 25)]",
        "[ValidateRange(1, 12)]",
        "PermissionPath must be target-local",
        "PermissionPath cannot contain wildcard characters",
        "PermissionPath cannot contain parent traversal segments",
        "No explicit targets were supplied",
    )
    for fragment in required:
        assert fragment in content, f"missing bounded-input contract: {fragment}"


def test_acl_posture_is_read_only_and_does_not_enumerate_contents() -> None:
    content = read(SCRIPT)
    required = (
        "Get-Acl -LiteralPath",
        "path_contents_enumerated = $false",
        "no_directory_content_enumeration",
        "target_mutation_performed = $false",
        "target_side_sysadminsuite_artifacts_written = $false",
        "survey/output/autologon_file_access",
        "Assert-SasApprovedOutputPath",
        "Assert-SasNorthwellWifi",
    )
    for fragment in required:
        assert fragment in content, f"missing read-only ACL contract: {fragment}"

    forbidden = (
        "Get-ChildItem -LiteralPath $Path -Recurse",
        "Get-ChildItem -LiteralPath $Path -File",
        "Copy-Item -ToSession",
        "Set-Acl",
        "icacls.exe /grant",
        "takeown.exe",
        "New-ItemProperty",
        "Set-ItemProperty",
        "Remove-ItemProperty",
        "Clear-EventLog",
        "wevtutil cl",
    )
    lowered = content.lower()
    for fragment in forbidden:
        assert fragment.lower() not in lowered, f"forbidden mutation/content-enumeration fragment: {fragment}"


def test_relevant_acl_signals_and_review_states_are_reported() -> None:
    content = read(SCRIPT)
    required = (
        "allow_read_signal",
        "allow_write_signal",
        "deny_signal",
        "explicit_deny_review",
        "no_relevant_grant_observed",
        "acl_unavailable",
        "review_required",
        "expected_identity_rule_count",
    )
    for fragment in required:
        assert fragment in content, f"missing ACL posture signal: {fragment}"


def test_profile_redirect_and_mapped_drive_metadata_are_bounded() -> None:
    content = read(SCRIPT)
    required = (
        "Win32_UserProfile",
        "User Shell Folders",
        "Registry::HKEY_USERS\\$Sid\\Network",
        "shell_folder_redirections",
        "mapped_network_drives",
        "redirected_shell_folder_count",
        "mapped_drive_count",
        "contacted = $false",
    )
    for fragment in required:
        assert fragment in content, f"missing profile/share-roundabout signal: {fragment}"


def test_share_and_effective_access_are_not_claimed() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    required = (
        "share_paths_contacted = $false",
        "effective_access_proven = $false",
        "effective_access_not_proven",
        "no_share_path_contact",
    )
    for fragment in required:
        assert fragment in content, f"missing access-proof boundary: {fragment}"

    assert "does not prove effective access" in doc
    assert "does not contact those shares" in doc


def test_before_after_delta_has_access_specific_decisions() -> None:
    content = read(SCRIPT)
    required = (
        "ACCESS_POSTURE_IMPROVED",
        "NO_MATERIAL_ACCESS_CHANGE",
        "ACCESS_POSTURE_REVIEW",
        "ACCESS_REGRESSION_REVIEW",
        "INCONCLUSIVE",
        "access_posture_changes",
        "sas-autologon-file-access-delta/v1",
    )
    for fragment in required:
        assert fragment in content, f"missing access-delta decision: {fragment}"


def test_fixture_models_profile_and_file_share_roundabout() -> None:
    content = read(SCRIPT)
    required = (
        "fixture_mode",
        "no_network_activity",
        r"\\fileserver\autologon",
        "path_kind = 'unc'",
        "ACCESS_POSTURE_IMPROVED",
    )
    for fragment in required:
        assert fragment in content, f"missing fixture contract: {fragment}"


def test_runbook_connects_access_posture_to_autologon_pilot() -> None:
    content = read(DOC)
    required = (
        "Before AutoLogon deployment",
        "After AutoLogon deployment",
        "same approved target manifest",
        "explicit deny",
        "expected profile",
        "shell-folder redirection",
        "mapped drive",
        "real AutoLogon session",
        "local application directories",
    )
    for fragment in required:
        assert fragment in content, f"missing runbook requirement: {fragment}"


def main() -> None:
    tests = [
        test_entrypoint_and_runbook_exist,
        test_modes_targets_and_local_path_bounds_are_explicit,
        test_acl_posture_is_read_only_and_does_not_enumerate_contents,
        test_relevant_acl_signals_and_review_states_are_reported,
        test_profile_redirect_and_mapped_drive_metadata_are_bounded,
        test_share_and_effective_access_are_not_claimed,
        test_before_after_delta_has_access_specific_decisions,
        test_fixture_models_profile_and_file_share_roundabout,
        test_runbook_connects_access_posture_to_autologon_pilot,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon file-access posture contracts")


if __name__ == "__main__":
    main()
