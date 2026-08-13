#!/usr/bin/env python3
"""Completion contracts for the supported AutoLogon field-deployment transaction."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"
RECOVERY = ROOT / "scripts" / "Recover-SasLatestInterruptedAutoLogonS4U.ps1"
STATE = ROOT / "scripts" / "SasAutoLogonOperatorState.psm1"
DOC = ROOT / "docs" / "AUTOLOGON_FIELD_DEPLOYMENT_COMPLETION.md"
ARTIFACTS = ROOT / "harness" / "api" / "harness-artifact-registry.json"
OUTCOMES = ROOT / "harness" / "api" / "harness-outcome-registry.json"
DEPLOYMENT_STATE = ROOT / "harness" / "api" / "deployment-state-registry.json"
WORKFLOW = ROOT / "harness" / "workflows" / "cybernet-autologon-deployment-state.yaml"


def read(path: Path) -> str:
    assert path.is_file(), path
    return path.read_text(encoding="utf-8-sig")


def test_deterministic_legacy_completion_then_apply_boundary_once() -> None:
    """Synthetic source-level E2E: old probe schema + completed recovery + short target."""
    field = read(FIELD)
    recovery = read(RECOVERY)
    requested_target = "AUTHORIZEDHOST01"
    resolved_target = "authorizedhost01.example.net"
    assert requested_target.split(".")[0].lower() == resolved_target.split(".")[0].lower()
    assert "Get-SasOptionalJsonString -Object $lifecycle -Name 'mode'" in recovery
    assert "$previousStatus -eq 'COMPLETED'" in recovery
    assert "$previousClassification -eq 'S4U_PROBE_CREATE_HANG_RECOVERED'" in recovery
    assert "classification='NO_INTERRUPTED_PROBE_RUN_FOUND'" in recovery
    assert "Resolve-SasCanonicalTargetFqdn -TargetName $requestedTarget" in field
    assert "$result.apply_invocation_count = 1" in field
    assert field.count("& $deploymentScript -ComputerName $resolvedTarget") == 1
    assert "clinical_core_invoked = $false" in field


def test_network_resolution_exact_eligibility_lock_recovery_apply_order() -> None:
    text = read(FIELD)
    network = text.index("=== PROTECTED NETWORK GATE ===")
    resolution = text.index("Resolve-SasCanonicalTargetFqdn -TargetName $requestedTarget", network)
    eligibility = text.index("& $eligibilityScript -Target $resolvedTarget -ExecContext remote -RepoRoot $repoRoot", resolution)
    eligibility_pass = text.index("profile_eligibility_proven=$true", eligibility)
    lock = text.index("$targetMutexAcquired = $targetMutex.WaitOne(0)", eligibility_pass)
    recovery = text.index("$recovery = & $recoveryScript", lock)
    apply = text.index("$deployment = & $deploymentScript", recovery)
    assert network < resolution < eligibility < eligibility_pass < lock < recovery < apply
    for marker in (
        "Test-SasHostEligibility.ps1",
        "host_eligibility_proven",
        "host_eligibility_evidence_path",
        "Canonical target failed exact local host eligibility",
    ):
        assert marker in text, marker


def test_apply_is_unreachable_without_completed_safe_recovery_gate() -> None:
    text = read(FIELD)
    recovery = text.index("$recovery = & $recoveryScript")
    complete = text.index("'NO_INTERRUPTED_PROBE_RUN_FOUND'", recovery)
    complete2 = text.index("'INTERRUPTED_PROBE_RUNS_RECOVERED'", complete)
    apply = text.index("$deployment = & $deploymentScript", complete2)
    assert recovery < complete < complete2 < apply
    assert "Interrupted-run gate did not return a completed result. AutoLogon apply was not started." in text


def test_terminal_completion_and_atomic_target_lock_precede_recovery_apply() -> None:
    field = read(FIELD)
    state = read(STATE)
    lock = field.index("$targetMutexAcquired = $targetMutex.WaitOne(0)")
    prior = field.index("Find-SasLatestAutoLogonFieldResult", lock)
    terminal = field.index("AUTOLOGON_DEPLOYMENT_ALREADY_COMPLETED", prior)
    recovery = field.index("$recovery = & $recoveryScript", terminal)
    apply = field.index("$deployment = & $deploymentScript", recovery)
    assert lock < prior < terminal < recovery < apply
    for marker in (
        "AUTOLOGON_FIELD_TARGET_LOCKED",
        "ReleaseMutex()",
        "existing_terminal_result_path",
        "ExcludePath $resultPath",
        "STOP - durable terminal deployment evidence already exists; do not rerun.",
    ):
        assert marker in field, marker
    assert "$terminal = @(" in state
    assert "if ($terminal.Count -gt 0) { return $terminal }" in state
    assert "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" in state


def test_dns_resolution_does_not_claim_profile_eligibility() -> None:
    state = read(STATE)
    initialize = state[state.index("function Initialize-SasAutoLogonOperatorState"):state.index("function Find-SasLatestAutoLogonFieldResult")]
    assert "equipment_profile='unknown'" in initialize
    assert "profile_eligibility_proven=$false" in initialize
    assert "unproven_pending_exact_local_host_policy" in initialize
    assert "profile_eligibility_proven=$true" not in initialize
    assert "host_eligibility_proven" in state
    assert "Test-SasHostEligibility.ps1 canonical FQDN remote policy gate" in state


def test_legacy_short_recovery_is_recanonicalized_and_exact_helper_uses_canonical_target() -> None:
    text = read(RECOVERY)
    for marker in (
        "Resolve-SasCanonicalTargetFqdn -TargetName $Recorded",
        "canonical_recovery_target=$ComputerName",
        "$one = & $recoveryScript -ComputerName $ComputerName",
        "$root[2] -eq [char]92",
        "QueryDosDevice",
    ):
        assert marker in text, marker
    assert "$one = & $recoveryScript -ComputerName ([string]$item.target)" not in text


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


def test_outer_field_result_is_canonical_harness_terminal_artifact() -> None:
    artifacts = read(ARTIFACTS)
    outcomes = read(OUTCOMES)
    deployment = read(DEPLOYMENT_STATE)
    workflow = read(WORKFLOW)
    assert '"id":"autologon-field-deployment-result"' in artifacts
    assert "autologon_field_deployment_result.json" in artifacts
    assert '"command_id":"autologon-remote","success_outcome":"product_deployed","success_artifact_id":"autologon-field-deployment-result"' in outcomes
    assert '"artifact_id": "autologon-field-deployment-result"' in deployment
    assert "require artifact id autologon-field-deployment-result" in workflow
    assert "host_eligibility_proven true" in workflow


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
    assert "STOP - another AutoLogon transaction owns this target" in text
    assert "sas autologon Remote $requested" in text


def test_runbook_is_sanitized_and_preserves_field_contract() -> None:
    text = read(DOC)
    for marker in (
        "AUTHORIZED_SHORT_HOST",
        "authorized-host.example.net",
        "NSLIJHS-WAB",
        "S4U_PROBE_CREATE_HANG_RECOVERED",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "host_eligibility_proven = true",
        "do not manually reboot",
        "does not prove human-observed interactive desktop sign-in",
    ):
        assert marker.lower() in text.lower(), marker

    # Build sensitive sentinels at runtime so the validator can safely scan its own source without
    # guaranteeing a false positive merely by declaring the strings it is supposed to forbid.
    combined = (text + "\n" + read(Path(__file__))).lower()
    forbidden = (
        "wpj" + "075opr046",
        "nslijhs" + ".net",
        "pa_" + "rperez26",
        "sysadminsuite-autologon" + "s4uprobe-",
        "autologon-s4u-deployment-" + "2026",
        "autologon-kerberos-s4u-" + "2026",
    )
    for marker in forbidden:
        assert marker not in combined, marker


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon field deployment completion contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
