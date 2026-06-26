#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "survey" / "sas-ad-existence-bulk.ps1"
MODULE = ROOT / "scripts" / "SasTargetIntake.psm1"

text = SCRIPT.read_text(encoding="utf-8")
module_text = MODULE.read_text(encoding="utf-8")

required = [
    "Fast read-only Active Directory existence check",
    "HostNameColumn",
    "BatchSize",
    "Invoke-BatchedADComputerLookup",
    "Get-ADComputer -LDAPFilter",
    "ADExists",
    "AD EXISTENCE SUMMARY",
    "AD_CONFIRMED",
    "AD_NOT_FOUND",
    "AD_DUPLICATE_CANDIDATES",
    "AD_QUERY_BLOCKED",
]
for item in required:
    assert item in text, f"missing required fragment: {item}"

intake_required = [
    "scripts/SasTargetIntake.psm1",
    "Import-Module $targetIntakeModule -Force",
    "Get-SasRepoRoot -StartPath $PSCommandPath",
    "Assert-SasApprovedInputPath -Path $Manifest",
    "-Role 'AD existence manifest'",
    "-AllowStaging -AllowGenerated",
    "Assert-SasApprovedOutputPath -Path $Output",
    "-Role 'AD existence output CSV'",
]
for item in intake_required:
    assert item in text, f"bulk AD existence helper missing target-intake fragment: {item}"

module_required = [
    "[switch]$AllowGenerated",
    "$approved += $roots.OutputRoots",
    "generated SysAdminSuite manifests",
]
for item in module_required:
    assert item in module_text, f"PowerShell target-intake module missing generated-manifest support: {item}"

for unsafe in [
    r"\bSet-AD\w+\b",
    r"\bNew-AD\w+\b",
    r"\bRemove-AD\w+\b",
    r"\bDisable-AD\w+\b",
    r"\bEnable-AD\w+\b",
    r"\bMove-AD\w+\b",
    r"\bInvoke-Command\b",
    r"\bEnter-PSSession\b",
]:
    assert not re.search(unsafe, text, flags=re.I), f"unsafe AD/write pattern present: {unsafe}"

for wildcard in [
    "(name=*$safe*)",
    "(dNSHostName=*$safe*)",
    "(description=*$safe*)",
    "name=*$",
    "dNSHostName=*$",
]:
    assert wildcard not in text, f"broad wildcard AD lookup present: {wildcard}"

print("bulk AD existence contract tests passed")
