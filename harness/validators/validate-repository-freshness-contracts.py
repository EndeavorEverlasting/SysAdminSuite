#!/usr/bin/env python3
"""Repository freshness contracts for the operational harness."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE = ROOT / "AGENTS.md"
WORKFLOW = ROOT / "harness/workflows/repository-freshness-before-launch.yaml"
FRESH = ROOT / "harness/workflows/fresh-agent-intake.yaml"
README = ROOT / "harness/README.md"
SKILL = ROOT / "harness/skills/harness-maintenance/SKILL.md"
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/harness-registry-integrity.yml"
REPORT = ROOT / "harness/reports/REPOSITORY_FRESHNESS_STATUS.md"


def read(path: Path) -> str:
    assert path.is_file(), path.relative_to(ROOT).as_posix()
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    relative = path.relative_to(ROOT).as_posix()
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", relative],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def test_freshness_workflow() -> None:
    text = read(WORKFLOW).lower()
    for marker in (
        "repository-freshness-before-launch",
        "any repository-owned command",
        "operator_command_requested",
        "configured git-remote freshness fetch",
        "git pull --ff-only before product invocation",
        "working installed sas shim is not repository freshness proof",
        "operator handoff is not freshness proof",
        "fetching a remote ref does not update the checked-out branch or worktree",
        "missing path in a stale worktree is not evidence",
        "repository_network_authorized",
        "target-network or product-mutation authority",
        "default_branch_update_authorized",
        "fast-forward-only",
        "isolated worktree",
        "fetched origin/main but continued executing an older local main",
        "repository-owned operator command issued before freshness proof",
        "installed sas availability treated as repository freshness proof",
        "alternate direct script invented",
        "target_network_activity: false",
        "target_mutation: false",
    ):
        assert marker in text, marker


def test_fresh_agent_routes_before_reconstruction_and_operator_handoff() -> None:
    text = read(FRESH).lower()
    freshness = "harness/workflows/repository-freshness-before-launch.yaml"
    canonical = "use the canonical command or workflow instead of reconstructing implementation details"
    assert freshness in text
    assert "missing locally" in text
    assert "before any repository-owned command or launcher is executed or handed to an operator" in text
    assert "working installed sas shim" in text
    assert "git pull --ff-only" in text
    assert "stop before the product command" in text
    assert "fetching origin/main alone does not update local main" in text
    assert "freshness routing does not grant target-network or product-mutation authority" in text
    assert "default branch" in text and "isolated worktree" in text
    assert "fast-forward-only" in text
    assert text.index(freshness) < text.index(canonical)


def test_operator_handoff_is_pull_first_or_fail_closed() -> None:
    governance = read(GOVERNANCE).lower()
    fresh = read(FRESH).lower()
    workflow = read(WORKFLOW).lower()

    for marker in (
        "before executing or handing any repository-owned command or launcher to an operator",
        "git pull --ff-only",
        "missing, dirty, diverged, unhealthy, or unproved checkout",
        "stale installed `sas` or repo-relative command",
        "harness/workflows/repository-freshness-before-launch.yaml",
    ):
        assert marker in governance, marker

    for text, label in ((fresh, "fresh-agent"), (workflow, "freshness-workflow")):
        assert "repository-owned" in text, label
        assert "operator" in text, label
        assert "git pull --ff-only" in text, label
        assert "installed sas" in text, label
        assert "freshness" in text, label

    # Regression for the incident class: a familiar local-only command such as `sas clipboard`
    # is still a repository-owned operator command and therefore cannot bypass the generic gate.
    assert "any repository-owned command" in workflow
    assert "bare product command" in fresh or "stop before the product command" in fresh


def test_front_door_and_skill_repeat_the_rule_and_authority_boundary() -> None:
    for text in (read(README).lower(), read(SKILL).lower()):
        assert "repository-freshness-before-launch.yaml" in text
        assert "does not update" in text
        assert "stale" in text
        assert "repository-network" in text
        assert "default branch" in text
        assert "fast-forward" in text
        assert "isolated worktree" in text


def test_manifest_and_validator_registry_track_freshness_contract() -> None:
    components = {item["id"]: item for item in load(MANIFEST)["components"]}
    expected = {
        "repository-freshness-workflow": "harness/workflows/repository-freshness-before-launch.yaml",
        "repository-freshness-validator": "harness/validators/validate-repository-freshness-contracts.py",
        "repository-freshness-report": "harness/reports/REPOSITORY_FRESHNESS_STATUS.md",
    }
    for component_id, path in expected.items():
        item = components[component_id]
        assert item["path"] == path
        assert item["required"] is True
        assert item["tracked"] is True
        assert tracked(ROOT / path), path

    validators = {item["id"]: item for item in load(VALIDATORS)["validators"]}
    item = validators["repository-freshness-contracts"]
    assert item["blocking"] is True
    assert item["command"] == "python harness/validators/validate-repository-freshness-contracts.py"
    scope = " ".join(item["scope"])
    assert "fresh-agent-intake.yaml" in scope
    assert "repository-freshness-before-launch.yaml" in scope


def test_pre_commit_and_ci_enforce_freshness_validator() -> None:
    marker = "validate-repository-freshness-contracts.py"
    assert marker in read(PRE_COMMIT)
    ci = read(CI)
    assert marker in ci
    assert "Validate repository freshness contracts" in ci
    assert "repository-freshness-before-launch.yaml" in ci


def test_pre_push_validates_exact_ref_tip_not_live_worktree() -> None:
    text = read(PRE_PUSH)
    assert "validate_freshness_tip" in text
    assert "git worktree add --detach --quiet" in text
    assert "python3 harness/validators/validate-repository-freshness-contracts.py" in text
    assert "dirty local files cannot mask failures" in text
    top = text.index('echo "[sas-harness] pre-push: running offline survey guardrails"')
    function = text.index("validate_freshness_tip()")
    assert "validate-repository-freshness-contracts.py" not in text[top:function]


def test_operator_report_records_incident_repair_and_authority() -> None:
    text = read(REPORT).lower()
    for marker in (
        "fetching origin/main did not update local main",
        "missing launcher",
        "repository-network",
        "default branch",
        "fast-forward-only",
        "isolated worktree",
        "do not invent an alternate deployment path",
        "exact pushed ref-update tip",
        "remaining proof limits",
    ):
        assert marker in text, marker


def test_required_freshness_surfaces_are_tracked() -> None:
    for path in (GOVERNANCE, WORKFLOW, FRESH, README, SKILL, MANIFEST, VALIDATORS, PRE_COMMIT, PRE_PUSH, CI, REPORT, Path(__file__)):
        assert tracked(path), path.relative_to(ROOT).as_posix()


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: repository freshness harness contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
