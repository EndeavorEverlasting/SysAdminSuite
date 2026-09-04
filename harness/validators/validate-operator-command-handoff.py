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
        "A bare product snippet that starts at step 4 is invalid.",
    ):
        require(skill, marker, "operator command handoff skill")

    ordering = [
        skill.index("1. **Canonical path**"),
        skill.index("2. **Repository freshness**"),
        skill.index("3. **Starting network + required intent**"),
        skill.index("4. **Execute the canonical front door**"),
        skill.index("5. **Restore the starting network"),
    ]
    assert ordering == sorted(ordering), "operator handoff gate order drift"

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
    require(pre_push, "has_operator_handoff", "pre-push hook")

    ci = read(CI)
    require(ci, "python harness/validators/validate-operator-command-handoff.py", "focused CI")
    require(ci, "python Tests/survey/test_operator_command_handoff_contracts.py", "focused CI")
    require(ci, "git diff --check", "focused CI")

    print("PASS: operator command handoff composition")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
