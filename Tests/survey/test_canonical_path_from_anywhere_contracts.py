#!/usr/bin/env python3
"""Contracts for canonical SysAdminSuite resolution from an arbitrary shell directory."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/canonical-path-registry.json"
WORKFLOW = ROOT / "harness/workflows/canonical-path-resolution.yaml"
SKILL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"
RESOLVER = ROOT / "scripts/Resolve-SasCanonicalDevelopmentPath.ps1"
CI = ROOT / ".github/workflows/canonical-path-contracts.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing from-anywhere path surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def assert_registry_owns_resolver() -> None:
    registry = load(REGISTRY)
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert "scripts/Resolve-SasCanonicalDevelopmentPath.ps1" in registry["consumers"]
    assert registry["policy"]["canonical_development_checkout_must_be_unique"] is True
    assert registry["policy"]["canonical_development_checkout_requires_git_io_health"] is True
    assert registry["policy"]["second_mutable_clone_is_forbidden"] is True
    assert registry["policy"]["desktop_dev_root_is_authoritative"] is True
    assert registry["policy"]["onedrive_toggle_does_not_choose_desktop_location"] is True
    admin = next(item for item in registry["profiles"] if item["id"] == "windows-admin-box")
    assert admin["production_use_path"]["template"] == "C:\\SASAL"
    assert admin["production_use_path"]["mutable"] is False
    assert admin["real_operator_entrypoint"]["production_update_authority"] == "scripts/Refresh-SasOperatorCommand.ps1"
    assert "never ad-hoc" in admin["real_operator_entrypoint"]["production_update_boundary"].lower()
    safety = registry["operator_command_safety"]
    assert safety["powershell_if_else_must_be_one_paste_block"] is True
    assert safety["powershell_native_failure_must_abort_single_paste_block"] is True
    assert safety["next_command_must_not_require_unmerged_default_branch_artifact"] is True
    assert "arbitrary-shell" in safety["reason"]
    assert "production/use paths" in safety["reason"]


def assert_resolver_fails_closed_without_cwd_authority() -> None:
    text = read(RESOLVER)
    required = (
        "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)",
        "Join-Path $desktopKnownFolder 'Dev'",
        "Join-Path $desktopDev 'SysAdminSuite'",
        "desktop_known_folder = $desktopKnownFolder",
        "desktop_source = $desktopSource",
        "OneDriveCommercial",
        "OneDriveConsumer",
        "TARGET_FOLDER_REDIRECTED",
        "ROOT_UNAVAILABLE",
        "MULTIPLE_ROOTS",
        "CANONICAL_DEVELOPMENT",
        "ISOLATED_WORKTREE",
        "UPDATER_SYNC_CACHE",
        "UPDATER_FIELD_READY_WORKTREE",
        "EPHEMERAL_ACQUISITION",
        "CONFLICT_WRONG_REPOSITORY",
        "CONFLICT_NESTED_OR_WRONG_ROOT",
        "CONFLICT_REPARSE_POINT_UNINSPECTED",
        "CONFLICT_GIT_IO_UNHEALTHY",
        "status --porcelain=v1 --untracked-files=no --ignore-submodules=dirty",
        "canonical_git_io_health = $canonicalGitIoHealth",
        "CANONICAL_PROVED",
        "current_directory_is_authority = $false",
        "path_semantics = 'WINDOWS_CASE_INSENSITIVE_NORMALIZED_FULL_PATH'",
        "path_disposition = $pathDisposition",
        "canonical_checkout_reparse_state = $canonicalReparseState",
        "canonical_entrypoint_authority = $entrypointAuthority",
        "path_relation = $pathRelation",
        "exit 3",
    )
    for marker in required:
        assert marker in text, f"resolver missing fail-closed/path-input marker: {marker}"
    assert "do not create a fallback clone elsewhere" in text.lower()
    assert "evilgithub.com" not in text

    for disposition in (
        "'CANONICAL + PROVED'",
        "'NONCANONICAL + PRESERVE'",
        "'MISSING'",
        "'CONFLICT'",
        "'UNKNOWN'",
    ):
        assert disposition in text, f"resolver missing path disposition: {disposition}"

    forbidden = (
        "pa_rperez26",
        "CheeksMcClappeth",
        "git clone",
        "reset --hard",
        "%USERPROFILE%\\Desktop\\Dev\\SysAdminSuite",
        "$desktop = Split-Path -Parent $desktopDev",
    )
    for marker in forbidden:
        assert marker not in text, f"resolver contains forbidden machine-specific/destructive behavior: {marker}"


def assert_execution_context_and_production_use_state_are_explicit() -> None:
    text = read(RESOLVER)
    for marker in (
        "execution_context_status = $executionContextStatus",
        "execution_target_source = $executionTargetSource",
        "terminal_host = $terminalHost",
        "terminal_application = $terminalApplication",
        "shell_interpreter = $processPath",
        "powershell_edition = $powershellEdition",
        "powershell_version = $powershellVersion",
        "runtime_boundary = $runtimeBoundary",
        "execution_target = $executionTarget",
        "current_location_provider = $currentLocationProvider",
        "current_working_directory = $currentWorkingDirectory",
        "current_working_directory_filesystem = $currentWorkingDirectoryFileSystem",
        "WINDOWS_PROCESS_CONTEXT_PARTIAL",
        "EXPLICIT_EXECUTION_TARGET",
        "PROVED_WINDOWS_CI",
        "UNKNOWN_NOT_PROBED",
        "production_use_state = $productionUseState",
        "production_use_state_evidence = $productionUseStateEvidence",
        "production_use_reparse_state = $productionReparseState",
        "production_ad_hoc_mutation_allowed = $productionAdHocMutationAllowed",
        "production_update_authority = $productionUpdateAuthority",
        "production_update_boundary = $productionUpdateBoundary",
        "development_mutation_guard = $developmentMutationGuard",
        "remote_integration_is_local_deployment = $false",
        "cleanup_authorized = $false",
    ):
        assert marker in text, f"execution/production receipt missing: {marker}"

    assert "$executionTarget = 'UNKNOWN'" in text
    assert "$currentLocationProvider -eq 'FileSystem'" in text
    assert "UNKNOWN_NON_FILESYSTEM_CURRENT_LOCATION" in text
    assert "Registered production/use path exists, but this read-only resolver does not infer quiescence" in text
    assert "$productionUseState = 'UNKNOWN'" in text
    assert "$productionUseState = 'OFFLINE'" in text
    assert "$productionUseState = 'NOT_APPLICABLE'" in text
    assert "$productionAdHocMutationAllowed = $false" in text
    assert "SAME_PHYSICAL_PATH_PRODUCTION_IMPACTING" in text
    assert "UNKNOWN_REPARSE_POINT_RELATION" in text
    assert "BLOCK_UNTIL_PHYSICAL_PATH_RELATION_PROVED" in text
    assert "BLOCK_UNTIL_PRODUCTION_QUIESCED_OR_TRACKED_IN_PLACE_SAFETY_PROVED" in text


def assert_bounded_copy_inventory_prevents_path_sprawl() -> None:
    text = read(RESOLVER)
    for marker in (
        "candidate_location_class = $candidateLocationClass",
        "location_class_vocabulary = @('CLONE','WORKTREE','INSTALL','MIRROR','CACHE','OUTPUT','BACKUP','UNKNOWN')",
        "known_location_inventory = $knownLocations",
        "PRESERVE_UNTIL_PROVED_DISPOSABLE",
        "short-runtime-preservation",
        "closeout-entry-*",
        "sync-cache",
        "field-ready",
        "UPDATER_SYNC_CACHE",
        "UPDATER_FIELD_READY_WORKTREE",
        "APPROVED_ISOLATED_WORKTREE",
        "RUNTIME_OUTPUT_ROOT",
        "PRESERVED_RUNTIME_BACKUP",
    ):
        assert marker in text, f"copy classification/inventory missing: {marker}"
    assert "Get-PSDrive" not in text, "resolver must not broaden bounded copy inventory into arbitrary drive scanning"
    assert "disposition='DISPOSABLE'" not in text, "resolver must not declare a copy disposable without content/ownership proof"


def assert_workflow_and_skill_block_the_recurrence() -> None:
    workflow = read(WORKFLOW)
    skill = read(SKILL)
    for text, label in ((workflow, "workflow"), (skill, "skill")):
        assert "current working directory" in text.lower(), f"{label} must classify CWD as evidence only"
        assert "git rev-parse --show-toplevel" in text, f"{label} must name the original bad bootstrap"
        assert "fallback clone" in text.lower(), f"{label} must forbid fallback checkout creation"
        assert "git i/o" in text.lower(), f"{label} must require Git I/O health"
        assert "unmerged" in text.lower(), f"{label} must forbid default-branch dependence on unmerged helpers"

    for marker in (
        "resolve-execution-context",
        "PROD_USE_STATE",
        "UNKNOWN is not idle",
        "ACTIVE or UNKNOWN production/use state blocks ad-hoc production-path mutation",
        "path_relation=SAME_PHYSICAL_PATH_PRODUCTION_IMPACTING",
        "path_relation=UNKNOWN_REPARSE_POINT_RELATION",
        "CLONE, WORKTREE, INSTALL, MIRROR, CACHE, OUTPUT, BACKUP, or UNKNOWN",
        "production_update_authority",
        "cleanup_authorized",
        "terminal_application",
        "powershell_edition",
        "powershell_version",
        "current_working_directory",
        "execution_target=UNKNOWN",
        "non-filesystem",
        "sync-cache",
        "field-ready",
    ):
        assert marker.lower() in workflow.lower(), f"workflow missing execution/use safety marker: {marker}"

    for marker in (
        "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)",
        "& {",
        "$LASTEXITCODE",
        "status --porcelain=v1 --untracked-files=no --ignore-submodules=dirty",
        "native-command failures do not honor `$ErrorActionPreference`",
        "Never make an unmerged helper a prerequisite",
    ):
        assert marker.lower() in skill.lower(), f"skill is missing atomic recurrence-prevention marker: {marker}"


def assert_provider_fixture_is_wired() -> None:
    ci = read(CI)
    for marker in (
        "scripts/Resolve-SasCanonicalDevelopmentPath.ps1",
        "Tests/survey/test_canonical_path_from_anywhere_contracts.py",
        "windows-resolution:",
        "Start outside any Git repository",
        "Prove missing canonical checkout fails closed",
        "Prove wrong repository checkout fails closed",
        "Prove Git I/O unhealthy checkout fails closed",
        "Prove explicit canonical checkout succeeds",
        "CONFLICT_GIT_IO_UNHEALTHY",
        "canonical_git_io_health",
        "CONFLICT_WRONG_REPOSITORY",
        "Explicit DesktopDevRoot incorrectly replaced real Desktop Known Folder",
    ):
        assert marker in ci, f"canonical path CI missing provider proof marker: {marker}"


def main() -> int:
    assert_registry_owns_resolver()
    assert_resolver_fails_closed_without_cwd_authority()
    assert_execution_context_and_production_use_state_are_explicit()
    assert_bounded_copy_inventory_prevents_path_sprawl()
    assert_workflow_and_skill_block_the_recurrence()
    assert_provider_fixture_is_wired()
    print("[PASS] canonical path registry owns uniqueness, Git I/O health, and atomic/default-branch-safe handoffs")
    print("[PASS] resolver keeps actual Windows Desktop Known Folder distinct from an explicit Desktop Dev override")
    print("[PASS] resolver fails closed on cwd, OneDrive conflicts, wrong origin, reparse state, and Git I/O failure")
    print("[PASS] execution target stays UNKNOWN unless explicitly/provably scoped; non-filesystem providers remain resolvable")
    print("[PASS] PROD_USE_STATE, same/reparse path safety, and registered production update authority are explicit")
    print("[PASS] bounded updater/worktree/cache/output/backup inventory forbids silent cleanup")
    print("[PASS] workflow blocks repeated native-continuation, production-mutation, and unmerged-helper handoff defects")
    print("[PASS] Windows provider fixtures cover missing, wrong-repository, unhealthy-I/O, and canonical checkout states")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
