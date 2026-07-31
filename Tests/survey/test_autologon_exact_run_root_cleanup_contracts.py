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


def test_cleanup_refuses_unexpected_remote_entries() -> None:
    text = read()
    for marker in (
        "NW_AutoLogon_Setup_x64.exe",
        "s4u-probe-worker.ps1",
        "s4u-probe-result.json",
        "contains unexpected entries; refusing cleanup",
    ):
        assert marker in text, marker


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
