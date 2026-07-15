#!/usr/bin/env python3
"""Dependency-free English renderer for developer-workstation inventory results."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


STATUS_ICON = {"PASS": "[PASS]", "SKIP": "[SKIP]", "FAIL": "[FAIL]"}


def render_inventory_summary(inventory: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.append("Developer Workstation Inventory")
    lines.append("================================")
    lines.append("")
    lines.append(f"Platform: {inventory['detected_platform']}")
    lines.append(f"Environment: {inventory['execution_environment']}")
    lines.append(f"Generated: {inventory['generated_at']}")
    lines.append("")

    checks = inventory["checks"]
    named_checks = [
        ("WezTerm", checks.get("wezterm")),
        ("Shell", checks.get("shell")),
        ("Multiplexer", checks.get("multiplexer")),
        ("Repository", checks.get("repository")),
        ("AgentSwitchboard", checks.get("agent_switchboard")),
    ]
    for name, check in named_checks:
        if check is not None:
            icon = STATUS_ICON[check["status"]]
            lines.append(f"{icon} {name}: {check['reason']}")

    wsl = checks.get("wsl")
    if wsl and wsl.get("status") not in ("SKIP", None):
        lines.append("")
        lines.append("WSL Distributions:")
        for dist in wsl.get("distributions", []):
            d_icon = STATUS_ICON[dist["status"]]
            lines.append(f"  {d_icon} {dist['name']}: {dist['reason']}")
            if dist.get("tmux"):
                t_icon = STATUS_ICON[dist["tmux"]["status"]]
                lines.append(f"    {t_icon} tmux: {dist['tmux']['reason']}")

    lines.append("")
    lines.append("Agent Commands:")
    for agent in checks.get("agent_commands", []):
        a_icon = STATUS_ICON[agent["status"]]
        lines.append(f"  {a_icon} {agent['agent_id']}: {agent['reason']}")

    lines.append("")
    lines.append(f"Selected Profile: {inventory['selected_profile']}")
    lines.append(f"Eligible Profiles: {', '.join(inventory['eligible_profiles'])}")
    lines.append("")
    lines.append(f"Proof Ceiling: {inventory['proof_ceiling']}")

    return "\n".join(lines)


def main() -> None:
    import sys
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <inventory.json>", file=sys.stderr)
        sys.exit(1)
    path = Path(sys.argv[1])
    inventory = json.loads(path.read_text(encoding="utf-8"))
    print(render_inventory_summary(inventory))


if __name__ == "__main__":
    main()
