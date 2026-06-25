#!/usr/bin/env bash
# SysAdminSuite Cybernet cleanup/revisit report builder
# Consumes offline resolver output and produces tracker cleanup + revisit priority CSVs.

set -euo pipefail

RESOLVER_CSV=""
OUTPUT_CLEANUP="survey/output/cybernet_tracker_cleanup.csv"
OUTPUT_REVISIT="survey/output/cybernet_revisit_priority.csv"
PASS_THRU=0

usage(){ cat <<'USAGE'
Cybernet Cleanup/Revisit Report Builder

Usage:
  bash survey/sas-build-cybernet-cleanup-report.sh --resolver-csv live_serial_probe_results.csv [options]

Options:
  --resolver-csv PATH      Input CSV from survey/sas-live-serial-probe.sh
  --output-cleanup PATH    Tracker cleanup CSV output. Default: survey/output/cybernet_tracker_cleanup.csv
  --output-revisit PATH    Revisit priority CSV output. Default: survey/output/cybernet_revisit_priority.csv
  --pass-thru              Print both generated CSVs after writing
  -h, --help               Show help

Safety:
  - Offline only. Reads CSV evidence and writes reports.
  - Does not query AD, WMI, DNS, or endpoints.
  - Does not mutate tracker/device records.
USAGE
}

fail(){ echo "[cybernet-cleanup] ERROR: $*" >&2; exit 1; }
log(){ echo "[cybernet-cleanup] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resolver-csv) RESOLVER_CSV="${2:?missing --resolver-csv value}"; shift 2 ;;
    --output-cleanup) OUTPUT_CLEANUP="${2:?missing --output-cleanup value}"; shift 2 ;;
    --output-revisit) OUTPUT_REVISIT="${2:?missing --output-revisit value}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$RESOLVER_CSV" ]] || fail "--resolver-csv is required"
[[ -f "$RESOLVER_CSV" ]] || fail "Resolver CSV not found: $RESOLVER_CSV"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
mkdir -p "$(dirname "$OUTPUT_CLEANUP")" "$(dirname "$OUTPUT_REVISIT")"

python3 - "$RESOLVER_CSV" "$OUTPUT_CLEANUP" "$OUTPUT_REVISIT" <<'PY'
import csv, datetime as dt, re, sys
from pathlib import Path

resolver_csv, output_cleanup, output_revisit = sys.argv[1:4]

cleanup_fields = [
    "GeneratedAt","SourceRow","CybernetSerial","OldHostName","ObservedHostName",
    "ObservedMAC","ObservedSerial","CleanupStatus","RecommendedAction",
    "Confidence","EvidenceSource","Notes",
]
revisit_fields = [
    "GeneratedAt","PriorityBucket","Target","CybernetSerial","HostName",
    "ObservedHostName","ObservedSerial","ObservedMAC","Reason",
    "RecommendedAction","FollowUpSystem","SourceRow","EvidenceSource",
    "ProbeMethodsAttempted","Notes",
]

def first(row, names):
    lower = {str(k).strip().lower(): (v or "").strip() for k, v in row.items() if k is not None}
    for name in names:
        value = lower.get(name.lower(), "")
        if value:
            return value
    return ""

def norm(value):
    return re.sub(r"\s+", "", value or "").upper()

def expected_serial(row):
    return first(row, ["expected_cybernet_serial","ExpectedSerial","CybernetSerial","Serial","SerialNumber","ServiceTag","AssetSerial"])

def observed_serial(row):
    return first(row, ["resolved_serial","observed_serial","ObservedSerial"])

def cybernet_serial(row):
    # Use only explicit serial evidence columns. Never infer a serial from target,
    # input identifier, or hostname because hostnames are mutable probe hints.
    return expected_serial(row) or observed_serial(row)

def observed_mac(row):
    return first(row, ["resolved_mac","observed_mac","ObservedMAC","ObservedMACs"])

def expected_host(row):
    return first(row, ["expected_hostname","HostName","Hostname"])

def observed_host(row):
    return first(row, ["resolved_hostname","observed_hostname","ObservedHostName"])

def has_hard_identity(row):
    return bool(observed_serial(row) or observed_mac(row))

def has_populate_evidence(row):
    return bool(
        (first(row, ["can_populate_serial"]) == "yes" and observed_serial(row))
        or (first(row, ["can_populate_mac"]) == "yes" and observed_mac(row))
        or (first(row, ["log_status"]) == "populate_missing_fields" and has_hard_identity(row))
    )

def cleanup_status(row):
    cls = first(row, ["classification"])
    log = first(row, ["log_status"])
    drift = first(row, ["identity_drift_status"])
    can_serial = first(row, ["can_populate_serial"])
    can_mac = first(row, ["can_populate_mac"])
    exp_host = expected_host(row)
    obs_host = observed_host(row)
    exp_serial = expected_serial(row)
    obs_serial = observed_serial(row)

    if cls == "manual_review" or log in {"serial_conflict", "mac_conflict"}:
        return "manual_review_required", "Do not update tracker automatically; verify source tracker and device evidence."
    if drift == "hostname_drift" or log == "hostname_drift":
        extra = []
        if can_serial == "yes" and obs_serial:
            extra.append(f"populate serial {obs_serial}")
        if can_mac == "yes" and observed_mac(row):
            extra.append(f"populate MAC {observed_mac(row)}")
        suffix = f" Also {' and '.join(extra)}." if extra else ""
        return "hostname_drift", f"Update tracker hostname from {exp_host or '<blank>'} to {obs_host or '<blank>'}; keep serial as identity.{suffix}"
    if can_serial == "yes" and obs_serial:
        return "populate_missing_serial", f"Populate tracker Cybernet serial with {obs_serial}."
    if can_mac == "yes" and observed_mac(row):
        return "populate_missing_mac", f"Populate tracker MAC with {observed_mac(row)}."
    if cls in {"identity_resolved", "live_serial_confirmed"} and exp_serial and obs_serial and norm(exp_serial) == norm(obs_serial):
        return "already_confirmed", "No tracker cleanup needed based on supplied evidence."
    return "no_tracker_update", "No tracker cleanup action from supplied evidence."

