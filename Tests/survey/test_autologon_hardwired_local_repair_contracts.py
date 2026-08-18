#!/usr/bin/env python3
"""Static contracts for the bounded hardwired AutoLogon local-repair lane."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonHardwiredLocalRepair.ps1"
CMD = ROOT / "Run-AutoLogonHardwiredLocalRepair.cmd"


def read(path: Path) -> str:
    assert path.is_file(), f"missing hardwired repair surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_hardwired_repair_requires_exact_local_detached_commit_without_git() -> None:
    text = read(SCRIPT)
    for marker in (
        "Resolve-SasDetachedHeadWithoutGit",
        "source must be an already-local drive path",
        "source must be an isolated detached worktree",
        "source HEAD mismatch",
        "Expected=$ExpectedCommit Source=$sourceHead",
        "source_head_verified_without_git = $true",
    ):
        assert marker in text, marker
    lowered = text.lower()
    for forbidden in (
        "& git",
        "git.exe",
        "git fetch",
        "git pull",
        "git clone",
        "ls-remote",
        "github.com",
    ):
        assert forbidden not in lowered, forbidden


def test_hardwired_repair_proves_domain_authenticated_non_wifi_before_copy_or_target() -> None:
    text = read(SCRIPT)
    assert "Enable-SasNorthwellVpnNetworkGuard.ps1" in text
    assert "SAS_VPN_NETWORK_GUARD_READY" in text
    assert "target_contact_performed" in text
    assert "target_mutation_performed" in text
    assert "$env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig" in text
    network = text.index("PROVING HARDWIRED DOMAIN-AUTHENTICATED NORTHWELL POSTURE")
    copy = text.index("LOCAL-ONLY HARDWIRED RUNTIME REPAIR - NO GIT COMMANDS")
    deploy = text.index("STARTING EXISTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION")
    assert network < copy < deploy


def test_repair_is_bounded_by_previous_sealed_tracked_file_list_and_hash_parity() -> None:
    text = read(SCRIPT)
    for marker in (
        "previous sealed runtime manifest is missing",
        "$previousEntries = @($previousManifest.tracked_file_hashes)",
        "runtime_remotes_removed",
        "protected_bootstrap_git_network_allowed",
        "Copy-Item -LiteralPath $sourcePath -Destination $runtimePath -Force",
        "Get-SasSha256Hex -LiteralPath $sourcePath",
        "Get-SasSha256Hex -LiteralPath $runtimePath",
        "local copy hash mismatch",
        "tracked_file_hash_algorithm = 'SHA256'",
    ):
        assert marker in text, marker


def test_repair_refreshes_shim_and_writes_explicit_non_guest_manifest() -> None:
    text = read(SCRIPT)
    for marker in (
        "Install-SasPortableLauncher.ps1",
        "sas-autologon-short-runtime/hardwired-repair-v1",
        "preparation_network_classification = 'PROTECTED_NORTHWELL'",
        "preparation_git_transport = 'NONE'",
        "preparation_remote_git_performed = $false",
        "Remote Git performed: NO",
        "Target contact during repair: NO",
    ):
        assert marker in text, marker


def test_repair_enters_existing_crash_safe_autologon_only_transaction() -> None:
    text = read(SCRIPT)
    for marker in (
        "Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "$env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = $ComputerName.Trim()",
        "-RepositoryRoot $RuntimeRoot -RepositoryHead $ExpectedCommit -ConfirmDeployment",
        "System.Management.Automation.Language.Parser",
    ):
        assert marker in text, marker
    assert "Deploy-CybernetSoftware" not in text
    assert "Deploy-CybernetClinicalCore" not in text


def test_cmd_is_short_and_forwards_exact_target_and_commit() -> None:
    text = read(CMD)
    for marker in (
        "Usage: Run-AutoLogonHardwiredLocalRepair.cmd HOST EXPECTED_COMMIT",
        "Invoke-SasAutoLogonHardwiredLocalRepair.ps1",
        "-ComputerName \"%SAS_TARGET%\"",
        "-ExpectedCommit \"%SAS_EXPECTED%\"",
        "-ConfirmDeployment",
        "Git commands: NONE",
        "Remote repository access: NONE",
        "Clinical-core deployment: NONE",
    ):
        assert marker in text, marker


def test_no_live_target_secret_or_private_operator_literal() -> None:
    combined = "\n".join(read(path) for path in (SCRIPT, CMD)).lower()
    for forbidden in (
        "wpj075opr046",
        "pa_rperez26",
        "defaultpassword",
        "password=",
        "nslijhs.net",
    ):
        assert forbidden not in combined, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon hardwired local repair contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
