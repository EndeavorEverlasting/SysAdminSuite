#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREP = ROOT / "Prepare-SysAdminSuiteAutoLogonCloseout.ps1"
CMD = ROOT / "Prepare-SysAdminSuiteAutoLogonCloseout.cmd"
HANDOFF = ROOT / "scripts" / "New-SasAutoLogonDeploymentHandoff.ps1"
RUNBOOK = ROOT / "docs" / "AUTOLOGON_CLOSEOUT_PREPARATION.md"
REGISTRY = ROOT / "harness" / "api" / "harness-command-registry.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_tracked_launcher_hides_preparation_complexity() -> None:
    text = read(CMD)
    assert "Prepare-SysAdminSuiteAutoLogonCloseout.ps1" in text
    assert "HOST" in text
    assert "Guest / ordinary Internet" in text
    assert "does not contact or mutate the target" in text


def test_preparer_owns_current_controller_without_touching_historical_checkouts() -> None:
    text = read(PREP)
    assert "autologon-closeout-controller" in text
    assert "autologon-closeout-controller-preservation" in text
    assert "fetch','--all','--prune','--tags'" in text
    assert "checkout','--detach',$remoteHead" in text
    assert "Historical operator checkouts: PRESERVED / NOT USED AS AUTHORITY" in text
    for forbidden in ("reset --hard", "clean -fd", "Remove-Item -LiteralPath $controllerRoot -Recurse"):
        assert forbidden not in text, forbidden


def test_preparer_delegates_to_canonical_refresh_and_full_seal_audit() -> None:
    text = read(PREP)
    refresh = "scripts\\Refresh-SasOperatorCommand.ps1"
    audit = "scripts\\Test-SasAutoLogonRuntimeSeal.ps1"
    handoff = "scripts\\New-SasAutoLogonDeploymentHandoff.ps1"
    assert refresh in text
    assert audit in text
    assert handoff in text
    assert text.index(refresh) < text.index(audit) < text.index(handoff)
    assert "sas-autologon-short-runtime/v2" in text
    assert "GUEST_INTERNET" in text
    assert "LOCAL_FILESYSTEM_ONLY" in text
    assert "runtime_remotes_removed" in text
    assert "AUTOLOGON_CLOSEOUT_PREPARATION_COMPLETED" in text


def test_preparation_never_calls_deployment_engine_directly() -> None:
    text = read(PREP)
    for forbidden in (
        "Invoke-SasAutoLogonFieldDeployment.ps1",
        "Invoke-SasAutoLogonKerberosS4UPilot.ps1",
        "Invoke-SasAutoLogonS4URestartDeployment.ps1",
        "schtasks.exe",
        "Restart-Computer",
    ):
        assert forbidden not in text, forbidden


def test_handoff_is_pinned_and_uses_only_canonical_protected_bootstrap() -> None:
    text = read(HANDOFF)
    assert "AUTOLOGON_RUNTIME_SEAL_VERIFIED" in text
    assert "READY_FOR_PROTECTED_DEPLOYMENT" in text
    assert "Bootstrap-SysAdminSuiteAutoLogon.cmd" in text
    assert "SAS_EXPECTED" in text
    assert "next_required_network = 'PROTECTED_NORTHWELL'" in text
    assert "target_contact_performed = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "authoritative_for_deployment = $false" in text


def test_no_live_target_or_secret_literal() -> None:
    text = "\n".join(read(path).lower() for path in (PREP, CMD, HANDOFF))
    for forbidden in ("wpj075", "nslijhs.net", "defaultpassword", "password="):
        assert forbidden not in text, forbidden


def test_runbook_and_command_registry_expose_preparation_front_door() -> None:
    runbook = read(RUNBOOK)
    registry = read(REGISTRY)
    assert "Prepare-SysAdminSuiteAutoLogonCloseout.cmd HOST" in runbook
    assert "Run-Prepared-AutoLogon.cmd" in runbook
    assert '"id":"autologon-closeout-prepare"' in registry
    assert "Prepare-SysAdminSuiteAutoLogonCloseout.cmd HOST" in registry


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon closeout preparation contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
