#!/usr/bin/env python3
"""Static contract for SysAdminSuite sprint working rules."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "SPRINTS.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_sprint_rules_require_repo_progress():
    text = read(DOC)
    required = [
        "Implementation sprints should produce repository progress",
        "tracked file changes",
        "validation",
        "Planning and next-agent prompts are closeout artifacts",
        "not substitutes for implementation work",
    ]
    for fragment in required:
        assert fragment in text, f"missing sprint progress rule: {fragment}"


def test_sprint_rules_require_repo_evidence_before_new_patterns():
    text = read(DOC)
    required = [
        "inspect existing docs",
        "scripts",
        "tests",
        "contracts",
        "naming conventions",
        "output paths",
    ]
    for fragment in required:
        assert fragment in text, f"missing repo evidence rule: {fragment}"


def test_sprint_rules_name_next_queue():
    text = read(DOC)
    required = [
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
    ]
    for fragment in required:
        assert fragment in text, f"missing sprint queue item: {fragment}"


if __name__ == "__main__":
    test_sprint_rules_require_repo_progress()
    test_sprint_rules_require_repo_evidence_before_new_patterns()
    test_sprint_rules_name_next_queue()
