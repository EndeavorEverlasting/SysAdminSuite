#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "survey" / "sas-ad-existence-bulk.ps1"

text = SCRIPT.read_text(encoding="utf-8")

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
