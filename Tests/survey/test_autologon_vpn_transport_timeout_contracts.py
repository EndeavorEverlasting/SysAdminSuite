#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARD = ROOT / "scripts" / "SasSoftwareDeploymentKerberosSmbHardBounded.psm1"
REPAIR = ROOT / "scripts" / "Repair-SasKerberosSmbTransportPreflightRuntime.ps1"
HANDOFF = ROOT / "docs" / "handoff" / "autologon-vpn-transport-preflight-timeout.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def main() -> None:
    hard = read(HARD)
    repair = read(REPAIR)
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
        "TRANSPORT_OUTPUT_ROOT_COMPACTED",
    ):
        assert marker in repair, marker

    assert "Do not immediately retry the full AutoLogon transaction" in handoff
    assert "read-only `kerberos_smb_task` preflight" in handoff
    assert "not permission to disconnect the protected VPN" in handoff
    print("PASS: AutoLogon VPN transport timeout contracts")


if __name__ == "__main__":
    main()
