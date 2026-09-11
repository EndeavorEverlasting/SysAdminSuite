#!/usr/bin/env python3
"""Completeness contract for the Cybernet hardware-identity harness."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATORS = (
    ROOT / "harness/validators/validate-cybernet-hardware-identity.py",
    ROOT / "harness/validators/validate-cybernet-device-exclusion-registry.py",
)


def run_validator(path: Path) -> None:
    assert path.is_file(), f"Cybernet harness validator is missing: {path.relative_to(ROOT)}"
    result = subprocess.run(
        [sys.executable, str(path)],
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


def main() -> None:
    for validator in VALIDATORS:
        run_validator(validator)
    print("PASS: Cybernet hardware-identity harness completeness contract")


if __name__ == "__main__":
    main()
