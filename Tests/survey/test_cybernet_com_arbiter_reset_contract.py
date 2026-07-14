#!/usr/bin/env python3
"""Fail-closed contract for the Cybernet COM Name Arbiter reset."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "Invoke-CybernetComPortAutoFix.ps1"


def main() -> None:
    content = SCRIPT_PATH.read_text(encoding="utf-8")
    function_start = content.index("function Invoke-CybernetComArbiterReset")
    mapping_start = content.index("function Set-CybernetComPortMapping", function_start)
    reset_block = content[function_start:mapping_start]

    assert "reg.exe add" in reset_block
    assert "$exitCode = $LASTEXITCODE" in reset_block
    assert "if ($exitCode -ne 0)" in reset_block
    assert "COM Name Arbiter reset failed with exit code" in reset_block

    reset_call = content.index("Invoke-CybernetComArbiterReset -RunDir")
    mapping_call = content.index("Set-CybernetComPortMapping -Mapping", reset_call)
    assert reset_call < mapping_call

    print("PASS: Cybernet COM arbiter reset fails closed before PortName mutation")


if __name__ == "__main__":
    main()
