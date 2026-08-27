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


def workflow_stage(text: str, stage_id: str, next_stage_id: str | None = None) -> str:
    start = text.index(f"  - id: {stage_id}")
    if next_stage_id is None:
        return text[start:]
    end = text.index(f"  - id: {next_stage_id}", start)
    return text[start:end]


def test_freshness_workflow() -> None:
    text = read(WORKFLOW).lower()
    for marker in (
        "repository-freshness-before-launch",
        "any repository-owned command",
        "operator_command_requested",
        "configured git-remote freshness fetch",
        "git pull --ff-only <intended_remote> <intended_remote_ref>",
        "git rev-parse head equals selected_repository_commit",
        "working installed sas shim is not repository freshness proof",
        "operator handoff is not freshness proof",
        "isolated worktree may prove refreshed repository content for agent-side analysis but never substitutes",
        "fetching a remote ref does not update the checked-out branch or worktree",
        "missing path in a stale worktree is not evidence",
        "repository_network_authorized",
        "target-network or product-mutation authority",
        "default_branch_update_authorized",
        "fast-forward-only",
        "isolated worktree",
        "fetched origin/main but continued executing an older local main",
        "repository-owned operator command issued before canonical-development currentness proof",
        "atomic operator refresh followed an unqualified configured upstream instead of intended_remote and intended_remote_ref",
        "post-pull head was not proven equal to selected_repository_commit before product invocation",
        "isolated worktree accepted as operator-command currentness proof",
        "installed sas availability treated as repository freshness proof",
        "alternate direct script invented",
        "target_network_activity: false",
        "target_mutation: false",
    ):
        assert marker in text, marker


def test_fresh_agent_routes_before_reconstruction_and_operator_handoff() -> None:
    text = read(FRESH).lower()
    governance = workflow_stage(text, "governance", "orient")
    execute = workflow_stage(text, "execute", "validate")
    handoff = workflow_stage(text, "handoff")

    freshness = "harness/workflows/repository-freshness-before-launch.yaml"
    trigger = "before any repository-owned command or launcher is executed or handed to an operator"
    canonical = "use the canonical command or workflow instead of reconstructing implementation details"
    execution_gate = "do not execute or hand out a repository-owned operator command until repository-freshness-before-launch proves"
    route_lookup = "resolve executable location before operator command handoff"
    execute_front_door = "when the execution environment can run the operator command"
    atomic_handoff = "one atomic copy-paste route-and-run command"
    bound_pull = "git pull --ff-only <intended_remote> <intended_remote_ref>"

    assert freshness in governance
    assert "missing locally" in governance
    assert trigger in governance
    assert "working installed sas shim" in governance
    assert bound_pull in governance
    assert "git rev-parse head equals selected_repository_commit" in governance
    assert "fetching origin/main alone does not update local main" in governance
    assert "freshness routing does not grant target-network or product-mutation authority" in governance
    assert "default branch" in governance and "isolated worktree" in governance
    assert "fast-forward-only" in governance

    assert canonical in execute
    assert execution_gate in execute
    assert "stop before the product command" in execute
    assert atomic_handoff in execute
    assert bound_pull in execute
    assert "git rev-parse head to equal selected_repository_commit" in execute
    assert execute.index(execution_gate) < execute.index(route_lookup) < execute.index(execute_front_door)
    assert execute.index(execution_gate) < execute.index(atomic_handoff)

    assert "freshness proof must precede command handoff" in handoff
    assert "atomic pull-first route-and-run command" in handoff
    assert "bound to intended_remote and intended_remote_ref" in handoff
    assert "post-pull head equality with selected_repository_commit" in handoff

    # The unconditional operator trigger must be established in governance before command execution/handoff stages.
    assert text.index(trigger) < text.index(canonical) < text.index(execution_gate)


