#!/usr/bin/env bash
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

MANIFEST=""
IDENTITY_CSV=""
AD_CSV=""
AD_LIVE=0
AD_OUTPUT=""
AD_SEARCH_DESCRIPTION=0
OUTPUT="survey/output/live_serial_probe_results.csv"
DASHBOARD=""
NO_DASHBOARD=0
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Identity Resolver

Usage:
  bash survey/sas-live-serial-probe.sh --manifest targets.csv [options]

Options:
  --manifest PATH       Input manifest CSV
  --identity-csv PATH   Optional offline identity evidence CSV
  --ad-csv PATH         Optional AD evidence CSV
  --ad-live             Generate AD evidence CSV through survey/sas-ad-identity-export.ps1
  --ad-output PATH      Path for generated AD evidence CSV
  --ad-search-description
                        Permit the AD helper to search Description for identifier matches
  --output PATH         Output resolver CSV
  --dashboard PATH      Output dashboard HTML
  --no-dashboard        Skip dashboard rendering
  --pass-thru           Print output CSV after writing
  -h, --help            Show help

Safety:
  Read-only. No endpoint mutation. AD live mode only queries directory data.
USAGE
}

fail(){ echo "[identity-resolver] ERROR: $*" >&2; exit 1; }
log(){ echo "[identity-resolver] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?missing --manifest value}"; shift 2 ;;
    --identity-csv) IDENTITY_CSV="${2:?missing --identity-csv value}"; shift 2 ;;
    --ad-csv) AD_CSV="${2:?missing --ad-csv value}"; shift 2 ;;
    --ad-live) AD_LIVE=1; shift ;;
    --ad-output) AD_OUTPUT="${2:?missing --ad-output value}"; shift 2 ;;
    --ad-search-description) AD_SEARCH_DESCRIPTION=1; shift ;;
    --output) OUTPUT="${2:?missing --output value}"; shift 2 ;;
    --dashboard) DASHBOARD="${2:?missing --dashboard value}"; shift 2 ;;
    --no-dashboard) NO_DASHBOARD=1; shift ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

OFFLINE_FIXTURE_MODE=0
if [[ -n "$IDENTITY_CSV" && "$AD_LIVE" -eq 0 ]]; then
  OFFLINE_FIXTURE_MODE=1
fi
if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" && "$OFFLINE_FIXTURE_MODE" -ne 1 ]]; then
  sas_require_northwell_wifi
fi

[[ -n "$MANIFEST" ]] || fail "--manifest is required"
[[ -f "$MANIFEST" ]] || fail "Manifest not found: $MANIFEST"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
mkdir -p "$(dirname "$OUTPUT")"
[[ -z "$DASHBOARD" ]] && DASHBOARD="$(dirname "$OUTPUT")/live_serial_probe_dashboard.html"

if [[ "$AD_LIVE" -eq 1 && -z "$AD_CSV" ]]; then
  AD_HELPER="survey/sas-ad-identity-export.ps1"
  [[ -f "$AD_HELPER" ]] || fail "AD helper not found: $AD_HELPER"
  [[ -z "$AD_OUTPUT" ]] && AD_OUTPUT="$(dirname "$OUTPUT")/ad_identity_evidence.csv"

  PS_EXE=""
  if command -v powershell.exe >/dev/null 2>&1; then PS_EXE="powershell.exe"; fi
  if [[ -z "$PS_EXE" ]] && command -v pwsh >/dev/null 2>&1; then PS_EXE="pwsh"; fi
  if [[ -z "$PS_EXE" ]] && command -v powershell >/dev/null 2>&1; then PS_EXE="powershell"; fi

  if [[ -z "$PS_EXE" ]]; then
    log "AD live requested, but no PowerShell runtime is available. Continuing without AD evidence."
  else
    AD_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$AD_HELPER" -Manifest "$MANIFEST" -Output "$AD_OUTPUT")
    [[ "$AD_SEARCH_DESCRIPTION" -eq 1 ]] && AD_ARGS+=(-SearchDescription)
    if "$PS_EXE" "${AD_ARGS[@]}"; then
      AD_CSV="$AD_OUTPUT"
      log "AD evidence CSV generated: $AD_CSV"
    else
      log "AD evidence helper failed. Continuing without AD evidence."
    fi
  fi
