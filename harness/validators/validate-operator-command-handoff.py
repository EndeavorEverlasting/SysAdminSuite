#!/usr/bin/env python3
"""Validate path -> freshness -> network -> execute -> restore operator handoff composition."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "harness/skills/operator-command-handoff/SKILL.md"
CANONICAL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"
ROUTE = ROOT / "harness/skills/operator-execution-route/SKILL.md"
FIELD = ROOT / ".claude/skills/field-workflow/SKILL.md"
REPO_SPRINT = ROOT / ".claude/skills/repository-sprint/SKILL.md"
INTAKE = ROOT / "harness/workflows/fresh-agent-intake.yaml"
NETWORK = ROOT / "scripts/SasNetworkIntent.psm1"
WRAPPER = ROOT / "scripts/Invoke-SasNetworkAwareField.ps1"
PORTABLE = ROOT / "scripts/SasPortableLauncher.ps1"
REFRESH = ROOT / "scripts/Refresh-SasOperatorCommand.ps1"
DOC = ROOT / "docs/OPERATOR_COMMAND_HANDOFF.md"
MAP = ROOT / "harness/maps/OPERATOR_COMMAND_HANDOFF_MAP.md"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/operator-command-handoff-contracts.yml"
TEST = ROOT / "Tests/survey/test_operator_command_handoff_contracts.py"


def read(path: Path) -> str:
    assert path.is_file(), f"missing operator handoff component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def require(text: str, marker: str, owner: str) -> None:
    assert marker in text, f"{owner} missing: {marker}"


def require_ordered_once(text: str, markers: tuple[str, ...], owner: str) -> None:
    positions: list[int] = []
    for marker in markers:
        count = text.count(marker)
        assert count == 1, f"{owner} must contain exactly one executable marker {marker!r}; found {count}"
        positions.append(text.index(marker))
    assert positions == sorted(positions), f"{owner} gate order drift: {markers}"


def main() -> int:
    paths = (
        SKILL,
        CANONICAL,
        ROUTE,
        FIELD,
        REPO_SPRINT,
        INTAKE,
        NETWORK,
        WRAPPER,
        PORTABLE,
        REFRESH,
        DOC,
        MAP,
        PRE_COMMIT,
        PRE_PUSH,
        CI,
        TEST,
    )
    for path in paths:
        assert tracked(path), f"operator handoff component not tracked: {path.relative_to(ROOT)}"

    skill = read(SKILL)
    for marker in (
        "1. **Canonical path**",
        "2. **Repository freshness**",
        "3. **Starting network + required intent**",
        "4. **Execute the canonical front door**",
        "5. **Restore the starting network",
        "capture the starting network posture before any transition",
        "Repository synchronization is an `InternetSync` subtransaction",
        "return to the recorded starting network posture",
        "git fetch --all --prune --tags",
        "git pull --ff-only",
        "Set-Location",
        "InternetSync",
        "ProtectedNorthwell",
        "LocalOnly",
        "CommandSpecific",
        "Restore-SasNetworkIntent",
        "finally",
        "sas-leave.cmd",
        "autologon-short-runtime.json",
        "prepared_commit",
        "scripts/Refresh-SasOperatorCommand.ps1",
        "A bare product snippet that starts at step 4 is invalid.",
    ):
        require(skill, marker, "operator command handoff skill")

    heading_positions = [
        skill.index("1. **Canonical path**"),
        skill.index("2. **Repository freshness**"),
        skill.index("3. **Starting network + required intent**"),
        skill.index("4. **Execute the canonical front door**"),
        skill.index("5. **Restore the starting network"),
    ]
    assert heading_positions == sorted(heading_positions), "operator handoff skill heading order drift"
    assert skill.index("capture the starting network posture before any transition") < skill.index("git fetch --all --prune --tags"), "skill must capture starting network before fetch"

    canonical = read(CANONICAL)
    route = read(ROUTE)
    field = read(FIELD)
    repo_sprint = read(REPO_SPRINT)
    intake = read(INTAKE)
    for text, owner in (
        (canonical, "canonical path skill"),
        (route, "operator execution route skill"),
        (field, "field workflow skill"),
        (repo_sprint, "repository sprint skill"),
        (intake, "fresh-agent intake"),
    ):
        require(text, "harness/skills/operator-command-handoff/SKILL.md", owner)

    require(repo_sprint, "path -> freshness -> network intent -> command -> restoration", "repository sprint skill")
    require(intake, "python harness/validators/validate-operator-command-handoff.py", "fresh-agent intake")
    require(intake, "python Tests/survey/test_operator_command_handoff_contracts.py", "fresh-agent intake")
    require(intake, "path -> freshness -> network intent -> command -> restoration", "fresh-agent intake")

    assert "  - id: execute\n" in intake and "\n  - id: validate\n" in intake, "fresh-agent intake stage boundaries missing"
    execute_stage = intake.split("  - id: execute\n", 1)[1].split("\n  - id: validate\n", 1)[0]
    gate_markers = (
        "operator handoff gate 1 canonical path",
        "operator handoff gate 2 repository freshness",
        "operator handoff gate 3 network intent",
        "operator handoff gate 4 canonical command",
        "operator handoff gate 5 restoration",
    )
    require_ordered_once(execute_stage, gate_markers, "fresh-agent execute stage")
    gate1 = next(line for line in execute_stage.splitlines() if gate_markers[0] in line)
    gate2 = next(line for line in execute_stage.splitlines() if gate_markers[1] in line)
    gate3 = next(line for line in execute_stage.splitlines() if gate_markers[2] in line)
    gate4 = next(line for line in execute_stage.splitlines() if gate_markers[3] in line)
    gate5 = next(line for line in execute_stage.splitlines() if gate_markers[4] in line)
    require(gate1, "captures the starting network", "fresh-agent gate 1")
    require(gate1, "before any freshness or product transition", "fresh-agent gate 1")
    require(gate2, "InternetSync", "fresh-agent gate 2")
    require(gate2, "returns to the captured starting network posture", "fresh-agent gate 2")
    require(gate3, "recorded/restored starting posture", "fresh-agent gate 3")
    require(gate4, "after gates 1 through 3 plus any separate production/runtime currentness proof are proven", "fresh-agent gate 4")
    require(gate5, "Restore-SasNetworkIntent", "fresh-agent gate 5")
    require(execute_stage, "for sealed C:\\SASAL AutoLogon routes, do not run Git in the sealed runtime", "fresh-agent sealed runtime")
    require(execute_stage, "autologon-short-runtime.json prepared_commit plus SHA-256 seal to match the selected_repository_commit", "fresh-agent sealed runtime")

    handoff_stage = intake.split("  - id: handoff\n", 1)[1]
    for marker in (
        "freshness proof must precede command handoff",
        "atomic pull-first route-and-run command",
        "bound to intended_remote and intended_remote_ref",
        "post-pull head equality with selected_repository_commit",
    ):
        require(handoff_stage, marker, "fresh-agent freshness compatibility")

    network = read(NETWORK)
    for marker in (
        "'InternetSync'",
        "'ProtectedNorthwell'",
        "'LocalOnly'",
        "'CommandSpecific'",
        "SAVED_WLAN_PROFILE",
        "restore_required",
        "restore_profile",
        "SAS_NETWORK_TRANSITION_MANUAL_VPN_REQUIRED",
        "SAS_NETWORK_TRANSITION_MANUAL_WIRED_REQUIRED",
    ):
        require(network, marker, "network intent authority")

    wrapper = read(WRAPPER)
    for marker in (
        "Enter-SasNetworkIntent",
        "& powershell.exe @childArgs",
        "finally",
        "Restore-SasNetworkIntent",
        "if ($restoreFailed -and $childExit -eq 0) { $childExit = 1 }",
    ):
        require(wrapper, marker, "network-aware wrapper")
    assert wrapper.index("Enter-SasNetworkIntent") < wrapper.index("& powershell.exe @childArgs") < wrapper.index("Restore-SasNetworkIntent"), "network wrapper transaction ordering drift"
    finally_section = wrapper.split("finally {", 1)[1]
    require(finally_section, "Restore-SasNetworkIntent", "network-aware wrapper finally block")

    refresh = read(REFRESH)
    for marker in (
        "GUEST_INTERNET",
        "sync-cache",
        "field-ready",
        "C:\\SASAL",
        "prepared_commit",
    ):
        require(refresh, marker, "refresh/seal authority")
    require(refresh, "No target contact or target mutation occurs in this script.", "refresh/seal authority")

    portable = read(PORTABLE)
    for marker in (
        "autologon-short-runtime.json",
        "sas-autologon-short-runtime/v2",
        "prepared_commit",
        "LOCAL_FILESYSTEM_ONLY",
        "runtime_remotes_removed",
        "tracked_file_hash_algorithm",
        "SHA256",
        "Protected-side Git activity: NONE",
    ):
        require(portable, marker, "sealed runtime authority")

    for marker in (
        "one copy-paste",
        "C:\\SASAL",
        "prepared_commit",
        "scripts/Refresh-SasOperatorCommand.ps1",
        "do not run remote Git inside `C:\\SASAL`",
    ):
        require(route, marker, "operator execution route skill")

    doc = read(DOC)
    map_text = read(MAP)
    for text, owner in ((doc, "operator handoff documentation"), (map_text, "operator handoff map")):
        require(text, "canonical path", owner)
        require(text, "freshness", owner)
        require(text, "network", owner)
        require(text, "restor", owner)
    require(map_text, "path -> freshness -> network intent -> command -> restoration", "operator handoff map")

    pre_commit = read(PRE_COMMIT)
    pre_push = read(PRE_PUSH)
    for text, owner in ((pre_commit, "pre-commit hook"), (pre_push, "pre-push hook")):
        require(text, "validate-operator-command-handoff.py", owner)
        require(text, "test_operator_command_handoff_contracts.py", owner)
    for marker in (
        "snapshot_tree=\"$(git write-tree)\"",
        "GIT_INDEX_FILE=\"$snapshot_index\" git read-tree \"$snapshot_tree\"",
        "GIT_INDEX_FILE=\"$snapshot_index\" git checkout-index",
        "export GIT_INDEX_FILE=\"$snapshot_index\"",
    ):
        require(pre_commit, marker, "pre-commit frozen-index snapshot")
    require(pre_push, "has_operator_handoff", "pre-push hook")

    ci = read(CI)
    require(ci, "python harness/validators/validate-operator-command-handoff.py", "focused CI")
    require(ci, "python Tests/survey/test_operator_command_handoff_contracts.py", "focused CI")
    require(ci, "git diff --check", "focused CI")

    print("PASS: operator command handoff composition")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
