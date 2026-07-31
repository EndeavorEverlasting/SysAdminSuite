#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Remove-SasExactRemoteAutoLogonRunRoot.ps1"


def read() -> str:
    assert SCRIPT.is_file(), f"missing required file: {SCRIPT.relative_to(ROOT)}"
    return SCRIPT.read_text(encoding="utf-8-sig")


def test_cleanup_is_exact_and_bounded() -> None:
    text = read()
    for marker in (
        "ConfirmExactCleanup",
        "ValidatePattern('^autologon-kerberos-s4u-",
        "AutoLogonKerberosS4U\\$RunId",
        "TimeoutSeconds",
        "process.WaitForExit($TimeoutSeconds * 1000)",
        "process.Kill()",
        "Remove-Item -LiteralPath `$root -Recurse -Force",
        "exact_autologon_s4u_run_root_only",
    ):
        assert marker in text, marker


def test_cleanup_profiles_fail_closed_before_deletion() -> None:
    text = read()
    for marker in (
        "ValidateSet('FullS4U','ProbeOnly')",
        "$AllowedArtifactProfile = 'FullS4U'",
        "$probeOnlyNames = @(",
        "NW_AutoLogon_Setup_x64.exe",
        "s4u-probe-worker.ps1",
        "s4u-probe-result.json",
        "$fullS4UNames = @(",
        "s4u-install-worker.ps1",
        "s4u-install-result.json",
        "$unexpected = @($inventory.names",
        "outside the $AllowedArtifactProfile cleanup profile; refusing cleanup",
    ):
        assert marker in text, marker
    unexpected = text.index("$unexpected = @($inventory.names")
    refusal = text.index("outside the $AllowedArtifactProfile cleanup profile; refusing cleanup", unexpected)
    deletion = text.index("Remove-Item -LiteralPath `$root -Recurse -Force", refusal)
    assert unexpected < refusal < deletion


def test_cleanup_reports_selected_profile() -> None:
    text = read()
    assert "allowed_artifact_profile = $AllowedArtifactProfile" in text


def test_cleanup_does_not_disable_safety_controls() -> None:
    text = read().lower()
    for forbidden in (
        "-forceeligibility",
        "defaultpassword",
        "credential =",
        "cmdkey",
        "net use",
        "*\\programdata\\sysadminsuite",
    ):
        assert forbidden not in text, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: exact AutoLogon run-root cleanup contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
