#!/usr/bin/env python3
"""Render a concise terminal-labeled workstation orchestration summary."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def render(result: dict) -> str:
    context = "Windows PowerShell" if result["platform"] == "windows" else "WezTerm/tmux Bash" if result["platform"] == "linux" else "unsupported platform"
    lines = [f"DEVELOPER WORKSTATION [{context}]", f"Overall: {result['outcome']}", f"Mode: {result['mode']} | Domain: {result['execution_domain']}"]
    for item in result["steps"]:
        lines.append(f"[{item['status']}] {item['name']}: {item['message']}")
    proof = result["proof"]
    lines.append(f"Proof: fixture={str(proof['fixture']).lower()}; live_runtime={str(proof['live_runtime']).lower()}; persistence={str(proof['persistence_observed']).lower()}; operator_accepted={str(proof['operator_accepted']).lower()}")
    if result["mode"] == "Stop":
        lines.append("Warning: Stop is explicitly destructive to the persistent tmux dev session.")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = json.loads(args.input.read_text(encoding="utf-8-sig"))
    text = render(result)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
