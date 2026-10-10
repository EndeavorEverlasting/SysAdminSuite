#!/usr/bin/env python3
"""Real Windows process boundary regressions; no provider or target contact."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def test_real_windows_process_boundary():
    if os.name != "nt":
        raise RuntimeError("Windows host required; this gate cannot supply simulated Windows proof")
    module = Path(os.environ.get("SAS_NATIVE_PROCESS_MODULE", str(ROOT / "scripts/SasBoundedNative.psm1")))
    script = ROOT / "Tests/PowerShell/native-process-528-contract.Tests.ps1"
    shells = [Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe",
              shutil.which("pwsh")]
    for shell in shells:
        assert shell, "Both Windows PowerShell 5.1 and PowerShell 7 are required"
        result = subprocess.run([str(shell), "-NoProfile", "-File", str(script), "-ModulePath", str(module)],
                                capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, (shell, result.stdout, result.stderr)
        assert "PASS: native-process-528 real-child contract" in result.stdout
        print(result.stdout.strip())


if __name__ == "__main__":
    test_real_windows_process_boundary()
