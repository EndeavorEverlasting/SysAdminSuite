#!/usr/bin/env bash
# SysAdminSuite Cybernet remote evidence collector
# Reads a survey manifest and collects hostname/serial/MAC evidence without mutating targets.
# Uses bash/transport/sas-workstation-identity.sh when available.

set -euo pipefail

MANIFEST=""
OUTPUT="survey/output/cybernet_evidence.csv"
TIMEOUT_SEC=5
SSH_USER=""
SSH_KEY=""
ALLOW_SSH=0
PASS_THRU=0
IDENTITY_ADAPTER=""

usage() {
  cat <<'USAGE'
Cybernet Remote Evidence Collector

Usage:
  ./survey/sas-collect-cybernet-evidence.sh --manifest remote_survey_manifest.csv [options]

Options:
  --manifest PATH          Survey manifest CSV from deployment-audit/sas-build-survey-manifest.sh or survey/sas-survey-targets.sh
  --output PATH            Output evidence CSV. Default: survey/output/cybernet_evidence.csv
  --identity-adapter PATH  Optional workstation identity adapter. Defaults to bash/transport/sas-workstation-identity.sh when present
  --timeout SEC            Network timeout for lightweight probes. Default: 5
  --ssh-user USER          Optional SSH username for SSH-capable targets
  --ssh-key PATH           Optional SSH private key
  --allow-ssh              Permit SSH read-only commands through the identity adapter
  --pass-thru              Print evidence CSV after writing
  -h, --help               Show help

Safety:
  - Read-only.
  - Does not change devices.
  - SSH is disabled unless --allow-ssh is passed.
  - If no trusted transport is available, the tool still emits an evidence row with a clear status.

Output columns:
  Timestamp,ExcelRow,ConflictField,ConflictValue,InputIdentifier,Target,HostName,ExpectedSerial,ExpectedMAC,
  ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,TransportUsed,EvidenceStatus,RevisitRecommendation,Notes
USAGE
}

