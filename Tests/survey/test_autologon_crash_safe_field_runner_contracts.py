#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonCrashSafeFieldRun.ps1"
CMD = ROOT / "Run-AutoLogonCrashSafe.cmd"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_child_process_contains_internal_exit() -> None:
    text = read(SCRIPT)
    assert "& powershell.exe @childArguments" in text
    assert "Invoke-SasAutoLogonOnsite.ps1" in text
    assert "-Action', 'Remote'" in text
    assert "exit $ExitCode" not in text


def test_native_child_exit_codes_are_primed_under_strict_mode() -> None:
    text = read(SCRIPT)
    assert text.count("$LASTEXITCODE = 0") >= 2
    child_prime = text.index("$LASTEXITCODE = 0", text.index("$childArguments = @("))
    child_call = text.index("& powershell.exe @childArguments", child_prime)
    child_capture = text.index("$result.child_exit_code = [int]$LASTEXITCODE", child_call)
    evidence_prime = text.index("$LASTEXITCODE = 0", child_capture)
    evidence_call = text.index("& powershell.exe @evidenceArguments", evidence_prime)
    evidence_capture = text.index("$result.evidence_recovery_exit_code = [int]$LASTEXITCODE", evidence_call)
    assert child_prime < child_call < child_capture
    assert evidence_prime < evidence_call < evidence_capture


def test_stable_diagnostics_survive_terminal_loss() -> None:
    text = read(SCRIPT)
    assert "Start-Transcript" in text
    assert "Tee-Object -FilePath $childOutputPath" in text
    assert "field-runs\\autologon" in text
    assert "field-run-result.json" in text
    assert "last-autologon-field-run.json" in text
    assert "finally" in text


def test_offline_evidence_recovery_runs_after_child() -> None:
    text = read(SCRIPT)
    assert "Show-SasOperatorEvidence.ps1" in text
    assert "'AutoLogon', '20'" in text
    assert "last-evidence.json" in text
    assert "$result.evidence_recovery_exit_code = [int]$LASTEXITCODE" in text
    assert "[int]$result.evidence_recovery_exit_code -ne 0" in text
    assert "target_contact_performed_by_runner = $false" in text
    assert "target_mutation_performed_by_runner = $false" in text


def test_explicit_deployment_confirmation_is_required() -> None:
    text = read(SCRIPT)
    assert "ConfirmDeployment" in text
    assert "Explicit -ConfirmDeployment is required" in text


def test_repository_head_is_supplied_without_git() -> None:
    text = read(SCRIPT)
    assert "[string]$RepositoryHead" in text
    assert "$repoHead = if ([string]::IsNullOrWhiteSpace($RepositoryHead))" in text
    assert "Repository identity is supplied by the already-sealed runtime manifest/bootstrap" in text
    for forbidden in (
        "git -C",
        "& git",
        "git.exe",
        "rev-parse HEAD",
    ):
        assert forbidden not in text, forbidden


def test_cmd_keeps_visible_failure_boundary() -> None:
    text = read(CMD)
    assert "Invoke-SasAutoLogonCrashSafeFieldRun.ps1" in text
    assert "pause" in text.lower()
    assert "%%LOCALAPPDATA%%\\SysAdminSuite\\field-runs\\autologon" in text


def test_cmd_preserves_confirmdeployment_across_native_boundary() -> None:
    text = read(CMD)
    assert 'set "SAS_ROOT=%~dp0."' in text
    assert '-RepositoryRoot "%SAS_ROOT%" -ConfirmDeployment' in text
    assert '-RepositoryRoot "%~dp0" -ConfirmDeployment' not in text


def test_no_live_target_or_secret_literal() -> None:
    text = (read(SCRIPT) + read(CMD)).lower()
    for forbidden in ("wpj075", "defaultpassword", "nslijhs.net", "password="):
        assert forbidden not in text, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon crash-safe field runner contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
