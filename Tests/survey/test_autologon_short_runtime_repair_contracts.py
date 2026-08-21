#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPAIR = ROOT / "scripts" / "Repair-SasAutoLogonShortRuntimeForRefresh.ps1"
REFRESH = ROOT / "scripts" / "Refresh-SasOperatorCommand.ps1"


def main() -> None:
    text = REPAIR.read_text(encoding="utf-8-sig")
    refresh = REFRESH.read_text(encoding="utf-8-sig")

    required = (
        "[string]$RuntimeRoot = 'C:\\SASAL'",
        "short-runtime-preservation",
        "sas-autologon-short-runtime-preservation/v1",
        "SAS_SHORT_RUNTIME_PRESERVED_FOR_REFRESH",
        "SAS_SHORT_RUNTIME_REPAIR_NOT_REQUIRED",
        "Move-Item -LiteralPath $runtimeFull -Destination $preservedRuntime",
        "preserved_runtime_path = $preservedRuntime",
        "source_runtime_deleted = $false",
        "reset_performed = $false",
        "clean_performed = $false",
        "remote_git_performed = $false",
        "network_transition_performed = $false",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
        "FixtureMode",
        "fixture runtime must remain beneath TEMP",
    )
    missing = [marker for marker in required if marker not in text]
    assert not missing, f"missing short-runtime preservation markers: {missing}"

    forbidden = (
        "reset --hard",
        "clean -fd",
        "Remove-Item -LiteralPath $runtimeFull",
        "Invoke-Command",
        "Test-NetConnection",
        "admin$",
        "c$\\",
        "schtasks",
        "PrintUIEntry",
        "Get-Credential",
        "raw.githubusercontent.com",
        "github.com",
    )
    present = [marker for marker in forbidden if marker.lower() in text.lower()]
    assert not present, f"unsafe short-runtime repair behavior present: {present}"

    move = text.index("Move-Item -LiteralPath $runtimeFull -Destination $preservedRuntime")
    verify = text.index("AUTOLOGON_SHORT_RUNTIME_PRESERVATION_VERIFY_FAILED")
    receipt = text.index("$receipt | ConvertTo-Json")
    ready = text.index("SAS_SHORT_RUNTIME_PRESERVED_FOR_REFRESH")
    assert move < verify < receipt < ready

    for marker in (
        "scripts\\Repair-SasAutoLogonShortRuntimeForRefresh.ps1",
        "$runtimeRepair = Join-Path $fieldReady 'scripts\\Repair-SasAutoLogonShortRuntimeForRefresh.ps1'",
        "PREPARING GENERATED SHORT AUTOLOGON RUNTIME FOR CLEAN REFRESH",
        "-File $runtimeRepair -RuntimeRoot 'C:\\SASAL'",
        "Short AutoLogon runtime preservation failed",
    ):
        assert marker in refresh, f"refresh lost runtime self-heal marker: {marker}"

    repair_call = refresh.index("-File $runtimeRepair -RuntimeRoot 'C:\\SASAL'")
    stage_call = refresh.index("-File $runtimePreparer")
    assert repair_call < stage_call, "dirty generated runtime must be preserved before short-runtime staging"

    print("PASS: AutoLogon short-runtime preservation contracts")


if __name__ == "__main__":
    main()