fi

python3 - "$MANIFEST" "$IDENTITY_CSV" "$AD_CSV" "$OUTPUT" <<'PY'
import csv, datetime as dt, re, sys
from pathlib import Path

manifest, identity_csv, ad_csv, output = sys.argv[1:5]
fields = [
    "input_identifier","input_identifier_type","target","source_row","device_type",
    "expected_hostname","expected_cybernet_serial","expected_neuron_serial","expected_mac",
    "resolved_hostname","resolved_serial","resolved_mac",
    "observed_hostname","observed_serial","observed_mac",
    "reachability_status","serial_probe_status","classification","follow_up_system",
    "probe_methods_attempted","probe_method_success","probe_confidence",
    "evidence_source","evidence_detail","identity_drift_status",
    "already_had_serial","already_had_mac","can_populate_serial","can_populate_mac",
    "log_status","notes","probed_at",
]

def first(row, names):
    lower = {str(k).strip().lower(): (v or "").strip() for k, v in row.items() if k is not None}
    for name in names:
        value = lower.get(name.lower(), "")
        if value:
            return value
    return ""

def norm_id(value):
    return re.sub(r"\s+", "", value or "").upper()

def norm_mac(value):
    value = value or ""
    if value.upper().startswith("SAMPLEMAC"):
        return value.upper()
    hx = re.sub(r"[^0-9A-Fa-f]", "", value).upper()
    return ":".join(hx[i:i+2] for i in range(0, 12, 2)) if len(hx) == 12 else value.strip().upper()

def ident_type(value):
    value = (value or "").strip()
    mac = norm_mac(value)
    if not value:
        return "missing"
    if value.upper().startswith("SAMPLEMAC") or (":" in mac and len(mac) == 17):
        return "mac"
    if "HOST" in value.upper() or "OPR" in value.upper():
        return "hostname"
    if any(c.isdigit() for c in value) and any(c.isalpha() for c in value):
        return "serial"
    return "identifier"

def key(value):
    if not value:
        return ""
    mac = norm_mac(value)
    if value.upper().startswith("SAMPLEMAC") or (":" in mac and len(mac) == 17):
        return "MAC:" + mac
    return "ID:" + norm_id(value)

def evidence_from(row, source):
    host = first(row, ["observed_hostname","ObservedHostName","ADHostname","ComputerName","HostName","Hostname","Name"])
    serial = first(row, ["observed_serial","ObservedSerial","ADSerial","Serial","SerialNumber","BiosSerial"])
    mac = first(row, ["observed_mac","ObservedMAC","ObservedMACs","ADMAC","MAC","MACAddress"])
    status = first(row, ["serial_probe_status","IdentityStatus","ADStatus"]) or ("ad_object_found" if source == "ad_csv" else "identity_csv_match")
    probe_method = first(row, ["ADProbeMethod","ProbeMethod","probe_method_success"])
    if not probe_method:
        if source == "ad_csv":
            probe_method = "ad_computer_lookup" if ident_type(first(row, ["Target","Identifier"])) == "hostname" else "ad_attribute_lookup"
        else:
            probe_method = "identity_csv_match"
    detail = " | ".join(x for x in [
        first(row, ["DirectoryPath","DistinguishedName","CanonicalName","OU"]),
        first(row, ["Enabled","ADEnabled"]),
        first(row, ["notes","Notes","Description"]),
    ] if x) or source
    confidence = "high" if source == "ad_csv" and status in {"ad_object_found","ad_multiple_matches"} else "none" if status in {"ad_probe_unavailable","ad_no_match"} else "medium"
    return {
        "reachability_status": first(row, ["reachability_status","ReachabilityStatus"]) or ("directory_only" if source == "ad_csv" else "offline_identity"),
        "observed_hostname": host,
        "observed_serial": serial,
        "observed_mac": mac,
        "serial_probe_status": status,
        "evidence_source": source,
        "evidence_detail": detail,
        "probe_method_success": probe_method,
        "probe_confidence": confidence,
    }

