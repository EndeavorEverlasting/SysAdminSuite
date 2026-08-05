#!/usr/bin/env python3
"""Completion contracts for the supported AutoLogon field-deployment transaction."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"
RECOVERY = ROOT / "scripts" / "Recover-SasLatestInterruptedAutoLogonS4U.ps1"
STATE = ROOT / "scripts" / "SasAutoLogonOperatorState.psm1"
DOC = ROOT / "docs" / "AUTOLOGON_FIELD_DEPLOYMENT_COMPLETION.md"


def read(path: Path) -> str:
    assert path.is_file(), path
    return path.read_text(encoding="utf-8-sig")


def test_deterministic_legacy_completion_then_apply_boundary_once() -> None:
    """Synthetic source-level E2E: old probe schema + completed recovery + short target."""
    field = read(FIELD)
    recovery = read(RECOVERY)
    requested_target = "WPJ075OPR046"
    resolved_target = "wpj075opr046.nslijhs.net"
    assert requested_target.split(".")[0].lower() == resolved_target.split(".")[0].lower()
    assert "Get-SasOptionalJsonString -Object $lifecycle -Name 'mode'" in recovery
    assert "$previousStatus -eq 'COMPLETED'" in recovery
    assert "$previousClassification -eq 'S4U_PROBE_CREATE_HANG_RECOVERED'" in recovery
    assert "classification='NO_INTERRUPTED_PROBE_RUN_FOUND'" in recovery
    assert "Resolve-SasCanonicalTargetFqdn -TargetName $requestedTarget" in field
    assert "$result.apply_invocation_count = 1" in field
    assert field.count("& $deploymentScript -ComputerName $resolvedTarget") == 1
    assert "clinical_core_invoked = $false" in field


def test_apply_is_unreachable_without_completed_safe_recovery_gate() -> None:
    text = read(FIELD)
    recovery = text.index("$recovery = & $recoveryScript")
    complete = text.index("'NO_INTERRUPTED_PROBE_RUN_FOUND'", recovery)
    complete2 = text.index("'INTERRUPTED_PROBE_RUNS_RECOVERED'", complete)
    apply = text.index("$deployment = & $deploymentScript", complete2)
    assert recovery < complete < complete2 < apply
    assert "Interrupted-run gate did not return a completed result. AutoLogon apply was not started." in text


def test_terminal_success_requires_every_restart_completion_flag() -> None:
    text = read(FIELD)
    start = text.index("if ([string]$result.deployment_status")
    gate = text[start:text.index("$result.status = 'COMPLETED'", start)]
    for marker in (
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "autologon_applied",
        "pre_reboot_autologon_ready",
        "automatic_reboot_performed",
        "restart_offline_observed",
        "restart_online_observed",
        "restart_task_cleanup_verified",
        "target_mutation_performed",
    ):
        assert marker in gate, marker


def test_default_password_and_clinical_core_boundaries_are_explicit() -> None:
    text = read(FIELD).lower()
    assert "default_password_value_collected = $false" in text
    assert "clinical_core_invoked = $false" in text
    for forbidden in (
        "sas cybernet core",
        "deploy-cybernetclinicalcore",
        "deploy-cybernetprofiledclinicalcore",
        "defaultpassword value",
        "get-credential",
    ):
        assert forbidden not in text, forbidden


def test_operator_state_stops_rerun_after_completion_or_mutation() -> None:
    text = read(STATE)
    assert "STOP - AutoLogon deployment completed; do not rerun." in text
    assert "STOP - inspect persisted AutoLogon evidence; do not rerun." in text
    assert "sas autologon Remote $requested" in text


def test_runbook_preserves_exact_field_contract() -> None:
    text = read(DOC)
    for marker in (
        "WPJ075OPR046",
        "wpj075opr046.nslijhs.net",
        "NSLIJHS-WAB",
        "sas autologon Remote WPJ075OPR046",
        "S4U_PROBE_CREATE_HANG_RECOVERED",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "do not manually reboot",
        "does not prove human-observed interactive desktop sign-in",
    ):
        assert marker.lower() in text.lower(), marker


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon field deployment completion contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
