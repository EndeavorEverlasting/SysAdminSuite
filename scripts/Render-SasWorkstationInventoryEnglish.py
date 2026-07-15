#!/usr/bin/env python3
"""Render execution-domain workstation inventory as concise English."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def render_inventory_summary(data: dict) -> str:
    lines = [
        "Developer Workstation Inventory",
        "================================",
        f"Host: {data['host_platform']} ({data['detected_context']})",
        f"Selected tmux backend: {data['selected_backend'] or 'none'}",
        f"Lifecycle: {data['lifecycle']['outcome']} / {data['lifecycle']['state']}",
        f"Reasons: {', '.join(data['lifecycle']['reason_codes'])}",
        "",
        "Terminal host:",
        f"  WezTerm CLI: {'present' if data['terminal']['wezterm_cli']['present'] else 'missing'}",
        f"  WezTerm GUI: {'present' if data['terminal']['wezterm_gui']['present'] else 'missing'}",
        f"  Default workspace: {data['terminal']['default_workspace']['name'] or 'not configured'}",
        f"  Font availability: {data['terminal']['font']['availability']}",
        "",
        "Execution domains:",
    ]
    for domain in data["domains"]:
        backend = domain["backend"]
        lines.append(f"  {domain['id']}: {domain['health']} ({backend['kind']})")
        lines.append(f"    tmux: {'present' if backend['tmux']['present'] else 'missing/unknown'}; sessions: {', '.join(backend['tmux']['sessions']) or 'none'}")
        for agent in domain["agents"]:
            lines.append(f"    {agent['agent_id']}: {agent['resolution_kind']} via {agent['backend']} ({agent['authentication_readiness']})")
    lines.extend(["", f"Proof ceiling: {data['proof_ceiling']}"])
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <inventory.json>")
    print(render_inventory_summary(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))))


if __name__ == "__main__":
    main()
