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
        "capture the starting network posture before any transition",
        "Repository synchronization is an `InternetSync` subtransaction",
        "git fetch --all --prune --tags",
        "git pull --ff-only",
        "Restore-SasNetworkIntent",
        "sas-leave.cmd",
        "autologon-short-runtime.json",
        "prepared_commit",
    )
    for marker in required:
        assert marker in text, marker
    assert text.index("capture the starting network posture before any transition") < text.index("git fetch --all --prune --tags")


def test_repository_sprint_next_command_uses_composed_handoff() -> None:
    text = read(REPO_SPRINT)
    assert "path -> freshness -> network intent -> command -> restoration" in text
    assert "one next command" in text.lower()
    assert "operator-command-handoff/SKILL.md" in text
    assert "capture the starting network **before any transition**" in text
    assert "do not run remote Git in the sealed runtime" in text


def test_fresh_agent_execute_stage_orders_real_gates_once() -> None:
    text = read(INTAKE)
    execute = text.split("  - id: execute\n", 1)[1].split("\n  - id: validate\n", 1)[0]
    markers = (
        "operator handoff gate 1 canonical path",
        "operator handoff gate 2 repository freshness",
        "operator handoff gate 3 network intent",
        "operator handoff gate 4 canonical command",
        "operator handoff gate 5 restoration",
    )
    positions = []
    for marker in markers:
        assert execute.count(marker) == 1, marker
        positions.append(execute.index(marker))
    assert positions == sorted(positions)

    gate1 = next(line for line in execute.splitlines() if markers[0] in line)
    gate2 = next(line for line in execute.splitlines() if markers[1] in line)
    gate3 = next(line for line in execute.splitlines() if markers[2] in line)
    assert "captures the starting network" in gate1
    assert "before any freshness or product transition" in gate1
    assert "InternetSync" in gate2
    assert "returns to the captured starting network posture" in gate2
    assert "recorded/restored starting posture" in gate3


def test_sealed_runtime_does_not_use_git_as_currentness_proof() -> None:
    route = read(ROUTE)
    field = read(FIELD)
    for text in (route, field):
        assert "C:\\SASAL" in text
        assert "prepared_commit" in text
        assert "Refresh-SasOperatorCommand.ps1" in text
        assert "Git" in text
    assert "do not run remote Git inside `C:\\SASAL`" in route
    assert "do not run remote Git inside `C:\\SASAL`" in field


def test_fresh_agent_retains_existing_freshness_handoff_contract() -> None:
    handoff = read(INTAKE).split("  - id: handoff\n", 1)[1]
    for marker in (
        "freshness proof must precede command handoff",
        "atomic pull-first route-and-run command",
        "bound to intended_remote and intended_remote_ref",
        "post-pull head equality with selected_repository_commit",
    ):
        assert marker in handoff


def main() -> int:
    test_focused_validator()
    test_agent_surfaces_cannot_skip_composed_handoff()
    test_skill_names_all_three_recurrence_guards_and_restore()
    test_repository_sprint_next_command_uses_composed_handoff()
    test_fresh_agent_execute_stage_orders_real_gates_once()
    test_sealed_runtime_does_not_use_git_as_currentness_proof()
    test_fresh_agent_retains_existing_freshness_handoff_contract()
    print("PASS: operator command handoff regression contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
