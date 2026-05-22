#!/usr/bin/env bash
# SysAdminSuite live serial/MAC probe workflow
# Bash-on-Windows, read-only, technician-safe by default.

set -euo pipefail

MANIFEST=""
OUTPUT="survey/output/live_serial_probe_results.csv"
DASHBOARD=""
NO_DASHBOARD=0
TIMEOUT_SEC=8
NO_WMIC=0
IDENTITY_CSV=""
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Live Serial Probe

Usage:
  bash survey/sas-live-serial-probe.sh --manifest targets.csv [options]

Options:
  --manifest PATH       Input manifest CSV from deployment audit, survey target normalization, or tracker export
  --output PATH         Output CSV path. Default: survey/output/live_serial_probe_results.csv
  --dashboard PATH      Output HTML dashboard path. Default: same folder as output, live_serial_probe_dashboard.html
  --no-dashboard        Do not render HTML dashboard
  --timeout SEC         Per-probe timeout in seconds. Default: 8
  --no-wmic             Do not attempt read-only WMIC serial/MAC probe
  --identity-csv PATH   Use pre-collected identity CSV instead of live probing, useful for tests or offline joins
  --pass-thru           Print output CSV after writing
  -h, --help            Show help

Expected runtime:
  Bash on Windows, usually Git Bash or MSYS2 Bash.

Safety:
  - Read-only.
  - No PowerShell default.
  - No remote staging.
  - No scheduled tasks.
  - No registry edits.
  - No endpoint mutation.

Output classifications:
  live_serial_confirmed
  reachable_no_serial
  unreachable_mark_off
  needs_ad_lookup
  needs_vision_lookup
  manual_review
USAGE
}

fail(){ printf '[live-serial-probe] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[live-serial-probe] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?missing value for --manifest}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --dashboard) DASHBOARD="${2:?missing value for --dashboard}"; shift 2 ;;
    --no-dashboard) NO_DASHBOARD=1; shift ;;
    --timeout) TIMEOUT_SEC="${2:?missing value for --timeout}"; shift 2 ;;
    --no-wmic) NO_WMIC=1; shift ;;
    --identity-csv) IDENTITY_CSV="${2:?missing value for --identity-csv}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$MANIFEST" ]] || fail "--manifest is required"
[[ -f "$MANIFEST" ]] || fail "Manifest not found: $MANIFEST"
[[ "$TIMEOUT_SEC" =~ ^[0-9]+$ && "$TIMEOUT_SEC" -ge 1 ]] || fail "--timeout must be a positive integer"
has_cmd python3 || fail "python3 is required"
has_cmd cmd.exe || fail "cmd.exe is required. Expected Bash-on-Windows runtime."
has_cmd ping.exe || fail "ping.exe is required. Expected Bash-on-Windows runtime."
mkdir -p "$(dirname "$OUTPUT")"

if [[ -z "$DASHBOARD" ]]; then
  DASHBOARD="$(dirname "$OUTPUT")/live_serial_probe_dashboard.html"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDERER="$REPO_ROOT/deployment-audit/sas-render-live-serial-dashboard.py"

python3 - "$MANIFEST" "$OUTPUT" "$TIMEOUT_SEC" "$NO_WMIC" "$IDENTITY_CSV" <<'PY'
import csv
import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path

manifest, output, timeout_s, no_wmic_s, identity_csv = sys.argv[1:6]
timeout = int(timeout_s)
no_wmic = no_wmic_s == '1'

OUTPUT_FIELDS = [
    'target',
    'source_row',
    'device_type',
    'expected_hostname',
    'expected_cybernet_serial',
    'expected_neuron_serial',
    'expected_mac',
    'observed_hostname',
    'observed_serial',
    'observed_mac',
    'reachability_status',
    'serial_probe_status',
    'classification',
    'follow_up_system',
    'already_had_serial',
    'already_had_mac',
    'can_populate_serial',
    'can_populate_mac',
    'log_status',
    'notes',
    'probed_at',
]

