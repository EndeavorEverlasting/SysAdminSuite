#!/usr/bin/env python3
"""Regression contract for long Windows repo paths in portable operator commands."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts" / "SasPortableLauncher.ps1"


def main() -> None:
    text = LAUNCHER.read_text(encoding="utf-8")
    required = (
        "Invoke-SasPortableRepoCommand",
        "subst.exe",
        "temporary short-path alias",
        "PathLengthThreshold",
        "Run-AutoLogonOnsite.cmd",
        "Run-CybernetBatchConfiguration.cmd",
        "finally",
        "'/D'",
    )
    missing = [marker for marker in required if marker not in text]
    assert not missing, f"missing portable short-path markers: {missing}"
    assert "pa_rperez26" not in text
    assert "S:" not in text, "launcher must choose a free drive dynamically, not hard-code S:"
    print("PASS: portable operator long-path trampoline contracts")


if __name__ == "__main__":
    main()
