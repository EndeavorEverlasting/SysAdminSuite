#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"
PREPARE = ROOT / "scripts" / "Prepare-SasAutoLogonShortRuntime.ps1"
REFRESH = ROOT / "scripts" / "Refresh-SasOperatorCommand.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_protected_runtime_is_prepared_and_commit_pinned_without_git() -> None:
    text = read(BOOTSTRAP)
    assert "[string]$RuntimeRoot = 'C:\\SASAL'" in text
    assert "autologon-short-runtime.json" in text
    assert "sas-autologon-short-runtime/v2" in text
    assert "prepared_commit" in text
    assert "AUTOLOGON_RUNTIME_COMMIT_MISMATCH" in text
    assert "Git activity after protected-network transition: NONE" in text
    assert "Checkout mutation: DISABLED" in text
    assert "Protected-side Git activity: NONE" in text
    for forbidden in (
        "Resolve-SasGitExecutable",
        "Invoke-SasLocalGit",
        "Get-SasLocalGitScalar",
        "& git",
        "git.exe",
        "rev-parse",
        "@('status','--porcelain')",
        "@('remote')",
        "git clone",
        "git fetch",
        "git pull",
        "checkout --detach",
        "reset --hard",
        "clean -fd",
        "ls-remote",
    ):
        assert forbidden not in text, forbidden


def test_guest_refresh_owns_remote_acquisition_and_creates_hash_seal() -> None:
    refresh = read(REFRESH)
    prepare = read(PREPARE)
    assert "$syncCache = Join-Path $operatorStateRoot 'sync-cache'" in refresh
    assert "SAS_REFRESH_REMOTE_GIT_BLOCKED" in refresh
    assert "Creating Guest-only SysAdminSuite sync cache" in refresh
    assert "Refreshing Guest-only sync cache" in refresh
    assert "STAGING SHORT AUTOLOGON RUNTIME BEFORE LEAVING GUEST" in refresh
    assert "-RuntimeRoot 'C:\\SASAL'" in refresh
    assert "SAS_AUTOLOGON_SHORT_RUNTIME_READY" in prepare
    assert "LOCAL_FILESYSTEM_ONLY" in prepare
    assert "runtime_remotes_removed = $true" in prepare
    assert "protected_bootstrap_git_network_allowed = $false" in prepare
    assert "remote','remove'" in prepare
    assert "sas-autologon-short-runtime/v2" in prepare
    assert "tracked_file_hash_algorithm = 'SHA256'" in prepare
    assert "$trackedFileHashes = @()" in prepare
    assert "$trackedFileHashCount = $trackedFileHashes.Count" in prepare
    assert "tracked_file_count = $trackedFileHashCount" in prepare
    assert "tracked_file_hashes = $trackedFileHashes" in prepare
    assert "System.Collections.Generic.List[object]" not in prepare
    assert "tracked_file_hashes = @($trackedFileHashes)" not in prepare
    assert "@('ls-files')" in prepare
    assert "Get-FileHash -LiteralPath $fullPath -Algorithm SHA256" in prepare
    assert "Protected-side Git activity: NONE" in prepare

    gate = refresh.index("$preRefreshNetwork = Get-SasOperatorNetworkClassification")
    rejection = refresh.index("SAS_REFRESH_REMOTE_GIT_BLOCKED")
    clone = refresh.index("@('clone','--origin','origin'")
    remote_fetch = refresh.index("@('fetch','--no-tags','--prune','origin'")
    stage = refresh.index("STAGING SHORT AUTOLOGON RUNTIME BEFORE LEAVING GUEST")
    assert gate < rejection < clone < remote_fetch < stage