fail(){ printf '[cybernet-evidence] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[cybernet-evidence] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ADAPTER="$REPO_ROOT/bash/transport/sas-workstation-identity.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?missing value for --manifest}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --identity-adapter) IDENTITY_ADAPTER="${2:?missing value for --identity-adapter}"; shift 2 ;;
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
[[ -z "$IDENTITY_ADAPTER" && -f "$DEFAULT_ADAPTER" ]] && IDENTITY_ADAPTER="$DEFAULT_ADAPTER"
if [[ -n "$IDENTITY_ADAPTER" && ! -f "$IDENTITY_ADAPTER" ]]; then fail "identity adapter not found: $IDENTITY_ADAPTER"; fi
mkdir -p "$(dirname "$OUTPUT")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TARGETS_FILE="$TMP_DIR/cybernet_targets.txt"
IDENTITY_CSV="$TMP_DIR/workstation_identity.csv"

python3 - "$MANIFEST" "$TARGETS_FILE" <<'PY'
import csv, sys
manifest, out = sys.argv[1:3]
def first(row, names):
    lower={k.lower():v for k,v in row.items()}
    for name in names:
        v=lower.get(name.lower())
        if v and str(v).strip(): return str(v).strip()
    return ''
seen=[]
with open(manifest, newline='', encoding='utf-8-sig') as f:
    for row in csv.DictReader(f):
        target=first(row, ['HostName','Target','Identifier','SurveyTargetHint'])
        if target and target not in seen: seen.append(target)
with open(out, 'w', encoding='utf-8') as f:
    for target in seen: f.write(target+'\n')
PY

if [[ -n "$IDENTITY_ADAPTER" ]]; then
  adapter_args=("$IDENTITY_ADAPTER" --targets-file "$TARGETS_FILE" --output "$IDENTITY_CSV" --timeout "$TIMEOUT_SEC")
  if [[ "$ALLOW_SSH" -eq 1 ]]; then
    adapter_args+=(--allow-ssh)
    [[ -n "$SSH_USER" ]] && adapter_args+=(--ssh-user "$SSH_USER")
    [[ -n "$SSH_KEY" ]] && adapter_args+=(--ssh-key "$SSH_KEY")
  fi
  bash "${adapter_args[@]}" >/dev/null
else
  printf 'Timestamp,Target,ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,TransportUsed,IdentityStatus,Notes\n' > "$IDENTITY_CSV"
fi

python3 - "$MANIFEST" "$OUTPUT" "$IDENTITY_CSV" <<'PY'
import csv, datetime as dt, re, sys
manifest, output, identity_csv = sys.argv[1:4]
fields = ['Timestamp','ExcelRow','ConflictField','ConflictValue','InputIdentifier','Target','HostName','ExpectedSerial','ExpectedMAC','ResolvedAddress','PingStatus','DnsName','ObservedHostName','ObservedSerial','ObservedMACs','TransportUsed','EvidenceStatus','RevisitRecommendation','Notes']
def first(row, names):
    lower={k.lower():v for k,v in row.items()}
    for name in names:
        v=lower.get(name.lower())
        if v and str(v).strip(): return str(v).strip()
    return ''
def norm_mac(v):
    hx=re.sub(r'[^0-9A-Fa-f]','',v or '').upper()
    return ':'.join(hx[i:i+2] for i in range(0,12,2)) if len(hx)==12 else (v or '').strip().upper()
def norm_serial(v): return re.sub(r'\s+','',(v or '').strip()).upper()
def verdict(ping_status, expected_serial, expected_mac, observed_serial, observed_macs, identity_status):
    evidence=[]
    if expected_serial and observed_serial:
        evidence.append('SerialMatch' if norm_serial(expected_serial)==norm_serial(observed_serial) else 'SerialConflict')
    if expected_mac and observed_macs:
        observed=[norm_mac(x) for x in re.split(r'[;\s,]+', observed_macs) if x.strip()]
        evidence.append('MACMatch' if norm_mac(expected_mac) in observed else 'MACConflict')
    if any(x.endswith('Conflict') for x in evidence): return 'Conflict','Physical revisit or privileged remote review justified'
    if evidence and all(x.endswith('Match') for x in evidence): return 'Confirmed','No revisit needed based on collected evidence'
    if identity_status == 'IdentityCollected': return 'IdentityCollectedNeedsComparisonData','Collected identity, but tracker lacks expected serial/MAC for hard comparison'
    if ping_status == 'Reachable': return 'ReachableNeedsPrivilegedSurvey','Try approved identity transport before revisit'
    return 'Unreachable','Revisit justified only after network/remote-management path is exhausted'
identity={}
with open(identity_csv, newline='', encoding='utf-8-sig') as f:
    for row in csv.DictReader(f):
        target=first(row, ['Target'])
        if target: identity[target.upper()]=row
rows=[]
with open(manifest, newline='', encoding='utf-8-sig') as f:
    for row in csv.DictReader(f):
        target=first(row, ['HostName','Target','Identifier','SurveyTargetHint'])
        host=first(row, ['HostName'])
        expected_serial=first(row, ['Serial','ExpectedSerial','Cybernet Serial'])
        expected_mac=norm_mac(first(row, ['MACAddress','ExpectedMAC','Cybernet MAC']))
        ident=identity.get((host or target).upper(), identity.get(target.upper(), {}))
        ping_status=first(ident, ['PingStatus'])
        identity_status=first(ident, ['IdentityStatus'])
        observed_serial=first(ident, ['ObservedSerial'])
        observed_macs=first(ident, ['ObservedMACs'])
        evidence_status,recommendation=verdict(ping_status, expected_serial, expected_mac, observed_serial, observed_macs, identity_status)
        rows.append({
            'Timestamp': dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'ExcelRow': first(row, ['ExcelRow']),
            'ConflictField': first(row, ['ConflictField']),
            'ConflictValue': first(row, ['ConflictValue']),
            'InputIdentifier': first(row, ['Identifier']),
            'Target': target,
            'HostName': host,
            'ExpectedSerial': expected_serial,
            'ExpectedMAC': expected_mac,
            'ResolvedAddress': first(ident, ['ResolvedAddress']),
            'PingStatus': ping_status or 'NotChecked',
            'DnsName': first(ident, ['DnsName']),
            'ObservedHostName': first(ident, ['ObservedHostName']),
            'ObservedSerial': observed_serial,
            'ObservedMACs': observed_macs,
            'TransportUsed': first(ident, ['TransportUsed']),
            'EvidenceStatus': evidence_status,
            'RevisitRecommendation': recommendation,
            'Notes': first(ident, ['Notes']),
        })
with open(output, 'w', newline='', encoding='utf-8') as f:
    writer=csv.DictWriter(f, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator='\n')
    writer.writeheader(); writer.writerows(rows)
print(f'Wrote {len(rows)} evidence row(s) to {output}')
PY

log "Evidence collection complete: $OUTPUT"
if [[ "$PASS_THRU" -eq 1 ]]; then cat "$OUTPUT"; fi
