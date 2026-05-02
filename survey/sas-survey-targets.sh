#!/usr/bin/env bash
# SysAdminSuite Bash survey target resolver
# Purpose: normalize Cybernet / Neuron target identifiers from args, TXT, CSV, and JSON.
# Safe default: no remote mutation. This prepares clear survey manifests and command targets.

set -euo pipefail

VERSION="0.1.0"
DEVICE_TYPE="Unknown"
OUTPUT_PATH="survey/output/device_survey_targets.csv"
INVENTORY_PATHS=()
TARGETS=()
INPUT_FILES=()
PASS_THRU=0

usage() {
  cat <<'USAGE'
SysAdminSuite Bash Survey Target Resolver

Usage:
  ./survey/sas-survey-targets.sh [options] TARGET...

Options:
  --device-type TYPE        Cybernet, Neuron, Workstation, or Unknown
  --target VALUE            Add one typed target identifier
  --file PATH               Import targets from TXT, CSV, or JSON by extension
  --txt PATH                Import plain text targets
  --csv PATH                Import CSV targets
  --json PATH               Import JSON targets
  --inventory PATH          CSV inventory used to resolve serial/MAC to hostname
  --output PATH             Output CSV path
  --pass-thru               Also print CSV to stdout
  -h, --help                Show help

Supported identifiers:
  - Hostname
  - Serial number
  - MAC address
  - Any mix of the above across typed args, txt, csv, and json

CSV accepted columns:
  Identifier, Target, KnownIdentifier, LookupValue,
  HostName, Hostname, Host, ComputerName, Computer, Name,
  Serial, SerialNumber, ServiceTag, AssetSerial,
  MACAddress, MacAddress, MAC, Mac,
  DeviceType, Type, DeviceClass

JSON accepted shapes:
  ["WMH300OPR001", "00:11:22:33:44:55"]
  { "targets": [ { "HostName": "WMH300OPR001", "SerialNumber": "ABC123" } ] }

Examples:
  ./survey/sas-survey-targets.sh --device-type Cybernet WMH300OPR001 00:11:22:33:44:55
  ./survey/sas-survey-targets.sh --device-type Neuron --csv neurons.csv --inventory known_devices.csv
  ./survey/sas-survey-targets.sh --json targets.json --output survey/output/wave2_targets.csv
USAGE
}

log() { printf '[sas-survey] %s\n' "$*" >&2; }
fail() { printf '[sas-survey] ERROR: %s\n' "$*" >&2; exit 1; }

trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

upper() { printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]'; }

