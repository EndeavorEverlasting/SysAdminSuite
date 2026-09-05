#!/usr/bin/env python3
"""Contracts for the Windows Admin Box canonical development/use split."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/canonical-path-registry.json"
RESOLVER = ROOT / "scripts/Resolve-SasCanonicalDevelopmentPath.ps1"
WORKFLOW = ROOT / "harness/workflows/canonical-path-resolution.yaml"
SKILL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing Admin Box path contract: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_admin_box_has_one_explicit_role_map() -> None:
    registry = json.loads(read(REGISTRY))
    profiles = [item for item in registry["profiles"] if item["id"] == "windows-admin-box"]
    assert len(profiles) == 1
    admin = profiles[0]
    assert admin["canonical_development_checkout"]["template"] == "{desktop_dev_root}\\SysAdminSuite"
    assert admin["canonical_development_checkout"]["mutable"] is True
    assert admin["temporary_worktree_root"]["template"] == "%LOCALAPPDATA%\\SysAdminSuite\\worktrees"
    assert admin["production_use_path"]["template"] == "C:\\SASAL"
    assert admin["production_use_path"]["mutable"] is False
    assert admin["real_operator_entrypoint"]["production_runtime_entrypoint"] == "C:\\SASAL\\Bootstrap-SysAdminSuiteAutoLogon.cmd"
    assert admin["real_operator_entrypoint"]["production_update_authority"] == "scripts/Refresh-SasOperatorCommand.ps1"


def test_production_use_state_never_assumes_idle() -> None:
    text = read(RESOLVER)
    assert "$productionUseState = 'OFFLINE'" in text
    assert "$productionUseState = 'UNKNOWN'" in text
    assert "does not infer quiescence" in text
    assert "$productionAdHocMutationAllowed = $false" in text
    assert "production_ad_hoc_mutation_allowed = $productionAdHocMutationAllowed" in text
    assert "BLOCK_UNTIL_PRODUCTION_QUIESCED_OR_TRACKED_IN_PLACE_SAFETY_PROVED" in text


def test_reparse_ambiguity_blocks_physical_relation_claims() -> None:
    text = read(RESOLVER)
    for marker in (
        "REPARSE_POINT_PRESENT",
        "UNKNOWN_REPARSE_POINT_RELATION",
        "BLOCK_UNTIL_PHYSICAL_PATH_RELATION_PROVED",
        "path_relation_evidence = $pathRelationEvidence",
        "Physical relation is not trusted because canonical_reparse=",
    ):
        assert marker in text, marker
    workflow = read(WORKFLOW)
    assert "path_relation=SAME_PHYSICAL_PATH_PRODUCTION_IMPACTING" in workflow
    assert "path_relation=UNKNOWN_REPARSE_POINT_RELATION" in workflow
    assert "junction, symlink, mount" in workflow


def test_bounded_inventory_includes_real_approved_worktree_children() -> None:
    text = read(RESOLVER)
    assert "Get-ChildItem -LiteralPath $worktreeRoot -Directory" in text
    assert "role='APPROVED_ISOLATED_WORKTREE'" in text
    assert "disposition='PRESERVE_UNTIL_PROVED_DISPOSABLE'" in text
    assert "Get-PSDrive" not in text


def test_skill_treats_use_path_as_consumer_not_checkout() -> None:
    skill = read(SKILL).lower()
    assert "production/use path is a **consumer path**" in skill
    assert "c:\\sasal" in skill
    assert "scripts/refresh-sasoperatorcommand.ps1" in skill
    assert "unknown` is not idle" in skill
    assert "never copy a partial tree into production" in skill


def main() -> int:
    tests = [fn for name, fn in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Admin Box canonical path/use-state contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
