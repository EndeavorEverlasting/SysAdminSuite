#!/usr/bin/env bash
# Contract tests for Bash transport tools.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PREFLIGHT="$ROOT_DIR/bash/transport/sas-network-preflight.sh"
PRINTER="$ROOT_DIR/bash/transport/sas-printer-probe.sh"
IDENTITY="$ROOT_DIR/bash/transport/sas-workstation-identity.sh"
WMI="$ROOT_DIR/bash/transport/sas-wmi-identity.sh"
SMB="$ROOT_DIR/bash/transport/sas-smb-readonly-recon.sh"

fail(){ printf '[transport-tests] FAIL: %s\n' "$*" >&2; exit 1; }
pass(){ printf '[transport-tests] PASS: %s\n' "$*"; }

[[ -f "$PREFLIGHT" ]] || fail "Missing network preflight tool"
[[ -f "$PRINTER" ]] || fail "Missing printer probe tool"
[[ -f "$IDENTITY" ]] || fail "Missing workstation identity adapter"
[[ -f "$WMI" ]] || fail "Missing WMI identity adapter"
[[ -f "$SMB" ]] || fail "Missing SMB read-only recon adapter"

bash -n "$PREFLIGHT" || fail "Network preflight has Bash syntax errors"
bash -n "$PRINTER" || fail "Printer probe has Bash syntax errors"
bash -n "$IDENTITY" || fail "Identity adapter has Bash syntax errors"
bash -n "$WMI" || fail "WMI adapter has Bash syntax errors"
bash -n "$SMB" || fail "SMB adapter has Bash syntax errors"

PREFLIGHT_HELP="$($PREFLIGHT --help)"
[[ "$PREFLIGHT_HELP" == *"Read-only"* || "$PREFLIGHT_HELP" == *"read-only"* ]] || fail "Preflight help must document read-only posture"
[[ "$PREFLIGHT_HELP" == *"--ports"* ]] || fail "Preflight help must document TCP port checks"
[[ "$PREFLIGHT_HELP" == *"--targets-file"* ]] || fail "Preflight help must document target file input"

PRINTER_HELP="$($PRINTER --help)"
[[ "$PRINTER_HELP" == *"SNMP"* ]] || fail "Printer help must document SNMP"
[[ "$PRINTER_HELP" == *"--skip-9100"* ]] || fail "Printer help must document 9100 risk control"
[[ "$PRINTER_HELP" == *"ARP"* ]] || fail "Printer help must document ARP fallback"

IDENTITY_HELP="$($IDENTITY --help)"
[[ "$IDENTITY_HELP" == *"Read-only"* || "$IDENTITY_HELP" == *"read-only"* ]] || fail "Identity help must document read-only posture"
[[ "$IDENTITY_HELP" == *"WMI/DCOM"* ]] || fail "Identity help must document WMI/DCOM limitation"
[[ "$IDENTITY_HELP" == *"--allow-ssh"* ]] || fail "Identity help must require explicit SSH enablement"
[[ "$IDENTITY_HELP" == *"--allow-wmi"* ]] || fail "Identity help must require explicit WMI enablement"
[[ "$IDENTITY_HELP" == *"Credentials are not written"* ]] || fail "Identity help must document credential output safety"
[[ "$IDENTITY_HELP" == *"IdentityStatus"* ]] || fail "Identity help must document IdentityStatus output"

WMI_HELP="$($WMI --help)"
[[ "$WMI_HELP" == *"Read-only"* || "$WMI_HELP" == *"read-only"* ]] || fail "WMI help must document read-only posture"
[[ "$WMI_HELP" == *"SAS_WMI_USER"* ]] || fail "WMI help must document env credential path"
[[ "$WMI_HELP" == *"No credentials are written"* ]] || fail "WMI help must document credential output safety"
[[ "$WMI_HELP" == *"WmiStatus"* ]] || fail "WMI help must document WmiStatus output"