def first(row, names):
    lower = {str(k).strip().lower(): v for k, v in row.items() if k is not None}
    for name in names:
        value = lower.get(name.lower())
        if value is not None and str(value).strip():
            return str(value).strip()
    return ''

def norm_serial(value):
    return re.sub(r'\s+', '', value or '').upper()

def norm_mac(value):
    raw = value or ''
    hx = re.sub(r'[^0-9A-Fa-f]', '', raw).upper()
    if len(hx) == 12:
        return ':'.join(hx[i:i+2] for i in range(0, 12, 2))
    return raw.strip().upper()

def split_macs(value):
    parts = re.split(r'[;,\s]+', value or '')
    return [norm_mac(p) for p in parts if norm_mac(p)]

def run_cmd(args):
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout, errors='replace')
        return proc.returncode, (proc.stdout or ''), (proc.stderr or '')
    except FileNotFoundError as exc:
        return 127, '', str(exc)
    except subprocess.TimeoutExpired:
        return 124, '', 'timeout'

def ping_target(target):
    code, out, err = run_cmd(['ping.exe', '-n', '1', '-w', str(timeout * 1000), target])
    text = f'{out}\n{err}'
    if code == 0:
        return 'reachable', text
    return 'unreachable', text

def dns_lookup(target):
    code, out, err = run_cmd(['nslookup.exe', target])
    text = f'{out}\n{err}'
    if code == 0 and 'Non-existent domain' not in text and "can't find" not in text.lower():
        return 'dns_resolved', text
    return 'dns_unresolved', text

def parse_wmic_value(text, header):
    lines = [line.strip() for line in (text or '').splitlines() if line.strip()]
    values = []
    for line in lines:
        if line.lower() == header.lower():
            continue
        if header.lower() in line.lower() and len(line.split()) <= 2:
            continue
        if line:
            values.append(line)
    return values[0] if values else ''

def parse_wmic_macs(text):
    found = re.findall(r'([0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5})', text or '')
    return ';'.join(sorted(set(norm_mac(x) for x in found if norm_mac(x))))

def wmic_query(target):
    if no_wmic:
        return {'status': 'serial_not_attempted', 'host': '', 'serial': '', 'mac': '', 'note': 'WMIC disabled by --no-wmic'}

    host_code, host_out, host_err = run_cmd(['cmd.exe', '/c', f'wmic /node:"{target}" computersystem get name'])
    serial_code, serial_out, serial_err = run_cmd(['cmd.exe', '/c', f'wmic /node:"{target}" bios get serialnumber'])
    mac_code, mac_out, mac_err = run_cmd(['cmd.exe', '/c', f'wmic /node:"{target}" nicconfig where IPEnabled=true get MACAddress'])

    combined = '\n'.join([host_out, host_err, serial_out, serial_err, mac_out, mac_err])
    lower = combined.lower()

    if any(token in lower for token in ['not recognized', 'not found']):
        return {'status': 'wmic_missing', 'host': '', 'serial': '', 'mac': '', 'note': 'WMIC unavailable on this workstation'}
    if any(token in lower for token in ['access is denied', 'rpc server is unavailable', 'logon failure']):
        return {'status': 'serial_probe_blocked', 'host': '', 'serial': '', 'mac': '', 'note': combined[:240].replace('\n', ' | ')}
    if host_code == 124 or serial_code == 124 or mac_code == 124:
        return {'status': 'serial_probe_timeout', 'host': '', 'serial': '', 'mac': '', 'note': 'WMIC query timed out'}

    host = parse_wmic_value(host_out, 'Name')
    serial = parse_wmic_value(serial_out, 'SerialNumber')
    mac = parse_wmic_macs(mac_out)

    if host or serial or mac:
        return {'status': 'serial_observed' if serial else 'identity_observed_no_serial', 'host': host, 'serial': serial, 'mac': mac, 'note': ''}

    if serial_code != 0 or host_code != 0 or mac_code != 0:
        return {'status': 'serial_probe_failed', 'host': '', 'serial': '', 'mac': '', 'note': combined[:240].replace('\n', ' | ')}

    return {'status': 'no_serial_returned', 'host': host, 'serial': serial, 'mac': mac, 'note': 'WMIC returned no identity values'}

