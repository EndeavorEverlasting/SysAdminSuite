#!/usr/bin/env python3
"""
Compatibility wrapper for the artifact delivery dashboard renderer.

The operational implementation lives in survey/sas-render-artifact-delivery-dashboard.py
so survey tooling remains in the Bash-first survey path. This wrapper preserves the
older deployment-audit entrypoint for operators and documentation that still call it.
"""

from __future__ import annotations

import runpy
import sys
from pathlib import Path


SURVEY_RENDERER = Path(__file__).resolve().parents[1] / "survey" / "sas-render-artifact-delivery-dashboard.py"


def main() -> int:
    if not SURVEY_RENDERER.exists():
        print(f"Required renderer not found: {SURVEY_RENDERER}", file=sys.stderr)
        return 1
    runpy.run_path(str(SURVEY_RENDERER), run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
