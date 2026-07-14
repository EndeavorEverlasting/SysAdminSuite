#!/usr/bin/env python3
"""Render structured SysAdminSuite JSONL events into agent-readable English."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from harness.reporting.english import register_rendered_artifacts, render_event_log


def main() -> int:
    parser = argparse.ArgumentParser(description="Render local structured events without network activity.")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--jsonl-output", type=Path, required=True)
    parser.add_argument("--english-output", type=Path, required=True)
    parser.add_argument("--artifact-registry", type=Path)
    args = parser.parse_args()
    render_event_log(args.input, args.jsonl_output, args.english_output)
    if args.artifact_registry:
        register_rendered_artifacts(args.artifact_registry, args.jsonl_output, args.english_output)
    print(f"Rendered structured JSONL: {args.jsonl_output}", file=sys.stderr)
    print(f"Rendered syntactic English: {args.english_output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
