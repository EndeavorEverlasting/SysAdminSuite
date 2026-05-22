#!/usr/bin/env bash
set -euo pipefail

MANIFEST=""
IDENTITY_CSV=""
OUTPUT="survey/output/live_serial_probe_results.csv"
DASHBOARD=""
NO_DASHBOARD=0
TIMEOUT_SEC=8
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Live Serial Probe

Usage:
  bash survey/sas-live-serial-probe.sh --manifest targets.csv [options]

Options:
  --manifest PATH       Input manifest CSV from audit, survey output, or tracker export
  --identity-csv PATH   Optional pre-collected identity CSV for offline/test joins
  --output PATH         Output CSV path. Default: survey/output/live_serial_probe_results.csv
  --dashboard PATH      Output dashboard HTML path. Default: same folder as CSV
  --no-dashboard        Skip dashboard rendering
  --timeout SEC         Ping timeout in seconds. Default: 8
  --pass-thru           Print output CSV after writing
  -h, --help            Show help

Runtime:
  Bash on Windows. Uses Windows-native ping/nslookup/wmic through cmd.exe when live probing.

Safety:
  Read-only. No staging, no scheduled tasks, no registry edits, no endpoint mutation.
USAGE
}

fail(){ echo "[live-serial-probe] ERROR: $*" >&2; exit 1; }
log(){ echo "[live-serial-probe] $*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?missing --manifest value}"; shift 2 ;;
    --identity-csv) IDENTITY_CSV="${2:?missing --identity-csv value}"; shift 2 ;;
    --output) OUTPUT="${2:?missing --output value}"; shift 2 ;;
    --dashboard) DASHBOARD="${2:?missing --dashboard value}"; shift 2 ;;
    --no-dashboard) NO_DASHBOARD=1; shift ;;
    --timeout) TIMEOUT_SEC="${2:?missing --timeout value}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$MANIFEST" ]] || fail "--manifest is required"
[[ -f "$MANIFEST" ]] || fail "Manifest not found: $MANIFEST"
[[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]] || fail "--timeout must be numeric"
has_cmd python3 || fail "python3 is required"
mkdir -p "$(dirname "$OUTPUT")"
[[ -z "$DASHBOARD" ]] && DASHBOARD="$(dirname "$OUTPUT")/live_serial_probe_dashboard.html"

python3 - "$MANIFEST" "$IDENTITY_CSV" "$OUTPUT" "$TIMEOUT_SEC" <<'PY'
import csv, datetime as dt, re, subprocess, sys
from pathlib import Path

manifest, identity_csv, output, timeout_s = sys.argv[1:5]
timeout = int(timeout_s)
fields = ['target','source_row','device_type','expected_hostname','expected_cybernet_serial','expected_neuron_serial','expected_mac','observed_hostname','observed_serial','observed_mac','reachability_status','serial_probe_status','classification','follow_up_system','already_had_serial','already_had_mac','can_populate_serial','can_populate_mac','log_status','notes','probed_at']

def first(row, names):
    lower = {str(k).strip().lower(): (v or '') for k, v in row.items() if k is not None}
    for name in names:
        v = lower.get(name.lower(), '').strip()
        if v: return v
    return ''

def norm_serial(v): return re.sub(r'\s+', '', v or '').upper()
def norm_mac(v):
    hx = re.sub(r'[^0-9A-Fa-f]', '', v or '').upper()
    return ':'.join(hx[i:i+2] for i in range(0,12,2)) if len(hx) == 12 else (v or '').strip().upper()
def macs(v): return [norm_mac(x) for x in re.split(r'[;,\s]+', v or '') if norm_mac(x)]

def run(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, errors='replace')
        return p.returncode, p.stdout or '', p.stderr or ''
    except Exception as e:
        return 127, '', str(e)

def live_probe(target):
    code, out, err = run(['ping.exe','-n','1','-w',str(timeout*1000),target])
    reachable = 'reachable' if code == 0 else 'unreachable'
    hcode, hout, herr = run(['cmd.exe','/c',f'wmic /node:"{target}" computersystem get name'])
    scode, sout, serr = run(['cmd.exe','/c',f'wmic /node:"{target}" bios get serialnumber'])
    mcode, mout, merr = run(['cmd.exe','/c',f'wmic /node:"{target}" nicconfig where IPEnabled=true get MACAddress'])
    blob = '\n'.join([hout,herr,sout,serr,mout,merr])
    low = blob.lower()
    def value(text, header):
        vals=[]
        for line in text.splitlines():
            s=line.strip()
            if not s or s.lower()==header.lower(): continue
            if header.lower() in s.lower() and len(s.split())<=2: continue
            vals.append(s)
        return vals[0] if vals else ''
    host=value(hout,'Name')
    serial=value(sout,'SerialNumber')
    found=';'.join(sorted(set(norm_mac(x) for x in re.findall(r'([0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5})', mout))))
    if 'not recognized' in low or 'not found' in low: status='wmic_missing'
    elif any(x in low for x in ['access is denied','rpc server is unavailable','logon failure']): status='serial_probe_blocked'
    elif serial: status='serial_observed'
    elif host or found: status='identity_observed_no_serial'
    else: status='serial_probe_failed'
    return dict(reachability_status=reachable, observed_hostname=host, observed_serial=serial, observed_mac=found, serial_probe_status=status, notes=blob[:220].replace('\n',' | ') if status in ['serial_probe_blocked','serial_probe_failed'] else '')

