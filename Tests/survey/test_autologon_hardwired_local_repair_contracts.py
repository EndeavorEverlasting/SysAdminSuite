#!/usr/bin/env python3
"""Contracts for protected hardwired local-only AutoLogon runtime reseal/deploy."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonHardwiredLocalRepair.ps1"
CMD = ROOT / "Run-AutoLogonHardwiredLocalRepair.cmd"
DOC = ROOT / "docs" / "AUTOLOGON_HARDWIRED_LOCAL_REPAIR.md"
REGISTRY = ROOT / "harness" / "api" / "harness-command-registry.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing hardwired local-repair surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_source_is_exact_clean_local_checkout_before_any_runtime_mutation() -> None:
    text = read(SCRIPT)
    for marker in (
        "source must be an already-local drive path",
        "source checkout and sealed runtime must be different local roots",
        "@('rev-parse','--is-inside-work-tree')",
        "@('rev-parse','HEAD')",
        "local source HEAD mismatch",
        "@('status','--porcelain')",
        "local source checkout is dirty; no runtime mutation was started",
        "@('ls-files')",
        "exact local source returned no tracked files",
    ):
        assert marker in text, marker
    source_head = text.index("$sourceHead =")
    source_clean = text.index("$sourceDirty =")
    network = text.index("PROVING DOMAIN-AUTHENTICATED NON-WIFI NORTHWELL AUTHORITY")
    runtime_mutation = text.index("LOCAL-ONLY HARDWIRED RUNTIME RESEAL")
    assert source_head < source_clean < network < runtime_mutation


def test_prior_sealed_runtime_is_required_and_never_force_cleaned() -> None:
    text = read(SCRIPT)
    for marker in (
        "a prior sealed AutoLogon v2 manifest is required",
        "sas-autologon-short-runtime/v2",
        "runtime_remotes_removed",
        "protected_bootstrap_git_network_allowed",
        "C:\\SASAL contains local work. Nothing was reset, cleaned, or overwritten.",
    ):
        assert marker in text, marker
    lowered = text.lower()
    for forbidden in ("reset --hard", "clean -fd", "clean -xdf", "remove-item -recurse $runtimeroot"):
        assert forbidden not in lowered, forbidden


def test_network_authority_precedes_runtime_transfer_and_target_contact() -> None:
    text = read(SCRIPT)
    for marker in (
        "Enable-SasNorthwellVpnNetworkGuard.ps1",
        "-ConfirmVpnPosture",
        "SAS_VPN_NETWORK_GUARD_READY",
        "target_contact_performed",
        "target_mutation_performed",
        "$env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig",
    ):
        assert marker in text, marker
    network = text.index("PROVING DOMAIN-AUTHENTICATED NON-WIFI NORTHWELL AUTHORITY")
    transfer = text.index("LOCAL-ONLY HARDWIRED RUNTIME RESEAL")
    deploy = text.index("STARTING EXISTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION")
    assert network < transfer < deploy


def test_only_explicit_local_git_verbs_and_local_fetch_are_allowed() -> None:
    text = read(SCRIPT)
    assert "@('rev-parse','status','ls-files','fetch','checkout','remote')" in text
    assert "@('fetch','--no-tags','--no-write-fetch-head',$SourceRoot,$ExpectedCommit)" in text
    assert "[string]$Arguments[3] -ne $SourceRoot" in text
    assert "[string]$Arguments[-1] -ne $ExpectedCommit" in text
    for marker in (
        "hardwired Git fetch must name the already-local SourceRoot explicitly",
        "hardwired local fetch must request the exact expected commit",
        "preparation_git_transport = 'LOCAL_FILESYSTEM_ONLY'",
        "preparation_remote_git_performed = $false",
        "Remote repository acquisition: NONE",
    ):
        assert marker in text, marker
    lowered = text.lower()
    for forbidden in (
        "github.com",
        "ls-remote",
        "git pull",
        "git clone",
        "fetch origin",
        "http://",
        "https://",
    ):
        assert forbidden not in lowered, forbidden


def test_full_current_tracked_tree_is_transferred_and_resealed() -> None:
    text = read(SCRIPT)
    for marker in (
        "$sourceTracked = @(",
        "$runtimeTracked = @(",
        "Compare-Object -ReferenceObject $sourceTracked -DifferenceObject $runtimeTracked",
        "source/runtime tracked-file sets differ after exact local transfer",
        "Get-SasSha256Hex",
        "tracked_file_hash_algorithm = 'SHA256'",
        "tracked_file_count = $hashes.Count",
        "tracked_file_hashes = $hashes",
        "post-seal SHA-256 mismatch",
    ):
        assert marker in text, marker
    assert "repairLaneAddedTrackedPaths" not in text
    assert "previousEntries" not in text


def test_runtime_is_exact_detached_commit_and_has_no_remotes_before_deploy() -> None:
    text = read(SCRIPT)
    for marker in (
        "@('checkout','--detach',$ExpectedCommit)",
        "runtime HEAD mismatch",
        "@('remote','remove',[string]$remote)",
        "still has a Git remote after local-only reseal",
        "runtime_remotes_removed = $true",
        "protected_bootstrap_git_network_allowed = $false",
    ):
        assert marker in text, marker
    checkout = text.index("@('checkout','--detach',$ExpectedCommit)")
    manifest = text.index("$manifest = [pscustomobject][ordered]@{")
    deploy = text.index("STARTING EXISTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION")
    assert checkout < manifest < deploy


def test_hardwired_manifest_stays_v2_but_records_truthful_provenance() -> None:
    text = read(SCRIPT)
    for marker in (
        "schema_version = 'sas-autologon-short-runtime/v2'",
        "preparation_network_classification = 'PROTECTED_NORTHWELL'",
        "preparation_mode = 'HARDWIRED_LOCAL_RESEAL'",
        "preparation_git_transport = 'LOCAL_FILESYSTEM_ONLY'",
        "preparation_remote_git_performed = $false",
        "runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
        "autologon-hardwired-local-reseal.json",
        "sas-autologon-hardwired-local-reseal/v1",
    ):
        assert marker in text, marker
    assert "preparation_network_classification = 'GUEST_INTERNET'" not in text


def test_existing_crash_safe_autologon_only_transaction_remains_the_deploy_owner() -> None:
    text = read(SCRIPT)
    for marker in (
        "Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "-ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -RepositoryHead $ExpectedCommit -ConfirmDeployment",
        "HARDWIRED_AUTOLOGON_FAILED",
        "do not blindly rerun",
        "HARDWIRED_AUTOLOGON_TRANSACTION_RETURNED_SUCCESS",
    ):
        assert marker in text, marker
    for forbidden in (
        "Deploy-CybernetSoftware",
        "Deploy-CybernetClinicalCore",
        "Invoke-SasCybernetSoftwareDeployment",
    ):
        assert forbidden not in text, forbidden


def test_cmd_is_short_and_forwards_only_target_exact_commit_and_confirmation() -> None:
    text = read(CMD)
    for marker in (
        "Usage: Run-AutoLogonHardwiredLocalRepair.cmd HOST EXPECTED_COMMIT",
        "Invoke-SasAutoLogonHardwiredLocalRepair.ps1",
        '-ComputerName "%SAS_TARGET%"',
        '-ExpectedCommit "%SAS_EXPECTED%"',
        '-SourceRoot "%SAS_ROOT%"',
        "-ConfirmDeployment",
        "Remote repository acquisition: NONE",
        "Runtime transfer: LOCAL FILESYSTEM ONLY",
        "Clinical-core deployment: NONE",
    ):
        assert marker in text, marker


def test_command_registry_names_the_explicit_hardwired_lane() -> None:
    registry = json.loads(read(REGISTRY))
    commands = {entry["id"]: entry for entry in registry["commands"]}
    entry = commands["autologon-hardwired-local-repair"]
    assert entry["command"] == "Run-AutoLogonHardwiredLocalRepair.cmd HOST EXPECTED_COMMIT"
    assert entry["source_of_truth"] == "scripts/Invoke-SasAutoLogonHardwiredLocalRepair.ps1"
    assert entry["mutation"] == "authorized_target_mutation"
    assert entry["network"] is True
    assert "already-local" in entry["purpose"]
    assert "remote repository acquisition" in entry["purpose"]


def test_doc_preserves_guest_remote_acquisition_boundary() -> None:
    text = read(DOC).lower()
    for marker in (
        "ordinary `sas refresh` remains guest/internet-only",
        "already-local clean checkout",
        "domainauthenticated non-wi-fi",
        "remote repository acquisition",
        "local filesystem",
        "full current tracked tree",
        "existing crash-safe autologon transaction",
        "do not blindly rerun",
    ):
        assert marker in text, marker


def test_no_live_target_secret_or_private_operator_literal() -> None:
    combined = "\n".join(read(path) for path in (SCRIPT, CMD, DOC)).lower()
    for forbidden in (
        "wpj075opr046",
        "nslijhs.net",
        "pa_rperez26",
        "defaultpassword",
        "password=",
    ):
        assert forbidden not in combined, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    assert len(tests) >= 12, f"hardwired local-repair contract floor shrank unexpectedly: {len(tests)}"
    for test in tests:
        test()
    print(f"PASS: AutoLogon hardwired local repair contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
