#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARD = ROOT / "scripts" / "SasSoftwareDeploymentKerberosSmbHardBounded.psm1"
REPAIR = ROOT / "scripts" / "Repair-SasKerberosSmbTransportPreflightRuntime.ps1"
REPAIR_TEST = ROOT / "Tests" / "PowerShell" / "KerberosSmbTransportPreflightRuntimeRepair.Tests.ps1"
HANDOFF = ROOT / "docs" / "handoff" / "autologon-vpn-transport-preflight-timeout.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def main() -> None:
    hard = read(HARD)
    repair = read(REPAIR)
    repair_test = read(REPAIR_TEST)
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

    # Protected-network authority is transport-agnostic at this layer: a live DomainAuthenticated
    # Ethernet/LAN path is sufficient; VPN is not required when that stronger path already exists.
    for marker in (
        "corporate Ethernet/LAN interface or an authenticated VPN adapter",
        "VPN is not itself a requirement",
        "DomainAuthenticated` Ethernet path",
    ):
        assert marker in handoff, marker

    # The field handoff must advance monotonically from diagnosis to one controlled retry only after
    # the hard-bounded read-only transport proof reached the exact ready classification without mutation.
    for marker in (
        "classification = kerberos_smb_task_ready",
        "selected_transport = kerberos_smb_task",
        "reason_codes = all_kerberos_smb_task_prerequisites_satisfied",
        "probe engine = hard_process_bounded",
        "timeout stage = none",
        "transport_authorization_proven = True",
        "target_mutation_performed = False",
        "Exactly one new canonical AutoLogon `Remote` transaction is appropriate",
        "autologon_applied = false",
        "pre_reboot_autologon_ready = false",
        "automatic_reboot_performed = false",
        "Do not blindly rerun",
    ):
        assert marker in handoff, marker

    assert "The canonical deployment will perform its own bounded transport preflight again" in handoff
    assert "not permission to disconnect an approved protected path" in handoff
    print("PASS: AutoLogon protected transport timeout/retry contracts")


if __name__ == "__main__":
    main()
