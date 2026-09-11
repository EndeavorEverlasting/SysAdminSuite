#!/usr/bin/env python3
"""Enforce CMD-first technician guide and GUI-wrapper doctrine."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE = ROOT / "AGENTS.md"
FIELD_SKILL = ROOT / ".claude" / "skills" / "field-workflow" / "SKILL.md"
FIELD_COMMAND = ROOT / ".claude" / "capabilities" / "field-command-design.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing authority: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def main() -> int:
    governance = read(GOVERNANCE)
    field_skill = read(FIELD_SKILL)
    field_command = read(FIELD_COMMAND)

    technician = governance.split("## Technician execution doctrine", 1)[1].split(
        "## Northwell printer mapping doctrine", 1
    )[0]

    governance_markers = (
        "Guide-to-launcher invariant",
        "guide a technician through an executable Windows field use case",
        "must first create or strengthen a tracked repository-owned `.cmd` launcher",
        "Prose guidance, shell snippets, GUI buttons, dashboard actions, menus, QR wrappers, and tutorials are incomplete",
        "any working directory and any Windows username",
        "`C:\\SASAL`",
        "`%ProgramData%\\SysAdminSuite`",
        "Only after the CMD contract is implemented and validated",
    )
    for marker in governance_markers:
        assert marker in technician, f"missing CMD-first governance marker: {marker}"

    capability_markers = (
        "## CMD-first guide invariant",
        "guide, runbook, walkthrough, or how-to",
        "tracked repository-owned `.cmd` launcher",
        "launch-folder independent and Windows-username independent",
        "named-user Desktop, OneDrive, profile, or checkout paths are never execution authority",
        "GUI buttons, dashboard actions, menus, QR capsules, shortcuts, and prose tutorials are downstream wrappers",
        "PowerShell/Bash snippets remain developer diagnostics or implementation detail",
        '"Functioning CMD" means',
    )
    for marker in capability_markers:
        assert marker in field_command, f"missing field-command capability marker: {marker}"

    dependency = "[Field Command Design](../../capabilities/field-command-design.md)"
    assert dependency in field_skill, "Field Workflow must load the Field Command Design capability"

    cmd_index = field_command.index("## CMD-first guide invariant")
    gui_index = field_command.index("GUI buttons, dashboard actions")
    proof_index = field_command.index('"Functioning CMD" means')
    assert cmd_index < gui_index < proof_index, (
        "CMD creation must precede GUI-wrapper guidance and validation must remain explicit"
    )

    contradictions = (
        "write the guide first and add the cmd later",
        "gui may replace the cmd",
        "snippets are sufficient technician guidance",
        "named-user path is execution authority",
    )
    joined = (technician + "\n" + field_command).lower()
    for contradiction in contradictions:
        assert contradiction not in joined, f"contradictory CMD-first doctrine: {contradiction}"

    print("[PASS] Technician guide requests are CMD-first by root governance")
    print("[PASS] Field Command Design requires any-folder and any-username launchers")
    print("[PASS] GUI/tutorial/menu/QR surfaces are downstream wrappers over proven CMD/runtime contracts")
    print("[PASS] Field Workflow still loads the capability that owns this invariant")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
