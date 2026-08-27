#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARD = ROOT / "scripts" / "SasSoftwareDeploymentKerberosSmbHardBounded.psm1"
REPAIR = ROOT / "scripts" / "Repair-SasKerberosSmbTransportPreflightRuntime.ps1"
REPAIR_TEST = ROOT / "Tests" / "PowerShell" / "KerberosSmbTransportPreflightRuntimeRepair.Tests.ps1"
DEPLOY = ROOT / "scripts" / "Invoke-SasAutoLogonS4URestartDeployment.ps1"
HANDOFF = ROOT / "docs" / "handoff" / "autologon-vpn-transport-preflight-timeout.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def main() -> None:
    hard = read(HARD)
    repair = read(REPAIR)
    repair_test = read(REPAIR_TEST)
    deploy = read(DEPLOY)
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

    # Protected-network authority is transport-agnostic at this layer: a live DomainAuthenticated
    # Ethernet/LAN path is sufficient; VPN is not required when that stronger path already exists.
    for marker in (
        "corporate Ethernet/LAN interface or an authenticated VPN adapter",
        "VPN is not itself a requirement",
        "DomainAuthenticated` Ethernet path",
    ):
        assert marker in handoff, marker

    # The earlier Ethernet proof is historical evidence only; its one controlled retry has now been
    # consumed by a later fail-closed VPN attempt. Another full deployment must remain blocked until
    # a fresh read-only proof reaches the exact ready classification on the intended current path.
    for marker in (
        "That proof authorized one controlled canonical retry on the then-proven transport floor",
        "The controlled canonical retry has now been consumed",
        "KERBEROS_S4U_TRANSPORT_BLOCKED",
        "public transport classification `inconclusive`",
        "stopped before stage-8 remote staging",
        "no target mutation authorized by this run",
        "Do **not** run another full AutoLogon `Remote` transaction from this state",
        "First recover the already-written local preflight result and English summary",
        "fresh **read-only** preflight",
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
