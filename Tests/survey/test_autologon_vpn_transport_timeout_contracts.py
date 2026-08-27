#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
HARD = ROOT / "scripts" / "SasSoftwareDeploymentKerberosSmbHardBounded.psm1"
REPAIR = ROOT / "scripts" / "Repair-SasKerberosSmbTransportPreflightRuntime.ps1"
REPAIR_TEST = ROOT / "Tests" / "PowerShell" / "KerberosSmbTransportPreflightRuntimeRepair.Tests.ps1"
DEPLOY = ROOT / "scripts" / "Invoke-SasAutoLogonS4URestartDeployment.ps1"
COMPLETE = ROOT / "scripts" / "Invoke-SasAutoLogonCompletion.ps1"
COMPLETE_CMD = ROOT / "Complete-SysAdminSuiteAutoLogon.cmd"
HANDOFF = ROOT / "docs" / "handoff" / "autologon-vpn-transport-preflight-timeout.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def main() -> None:
    hard = read(HARD)
    repair = read(REPAIR)
    repair_test = read(REPAIR_TEST)
    deploy = read(DEPLOY)
    complete = read(COMPLETE)
    complete_cmd = read(COMPLETE_CMD)
    handoff = read(HANDOFF)

    for marker in (
        "$process.WaitForExit($TimeoutSeconds * 1000)",
        "$process.Kill()",
        "timeoutStage = 'admin_share'",
        "timeoutStage = 'schedule_service'",
        "timeoutStage = 'scheduled_task_query'",
        "target_mutation_performed = $false",
    ):
        assert marker in hard, marker

    for marker in (
        "KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_APPLIED",
        "KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_ALREADY_PRESENT",
        "git_performed = $false",
        "network_activity_performed = $false",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
    ):
        assert marker in repair, marker

    # The transport repair does not own the separate path-budget implementation. Its CRLF/LF
    # fixture carries those markers into the runtime and proves the surgical repair preserves them.
    assert "TRANSPORT_OUTPUT_ROOT_COMPACTED" in repair_test
    assert "$transportWindowsPathBudget = 240" in repair_test

    # A fail-closed S4U transport block must preserve the hard-bounded observer's already-sanitized
    # diagnostic boundary instead of collapsing operator output to only the public "inconclusive"
    # classification. The deployment wrapper reads only local durable preflight artifacts and must
    # distinguish missing/invalid evidence from an actual unknown transport value.
    for marker in (
        "Get-SasAutoLogonTransportDiagnostic",
        "preflight_result_path",
        "reports\\english_summary.txt",
        "^Probe engine:\\s*(.+)$",
        "^Hard child-process isolation:\\s*(.+)$",
        "^Probe timeout stage:\\s*(.+)$",
        "preflight_result_read = $false",
        "english_summary_read = $false",
        "evidence_status = 'unavailable'",
        "evidence_issues = @()",
        "S4U result did not provide preflight_result_path.",
        "S4U result provided an empty preflight_result_path.",
        "Preflight result artifact is unreadable or schema-incompatible.",
        "Preflight result artifact is missing.",
        "Preflight English summary artifact is missing.",
        "Preflight English summary artifact could not be resolved or read.",
        "$diagnostic.evidence_status = 'complete'",
        "$diagnostic.evidence_status = 'partial'",
        "transport_preflight = $null",
        "$result.transport_preflight = Get-SasAutoLogonTransportDiagnostic -S4UResult $s4u.result",
        "KERBEROS_S4U_TRANSPORT_BLOCKED",
        "Transport preflight classification:",
        "Transport reason codes:",
        "Transport probe engine:",
        "Transport timeout stage:",
        "Transport diagnostic evidence:",
        "Transport diagnostic evidence issues:",
        "Transport preflight: $renderedTransport",
    ):
        assert marker in deploy, marker

    invoke = deploy.index("$s4u = & $s4uScript")
    capture = deploy.index("$result.transport_preflight = Get-SasAutoLogonTransportDiagnostic -S4UResult $s4u.result")
    transport_render = deploy.index("if ([string]$s4u.classification -eq 'KERBEROS_S4U_TRANSPORT_BLOCKED')")
    clean_gate = deploy.index("if ([string]$s4u.classification -ne 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING'")
    mutation = deploy.index("$result.autologon_applied = $true")
    assert invoke < capture < transport_render < clean_gate < mutation

    # Completion is an admission/composition layer, never a second deployment implementation. It
    # must prove the sealed runtime before target contact, establish exact protected authority, use
    # one VPN-tolerant but still hard-bounded read-only preflight, and enter the existing bootstrap
    # only after a fresh ready result with no timeout or mutation.
    for marker in (
        "Resolve-SasAutoLogonManifestAuthority.ps1",
        "Test-SasAutoLogonRuntimeSeal.ps1",
        "Enable-SasNorthwellVpnNetworkGuard.ps1",
        "Confirm-SasNorthwellNetwork.ps1",
        "SasTargetNameResolution.psm1",
        "Test-SasSoftwareDeploymentTransport.ps1",
        "Bootstrap-SysAdminSuiteAutoLogon.cmd",
        "[int]$PreflightTimeoutSeconds = 15",
        "-TransportIntent kerberos_smb_task -TimeoutSeconds $PreflightTimeoutSeconds",
        "if ([bool]$preflight.result.target_mutation_performed)",
        "$classification -ne 'kerberos_smb_task_ready'",
        "AUTOLOGON_COMPLETION_TRANSPORT_BLOCKED",
        "No AutoLogon deployment bootstrap was started by the completion gate.",
        "AUTOLOGON_COMPLETION_PREFLIGHT_READY",
        "& $deploymentBootstrap $ComputerName $preparedCommit",
    ):
        assert marker in complete, marker

    manifest_call = complete.index("& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $manifestResolver")
    seal_call = complete.index("& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $sealAuditor")
    authority_call = complete.index("$authority = @(& $networkBootstrap -ConfirmVpnPosture)")
    preflight_call = complete.index("$preflight = & $transportPreflight")
    ready_gate = complete.index("$classification -ne 'kerberos_smb_task_ready'")
    bootstrap_call = complete.index("& $deploymentBootstrap $ComputerName $preparedCommit")
    assert manifest_call < seal_call < authority_call < preflight_call < ready_gate < bootstrap_call

    for forbidden in (
        r"(?im)^\s*&\s*git(?:\.exe)?\b",
        r"(?im)^\s*git(?:\.exe)?\b",
        r"\bNew-ScheduledTask\b",
        r"\bRegister-ScheduledTask\b",
        r"schtasks(?:\.exe)?\s+/(?:Create|Run|Delete|Change)\b",
        r"\bSet-ItemProperty\b",
        r"\bNew-ItemProperty\b",
        r"\bGet-Credential\b",
        r"ConvertFrom-SecureString|ConvertTo-SecureString",
    ):
        assert not re.search(forbidden, complete, re.I), forbidden

    for marker in (
        "Usage: Complete-SysAdminSuiteAutoLogon.cmd HOST",
        "-File \"%SAS_COMPLETION%\" -ComputerName \"%SAS_TARGET%\" -RuntimeRoot \"%SAS_RUNTIME%\" -PreflightTimeoutSeconds 15",
        "Preflight mutation authority: NONE",
    ):
        assert marker in complete_cmd, marker

    # Protected-network authority is transport-agnostic at this layer: a live DomainAuthenticated
    # Ethernet/LAN path is sufficient; VPN is not required when that stronger path already exists.
    for marker in (
        "corporate Ethernet/LAN interface or an authenticated VPN adapter",
        "VPN is not itself a requirement",
        "DomainAuthenticated` Ethernet path",
    ):
        assert marker in handoff, marker

    # The exact later VPN evidence is now known: 445 was reachable and the bounded ADMIN$ read hit
    # the five-second historical budget. The controlled retry stays consumed, but the repository now
    # owns an atomic completion gate that first retries only the read-only admission with 15 seconds.
    for marker in (
        "The controlled canonical retry has now been consumed",
        "Probe timeout stage: `admin_share`",
        "Ports actually tested: `445`",
        "reason codes: `observation_timeout`, `required_observation_missing`",
        "target mutation performed: `False`",
        "Complete-SysAdminSuiteAutoLogon.cmd HOST",
        "15-second",
        "AUTOLOGON_COMPLETION_PREFLIGHT_READY",
        "AUTOLOGON_COMPLETION_TRANSPORT_BLOCKED",
        "classification = kerberos_smb_task_ready",
        "selected_transport = kerberos_smb_task",
        "reason_codes = all_kerberos_smb_task_prerequisites_satisfied",
        "probe engine = hard_process_bounded",
        "timeout stage = none",
        "transport_authorization_proven = True",
        "target_mutation_performed = False",
        "Do not blindly rerun",
    ):
        assert marker in handoff, marker

    assert "The canonical deployment will perform its own bounded transport preflight again" in handoff
    assert "not permission to disconnect an approved protected path" in handoff
    assert "Exactly one new canonical AutoLogon `Remote` transaction is appropriate" not in handoff
    print("PASS: AutoLogon protected transport timeout/retry contracts")


if __name__ == "__main__":
    main()