def test_protected_runtime_verifies_sealed_tracked_files_with_filesystem_hashing() -> None:
    text = read(BOOTSTRAP)
    assert "tracked_file_hash_algorithm" in text
    assert "tracked_file_hashes" in text
    assert "tracked_file_count" in text
    assert "Get-FileHash -LiteralPath $fullPath -Algorithm SHA256" in text
    assert "AUTOLOGON_RUNTIME_SEAL_INVALID" in text
    assert "AUTOLOGON_RUNTIME_SEAL_MISMATCH" in text
    assert "tracked runtime file changed after Guest staging" in text
    assert "PASS: sealed tracked runtime content verified without Git" in text
    assert "staging manifest records runtime remotes removed before protected transition" in text


def test_legacy_checkout_is_explicit_evidence_fallback_only() -> None:
    text = read(BOOTSTRAP)
    assert "Legacy evidence fallback is opt-in only" in text
    assert "if (-not [string]::IsNullOrWhiteSpace($LegacyEvidenceRoot))" in text
    assert "$env:SAS_REPO_ROOT = $legacyRoot" in text
    assert "Legacy evidence fallback: disabled." in text
    assert "GetFolderPath" not in text
    assert "Desktop\\dev" not in text
    assert "$env:SAS_NETWORK_GUARD_CONFIG = $legacyNetworkConfig" not in text


def test_native_git_stderr_handling_remains_guest_side_only() -> None:
    for path in (PREPARE, REFRESH):
        text = read(path)
        assert "2> $stderrPath" in text
        assert "$ErrorActionPreference = 'Continue'" in text
        assert "$exitCode = [int]$LASTEXITCODE" in text
        assert "2>&1" not in text
    bootstrap = read(BOOTSTRAP)
    assert "2> $stderrPath" not in bootstrap
    assert "Resolve-SasGitExecutable" not in bootstrap


def test_vpn_authority_and_canonical_guard_still_own_protected_admission() -> None:
    text = read(BOOTSTRAP)
    assert "Enable-SasNorthwellVpnNetworkGuard.ps1" in text
    assert "$authority = @(& $networkBootstrap -ConfirmVpnPosture) | Select-Object -Last 1" in text
    assert "SAS_VPN_NETWORK_GUARD_READY" in text
    assert "$env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig" in text
    assert "target_contact_performed" in text
    assert "target_mutation_performed" in text
    assert "Confirm-SasNorthwellNetwork.ps1" in text
    assert "canonical field guard will independently verify" in text.lower()
    assert "PROVING NETWORK BEFORE CANONICAL TARGET AUTHORIZATION" in text


def test_exact_canonical_target_authorization_precedes_crash_safe_transaction() -> None:
    text = read(BOOTSTRAP)
    assert "SasTargetNameResolution.psm1" in text
    assert "Set-SasHostEligibilityLocalTarget.ps1" in text
    assert "-Target $resolvedAuthorizationTarget -ExecContext remote" in text
    assert "-ConfirmLocalAuthorization -PassThru" in text
    assert "Canonical target authorized: $resolvedAuthorizationTarget" in text

    network = text.index("PROVING NETWORK BEFORE CANONICAL TARGET AUTHORIZATION")
    resolve = text.index("Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName")
    authorize = text.index("& $hostAuthorizer -Target $resolvedAuthorizationTarget")
    deploy = text.index("PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION")
    assert network < resolve < authorize < deploy


def test_crash_safe_runner_receives_sealed_commit_and_parser_gate_remains_required() -> None:
    text = read(BOOTSTRAP)
    assert "Invoke-SasAutoLogonCrashSafeFieldRun.ps1" in text
    assert "-RepositoryRoot $RuntimeRoot -RepositoryHead $preparedCommit -ConfirmDeployment" in text
    assert "last-autologon-field-run.json" in text
    assert "System.Management.Automation.Language.Parser" in text
    assert "field-proof-worktrees" not in text


def test_no_live_target_secret_or_private_operator_literal() -> None:
    combined = "\n".join(read(path) for path in (BOOTSTRAP, PREPARE, REFRESH)).lower()
    for forbidden in (
        "wpj075",
        "nslijhs.net",
        "pa_rperez26",
        "onedrive - northwell",
        "defaultpassword",
        "password=",
    ):
        assert forbidden not in combined, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon protected bootstrap contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
