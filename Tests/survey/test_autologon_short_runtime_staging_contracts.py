#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREPARE = ROOT / "scripts" / "Prepare-SasAutoLogonShortRuntime.ps1"
BOOTSTRAP = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"
LAUNCHER = ROOT / "scripts" / "SasPortableLauncher.ps1"
DOC = ROOT / "docs" / "GUEST_SYNC_TO_PROTECTED_DEPLOYMENT.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_prepare_is_guest_only_local_transport_and_hash_sealed() -> None:
    text = read(PREPARE)
    assert "GUEST_INTERNET" in text
    assert "AUTOLOGON_RUNTIME_STAGE_BLOCKED" in text
    assert "LOCAL_FILESYSTEM_ONLY" in text
    assert "runtime_remotes_removed = $true" in text
    assert "protected_bootstrap_git_network_allowed = $false" in text
    assert "target_contact_performed = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "SAS_AUTOLOGON_SHORT_RUNTIME_READY" in text
    assert "sas-autologon-short-runtime/v2" in text
    assert "tracked_file_hash_algorithm = 'SHA256'" in text
    assert "tracked_file_count = $trackedFileHashes.Count" in text
    assert "tracked_file_hashes = @($trackedFileHashes)" in text
    assert "@('ls-files')" in text
    assert "Get-FileHash -LiteralPath $fullPath -Algorithm SHA256" in text
    lowered = text.lower()
    for forbidden in (
        "github.com",
        "ls-remote",
        "fetch origin",
        "pull origin",
        "clone https://",
        "invoke-command",
        "test-netconnection",
    ):
        assert forbidden not in lowered, forbidden


def test_prepare_preserves_dirty_runtime_and_removes_all_remotes() -> None:
    text = read(PREPARE)
    assert "Short runtime contains local work. Nothing was reset or cleaned" in text
    assert "remote','remove'" in text
    assert "Short runtime still has a Git remote" in text
    assert "reset --hard" not in text
    assert "clean -fd" not in text


def test_guest_git_capture_treats_empty_stderr_as_empty_string() -> None:
    text = read(PREPARE)
    assert "$stdout = @()" in text
    assert "$exitCode = 0" in text
    assert "$stderrRaw = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue" in text
    assert "if ($null -ne $stderrRaw)" in text
    assert "$stderr = ([string]$stderrRaw).Trim()" in text
    assert "$stderrRaw.Trim()" not in text
    assert "$stdoutLines = @($stdout | ForEach-Object { [string]$_ })" in text
    assert "if ($stdoutLines.Count -gt 0)" in text
    assert "return @($stdoutLines)" in text
    assert "return ([string]$value).Trim()" in text


def test_protected_bootstrap_is_git_free_and_verifies_guest_seal() -> None:
    text = read(BOOTSTRAP)
    assert "autologon-short-runtime.json" in text
    assert "sas-autologon-short-runtime/v2" in text
    assert "Git activity after protected-network transition: NONE" in text
    assert "Checkout mutation: DISABLED" in text
    assert "runtime_git_transport" in text
    assert "LOCAL_FILESYSTEM_ONLY" in text
    assert "runtime_remotes_removed" in text
    assert "protected_bootstrap_git_network_allowed" in text
    assert "tracked_file_hash_algorithm" in text
    assert "tracked_file_hashes" in text
    assert "tracked_file_count" in text
    assert "Get-FileHash -LiteralPath $fullPath -Algorithm SHA256" in text
    assert "AUTOLOGON_RUNTIME_NOT_PREPARED" in text
    assert "AUTOLOGON_RUNTIME_SEAL_INVALID" in text
    assert "AUTOLOGON_RUNTIME_SEAL_MISMATCH" in text
    assert "PASS: sealed tracked runtime content verified without Git" in text
    assert "Protected-side Git activity: NONE" in text
    assert "PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION" in text

    for forbidden in (
        "Resolve-SasGitExecutable",
        "Invoke-SasLocalGit",
        "Get-SasLocalGitScalar",
        "git.exe",
        "rev-parse",
        "@('status','--porcelain')",
        "@('remote')",
        "git fetch",
        "git clone",
        "git pull",
        "checkout --detach",
        "reset --hard",
        "clean -fd",
        "ls-remote",
        "repo_url",
    ):
        assert forbidden not in text, forbidden


def test_protected_bootstrap_legacy_evidence_fallback_is_explicit_only() -> None:
    text = read(BOOTSTRAP)
    assert "Legacy evidence fallback is opt-in only" in text
    assert "if (-not [string]::IsNullOrWhiteSpace($LegacyEvidenceRoot))" in text
    assert "Legacy evidence fallback: disabled." in text
    assert "GetFolderPath" not in text
    assert "Desktop\\dev" not in text
    assert "OG Laptop Backup" not in text


def test_native_git_stderr_handling_is_guest_side_only() -> None:
    bootstrap = read(BOOTSTRAP)
    prepare = read(PREPARE)
    assert "2> $stderrPath" in prepare
    assert "$ErrorActionPreference = 'Continue'" in prepare
    assert "2>&1" not in prepare
    assert "2> $stderrPath" not in bootstrap
    assert "$ErrorActionPreference = 'Continue'" not in bootstrap
    assert "Resolve-SasGitExecutable" not in bootstrap
    assert "2>&1" not in bootstrap


def test_sas_autologon_remote_consumes_sealed_runtime() -> None:
    text = read(LAUNCHER)
    assert "autologon-short-runtime.json" in text
    assert "Resolve-SasPreparedAutoLogonRuntime" in text
    assert "& $runtime.bootstrap $target $runtime.commit" in text
    assert "Protected-side Git network I/O: NONE" in text


def test_runbook_declares_two_phase_network_boundary() -> None:
    text = read(DOC).lower()
    assert "guest / internet" in text
    assert "sync-cache" in text
    assert "field-ready" in text
    assert "protected" in text
    assert "sas refresh" in text
    assert "sas autologon remote" in text
    assert "c:\\sasal" in text
    assert "git" in text


def test_no_live_target_or_private_operator_literals() -> None:
    combined = "\n".join(read(path) for path in (PREPARE, BOOTSTRAP, LAUNCHER))
    lowered = combined.lower()
    for forbidden in ("wpj075", "nslijhs.net", "pa_rperez26", "onedrive - northwell", "password="):
        assert forbidden not in lowered, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon short runtime staging contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