def load_identity(path):
    data={}
    if not path: return data
    with open(path, newline='', encoding='utf-8-sig') as f:
        for r in csv.DictReader(f):
            t=first(r,['target','Target','HostName','Hostname','expected_hostname'])
            if t: data[t.upper()]=r
    return data

def manifest_row(row):
    cyber=first(row,['Cybernet Hostname','CybernetHostName','Cybernet Host','HostName','Hostname'])
    neuron=first(row,['Neuron Hostname','NeuronHostName','Neuron Host'])
    target=first(row,['target','Target','SurveyTargetHint','HostName','Hostname','Cybernet Hostname','Neuron Hostname','Identifier']) or cyber or neuron
    dtype=first(row,['device_type','DeviceType','Type','DeviceClass']) or ('Neuron' if neuron and not cyber else 'Cybernet' if cyber else 'Unknown')
    return dict(target=target, source_row=first(row,['source_row','SourceRow','ExcelRow','source row']), device_type=dtype, expected_hostname=target, expected_cybernet_serial=first(row,['expected_cybernet_serial','ExpectedCybernetSerial','Cybernet Serial','Cybernet S/N']), expected_neuron_serial=first(row,['expected_neuron_serial','ExpectedNeuronSerial','Neuron S/N','Neuron Serial']), expected_mac=norm_mac(first(row,['expected_mac','ExpectedMAC','MACAddress','MAC','Cybernet MAC','Neuron MAC'])))

def classify(rec, probe):
    exp_serials=[norm_serial(rec['expected_cybernet_serial']), norm_serial(rec['expected_neuron_serial'])]
    exp_serials=[x for x in exp_serials if x]
    exp_mac=norm_mac(rec['expected_mac'])
    obs_serial=norm_serial(probe.get('observed_serial',''))
    obs_macs=macs(probe.get('observed_mac',''))
    had_serial='yes' if exp_serials else 'no'; had_mac='yes' if exp_mac else 'no'
    can_serial='yes' if obs_serial and not exp_serials else 'no'
    can_mac='yes' if obs_macs and not exp_mac else 'no'
    notes=probe.get('notes','')
    if not rec['target']: return 'needs_ad_lookup','AD;Vision',had_serial,had_mac,can_serial,can_mac,'missing_target','No target hostname or identifier'
    if exp_serials and obs_serial and obs_serial not in exp_serials: return 'manual_review','Tracker review',had_serial,had_mac,can_serial,can_mac,'serial_conflict','Observed serial conflicts with tracker serial'
    if exp_mac and obs_macs and exp_mac not in obs_macs: return 'manual_review','Tracker review',had_serial,had_mac,can_serial,can_mac,'mac_conflict','Observed MAC conflicts with tracker MAC'
    if obs_serial or obs_macs:
        status='populate_missing_fields' if can_serial=='yes' or can_mac=='yes' else 'already_confirmed'
        follow='Tracker update' if status=='populate_missing_fields' else 'None'
        return 'live_serial_confirmed',follow,had_serial,had_mac,can_serial,can_mac,status,notes
    if probe.get('reachability_status')=='reachable': return 'reachable_no_serial','Vision',had_serial,had_mac,can_serial,can_mac,'reachable_identity_gap',notes
    return 'unreachable_mark_off','AD;Vision',had_serial,had_mac,can_serial,can_mac,'marked_off_pending_external_lookup',notes

identity=load_identity(identity_csv)
rows=[]; seen=set()
with open(manifest, newline='', encoding='utf-8-sig') as f:
    for raw in csv.DictReader(f):
        rec=manifest_row(raw); key=(rec['target'],rec['source_row'],rec['expected_cybernet_serial'],rec['expected_neuron_serial'],rec['expected_mac'])
        if key in seen: continue
        seen.add(key)
        ident=identity.get(rec['target'].upper(),{}) if rec['target'] else {}
        if ident:
            probe=dict(reachability_status=first(ident,['reachability_status','PingStatus','ReachabilityStatus']), observed_hostname=first(ident,['observed_hostname','ObservedHostName']), observed_serial=first(ident,['observed_serial','ObservedSerial']), observed_mac=first(ident,['observed_mac','ObservedMACs','ObservedMAC']), serial_probe_status=first(ident,['serial_probe_status','IdentityStatus','WmiStatus']), notes=first(ident,['notes','Notes']))
        elif rec['target']:
            probe=live_probe(rec['target'])
        else:
            probe=dict(reachability_status='not_checked',observed_hostname='',observed_serial='',observed_mac='',serial_probe_status='not_checked',notes='No target supplied')
        c,follow,had_s,had_m,can_s,can_m,log_status,notes=classify(rec,probe)
        rows.append({**rec, **probe, 'classification':c, 'follow_up_system':follow, 'already_had_serial':had_s, 'already_had_mac':had_m, 'can_populate_serial':can_s, 'can_populate_mac':can_m, 'log_status':log_status, 'notes':notes, 'probed_at':dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S')})
Path(output).parent.mkdir(parents=True, exist_ok=True)
with open(output,'w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=fields,quoting=csv.QUOTE_ALL,lineterminator='\n'); w.writeheader(); w.writerows(rows)
print(f'Wrote {len(rows)} live serial probe row(s) to {output}')
PY

if [[ "$NO_DASHBOARD" -eq 0 ]]; then
  RENDERER="deployment-audit/sas-render-live-serial-dashboard.py"
  if [[ -f "$RENDERER" ]]; then
    python3 "$RENDERER" --input "$OUTPUT" --output "$DASHBOARD"
    log "Dashboard written: $DASHBOARD"
  else
    log "Dashboard renderer not found: $RENDERER"
  fi
fi

log "Live serial probe complete: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