def priority(row):
    cls = first(row, ["classification"])
    log = first(row, ["log_status"])
    drift = first(row, ["identity_drift_status"])
    reach = first(row, ["reachability_status"])
    evidence = first(row, ["evidence_source"])
    notes = first(row, ["notes","evidence_detail"])

    if cls == "manual_review" or log in {"serial_conflict", "mac_conflict"}:
        return "P0_manual_review", "Serial/MAC conflict", "Stop automation; verify tracker/source data and physical device evidence."
    if drift == "hostname_drift" or log == "hostname_drift":
        return "P1_tracker_cleanup_only", "Serial identity resolved but hostname drifted", "Update tracker hostname; no physical revisit needed from this evidence alone."
    if has_populate_evidence(row):
        return "P1_tracker_cleanup_only", "Missing tracker fields can be populated", "Update tracker fields from observed evidence; no physical revisit needed from this evidence alone."
    if cls in {"identity_resolved", "live_serial_confirmed"} and has_hard_identity(row):
        return "P2_no_revisit_needed", "Identity confirmed by serial or MAC evidence", "No revisit needed based on supplied evidence."
    if cls in {"identity_resolved", "live_serial_confirmed"} and not has_hard_identity(row):
        return "P3_wmi_or_network_retry", "Hostname-only evidence is not enough to confirm Cybernet identity", "Collect serial or MAC evidence before clearing revisit."
    if cls == "needs_ad_lookup":
        return "P3_ad_vision_lookup_needed", "No identity evidence resolved from supplied CSVs", "Check AD/Vision/tracker mapping before scheduling a physical revisit."
    if cls == "unreachable_mark_off":
        return "P4_remote_paths_exhausted", "Still unresolved after supplied remote evidence", "Only consider physical revisit after AD/Vision/network paths are exhausted."
    if reach in {"NoPing", "Unreachable", "not_checked"} or evidence in {"none", ""}:
        return "P3_wmi_or_network_retry", "No usable live identity evidence", "Retry from approved network or enrich with AD/Vision before physical revisit."
    return "P3_review_needed", notes or "Unclassified resolver row", "Review row before deciding on revisit."

now = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
cleanup_rows = []
revisit_rows = []

with open(resolver_csv, newline="", encoding="utf-8-sig") as handle:
    for row in csv.DictReader(handle):
        status, action = cleanup_status(row)
        bucket, reason, revisit_action = priority(row)
        cleanup_rows.append({
            "GeneratedAt": now,
            "SourceRow": first(row, ["source_row","SourceRow","ExcelRow"]),
            "CybernetSerial": cybernet_serial(row),
            "OldHostName": expected_host(row),
            "ObservedHostName": observed_host(row),
            "ObservedMAC": observed_mac(row),
            "ObservedSerial": observed_serial(row),
            "CleanupStatus": status,
            "RecommendedAction": action,
            "Confidence": first(row, ["probe_confidence"]),
            "EvidenceSource": first(row, ["evidence_source"]),
            "Notes": first(row, ["notes","evidence_detail"]),
        })
        revisit_rows.append({
            "GeneratedAt": now,
            "PriorityBucket": bucket,
            "Target": first(row, ["target","Target","input_identifier"]),
            "CybernetSerial": cybernet_serial(row),
            "HostName": expected_host(row),
            "ObservedHostName": observed_host(row),
            "ObservedSerial": observed_serial(row),
            "ObservedMAC": observed_mac(row),
            "Reason": reason,
            "RecommendedAction": revisit_action,
            "FollowUpSystem": first(row, ["follow_up_system"]),
            "SourceRow": first(row, ["source_row","SourceRow","ExcelRow"]),
            "EvidenceSource": first(row, ["evidence_source"]),
            "ProbeMethodsAttempted": first(row, ["probe_methods_attempted"]),
            "Notes": first(row, ["notes","evidence_detail"]),
        })

for path, fields, rows in [
    (output_cleanup, cleanup_fields, cleanup_rows),
    (output_revisit, revisit_fields, revisit_rows),
]:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

print(f"Wrote {len(cleanup_rows)} tracker cleanup row(s) to {output_cleanup}")
print(f"Wrote {len(revisit_rows)} revisit priority row(s) to {output_revisit}")
PY

log "Tracker cleanup report ready: $OUTPUT_CLEANUP"
log "Revisit priority report ready: $OUTPUT_REVISIT"
if [[ "$PASS_THRU" -eq 1 ]]; then
  echo "--- $OUTPUT_CLEANUP ---"
  cat "$OUTPUT_CLEANUP"
  echo "--- $OUTPUT_REVISIT ---"
  cat "$OUTPUT_REVISIT"
fi
