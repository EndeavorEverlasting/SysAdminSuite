#!/usr/bin/env python3
"""Static contract for SysAdminSuite sprint working rules."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "SPRINTS.md"


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"missing expected file: {path.relative_to(ROOT).as_posix()}")
    return path.read_text(encoding="utf-8")


def require_fragments(text: str, fragments: list[str], label: str) -> None:
    missing = [fragment for fragment in fragments if fragment not in text]
    if missing:
        raise AssertionError(f"missing {label}: {', '.join(missing)}")


def test_sprint_rules_require_repo_progress():
    text = read(DOC)
    require_fragments(
        text,
        [
            "Implementation sprints should produce repository progress",
            "tracked file changes",
            "validation",
            "Planning and next-agent prompts are closeout artifacts",
            "not substitutes for implementation work",
        ],
        "sprint progress rule",
    )


def test_sprint_rules_require_repo_evidence_before_new_patterns():
    text = read(DOC)
    require_fragments(
        text,
        [
            "inspect existing docs",
            "scripts",
            "tests",
            "contracts",
            "naming conventions",
            "output paths",
        ],
        "repo evidence rule",
    )


def test_sprint_rules_name_next_queue():
    text = read(DOC)
    require_fragments(
        text,
        [
            "Target Reduction Planner",
            "English Report Renderer",
            "Canonical Run Context",
            "Survey Workflow Specs",
            "End-to-End Harness Validator",
            "Local MCP Server Skeletons",
            "Standard CMD and PowerShell Renderers",
            "Location/Subnet Candidate Planner",
            "Dashboard Serial Controls Integration",
            "Executor Guardrail Expansion",
        ],
        "sprint queue item",
    )


if __name__ == "__main__":
    test_sprint_rules_require_repo_progress()
    test_sprint_rules_require_repo_evidence_before_new_patterns()
    test_sprint_rules_name_next_queue()
