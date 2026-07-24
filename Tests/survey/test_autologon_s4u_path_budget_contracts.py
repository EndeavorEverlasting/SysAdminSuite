#!/usr/bin/env python3
"""Regression contract for Windows PowerShell 5.1 path-budget safety in the S4U lane."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1"


def main() -> None:
    text = SCRIPT.read_text(encoding="utf-8")
    required = (
        "survey\\output\\s4u",
        "s4u-{0}-{1}",
        "Assert-SasS4ULocalPathBudget",
        "S4U local evidence path exceeds the Windows PowerShell 5.1 path budget",
        "Join-Path $repoRoot 'survey\\output\\pf'",
        "Join-Path $evidenceRoot 'bl'",
        "Join-Path $evidenceRoot 'af'",
        "Join-Path $evidenceRoot 'fg'",
    )
    missing = [marker for marker in required if marker not in text]
    assert not missing, f"missing compact S4U path-budget markers: {missing}"
    assert "Join-Path $runRoot 'preflight'" not in text
    assert "Join-Path $evidenceRoot 'baseline'" not in text
    assert "Join-Path $evidenceRoot 'after'" not in text
    assert "Join-Path $evidenceRoot 'final-gate'" not in text
    print("PASS: AutoLogon S4U compact path-budget contracts")


if __name__ == "__main__":
    main()
