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


def test_prepare_is_guest_only_and_local_transport_only() -> None:
    text = read(PREPARE)
    assert "GUEST_INTERNET" in text
    assert "AUTOLOGON_RUNTIME_STAGE_BLOCKED" in text
    assert "LOCAL_FILESYSTEM_ONLY" in text
    assert "runtime_remotes_removed = $true" in text
    assert "protected_bootstrap_git_network_allowed = $false" in text
    assert "target_contact_performed = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "SAS_AUTOLOGON_SHORT_RUNTIME_READY" in text
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


def test_protected_bootstrap_is_verification_only_for_git() -> None:
    text = read(BOOTSTRAP)
    assert "autologon-short-runtime.json" in text
    assert "Git network I/O: DISABLED" in text
    assert "Checkout mutation: DISABLED" in text
    assert "runtime_git_transport" in text
    assert "LOCAL_FILESYSTEM_ONLY" in text
    assert "runtime_remotes_removed" in text
    assert "protected_bootstrap_git_network_allowed" in text
    assert "AUTOLOGON_RUNTIME_NOT_PREPARED" in text
    assert "AUTOLOGON_RUNTIME_UNSEALED" in text
    assert "PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION" in text

    for command in ("rev-parse", "status", "remote"):
        assert command in text
    lowered = text.lower()
    for forbidden in (
        "git fetch",
        "git clone",
        "git pull",
        "checkout --detach",
        "reset --hard",
        "clean -fd",
        "ls-remote",
        "repo_url",
    ):
        assert forbidden not in lowered, forbidden


def test_protected_bootstrap_legacy_evidence_fallback_is_explicit_only() -> None:
    text = read(BOOTSTRAP)
    assert "Legacy evidence fallback is opt-in only" in text
    assert "if (-not [string]::IsNullOrWhiteSpace($LegacyEvidenceRoot))" in text
    assert "Legacy evidence fallback: disabled." in text
    assert "GetFolderPath" not in text
    assert "Desktop\\dev" not in text
    assert "OG Laptop Backup" not in text


def test_protected_bootstrap_does_not_merge_native_stderr_into_error_stream() -> None:
    text = read(BOOTSTRAP)
    prepare = read(PREPARE)
    assert "2> $stderrPath" in text
    assert "2> $stderrPath" in prepare
    assert "2>&1" not in text
    assert "2>&1" not in prepare
    assert "$ErrorActionPreference = 'Continue'" in text
    assert "$ErrorActionPreference = 'Continue'" in prepare


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
