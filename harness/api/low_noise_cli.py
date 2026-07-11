#!/usr/bin/env python3
"""CLI adapter for local agents, Bash consumers, and future MCP servers."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .low_noise_policy import DEFAULT_POLICY_PATH, explain_summary, get_profile, load_policy, render_profile_english


def main() -> int:
    parser = argparse.ArgumentParser(description="Read or explain the canonical low-noise policy without network activity.")
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY_PATH)
    subparsers = parser.add_subparsers(dest="operation", required=True)

    profile_parser = subparsers.add_parser("profile", help="Return one effective profile.")
    profile_parser.add_argument("--id", required=True)
    profile_parser.add_argument("--format", choices=("json", "english"), default="json")

    explain_parser = subparsers.add_parser("explain", help="Convert a structured run summary into syntactic English.")
    explain_parser.add_argument("--summary", type=Path, required=True)
    explain_parser.add_argument("--output", type=Path)

    args = parser.parse_args()
    policy = load_policy(args.policy)
    if args.operation == "profile":
        profile = get_profile(policy, args.id)
        output = json.dumps(profile, indent=2) + "\n" if args.format == "json" else render_profile_english(policy, profile) + "\n"
    else:
        summary = json.loads(args.summary.read_text(encoding="utf-8-sig"))
        output = explain_summary(summary, policy)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(output, encoding="utf-8")
            print(f"Rendered syntactic English: {args.output}", file=sys.stderr)
            return 0
    print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
