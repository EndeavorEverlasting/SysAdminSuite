#!/usr/bin/env python3
"""Contracts for revoking stale software-deployment review and approval state."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUARD = ROOT / "dashboard/js/software-deployment-input-invalidation.js"
LOADER = ROOT / "dashboard/js/launch-repo-setup-tutorial.js"
RUNTIME = ROOT / "dashboard/test_software_deployment_tutorial.js"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_every_pilot_defining_input_is_watched() -> None:
    guard = read(GUARD)
    for field_id in (
        "software-deployment-target",
        "software-deployment-package",
        "software-deployment-path",
        "software-deployment-args",
        "software-deployment-mode",
    ):
        assert field_id in guard
    assert "field.addEventListener('input', invalidate)" in guard
    assert "field.addEventListener('change', invalidate)" in guard


def test_input_edits_revoke_all_stale_authority() -> None:
    guard = read(GUARD)
    for marker in (
        "copiedRevision: -1",
        "planReviewed: false",
        "approvals: approvals.map(() => false)",
        "software-deployment-plan-reviewed",
        "[data-deploy-approval]",
        "Pilot inputs changed",
    ):
        assert marker in guard


def test_progress_fails_closed_until_current_request_is_reapproved() -> None:
    guard = read(GUARD)
    assert "requestMatchesCopiedRevision" in guard
    assert "event.stopImmediatePropagation()" in guard
    assert "if (step >= 5)" in guard
    assert "!planReviewed()" in guard
    assert "approvals.some(box => !box.checked)" in guard
    assert "next.addEventListener('click'" in guard
    assert "}, true);" in guard


def test_guard_loads_only_after_the_primary_tutorial() -> None:
    loader = read(LOADER)
    assert "software-deployment-input-invalidation.js" in loader
    assert "script.onload = loadSoftwareDeploymentInputInvalidation" in loader
    assert "Live pilot progression is unavailable" in loader


def test_runtime_smoke_executes_the_invalidation_helper() -> None:
    runtime = read(RUNTIME)
    assert "software-deployment-input-invalidation.js" in runtime
    assert "invalidateReviewState" in runtime
    assert "edited pilot input must revoke copied-command state" in runtime
    assert "edited pilot input must revoke WhatIf acknowledgement" in runtime
    assert "edited pilot input must revoke every live approval" in runtime


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: software deployment input invalidation contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