def test_operator_handoff_requires_canonical_currentness_or_atomic_canonical_pull() -> None:
    workflow = read(WORKFLOW).lower()
    prove = workflow_stage(workflow, "prove-executing-tree", "continue")
    continuation = workflow_stage(workflow, "continue")

    canonical_gate = "canonical_development_checkout_current=true before any bare product invocation or operator-command handoff"
    isolated_reject = "never allow an isolated_worktree, ephemeral_acquisition, or unknown path classification to satisfy operator-command currentness"
    bare_gate = "execute or emit a bare repository-owned operator command only when canonical_development_checkout_current=true"
    atomic_gate = "emit one atomic canonical pull-first command"
    blocked_gate = "stop before emitting the product command even if an isolated worktree is current"
    bound_pull = "git pull --ff-only <intended_remote> <intended_remote_ref>"

    assert canonical_gate in prove
    assert isolated_reject in prove
    assert bound_pull in prove
    assert "requires git rev-parse head to equal selected_repository_commit" in prove
    assert prove.index(canonical_gate) < prove.index("only after the applicable freshness proof")

    assert bare_gate in continuation
    assert atomic_gate in continuation
    assert blocked_gate in continuation
    assert bound_pull in continuation
    assert "requires git rev-parse head to equal selected_repository_commit" in continuation
    assert continuation.index(bare_gate) < continuation.index(atomic_gate) < continuation.index(blocked_gate)
    assert "proves clean/owned/healthy/default-branch/strictly-behind state" in continuation


def test_operator_handoff_is_pull_first_or_fail_closed() -> None:
    governance = read(GOVERNANCE).lower()
    fresh = read(FRESH).lower()
    workflow = read(WORKFLOW).lower()

    technician = governance.split("## technician execution doctrine", 1)[1].split(
        "## northwell printer mapping doctrine", 1
    )[0]
    rule = next(
        line for line in technician.splitlines()
        if "before executing or handing any repository-owned command or launcher to an operator" in line
    )
    for marker in (
        "prove that the tree which will execute the command is current at the selected refreshed commit",
        "canonical default-branch checkout is clean, owned, healthy, and strictly behind",
        "git pull --ff-only <intended_remote> <intended_remote_ref>",
        "git rev-parse head` equality check against the selected refreshed commit",
        "must remain one atomic handoff",
        "missing, dirty, diverged, unhealthy, or unproved checkout",
        "stale installed `sas` or repo-relative command",
        "harness/workflows/repository-freshness-before-launch.yaml",
    ):
        assert marker in rule, marker

    for text, label in ((fresh, "fresh-agent"), (workflow, "freshness-workflow")):
        assert "repository-owned" in text, label
        assert "operator" in text, label
        assert "git pull --ff-only <intended_remote> <intended_remote_ref>" in text, label
        assert "selected_repository_commit" in text, label
        assert "installed sas" in text, label
        assert "freshness" in text, label

    # Regression for the incident class: a familiar local-only command such as `sas clipboard`
    # is still a repository-owned operator command and therefore cannot bypass the generic gate.
    assert "any repository-owned command" in workflow
    assert "stop before the product command" in fresh


def test_atomic_pull_is_bound_to_selected_remote_identity() -> None:
    workflow = read(WORKFLOW).lower()
    fresh = read(FRESH).lower()
    bound_pull = "git pull --ff-only <intended_remote> <intended_remote_ref>"

    for text, label in ((workflow, "freshness-workflow"), (fresh, "fresh-agent")):
        assert bound_pull in text, label
        assert "selected_repository_commit" in text, label

    compare = workflow_stage(workflow, "compare", "prove-executing-tree")
    prove = workflow_stage(workflow, "prove-executing-tree", "continue")
    continuation = workflow_stage(workflow, "continue")
    assert bound_pull in compare and "git rev-parse head to equal selected_repository_commit" in compare
    assert bound_pull in prove and "git rev-parse head to equal selected_repository_commit" in prove
    assert bound_pull in continuation and "git rev-parse head to equal selected_repository_commit" in continuation


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