def load_index(path, source):
    index = {}
    if not path or not Path(path).exists():
        return index
    with open(path, newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            ev = evidence_from(row, source)
            values = [
                first(row, ["Target","Identifier","AssetTag"]),
                ev["observed_hostname"], ev["observed_serial"], ev["observed_mac"],
            ]
            for value in values:
                k = key(value)
                if k:
                    index.setdefault(k, []).append(ev.copy())
    return index

def lookup(index, value):
    return (index.get(key(value)) or [None])[0]

def serial_from_manifest(row):
    return first(row, [
        "expected_cybernet_serial","ExpectedCybernetSerial","ExpectedSerial","Expected Serial",
        "Serial","SerialNumber","ServiceTag","AssetSerial","Cybernet Serial","Cybernet S/N",
    ])

def manifest_record(row):
    cyber_host = first(row, ["Cybernet Hostname","CybernetHostName","Cybernet Host","HostName","Hostname"])
    neuron_host = first(row, ["Neuron Hostname","NeuronHostName","Neuron Host"])
    cyber_serial = serial_from_manifest(row)
    neuron_serial = first(row, ["expected_neuron_serial","ExpectedNeuronSerial","Neuron S/N","Neuron Serial"])
    mac = norm_mac(first(row, ["expected_mac","ExpectedMAC","MACAddress","MAC"] ))
    stable_serial = cyber_serial or neuron_serial
    target = stable_serial or first(row, ["target","Target","SurveyTargetHint","Identifier","HostName","Hostname","MACAddress"]) or cyber_host or neuron_host or mac
    typ = ident_type(target)
    expected_host = cyber_host or neuron_host or (target if typ == "hostname" else "")
    return {
        "input_identifier": target,
        "input_identifier_type": typ,
        "target": target,
        "source_row": first(row, ["source_row","SourceRow","ExcelRow"]),
        "device_type": first(row, ["device_type","DeviceType","Type","DeviceClass"]) or "Unknown",
        "expected_hostname": expected_host,
        "expected_cybernet_serial": cyber_serial,
        "expected_neuron_serial": neuron_serial,
        "expected_mac": mac,
    }

def lookup_candidates(rec):
    # Serial is the primary identity. Hostname is only a fallback because it can drift.
    values = [
        rec["expected_cybernet_serial"],
        rec["expected_neuron_serial"],
        rec["input_identifier"],
        rec["expected_mac"],
        rec["expected_hostname"],
    ]
    out = []
    for value in values:
        if value and value not in out:
            out.append(value)
    return out

def drift(expected, resolved, typ):
    expected, resolved = norm_id(expected), norm_id(resolved)
    if expected and resolved and expected == resolved:
        return "hostname_match"
    if expected and resolved and expected != resolved:
        return "hostname_drift"
    if not expected and resolved and typ in {"serial","mac","identifier"}:
        return "resolved_from_identifier"
    if expected and not resolved:
        return "hostname_unresolved"
    return "not_applicable"

def empty(reason):
    return {
        "reachability_status": "not_checked",
        "observed_hostname": "",
        "observed_serial": "",
        "observed_mac": "",
        "serial_probe_status": "not_checked",
        "evidence_source": "none",
        "evidence_detail": reason,
        "probe_method_success": "unresolved",
        "probe_confidence": "none",
    }

def classify(rec, ev, attempted):
    exp_serials = [x for x in [norm_id(rec["expected_cybernet_serial"]), norm_id(rec["expected_neuron_serial"])] if x]
    exp_mac = norm_mac(rec["expected_mac"])
    obs_serial = norm_id(ev["observed_serial"])
    obs_mac = norm_mac(ev["observed_mac"])
    drift_status = drift(rec["expected_hostname"], ev["observed_hostname"], rec["input_identifier_type"])
    had_serial = "yes" if exp_serials else "no"
    had_mac = "yes" if exp_mac else "no"
    can_serial = "yes" if obs_serial and not exp_serials else "no"
    can_mac = "yes" if obs_mac and not exp_mac else "no"

    if exp_serials and obs_serial and obs_serial not in exp_serials:
        ev["probe_method_success"] = "manual_review_required"
        ev["probe_confidence"] = "conflict"
        return "manual_review","Tracker review",had_serial,had_mac,can_serial,can_mac,"serial_conflict","Observed serial conflicts with tracker serial",drift_status

    if exp_mac and obs_mac and exp_mac != obs_mac:
        ev["probe_method_success"] = "manual_review_required"
        ev["probe_confidence"] = "conflict"
        return "manual_review","Tracker review",had_serial,had_mac,can_serial,can_mac,"mac_conflict","Observed MAC conflicts with tracker MAC",drift_status

    if ev["serial_probe_status"] in {"ad_probe_unavailable","ad_no_match","ad_probe_limited"} and not (ev["observed_hostname"] or obs_serial or obs_mac):
        return "needs_ad_lookup","AD;Vision",had_serial,had_mac,can_serial,can_mac,ev["serial_probe_status"],ev["evidence_detail"],drift_status

    if drift_status == "hostname_drift":
        return "identity_resolved","Tracker update",had_serial,had_mac,can_serial,can_mac,"hostname_drift","Resolved hostname differs from tracker/input hostname",drift_status

    if ev["observed_hostname"] or obs_serial or obs_mac:
        cls = "identity_resolved" if drift_status == "resolved_from_identifier" else "live_serial_confirmed"
        log_status = "populate_missing_fields" if can_serial == "yes" or can_mac == "yes" or drift_status == "resolved_from_identifier" else "already_confirmed"
        follow = "Tracker update" if log_status == "populate_missing_fields" else "None"
        return cls,follow,had_serial,had_mac,can_serial,can_mac,log_status,ev["evidence_detail"],drift_status

    if "ad_csv_lookup" not in attempted:
        return "needs_ad_lookup","AD;Vision",had_serial,had_mac,can_serial,can_mac,"ad_probe_unavailable","No AD evidence supplied and no identity evidence found",drift_status

    return "unreachable_mark_off","AD;Vision",had_serial,had_mac,can_serial,can_mac,"marked_off_pending_external_lookup",ev["evidence_detail"],drift_status

identity = load_index(identity_csv, "identity_csv")
ad = load_index(ad_csv, "ad_csv")
rows = []

with open(manifest, newline="", encoding="utf-8-sig") as handle:
    for raw in csv.DictReader(handle):
        rec = manifest_record(raw)
        attempted = ["manifest_match"]
        ev = None
        candidates = lookup_candidates(rec)
        if identity_csv:
            attempted.append("identity_csv_lookup")
            for candidate in candidates:
                ev = lookup(identity, candidate)
                if ev is not None:
                    break
        if ev is None and ad_csv:
            attempted.append("ad_csv_lookup")
            for candidate in candidates:
                ev = lookup(ad, candidate)
                if ev is not None:
                    break
        if ev is None:
            ev = empty("Identifier is not resolved by supplied evidence sources")

        classification, follow, had_s, had_m, can_s, can_m, log_status, notes, drift_status = classify(rec, ev, attempted)
        rows.append({
            **rec,
            "resolved_hostname": ev["observed_hostname"],
            "resolved_serial": ev["observed_serial"],
            "resolved_mac": ev["observed_mac"],
            **ev,
            "classification": classification,
            "follow_up_system": follow,
            "probe_methods_attempted": ";".join(attempted),
            "identity_drift_status": drift_status,
            "already_had_serial": had_s,
            "already_had_mac": had_m,
            "can_populate_serial": can_s,
            "can_populate_mac": can_m,
            "log_status": log_status,
            "notes": notes,
            "probed_at": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        })

Path(output).parent.mkdir(parents=True, exist_ok=True)
with open(output, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
print(f"Wrote {len(rows)} identity resolver row(s) to {output}")
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

log "Identity resolver complete: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT" || true
