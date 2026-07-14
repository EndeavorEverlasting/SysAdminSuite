#!/usr/bin/env python3
"""Static contracts for checkpoint-before-expansion harness discipline.

These tests verify the documentation-level recovery invariant without running
runtime proof, broad validation, or repo mutation.
"""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENTS_PATH = REPO_ROOT / "AGENTS.md"
REPOSITORY_SKILL_PATH = REPO_ROOT / ".claude" / "skills" / "repository-sprint" / "SKILL.md"
PROOF_CAPABILITY_PATH = REPO_ROOT / ".claude" / "capabilities" / "proof-and-checkpointing.md"
HARNESS_DISCIPLINE_PATH = REPO_ROOT / "docs" / "HARNESS_DISCIPLINE.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_factored_instructions_preserve_incremental_work_rule() -> None:
    agents = read(AGENTS_PATH)
    repository_skill = read(REPOSITORY_SKILL_PATH)
    proof_capability = read(PROOF_CAPABILITY_PATH)

    assert ".claude/skills/repository-sprint/SKILL.md" in agents
    assert "Checkpoint coherent tracked work before broad validation" in agents
    assert "proof-and-checkpointing.md" in repository_skill
    assert "Checkpoint before broad validation or runtime proof" in repository_skill

    required_capability_fragments = [
        "Checkpoint the first coherent tracked change before broad validation",
        "A valid checkpoint is a bounded commit, a complete patch, or another repo-approved recovery artifact",
        "A checkpoint proves preservation only",
        "It does not prove correctness, completion, merge readiness, or runtime behavior",
        "Keep raw runtime evidence outside git",
    ]
    for fragment in required_capability_fragments:
        assert fragment in proof_capability, (
            "proof-and-checkpointing capability missing rule fragment: " + fragment
        )


def test_harness_core_loop_requires_preservation_checkpoint() -> None:
    content = read(HARNESS_DISCIPLINE_PATH)

    request = content.index("request")
    coherent_action = content.index("-> coherent action", request)
    checkpoint = content.index("-> preservation checkpoint", coherent_action)
    targeted_validation = content.index("-> targeted validation", checkpoint)
    broader_validation = content.index("-> broader validation", targeted_validation)

    assert request < coherent_action < checkpoint < targeted_validation < broader_validation
    assert "recoverable boundary, not completion proof" in content


def test_harness_checkpoint_boundary_and_safety_are_explicit() -> None:
    content = read(HARNESS_DISCIPLINE_PATH)

    required_fragments = [
        "## Incremental checkpoint discipline",
        "### Required checkpoint boundary",
        "broad or full-suite validation",
        "long-running tests or builds",
        "runtime or device proof",
        "repository-wide refactoring",
        "external API or model work subject to context, token, time, or quota limits",
        "switching agents, models, worktrees, or execution environments",
        "### Acceptable checkpoint forms",
        "A bounded WIP commit on the owned feature branch",
        "A patch or bundle that includes both modified tracked files and newly created files",
        "A plain `git diff` patch is insufficient when untracked files are part of the implementation",
        "exclude secrets, credentials, runtime evidence, registry exports, generated logs, device identities, and machine-local artifacts",
    ]
    for fragment in required_fragments:
        assert fragment in content, f"HARNESS_DISCIPLINE.md missing checkpoint boundary fragment: {fragment}"


def test_harness_resume_report_and_proof_boundaries_are_explicit() -> None:
    content = read(HARNESS_DISCIPLINE_PATH)

    required_fragments = [
        "### Resume contract",
        "inspect the latest checkpoint",
        "verify its changed-file boundary",
        "run the smallest failing or pending validation first",
        "create a new checkpoint before expanding validation again",
        "### Proof boundary",
        "It does not prove:",
        "tests pass",
        "runtime behavior works",
        "a PR is mergeable",
        "### Harness report fields",
        "latest checkpoint SHA or artifact path",
        "files deliberately excluded",
        "first pending or failing validation",
        "exact resume command",
    ]
    for fragment in required_fragments:
        assert fragment in content, f"HARNESS_DISCIPLINE.md missing resume/proof fragment: {fragment}"


def test_harness_records_future_validator_and_negative_fixture() -> None:
    content = read(HARNESS_DISCIPLINE_PATH)

    required_fragments = [
        "### Machine-readable checkpoint fields",
        '"checkpointRequired": true',
        '"checkpointReason": "before_broad_validation"',
        '"checkpointType": "wip_commit"',
        '"preservedFiles": []',
        '"excludedDirtyFiles": []',
        "### Future validator seam",
        "but recorded no checkpoint SHA or recovery artifact",
        "Include a negative fixture for the Bluetooth interruption failure mode",
        "a recovery patch made with `git diff` alone does not preserve untracked files",
    ]
    for fragment in required_fragments:
        assert fragment in content, f"HARNESS_DISCIPLINE.md missing future validator fragment: {fragment}"


def test_refactoring_checkpoint_rule_requires_slices_and_verified_skill_path() -> None:
    content = read(HARNESS_DISCIPLINE_PATH)

    required_fragments = [
        "## Checkpointed refactoring discipline",
        "Refactoring must be planned as recoverable slices",
        "Name the invariant being preserved",
        "Name the owned files",
        "Run broad validation only after all bounded slices have checkpoints",
        "before renaming or moving multiple files",
        "before changing shared contracts or schemas",
        "before updating all callers",
        "Never mix unrelated dirty files into a refactoring checkpoint",
        "Do not guess the skill path; verify the path from the repository before editing it",
    ]
    for fragment in required_fragments:
        assert fragment in content, f"HARNESS_DISCIPLINE.md missing refactoring checkpoint fragment: {fragment}"


def main() -> None:
    tests = [
        test_factored_instructions_preserve_incremental_work_rule,
        test_harness_core_loop_requires_preservation_checkpoint,
        test_harness_checkpoint_boundary_and_safety_are_explicit,
        test_harness_resume_report_and_proof_boundaries_are_explicit,
        test_harness_records_future_validator_and_negative_fixture,
        test_refactoring_checkpoint_rule_requires_slices_and_verified_skill_path,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} checkpoint discipline contracts")


if __name__ == "__main__":
    main()
