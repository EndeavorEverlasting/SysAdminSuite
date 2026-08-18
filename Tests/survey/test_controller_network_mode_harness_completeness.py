#!/usr/bin/env python3
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[2]

REQUIRED = [
    "harness/maps/controller-network-mode-map.md",
    "harness/workflows/controller-network-mode-serialization.yaml",
    "harness/api/controller-network-mode-artifact-registry.json",
    "schemas/harness/controller-network-mode-artifact-registry.schema.json",
    "harness/validators/validate-controller-network-mode.py",
    "harness/skills/controller-network-mode-serialization/SKILL.md",
    "harness/reports/CONTROLLER_NETWORK_MODE_STATUS.md",
    ".github/workflows/controller-network-mode-harness.yml",
]


def fail(message: str) -> None:
    raise AssertionError(message)


def text(path: str) -> str:
    candidate = ROOT / path
    if not candidate.is_file():
        fail(f"missing harness component: {path}")
    return candidate.read_text(encoding="utf-8")


def main() -> int:
    groups = 0

    for path in REQUIRED:
        text(path)
    groups += 1

    registry = json.loads(text("harness/api/controller-network-mode-artifact-registry.json"))
    tracked_paths = {item["path"] for item in registry["artifacts"] if item["tracked"]}
    expected_tracked = {
        "harness/maps/controller-network-mode-map.md",
        "harness/workflows/controller-network-mode-serialization.yaml",
        "harness/skills/controller-network-mode-serialization/SKILL.md",
        "harness/reports/CONTROLLER_NETWORK_MODE_STATUS.md",
    }
    if not expected_tracked.issubset(tracked_paths):
        fail("registry does not register every tracked map/workflow/skill/report")
    groups += 1

    workflow = text("harness/workflows/controller-network-mode-serialization.yaml")
    for token in (
        "OFF_NETWORK_REPOSITORY_PREP",
        "TRANSITION_TO_PROTECTED_NETWORK",
        "PROTECTED_NETWORK_DEPLOYMENT",
        "no_git_after_transition",
        "refs/pull/<pr>/head",
        "refs/sas-cert/pr-<pr>",
        "REMOTE_PR_HEAD_UNAVAILABLE_OR_MOVED",
        "PRODUCT_RUNTIME_GIT_DEPENDENCY",
    ):
        if token not in workflow:
            fail(f"workflow missing {token}")
    groups += 1

    docs = (
        text("harness/maps/controller-network-mode-map.md")
        + text("harness/skills/controller-network-mode-serialization/SKILL.md")
        + text("harness/reports/CONTROLLER_NETWORK_MODE_STATUS.md")
    )
    for token in (
        "refs/pull/<pr>/head",
        "refs/sas-cert/pr-<pr>",
        "REMOTE_PR_HEAD_UNAVAILABLE_OR_MOVED",
    ):
        if token not in docs:
            fail(f"map/skill/report missing PR certification token {token}")
    groups += 1

    hooks = text(".githooks/pre-commit") + text(".githooks/pre-push")
    for token in (
        "validate-controller-network-mode.py",
        "test_controller_network_mode_harness_completeness.py",
    ):
        if token not in hooks:
            fail(f"hooks missing {token}")
    groups += 1

    intake = text("harness/workflows/fresh-agent-intake.yaml")
    fallback = text(".claude/skills/repository-sprint/SKILL.md")
    if "controller-network-mode-serialization" not in intake:
        fail("fresh-agent intake does not route controller network-mode incidents")
    if "controller-network-mode-serialization.yaml" not in fallback:
        fail("repository-sprint fallback does not route controller network-mode incidents")
    groups += 1

    ci = text(".github/workflows/controller-network-mode-harness.yml")
    for token in (
        "validate-controller-network-mode.py",
        "test_controller_network_mode_harness_completeness.py",
        "git diff --check",
    ):
        if token not in ci:
            fail(f"CI missing {token}")
    groups += 1

    print(f"PASS: controller network-mode harness completeness ({groups} groups)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
