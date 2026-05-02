#!/usr/bin/env bash
# SysAdminSuite Cybernet remote evidence collector
# Reads a survey manifest and collects hostname/serial/MAC evidence without mutating targets.
# Transport strategy is conservative: ping, DNS, optional SSH command, and optional vendor/API hook later.

set -euo pipefail

MANIFEST=""
OUTPUT="survey/output/cybernet_evidence.csv"
TIMEOUT_SEC=5
SSH_USER=""
SSH_KEY=""
ALLOW_SSH=0
PASS_THRU=0

usage() {
  cat <<'USAGE'
Cybernet Remote Evidence Collector

Usage:
  ./survey/sas-collect-cybernet-evidence.sh --manifest remote_survey_manifest.csv [options]

Options:
  --manifest PATH      Survey manifest CSV from deployment-audit/sas-build-survey-manifest.sh or survey/sas-survey-targets.sh
  --output PATH        Output evidence CSV. Default: survey/output/cybernet_evidence.csv
  --timeout SEC        Network timeout for lightweight probes. Default: 5
  --ssh-user USER      Optional SSH username for Linux/SSH-capable targets
  --ssh-key PATH       Optional SSH private key
  --allow-ssh          Permit SSH read-only commands when HostName/Target is reachable
  --pass-thru          Print evidence CSV after writing
  -h, --help           Show help

Safety:
  - Read-only.
  - Does not change devices.
  - SSH is disabled unless --allow-ssh is passed.
  - If no trusted transport is available, the tool still emits an evidence row with a clear status.

Output columns:
  Timestamp,ExcelRow,ConflictField,ConflictValue,InputIdentifier,Target,HostName,ExpectedSerial,ExpectedMAC,
  ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,EvidenceStatus,RevisitRecommendation,Notes
USAGE
}

fail(){ printf '[cybernet-evidence] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[cybernet-evidence] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?missing value for --manifest}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --timeout) TIMEOUT_SEC="${2:?missing value for --timeout}"; shift 2 ;;
    --ssh-user) SSH_USER="${2:?missing value for --ssh-user}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:?missing value for --ssh-key}"; shift 2 ;;
    --allow-ssh) ALLOW_SSH=1; shift ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$MANIFEST" ]] || fail "--manifest is required"
[[ -f "$MANIFEST" ]] || fail "Manifest not found: $MANIFEST"
[[ "$TIMEOUT_SEC" =~ ^[0-9]+$ && "$TIMEOUT_SEC" -ge 1 ]] || fail "--timeout must be a positive integer"
has_cmd python3 || fail "python3 is required"
mkdir -p "$(dirname "$OUTPUT")"

python3 - "$MANIFEST" "$OUTPUT" "$TIMEOUT_SEC" "$ALLOW_SSH" "$SSH_USER" "$SSH_KEY" <<'PY'
import csv
import datetime as dt
import os
import platform
import re
import socket
import subprocess
import sys

manifest, output, timeout_raw, allow_ssh_raw, ssh_user, ssh_key = sys.argv[1:7]
timeout = int(timeout_raw)
allow_ssh = allow_ssh_raw == '1'

fields = [
    'Timestamp','ExcelRow','ConflictField','ConflictValue','InputIdentifier','Target','HostName','ExpectedSerial','ExpectedMAC',
    'ResolvedAddress','PingStatus','DnsName','ObservedHostName','ObservedSerial','ObservedMACs','EvidenceStatus','RevisitRecommendation','Notes'
]

def first(row, names):
    lower = {k.lower(): v for k, v in row.items()}
    for name in names:
        v = lower.get(name.lower())
        if v and str(v).strip():
            return str(v).strip()
    return ''

def norm_mac(v):
    hx = re.sub(r'[^0-9A-Fa-f]', '', v or '').upper()
    return ':'.join(hx[i:i+2] for i in range(0, 12, 2)) if len(hx) == 12 else (v or '').strip().upper()

def resolve_host(target):
    if not target:
        return '', ''
    try:
        address = socket.gethostbyname(target)
    except Exception:
        return '', ''
    try:
        dns_name = socket.getfqdn(address)
    except Exception:
        dns_name = ''
    return address, dns_name

def ping(address_or_host):
    if not address_or_host:
        return 'NoTarget'
    count_flag = '-n' if platform.system().lower().startswith('win') else '-c'
    timeout_flag = '-w' if platform.system().lower().startswith('win') else '-W'
    cmd = ['ping', count_flag, '1', timeout_flag, str(timeout), address_or_host]
    try:
        result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout + 2)
        return 'Reachable' if result.returncode == 0 else 'NoPing'
    except Exception:
        return 'PingFailed'