normalize_mac() {
  local raw hex out i
  raw="$(trim "${1:-}")"
  [[ -z "$raw" ]] && { printf ''; return; }
  hex="$(printf '%s' "$raw" | tr -cd '[:xdigit:]' | tr '[:lower:]' '[:upper:]')"
  if [[ ${#hex} -eq 12 ]]; then
    out=""
    for ((i=0; i<12; i+=2)); do
      [[ -n "$out" ]] && out+=":"
      out+="${hex:i:2}"
    done
    printf '%s' "$out"
  else
    upper "$raw"
  fi
}

normalize_serial() {
  printf '%s' "$(trim "${1:-}")" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

normalize_hostname() {
  upper "$(trim "${1:-}")"
}

identifier_type() {
  local value mac_hex
  value="$(trim "${1:-}")"
  [[ -z "$value" ]] && { printf 'Unknown'; return; }
  mac_hex="$(printf '%s' "$value" | tr -cd '[:xdigit:]')"
  if [[ ${#mac_hex} -eq 12 && "$value" =~ ^([[:xdigit:]]{2}[:-]){5}[[:xdigit:]]{2}$|^[[:xdigit:]]{12}$|^[[:xdigit:]]{4}\.[[:xdigit:]]{4}\.[[:xdigit:]]{4}$ ]]; then
    printf 'MAC'; return
  fi
  if [[ "$value" =~ ^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$ || "$value" =~ ^[A-Za-z0-9]+[-_][A-Za-z0-9]+ ]]; then
    printf 'HostName'; return
  fi
  printf 'Serial'
}

csv_escape() {
  local s="${1:-}"
  s="${s//"/""}"
  printf '"%s"' "$s"
}

emit_record() {
  local identifier="${1:-}" host="${2:-}" serial="${3:-}" mac="${4:-}" dtype="${5:-$DEVICE_TYPE}" source="${6:-Typed}"
  identifier="$(trim "$identifier")"
  host="$(normalize_hostname "$host")"
  serial="$(normalize_serial "$serial")"
  mac="$(normalize_mac "$mac")"

  if [[ -z "$identifier" ]]; then
    if [[ -n "$host" ]]; then identifier="$host"; elif [[ -n "$serial" ]]; then identifier="$serial"; elif [[ -n "$mac" ]]; then identifier="$mac"; fi
  fi
  [[ -z "$identifier" ]] && return 0

  local itype
  itype="$(identifier_type "$identifier")"
  if [[ -z "$host" && "$itype" == "HostName" ]]; then host="$(normalize_hostname "$identifier")"; fi
  if [[ -z "$serial" && "$itype" == "Serial" ]]; then serial="$(normalize_serial "$identifier")"; fi
  if [[ -z "$mac" && "$itype" == "MAC" ]]; then mac="$(normalize_mac "$identifier")"; fi

  {
    csv_escape "$identifier"; printf ','
    csv_escape "$itype"; printf ','
    csv_escape "$dtype"; printf ','
    csv_escape "$host"; printf ','
    csv_escape "$serial"; printf ','
    csv_escape "$mac"; printf ','
    csv_escape "$source"; printf '\n'
  }
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

import_txt() {
  local path="$1"
  [[ -f "$path" ]] || fail "Text file not found: $path"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line//$'\t'/,}"
    line="${line//;/,}"
    IFS=',' read -r -a parts <<< "$line"
    for part in "${parts[@]}"; do
      part="$(trim "$part")"
      [[ -n "$part" ]] && emit_record "$part" "" "" "" "$DEVICE_TYPE" "TXT:$path"
    done
  done < "$path"
}

import_csv() {
  local path="$1" source_prefix="${2:-CSV}"
  [[ -f "$path" ]] || fail "CSV file not found: $path"
  if ! has_cmd python3; then fail "python3 is required for CSV parsing in this Bash implementation."; fi
  python3 - "$path" "$DEVICE_TYPE" "$source_prefix" <<'PY'
import csv, re, sys
path, device_type, source_prefix = sys.argv[1], sys.argv[2], sys.argv[3]

def first(row, names):
    lower = {k.lower(): v for k, v in row.items()}
    for name in names:
        v = lower.get(name.lower())
        if v and str(v).strip(): return str(v).strip()
    return ''

def norm_mac(v):
    v = (v or '').strip(); hexv = re.sub(r'[^0-9A-Fa-f]', '', v).upper()
    return ':'.join(hexv[i:i+2] for i in range(0, 12, 2)) if len(hexv) == 12 else v.upper()

def norm_serial(v): return re.sub(r'\s+', '', (v or '').strip()).upper()
def norm_host(v): return (v or '').strip().upper()
def id_type(v):
    v = (v or '').strip(); hexv = re.sub(r'[^0-9A-Fa-f]', '', v)
    if len(hexv) == 12 and re.search(r'[:\-.]|^[0-9A-Fa-f]{12}$', v): return 'MAC'
    if re.search(r'^[A-Za-z]{2,6}\d{2,}[A-Za-z0-9_-]*$', v) or re.search(r'^[A-Za-z0-9]+[-_][A-Za-z0-9]+', v): return 'HostName'
    return 'Serial' if v else 'Unknown'

with open(path, newline='', encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    out = csv.writer(sys.stdout, quoting=csv.QUOTE_ALL, lineterminator='\n')
    for row in reader:
        host = first(row, ['HostName','Hostname','Host','ComputerName','Computer','Name'])
        serial = first(row, ['Serial','SerialNumber','ServiceTag','AssetSerial'])
        mac = first(row, ['MACAddress','MacAddress','MAC','Mac','EthernetMAC','WifiMAC'])
        identifier = first(row, ['Identifier','Target','KnownIdentifier','LookupValue']) or host or serial or mac
        dtype = first(row, ['DeviceType','Type','DeviceClass']) or device_type
        if not identifier: continue
        itype = id_type(identifier)
        if not host and itype == 'HostName': host = identifier
        if not serial and itype == 'Serial': serial = identifier
        if not mac and itype == 'MAC': mac = identifier
        out.writerow([identifier, itype, dtype, norm_host(host), norm_serial(serial), norm_mac(mac), f'{source_prefix}:{path}'])
PY
}

import_json() {
  local path="$1"
  [[ -f "$path" ]] || fail "JSON file not found: $path"
  if ! has_cmd python3; then fail "python3 is required for JSON parsing."; fi
  python3 - "$path" "$DEVICE_TYPE" <<'PY'
import csv, json, re, sys
path, device_type = sys.argv[1], sys.argv[2]

def get_any(obj, names):
    lower = {str(k).lower(): v for k, v in obj.items()}
    for name in names:
        v = lower.get(name.lower())
        if v is not None and str(v).strip(): return str(v).strip()
    return ''
def norm_mac(v):
    v = (v or '').strip(); hexv = re.sub(r'[^0-9A-Fa-f]', '', v).upper()
    return ':'.join(hexv[i:i+2] for i in range(0, 12, 2)) if len(hexv) == 12 else v.upper()
def norm_serial(v): return re.sub(r'\s+', '', (v or '').strip()).upper()
def norm_host(v): return (v or '').strip().upper()
def id_type(v):
    v = (v or '').strip(); hexv = re.sub(r'[^0-9A-Fa-f]', '', v)
    if len(hexv) == 12 and re.search(r'[:\-.]|^[0-9A-Fa-f]{12}$', v): return 'MAC'
    if re.search(r'^[A-Za-z]{2,6}\d{2,}[A-Za-z0-9_-]*$', v) or re.search(r'^[A-Za-z0-9]+[-_][A-Za-z0-9]+', v): return 'HostName'
    return 'Serial' if v else 'Unknown'

with open(path, encoding='utf-8-sig') as f: data = json.load(f)
items = data.get('targets', data) if isinstance(data, dict) else data
if not isinstance(items, list): items = [items]
out = csv.writer(sys.stdout, quoting=csv.QUOTE_ALL, lineterminator='\n')
for item in items:
    if isinstance(item, str):
        identifier=item; host=serial=mac=''; dtype=device_type
    elif isinstance(item, dict):
        host=get_any(item,['HostName','Hostname','Host','ComputerName','Computer','Name'])
        serial=get_any(item,['Serial','SerialNumber','ServiceTag','AssetSerial'])
        mac=get_any(item,['MACAddress','MacAddress','MAC','Mac','EthernetMAC','WifiMAC'])
        identifier=get_any(item,['Identifier','Target','KnownIdentifier','LookupValue']) or host or serial or mac
        dtype=get_any(item,['DeviceType','Type','DeviceClass']) or device_type
    else: continue
    if not identifier: continue
    itype=id_type(identifier)
    if not host and itype == 'HostName': host=identifier
    if not serial and itype == 'Serial': serial=identifier
    if not mac and itype == 'MAC': mac=identifier
    out.writerow([identifier, itype, dtype, norm_host(host), norm_serial(serial), norm_mac(mac), f'JSON:{path}'])
PY
}

resolve_with_inventory() {
  local manifest="$1" inventory_combined="$2" output="$3"
  if [[ ${#INVENTORY_PATHS[@]} -eq 0 ]]; then
    { printf 'Identifier,IdentifierType,DeviceType,HostName,Serial,MACAddress,Source\n'; cat "$manifest"; } > "$output"
    return
  fi
  if ! has_cmd python3; then fail "python3 is required for inventory resolution."; fi
  { for inv in "${INVENTORY_PATHS[@]}"; do import_csv "$inv" "Inventory"; done; } > "$inventory_combined"
  python3 - "$manifest" "$inventory_combined" "$output" <<'PY'
import csv, sys
manifest, inventory, output = sys.argv[1], sys.argv[2], sys.argv[3]
fields = ['Identifier','IdentifierType','DeviceType','HostName','Serial','MACAddress','Source']
with open(inventory, newline='', encoding='utf-8-sig') as f: inv = list(csv.DictReader(f, fieldnames=fields))
with open(manifest, newline='', encoding='utf-8-sig') as f: rows = list(csv.DictReader(f, fieldnames=fields))
def find(row):
    for c in inv:
        if row['Serial'] and c['Serial'] == row['Serial']: return c
        if row['MACAddress'] and c['MACAddress'] == row['MACAddress']: return c
        if row['HostName'] and c['HostName'] == row['HostName']: return c
    return None
with open(output, 'w', newline='', encoding='utf-8') as f:
    out = csv.DictWriter(f, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator='\n')
    out.writeheader(); seen = set()
    for row in rows:
        match = find(row)
        if match and not row['HostName']:
            row['HostName'] = match['HostName']
            row['Serial'] = row['Serial'] or match['Serial']
            row['MACAddress'] = row['MACAddress'] or match['MACAddress']
            if row['DeviceType'] == 'Unknown': row['DeviceType'] = match['DeviceType']
            row['Source'] = row['Source'] + ';ResolvedFromInventory'
        key = (row['HostName'], row['Serial'], row['MACAddress'], row['Identifier'])
        if key in seen: continue
        seen.add(key); out.writerow(row)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-type) DEVICE_TYPE="${2:?missing value for --device-type}"; shift 2 ;;
    --target) TARGETS+=("${2:?missing value for --target}"); shift 2 ;;
    --file|--txt|--csv|--json) INPUT_FILES+=("$1:${2:?missing value for $1}"); shift 2 ;;
    --inventory) INVENTORY_PATHS+=("${2:?missing value for --inventory}"); shift 2 ;;
    --output) OUTPUT_PATH="${2:?missing value for --output}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done ;;
    -*) fail "Unknown option: $1" ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

[[ "$DEVICE_TYPE" =~ ^(Cybernet|Neuron|Workstation|Unknown)$ ]] || fail "Invalid --device-type: $DEVICE_TYPE"
[[ ${#TARGETS[@]} -gt 0 || ${#INPUT_FILES[@]} -gt 0 ]] || fail "No targets provided. Use --target, positional args, or --file/--txt/--csv/--json."

mkdir -p "$(dirname "$OUTPUT_PATH")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
raw_manifest="$tmp_dir/raw_manifest.csv"
resolved_manifest="$tmp_dir/resolved_manifest.csv"
inventory_manifest="$tmp_dir/inventory_manifest.csv"
: > "$raw_manifest"

for target in "${TARGETS[@]}"; do emit_record "$target" "" "" "" "$DEVICE_TYPE" "Typed" >> "$raw_manifest"; done
for entry in "${INPUT_FILES[@]}"; do
  mode="${entry%%:*}"; path="${entry#*:}"
  case "$mode" in
    --txt) import_txt "$path" >> "$raw_manifest" ;;
    --csv) import_csv "$path" "CSV" >> "$raw_manifest" ;;
    --json) import_json "$path" >> "$raw_manifest" ;;
    --file)
      case "${path,,}" in
        *.csv) import_csv "$path" "CSV" >> "$raw_manifest" ;;
        *.json) import_json "$path" >> "$raw_manifest" ;;
        *.txt|*) import_txt "$path" >> "$raw_manifest" ;;
      esac ;;
  esac
done

resolve_with_inventory "$raw_manifest" "$inventory_manifest" "$resolved_manifest"
cp "$resolved_manifest" "$OUTPUT_PATH"
log "Wrote target survey manifest: $OUTPUT_PATH"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT_PATH"
