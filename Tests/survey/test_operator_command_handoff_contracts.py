#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "harness/skills/operator-command-handoff/SKILL.md"
INTAKE = ROOT / "harness/workflows/fresh-agent-intake.yaml"
CANONICAL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"
ROUTE = ROOT / "harness/skills/operator-execution-route/SKILL.md"
FIELD = ROOT / ".claude/skills/field-workflow/SKILL.md"
REPO_SPRINT = ROOT / ".claude/skills/repository-sprint/SKILL.md"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def test_focused_validator() -> None:
    result = subprocess.run(
        [sys.executable, "harness/validators/validate-operator-command-handoff.py"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "PASS: operator command handoff composition" in result.stdout


def test_agent_surfaces_cannot_skip_composed_handoff() -> None:
    marker = "harness/skills/operator-command-handoff/SKILL.md"
    for path in (INTAKE, CANONICAL, ROUTE, FIELD, REPO_SPRINT):
        assert marker in read(path), f"{path.relative_to(ROOT)} does not route operator commands through composed handoff skill"


def test_skill_names_all_three_recurrence_guards_and_restore() -> None:
    text = read(SKILL)
    required = (
        "Canonical path",
        "Repository freshness",
        "Starting network + required intent",
        "git fetch --all --prune --tags",
        "git pull --ff-only",
        "Restore-SasNetworkIntent",
        "sas-leave.cmd",
    )
    for marker in required:
        assert marker in text, marker


def test_repository_sprint_next_command_uses_composed_handoff() -> None:
    text = read(REPO_SPRINT)
    assert "path -> freshness -> network intent -> command -> restoration" in text
    assert "one next command" in text.lower()
    assert "operator-command-handoff/SKILL.md" in text


def main() -> int:
    test_focused_validator()
    test_agent_surfaces_cannot_skip_composed_handoff()
    test_skill_names_all_three_recurrence_guards_and_restore()
    test_repository_sprint_next_command_uses_composed_handoff()
    print("PASS: operator command handoff regression contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
