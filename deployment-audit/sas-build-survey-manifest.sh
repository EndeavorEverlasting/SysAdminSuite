#!/usr/bin/env bash
# Build a remote survey manifest from deployment-audit duplicate resolution requests.
# Input: survey_requests_duplicate_resolution.csv
# Output: CSV compatible with survey/sas-survey-targets.sh

set -euo pipefail

REQUESTS=""
OUTPUT="deployment-audit/output/remote_survey_manifest.csv"
DEVICE_TYPE="Cybernet"
INCLUDE_COMPLETE=0

usage() {
  cat <<'USAGE'
Build Remote Survey Manifest

Usage:
  ./deployment-audit/sas-build-survey-manifest.sh --requests survey_requests_duplicate_resolution.csv [options]

Options:
  --requests PATH       CSV from sas-audit-deployments.sh
  --output PATH         Destination survey manifest CSV
  --device-type TYPE    Device type to emit. Default: Cybernet
  --include-complete    Include rows that already have all resolution identifiers
  -h, --help            Show help

Output columns:
  Identifier,Target,HostName,Serial,MACAddress,DeviceType,Source,Reason,ExcelRow,ConflictField,ConflictValue,LocationKey,MissingResolutionIdentifiers

The output can be passed to:

  ./survey/sas-survey-targets.sh --csv remote_survey_manifest.csv --output normalized_remote_survey_targets.csv
USAGE
}

fail(){ printf '[survey-manifest] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[survey-manifest] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --requests) REQUESTS="${2:?missing value for --requests}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --device-type) DEVICE_TYPE="${2:?missing value for --device-type}"; shift 2 ;;
    --include-complete) INCLUDE_COMPLETE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$REQUESTS" ]] || fail "--requests is required"
[[ -f "$REQUESTS" ]] || fail "Requests CSV not found: $REQUESTS"
has_cmd python3 || fail "python3 is required"
mkdir -p "$(dirname "$OUTPUT")"

python3 - "$REQUESTS" "$OUTPUT" "$DEVICE_TYPE" "$INCLUDE_COMPLETE" <<'PY'
import csv
import re
import sys

requests_path, output_path, device_type, include_complete_raw = sys.argv[1:5]
include_complete = include_complete_raw == '1'

fields = [
    'Identifier','Target','HostName','Serial','MACAddress','DeviceType','Source','Reason',
    'ExcelRow','ConflictField','ConflictValue','LocationKey','MissingResolutionIdentifiers'
]

def parse_known(value):
    out = {}
    for part in (value or '').split(';'):
        part = part.strip()
        if not part or '=' not in part:
            continue
        k, v = part.split('=', 1)
        out[k.strip().lower()] = v.strip()
    return out

def norm_mac(v):
    hx = re.sub(r'[^0-9A-Fa-f]', '', v or '').upper()
    return ':'.join(hx[i:i+2] for i in range(0, 12, 2)) if len(hx) == 12 else (v or '').strip().upper()

def choose_target(row, known):
    for key in ['cybernet hostname', 'cybernet serial', 'cybernet mac']:
        if known.get(key):
            return known[key]
    return row.get('SurveyTargetHint') or row.get('ConflictValue') or ''

seen = set()
written = 0
with open(requests_path, newline='', encoding='utf-8-sig') as src, open(output_path, 'w', newline='', encoding='utf-8') as dst:
    reader = csv.DictReader(src)
    writer = csv.DictWriter(dst, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator='\n')
    writer.writeheader()
    for row in reader:
        missing = (row.get('MissingResolutionIdentifiers') or '').strip()
        if missing == '' and not include_complete:
            continue
        known = parse_known(row.get('KnownResolutionIdentifiers'))
        target = choose_target(row, known).strip()
        host = known.get('cybernet hostname', '')
        serial = known.get('cybernet serial', '')
        mac = norm_mac(known.get('cybernet mac', '')) if known.get('cybernet mac') else ''
        identifier = target or host or serial or mac or row.get('ConflictValue', '')
        key = (identifier, row.get('ExcelRow'), row.get('ConflictField'), row.get('ConflictValue'))
        if key in seen:
            continue
        seen.add(key)
        writer.writerow({
            'Identifier': identifier,
            'Target': target,
            'HostName': host,
            'Serial': serial,
            'MACAddress': mac,
            'DeviceType': device_type,
            'Source': 'deployment-audit',
            'Reason': 'Resolve deployed duplicate before physical revisit',
            'ExcelRow': row.get('ExcelRow', ''),
            'ConflictField': row.get('ConflictField', ''),
            'ConflictValue': row.get('ConflictValue', ''),
            'LocationKey': row.get('LocationKey', ''),
            'MissingResolutionIdentifiers': missing,
        })
        written += 1
print(f'Wrote {written} survey target(s) to {output_path}')
PY

log "Manifest ready: $OUTPUT"