SMB_HELP="$($SMB --help)"
[[ "$SMB_HELP" == *"Read-only"* || "$SMB_HELP" == *"read-only"* ]] || fail "SMB help must document read-only posture"
[[ "$SMB_HELP" == *"Does not create scheduled tasks"* ]] || fail "SMB help must forbid scheduled tasks"
[[ "$SMB_HELP" == *"Does not copy files to the target"* ]] || fail "SMB help must forbid remote writes"
[[ "$SMB_HELP" == *"SAS_SMB_USER"* ]] || fail "SMB help must document env credential path"
[[ "$SMB_HELP" == *"ReconStatus"* ]] || fail "SMB help must document ReconStatus output"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PREFLIGHT_OUT="$TMP_DIR/network_preflight.csv"
PRINTER_OUT="$TMP_DIR/printer_probe.csv"
IDENTITY_OUT="$TMP_DIR/workstation_identity.csv"
WMI_OUT="$TMP_DIR/wmi_identity.csv"
SMB_OUT="$TMP_DIR/smb_readonly_recon.csv"

bash "$PREFLIGHT" --target 127.0.0.1 --ports 80 --timeout 1 --output "$PREFLIGHT_OUT" >/dev/null
[[ -f "$PREFLIGHT_OUT" ]] || fail "Preflight did not create CSV"
grep -q 'Timestamp,Target,ResolvedAddress,PingStatus,Port,PortStatus' "$PREFLIGHT_OUT" || fail "Preflight CSV header changed"
grep -q '127.0.0.1' "$PREFLIGHT_OUT" || fail "Preflight CSV missing target"

bash "$PRINTER" --target 127.0.0.1 --snmp-only --timeout 1 --output "$PRINTER_OUT" >/dev/null
[[ -f "$PRINTER_OUT" ]] || fail "Printer probe did not create CSV"
grep -q 'Timestamp,Target,ResolvedAddress,PingStatus,MAC,Serial,Source,Notes' "$PRINTER_OUT" || fail "Printer CSV header changed"
grep -q '127.0.0.1' "$PRINTER_OUT" || fail "Printer CSV missing target"

bash "$IDENTITY" --target 127.0.0.1 --timeout 1 --output "$IDENTITY_OUT" >/dev/null
[[ -f "$IDENTITY_OUT" ]] || fail "Identity adapter did not create CSV"
grep -q 'Timestamp,Target,ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,TransportUsed,IdentityStatus,Notes' "$IDENTITY_OUT" || fail "Identity CSV header changed"
grep -q '127.0.0.1' "$IDENTITY_OUT" || fail "Identity CSV missing target"
grep -Eq 'IdentityCollected|ReachableNeedsApprovedIdentityTransport|UnreachableOrBlocked' "$IDENTITY_OUT" || fail "Identity CSV missing status verdict"

bash "$WMI" --target 127.0.0.1 --timeout 1 --output "$WMI_OUT" >/dev/null
[[ -f "$WMI_OUT" ]] || fail "WMI adapter did not create CSV"
grep -q 'Timestamp,Target,ObservedHostName,ObservedSerial,ObservedMACs,WmiStatus,Notes' "$WMI_OUT" || fail "WMI CSV header changed"
grep -q '127.0.0.1' "$WMI_OUT" || fail "WMI CSV missing target"
grep -Eq 'WmiClientMissing|WmiQueryFailed|WmiIdentityCollected|WmiNoIdentityReturned' "$WMI_OUT" || fail "WMI CSV missing WmiStatus verdict"

bash "$SMB" --target 127.0.0.1 --timeout 1 --output "$SMB_OUT" >/dev/null
[[ -f "$SMB_OUT" ]] || fail "SMB adapter did not create CSV"
grep -q 'Timestamp,Target,Share,ApprovedPath,Reachable,ListStatus,ReadStatus,Evidence,ReconStatus,Notes' "$SMB_OUT" || fail "SMB CSV header changed"
grep -q '127.0.0.1' "$SMB_OUT" || fail "SMB CSV missing target"
grep -Eq 'EvidencePathReachable|NeedsApprovedCredentialsOrPolicy|SMBUnavailable|EvidencePathMissing|ReviewRequired' "$SMB_OUT" || fail "SMB CSV missing ReconStatus verdict"

pass "Bash syntax checks passed"
pass "Help contracts passed"
pass "Fixture CSV contracts passed"