def run_ssh(host):
    if not allow_ssh or not host:
        return '', '', 'SSHDisabled'
    if not ssh_user:
        return '', '', 'SSHUserMissing'
    if not shutil_which('ssh'):
        return '', '', 'SSHNotInstalled'
    dest = f'{ssh_user}@{host}'
    cmd = ['ssh', '-o', 'BatchMode=yes', '-o', f'ConnectTimeout={timeout}']
    if ssh_key:
        cmd.extend(['-i', ssh_key])
    script = "hostname; (cat /sys/class/dmi/id/product_serial 2>/dev/null || dmidecode -s system-serial-number 2>/dev/null || true); (ip link 2>/dev/null | awk '/link\/ether/ {print $2}' | paste -sd ';' - || true)"
    cmd.extend([dest, script])
    try:
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout + 5)
        if result.returncode != 0:
            return '', '', 'SSHFailed:' + (result.stderr.strip()[:120] if result.stderr else str(result.returncode))
        lines = [x.strip() for x in result.stdout.splitlines()]
        observed_host = lines[0] if len(lines) > 0 else ''
        observed_serial = lines[1] if len(lines) > 1 else ''
        observed_macs = lines[2] if len(lines) > 2 else ''
        return observed_host, observed_serial, observed_macs
    except Exception as exc:
        return '', '', 'SSHError:' + str(exc)[:120]

def shutil_which(name):
    from shutil import which
    return which(name)

def verdict(ping_status, expected_serial, expected_mac, observed_serial, observed_macs, notes):
    evidence = []
    if expected_serial and observed_serial:
        evidence.append('SerialMatch' if expected_serial.upper() == observed_serial.strip().upper() else 'SerialConflict')
    if expected_mac and observed_macs:
        normalized = [norm_mac(x) for x in re.split(r'[;\s,]+', observed_macs) if x.strip()]
        evidence.append('MACMatch' if norm_mac(expected_mac) in normalized else 'MACConflict')
    if any(x.endswith('Conflict') for x in evidence):
        return 'Conflict', 'Physical revisit or privileged remote review justified'
    if evidence and all(x.endswith('Match') for x in evidence):
        return 'Confirmed', 'No revisit needed based on collected evidence'
    if ping_status == 'Reachable':
        return 'ReachableNeedsPrivilegedSurvey', 'Try approved remote management path before revisit'
    return 'Unreachable', 'Revisit justified only after network/remote-management path is exhausted'

rows = []
with open(manifest, newline='', encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    for row in reader:
        now = dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        target = first(row, ['Target','HostName','Identifier','SurveyTargetHint'])
        host = first(row, ['HostName'])
        expected_serial = first(row, ['Serial','ExpectedSerial','Cybernet Serial'])
        expected_mac = norm_mac(first(row, ['MACAddress','ExpectedMAC','Cybernet MAC']))
        lookup = host or target
        resolved, dns_name = resolve_host(lookup)
        ping_status = ping(resolved or lookup)
        observed_host, observed_serial, observed_macs_or_note = run_ssh(lookup)
        notes = ''
        observed_macs = observed_macs_or_note
        if observed_macs_or_note.startswith('SSH'):
            notes = observed_macs_or_note
            observed_macs = ''
        evidence_status, recommendation = verdict(ping_status, expected_serial, expected_mac, observed_serial, observed_macs, notes)
        rows.append({
            'Timestamp': now,
            'ExcelRow': first(row, ['ExcelRow']),
            'ConflictField': first(row, ['ConflictField']),
            'ConflictValue': first(row, ['ConflictValue']),
            'InputIdentifier': first(row, ['Identifier']),
            'Target': target,
            'HostName': host,
            'ExpectedSerial': expected_serial,
            'ExpectedMAC': expected_mac,
            'ResolvedAddress': resolved,
            'PingStatus': ping_status,
            'DnsName': dns_name,
            'ObservedHostName': observed_host,
            'ObservedSerial': observed_serial,
            'ObservedMACs': observed_macs,
            'EvidenceStatus': evidence_status,
            'RevisitRecommendation': recommendation,
            'Notes': notes,
        })

with open(output, 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
print(f'Wrote {len(rows)} evidence row(s) to {output}')
PY

log "Evidence collection complete: $OUTPUT"
if [[ "$PASS_THRU" -eq 1 ]]; then cat "$OUTPUT"; fi
