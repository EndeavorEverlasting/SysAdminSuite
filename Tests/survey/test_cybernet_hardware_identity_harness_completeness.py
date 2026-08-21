#!/usr/bin/env python3
"""Completeness contract for the Cybernet hardware-identity harness."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "harness/validators/validate-cybernet-hardware-identity.py"


def main() -> None:
    assert VALIDATOR.is_file(), "Cybernet hardware-identity validator is missing"
    result = subprocess.run(
        [sys.executable, str(VALIDATOR)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        raise SystemExit(result.returncode)
    print(result.stdout, end="")
    print("PASS: Cybernet hardware-identity harness completeness contract")


if __name__ == "__main__":
    main()