def load_identity_csv(path):
    data = {}
    if not path:
        return data
    with open(path, newline='', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            target = first(row, ['target', 'Target', 'HostName', 'Hostname', 'expected_hostname'])
            if target:
                data[target.upper()] = row
    return data

def normalize_manifest_row(row):
    cybernet_host = first(row, ['Cybernet Hostname', 'CybernetHostName', 'Cybernet Host', 'HostName', 'Hostname'])
    neuron_host = first(row, ['Neuron Hostname', 'NeuronHostName', 'Neuron Host'])
    target = first(row, ['target', 'Target', 'SurveyTargetHint', 'HostName', 'Hostname', 'Cybernet Hostname', 'Neuron Hostname', 'Identifier'])
    device_type = first(row, ['device_type', 'DeviceType', 'Type', 'DeviceClass'])
    if not device_type:
        if neuron_host and not cybernet_host:
            device_type = 'Neuron'
        elif cybernet_host:
            device_type = 'Cybernet'
        else:
            device_type = 'Unknown'
    expected_hostname = target or cybernet_host or neuron_host
    return {
        'target': target or expected_hostname,
        'source_row': first(row, ['source_row', 'SourceRow', 'ExcelRow', 'source_row_number', 'source row']),
        'device_type': device_type,
        'expected_hostname': expected_hostname,
        'expected_cybernet_serial': first(row, ['expected_cybernet_serial', 'ExpectedCybernetSerial', 'Cybernet Serial', 'Cybernet Serial Number', 'Cybernet S/N']),
        'expected_neuron_serial': first(row, ['expected_neuron_serial', 'ExpectedNeuronSerial', 'Neuron S/N', 'Neuron Serial', 'Neuron Serial Number']),
        'expected_mac': norm_mac(first(row, ['expected_mac', 'ExpectedMAC', 'MACAddress', 'MAC', 'Cybernet MAC', 'Neuron MAC']))
    }

def classify(record, probe):
    expected_serials = [record['expected_cybernet_serial'], record['expected_neuron_serial']]
    expected_serials_norm = [norm_serial(s) for s in expected_serials if norm_serial(s)]
    expected_mac = norm_mac(record.get('expected_mac', ''))
    observed_serial = probe.get('serial', '')
    observed_serial_norm = norm_serial(observed_serial)
    observed_mac = probe.get('mac', '')
    observed_macs = split_macs(observed_mac)

    already_had_serial = 'yes' if expected_serials_norm else 'no'
    already_had_mac = 'yes' if expected_mac else 'no'
    can_populate_serial = 'yes' if observed_serial_norm and not expected_serials_norm else 'no'
    can_populate_mac = 'yes' if observed_macs and not expected_mac else 'no'

    notes = []
    if probe.get('note'):
        notes.append(probe['note'])

    if not record['target']:
        return 'needs_ad_lookup', 'AD;Vision', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, 'No target hostname or identifier in manifest', 'missing_target'

    if expected_serials_norm and observed_serial_norm and observed_serial_norm not in expected_serials_norm:
        notes.append('Observed serial conflicts with expected tracker serial')
        return 'manual_review', 'Tracker review', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, '; '.join(notes), 'serial_conflict'

    if expected_mac and observed_macs and expected_mac not in observed_macs:
        notes.append('Observed MAC conflicts with expected tracker MAC')
        return 'manual_review', 'Tracker review', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, '; '.join(notes), 'mac_conflict'

    if observed_serial_norm or observed_macs:
        if can_populate_serial == 'yes' or can_populate_mac == 'yes':
            return 'live_serial_confirmed', 'Tracker update', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, '; '.join(notes), 'populate_missing_fields'
        return 'live_serial_confirmed', 'None', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, '; '.join(notes), 'already_confirmed'

    if probe.get('reachability') in ('reachable', 'reachable_wmic_only'):
        return 'reachable_no_serial', 'Vision', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, '; '.join(notes), 'reachable_identity_gap'

    if probe.get('reachability') == 'dns_only_no_ping':
        return 'needs_ad_lookup', 'AD;Vision', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, '; '.join(notes), 'dns_only'

    return 'unreachable_mark_off', 'AD;Vision', already_had_serial, already_had_mac, can_populate_serial, can_populate_mac, '; '.join(notes), 'marked_off_pending_external_lookup'

identity = load_identity_csv(identity_csv)
records = []
seen = set()
with open(manifest, newline='', encoding='utf-8-sig') as f:
    for row in csv.DictReader(f):
        rec = normalize_manifest_row(row)
        key = (rec['target'], rec['source_row'], rec['expected_cybernet_serial'], rec['expected_neuron_serial'], rec['expected_mac'])
        if key in seen:
            continue
        seen.add(key)
        records.append(rec)

rows = []
for rec in records:
    target = rec['target']
    now = dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    if not target:
        probe = {'reachability': 'not_checked', 'serial_status': 'not_checked', 'host': '', 'serial': '', 'mac': '', 'note': 'No target supplied'}
    elif identity:
        ident = identity.get(target.upper(), {})
        reachability = first(ident, ['reachability_status', 'PingStatus', 'ReachabilityStatus']) or 'not_checked'
        serial_status = first(ident, ['serial_probe_status', 'IdentityStatus', 'WmiStatus']) or 'identity_csv'
        probe = {
            'reachability': reachability,
            'serial_status': serial_status,
            'host': first(ident, ['observed_hostname', 'ObservedHostName']),
            'serial': first(ident, ['observed_serial', 'ObservedSerial']),
            'mac': first(ident, ['observed_mac', 'ObservedMACs', 'ObservedMAC']),
            'note': first(ident, ['notes', 'Notes'])
        }
    else:
        ping_status, ping_text = ping_target(target)
        dns_status, dns_text = dns_lookup(target)
        wmi = wmic_query(target)
        reachability = ping_status
        if ping_status != 'reachable' and (wmi['host'] or wmi['serial'] or wmi['mac']):
            reachability = 'reachable_wmic_only'
        elif ping_status != 'reachable' and dns_status == 'dns_resolved':
            reachability = 'dns_only_no_ping'
        probe = {
            'reachability': reachability,
            'serial_status': wmi['status'],
            'host': wmi['host'],
            'serial': wmi['serial'],
            'mac': wmi['mac'],
            'note': wmi['note']
        }

    classification, follow_up, had_serial, had_mac, can_serial, can_mac, notes, log_status = classify(rec, probe)
    rows.append({
        'target': target,
        'source_row': rec['source_row'],
        'device_type': rec['device_type'],
        'expected_hostname': rec['expected_hostname'],
        'expected_cybernet_serial': rec['expected_cybernet_serial'],
        'expected_neuron_serial': rec['expected_neuron_serial'],
        'expected_mac': rec['expected_mac'],
        'observed_hostname': probe.get('host', ''),
        'observed_serial': probe.get('serial', ''),
        'observed_mac': probe.get('mac', ''),
        'reachability_status': probe.get('reachability', ''),
        'serial_probe_status': probe.get('serial_status', ''),
        'classification': classification,
        'follow_up_system': follow_up,
        'already_had_serial': had_serial,
        'already_had_mac': had_mac,
        'can_populate_serial': can_serial,
        'can_populate_mac': can_mac,
        'log_status': log_status,
        'notes': notes,
        'probed_at': now,
    })

Path(output).parent.mkdir(parents=True, exist_ok=True)
with open(output, 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=OUTPUT_FIELDS, quoting=csv.QUOTE_ALL, lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
print(f'Wrote {len(rows)} live serial probe row(s) to {output}')
PY

if [[ "$NO_DASHBOARD" -eq 0 ]]; then
  if [[ -f "$RENDERER" ]]; then
    python3 "$RENDERER" --input "$OUTPUT" --output "$DASHBOARD"
    log "Dashboard written: $DASHBOARD"
  else
    log "Dashboard renderer not found, skipping: $RENDERER"
  fi
fi

log "Live serial probe complete: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
