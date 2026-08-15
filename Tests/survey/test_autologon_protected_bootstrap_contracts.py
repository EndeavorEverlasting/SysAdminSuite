#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"
PREPARE = ROOT / "scripts" / "Prepare-SasAutoLogonShortRuntime.ps1"
REFRESH = ROOT / "scripts" / "Refresh-SasOperatorCommand.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_protected_runtime_is_prepared_and_commit_pinned_without_checkout_mutation() -> None:
    text = read(BOOTSTRAP)
    assert "[string]$RuntimeRoot = 'C:\\SASAL'" in text
    assert "autologon-short-runtime.json" in text
    assert "prepared_commit" in text
    assert "AUTOLOGON_RUNTIME_COMMIT_MISMATCH" in text
    assert "Git network I/O: DISABLED" in text
    assert "Checkout mutation: DISABLED" in text
    assert "Protected-side repository network activity: NONE" in text
    lowered = text.lower()
    for forbidden in (
        "git clone",
        "git fetch",
        "git pull",
        "checkout --detach",
        "reset --hard",
        "clean -fd",
        "ls-remote",
        "refs/heads/main:refs/remotes/origin/main",
    ):
        assert forbidden not in lowered, forbidden


def test_guest_refresh_owns_remote_acquisition_and_seals_runtime() -> None:
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

    gate = refresh.index("$preRefreshNetwork = Get-SasOperatorNetworkClassification")
    rejection = refresh.index("SAS_REFRESH_REMOTE_GIT_BLOCKED")
    clone = refresh.index("@('clone','--origin','origin'")
    remote_fetch = refresh.index("@('fetch','--no-tags','--prune','origin'")
    stage = refresh.index("STAGING SHORT AUTOLOGON RUNTIME BEFORE LEAVING GUEST")
    assert gate < rejection < clone < remote_fetch < stage


def test_protected_runtime_verifies_clean_state_and_has_no_remote() -> None:
    text = read(BOOTSTRAP)
    assert "@('status','--porcelain')" in text
    assert "AUTOLOGON_RUNTIME_DIRTY" in text
    assert "@('remote')" in text
    assert "AUTOLOGON_RUNTIME_UNSEALED" in text
    assert "PASS: no remote Git endpoint is configured in the protected runtime." in text
    assert "Nothing was reset or cleaned" in text


def test_legacy_checkout_is_explicit_evidence_fallback_only() -> None:
    text = read(BOOTSTRAP)
    assert "Legacy evidence fallback is opt-in only" in text
    assert "if (-not [string]::IsNullOrWhiteSpace($LegacyEvidenceRoot))" in text
    assert "$env:SAS_REPO_ROOT = $legacyRoot" in text
    assert "Legacy evidence fallback: disabled." in text
    assert "GetFolderPath" not in text
    assert "Desktop\\dev" not in text
    assert "$env:SAS_NETWORK_GUARD_CONFIG = $legacyNetworkConfig" not in text


def test_native_git_stderr_is_not_promoted_to_terminating_powershell_error() -> None:
    for path in (BOOTSTRAP, PREPARE, REFRESH):
        text = read(path)
        assert "2> $stderrPath" in text
        assert "$ErrorActionPreference = 'Continue'" in text
        assert "$exitCode = [int]$LASTEXITCODE" in text
        assert "2>&1" not in text


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


def test_crash_safe_runner_and_parser_gate_remain_required() -> None:
    text = read(BOOTSTRAP)
    assert "Invoke-SasAutoLogonCrashSafeFieldRun.ps1" in text
    assert "-RepositoryRoot $RuntimeRoot -ConfirmDeployment" in text
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
