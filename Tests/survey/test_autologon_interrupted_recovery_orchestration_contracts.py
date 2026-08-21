#!/usr/bin/env python3
"""Contracts for local-evidence-driven interrupted S4U recovery before AutoLogon apply."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DISCOVERY = ROOT / "scripts" / "Recover-SasLatestInterruptedAutoLogonS4U.ps1"
EXACT = ROOT / "scripts" / "Complete-SasInterruptedAutoLogonS4URecovery.ps1"
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
FIELD = ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1"
CMD = ROOT / "Run-AutoLogonOnsite.cmd"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_discovery_uses_only_local_durable_probe_lifecycle_identity() -> None:
    text = read(DISCOVERY)
    for marker in (
        "Get-SasEvidenceRoots -RepoRoot $repoRoot",
        "s4u_probe_lifecycle.json",
        "run_id",
        "task_name",
        "local_s4u_root",
        "install_or_after_evidence_present",
        "NO_INTERRUPTED_PROBE_RUN_FOUND",
        "INTERRUPTED_PROBE_RUNS_RECOVERED",
    ):
        assert marker in text, marker
    for forbidden in (
        "schtasks.exe",
        "'/Query'",
        '"/Query"',
        "Get-ScheduledTask",
        "MSFT_ScheduledTask",
        "Win32_ScheduledJob",
    ):
        assert forbidden not in text, forbidden


def test_discovery_accepts_pre_mode_probe_lifecycle_without_strictmode_property_failure() -> None:
    text = read(DISCOVERY)
    assert "function Get-SasOptionalJsonString" in text
    assert "$mode = Get-SasOptionalJsonString -Object $lifecycle -Name 'mode'" in text
    assert "if (-not [string]::IsNullOrWhiteSpace($mode) -and $mode -ne 'Probe') { continue }" in text
    assert "[string]$lifecycle.mode" not in text
    for name in ("target", "run_id", "task_name", "classification", "current_stage", "status"):
        assert f"-Name '{name}'" in text


def test_discovery_deduplicates_subst_alias_and_physical_paths() -> None:
    text = read(DISCOVERY)
    for marker in (
        "function Get-SasPhysicalPathIdentity",
        "QueryDosDevice",
        "$root[2] -eq [char]92",
        "physical_identity",
        "$seen.Add($identity)",
        "path_aliases_deduplicated=$true",
    ):
        assert marker in text, marker
    assert "$seen.Add($file.FullName)" not in text


def test_completed_recovery_is_terminal_and_never_rediscovered() -> None:
    text = read(DISCOVERY)
    completed = text.index("$previousStatus -eq 'COMPLETED'")
    classification = text.index("$previousClassification -eq 'S4U_PROBE_CREATE_HANG_RECOVERED'", completed)
    skip = text.index("continue", classification)
    candidate = text.index("$items +=", skip)
    assert completed < classification < skip < candidate
    assert "classification='NO_INTERRUPTED_PROBE_RUN_FOUND'" in text


def test_terminal_probe_create_timeout_is_the_only_terminal_result_admitted_for_discovery() -> None:
    text = read(DISCOVERY)
    assert "function Test-SasTerminalProbeCreateTimeoutRecoverable" in text
    for marker in (
        "sas-autologon-kerberos-s4u-pilot-result/v2",
        "S4U_PROBE_CREATE_TIMEOUT",
        "staging_cleanup_verified",
        "pre_reboot_autologon_ready",
        "automatic_reboot_performed",
        "automatic_sign_in_observed",
        "installer_exit_code",
        "after_snapshot_path",
        "terminal_probe_timeout_accepted",
        "sas-autologon-s4u-recovery-discovery/v3",
    ):
        assert marker in text, marker
    assert "if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }" not in text
    terminal_gate = text.index("if ($terminalPresent)")
    accept = text.index("Test-SasTerminalProbeCreateTimeoutRecoverable", terminal_gate)
    reject = text.index("if (-not $terminalProbeTimeoutAccepted) { continue }", accept)
    candidate = text.index("$items +=", reject)
    assert terminal_gate < accept < reject < candidate


def test_discovery_recanonicalizes_legacy_short_identity_before_exact_cleanup() -> None:
    text = read(DISCOVERY)
    resolution = text.index("Resolve-SasCanonicalTargetFqdn -TargetName $Recorded")
    candidate = text.index("canonical_recovery_target=$ComputerName", resolution)
    exact = text.index("$one = & $recoveryScript -ComputerName $ComputerName", candidate)
    assert resolution < candidate < exact
    assert "$one = & $recoveryScript -ComputerName ([string]$item.target)" not in text


def test_discovery_fails_closed_if_install_or_after_evidence_exists() -> None:
    text = read(DISCOVERY)
    for marker in (
        "s4u-install-worker.ps1",
        "s4u_install_lifecycle.json",
        "s4u_install_result.json",
        "after_lifecycle.json",
        "after_snapshot.json",
        "Refusing automatic recovery or redeployment",
    ):
        assert marker in text, marker
    assert text.index("if ($unsafe.Count -gt 0)") < text.index("$one = & $recoveryScript")


def test_discovery_invokes_exact_recovery_with_recorded_identity_and_canonical_target_only() -> None:
    text = read(DISCOVERY)
    call = text.index("$one = & $recoveryScript -ComputerName $ComputerName")
    for marker in (
        "-RunId ([string]$item.run_id)",
        "-TaskName ([string]$item.task_name)",
        "-LocalS4URoot ([string]$item.local_s4u_root)",
        "-ConfirmRecovery",
        "autologon_installer_launched=$false",
        "exact_cleanup_only=$true",
    ):
        assert marker in text[call:] or marker in text, marker


def test_exact_recovery_accepts_only_exact_safe_terminal_probe_create_timeout() -> None:
    text = read(EXACT)
    assert "function Test-SasExactTerminalProbeCreateTimeoutRecoverable" in text
    for marker in (
        "sas-autologon-kerberos-s4u-pilot-result/v2",
        "S4U_PROBE_CREATE_TIMEOUT",
        "staging_cleanup_verified",
        "pre_reboot_autologon_ready",
        "automatic_reboot_performed",
        "automatic_sign_in_observed",
        "installer_exit_code",
        "after_snapshot_path",
        "-ExpectedRunId $RunId",
        "-ExpectedTaskName $TaskName",
        "-ExpectedTarget $ComputerName",
        "Terminal probe-timeout result accepted for exact recovery",
        "not the exact safe probe-create-timeout shape",
        "sas-autologon-s4u-interrupted-recovery/v3",
        "terminal_pilot_result_present = $terminalPilotResultPresent",
        "terminal_probe_timeout_accepted = $terminalProbeTimeoutAccepted",
    ):
        assert marker in text, marker
    assert "A terminal S4U pilot result already exists; use that result instead of interrupted recovery." not in text
    gate = text.index("if ($terminalPilotResultPresent)")
    accept = text.index("Test-SasExactTerminalProbeCreateTimeoutRecoverable", gate)
    reject = text.index("if (-not $terminalProbeTimeoutAccepted)", accept)
    network = text.index("Assert-SasNorthwellWifi", reject)
    assert gate < accept < reject < network


def test_exact_recovery_can_remove_only_recorded_task_then_probe_only_run_root() -> None:
    text = read(EXACT)
    query = text.index("@('/Query','/S',$ComputerName,'/TN',$TaskName)")
    delete = text.index("@('/Delete','/S',$ComputerName,'/TN',$TaskName,'/F')", query)
    verify = text.index("@('/Query','/S',$ComputerName,'/TN',$TaskName)", delete)
    cleanup = text.index("& $cleanupScript -ComputerName $ComputerName -RunId $RunId", verify)
    assert query < delete < verify < cleanup
    assert "-AllowedArtifactProfile ProbeOnly" in text


def test_terminal_timeout_recovery_still_refuses_install_after_or_restart_proof() -> None:
    discovery = read(DISCOVERY)
    exact = read(EXACT)
    for text in (discovery, exact):
        for marker in (
            "installer_exit_code",
            "after_snapshot_path",
            "pre_reboot_autologon_ready",
            "staging_cleanup_verified",
            "automatic_reboot_performed",
            "automatic_sign_in_observed",
        ):
            assert marker in text, marker
    for marker in (
        "s4u-install-worker.ps1",
        "s4u_install_lifecycle.json",
        "s4u_install_result.json",
        "after_snapshot.json",
    ):
        assert marker in exact, marker


def test_normal_remote_deployment_canonicalizes_then_recovers_then_applies_once() -> None:
    onsite = read(ONSITE)
    field = read(FIELD)
    assert "Invoke-SasAutoLogonFieldDeployment.ps1" in onsite
    assert "-Action Remote -ComputerName $target" in onsite
    network = field.index("& powershell.exe", field.index("=== PROTECTED NETWORK GATE ==="))
    resolution = field.index("Resolve-SasCanonicalTargetFqdn -TargetName $requestedTarget", network)
    recovery = field.index("& $recoveryScript -ComputerName $resolvedTarget", resolution)
    apply = field.index("& $deploymentScript -ComputerName $resolvedTarget", recovery)
    assert network < resolution < recovery < apply
    assert "$result.apply_invocation_count = 1" in field
    assert field.count("& $deploymentScript -ComputerName $resolvedTarget") == 1
    assert "clinical_core_invoked = $false" in field


def test_cmd_surface_can_route_recover_target_without_manual_fragments() -> None:
    text = read(CMD)
    assert 'Invoke-SasAutoLogonOnsite.ps1" -Action "%~1" -ComputerName "%~2"' in text
    assert "try" not in text.lower()
    assert "finally" not in text.lower()


def test_no_live_target_user_or_secret_literals_in_product_sources() -> None:
    combined = "\n".join(read(path) for path in (DISCOVERY, EXACT, ONSITE, FIELD, CMD)).lower()
    for forbidden in (
        "wpj075opr046",
        "pa_rperez26",
        "defaultpassword_value",
        "get-credential",
        "securestring",
    ):
        assert forbidden not in combined, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: interrupted AutoLogon S4U recovery orchestration contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
