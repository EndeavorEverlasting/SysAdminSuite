#!/usr/bin/env bash
# Normalize AD registered population CSV, reconcile optional offline evidence,
# and emit bucketed target lists. No live AD queries. No network scans.
set -euo pipefail

VERSION="1.0.0"
AD_CSV=""
EVIDENCE_CSV=""
NETWORK_CSV=""
SERIAL_CSV=""
OUTPUT_DIR="survey/output/ad_reconcile"
PREFIX=""
STALE_DAYS=90
PASS_THRU=0

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-ad-reconcile.sh --ad-csv PATH [options]

Normalize an authorized AD computer export and reconcile optional offline evidence.
Population authority is AD. This script does not query AD live or run Naabu/Nmap.

Options:
  --ad-csv PATH         Required AD computer CSV export
  --evidence-csv PATH   Optional manifest/tracker evidence CSV
  --network-csv PATH    Optional pre-validated reachability evidence CSV
  --serial-csv PATH     Optional live-serial / identity evidence CSV
  --output-dir PATH     Output directory (default: survey/output/ad_reconcile)
  --prefix PREFIX       Optional hostname prefix filter (e.g. CYB, WNH)
  --stale-days N        Days before LastLogonDate is stale (default: 90)
  --pass-thru           Print ad_summary.json after writing
  --version             Print version and exit
  -h, --help            Show help

Outputs (under --output-dir):
  ad_registered_normalized.csv, ad_targets_hostnames.txt, ad_targets_dns.txt,
  ad_evidence_matches.csv, ad_only.csv, evidence_only.csv, ad_disabled.csv,
  ad_stale.csv, ad_missing_dns.csv, ad_duplicates.csv, network_reachable.csv,
  network_silent.csv, live_serial_matched.csv, live_serial_unavailable.csv,
  ad_summary.json, README.txt
USAGE
}

fail() { echo "[ad-reconcile] ERROR: $*" >&2; exit 1; }
log() { echo "[ad-reconcile] $*" >&2; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ad-csv) AD_CSV="${2:?}"; shift 2 ;;
    --evidence-csv) EVIDENCE_CSV="${2:?}"; shift 2 ;;
    --network-csv) NETWORK_CSV="${2:?}"; shift 2 ;;
    --serial-csv) SERIAL_CSV="${2:?}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?}"; shift 2 ;;
    --prefix) PREFIX="${2:?}"; shift 2 ;;
    --stale-days) STALE_DAYS="${2:?}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$AD_CSV" ]] || fail "--ad-csv is required"
[[ -f "$AD_CSV" ]] || fail "AD CSV not found: $AD_CSV"
[[ "$STALE_DAYS" =~ ^[0-9]+$ ]] || fail "--stale-days must be a non-negative integer"

mkdir -p "$OUTPUT_DIR"
py="$(find_python)"

"$py" - "$AD_CSV" "$EVIDENCE_CSV" "$NETWORK_CSV" "$SERIAL_CSV" "$OUTPUT_DIR" "$PREFIX" "$STALE_DAYS" <<'PY'
import csv
import datetime as dt
import json
import sys
from pathlib import Path

ad_csv, evidence_csv, network_csv, serial_csv, output_dir, prefix, stale_days_s = sys.argv[1:8]
out = Path(output_dir)
out.mkdir(parents=True, exist_ok=True)
prefix = (prefix or "").strip().upper()
stale_days = int(stale_days_s or "90")
now = dt.datetime.now(dt.timezone.utc)

NORM_FIELDS = [
    "HostName", "DNSHostName", "ADStatus", "Enabled", "OperatingSystem",
    "LastLogonDate", "Description", "DistinguishedName", "SourceFile",
    "PopulationAuthority", "ReconcileBucket",
]

MATCH_FIELDS = NORM_FIELDS + ["EvidenceHostName", "EvidenceDeviceType", "EvidenceSerial", "EvidenceSource", "MatchStatus"]
BUCKET_FIELDS = ["HostName", "DNSHostName", "Bucket", "Reason", "PopulationAuthority", "SourceFile"]
NET_FIELDS = ["HostName", "Reachability", "Source", "PopulationAuthority"]
SERIAL_FIELDS = ["HostName", "Serial", "ProbeStatus", "Source", "PopulationAuthority"]


def clean(value):
    return str(value or "").strip()


def norm_host(value):
    value = clean(value).upper()
    return value.split(".", 1)[0] if value else ""


def first(row, names):
    lowered = {str(k).lower(): clean(v) for k, v in row.items() if k is not None}
    for name in names:
        val = lowered.get(name.lower(), "")
        if val:
            return val
    return ""


def parse_bool_enabled(value):
    val = clean(value).lower()
    if val in {"false", "0", "no", "disabled"}:
        return False
    if val in {"true", "1", "yes", "enabled"}:
        return True
    return True


def parse_date(value):
    raw = clean(value)
    if not raw:
        return None
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y %H:%M:%S", "%m/%d/%Y"):
        try:
            parsed = dt.datetime.strptime(raw[:19], fmt)
            return parsed.replace(tzinfo=dt.timezone.utc)
        except ValueError:
            continue
    return None


def is_stale(last_logon):
    if last_logon is None:
        return False
    age = now - last_logon
    return age.days > stale_days


def write_csv(path, fields, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fields})


def write_lines(path, lines):
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def load_ad_rows(path):
    with Path(path).open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def normalize_ad(path):
    rows = []
    host_counts = {}
    for row in load_ad_rows(path):
        dns_host = first(row, ["DNSHostName", "DNS Host Name", "FQDN"])
        host = first(row, ["Name", "HostName", "Hostname", "ComputerName", "Computer", "CN"])
        if not host and dns_host:
            host = dns_host
        host_norm = norm_host(host)
        if not host_norm:
            continue
        if prefix and not host_norm.startswith(prefix):
            continue
        enabled = parse_bool_enabled(first(row, ["Enabled", "AccountEnabled", "ADEnabled"]))
        last_logon_raw = first(row, ["LastLogonDate", "LastLogonTimestamp", "LastLogon", "Last Seen", "LastSeen"])
        last_logon = parse_date(last_logon_raw)
        host_counts[host_norm] = host_counts.get(host_norm, 0) + 1
        ad_status = "AD_DISABLED" if not enabled else "AD_REGISTERED"
        rows.append({
            "HostName": host_norm,
            "DNSHostName": clean(dns_host),
            "ADStatus": ad_status,
            "Enabled": "true" if enabled else "false",
            "OperatingSystem": first(row, ["OperatingSystem", "OS", "Operating System"]),
            "LastLogonDate": last_logon_raw,
            "Description": first(row, ["Description", "Comment", "Notes"]),
            "DistinguishedName": first(row, ["DistinguishedName", "DN", "CanonicalName"]),
            "SourceFile": str(path),
            "PopulationAuthority": "ad_registered",
            "ReconcileBucket": "registered",
            "_enabled": enabled,
            "_stale": is_stale(last_logon),
            "_missing_dns": not clean(dns_host),
            "_duplicate": False,
            "_host_count": 0,
        })
    for row in rows:
        row["_host_count"] = host_counts.get(row["HostName"], 0)
        row["_duplicate"] = row["_host_count"] > 1
    return rows


def load_evidence(path):
    if not path or not Path(path).is_file():
        return {}
    index = {}
    with Path(path).open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            host = norm_host(first(row, ["HostName", "Hostname", "ComputerName", "Target", "Name"]))
            if not host:
                continue
            index[host] = {
                "EvidenceHostName": host,
                "EvidenceDeviceType": first(row, ["DeviceType", "Type"]),
                "EvidenceSerial": first(row, ["Serial", "SerialNumber", "ExpectedCybernetSerial", "ExpectedNeuronSerial"]),
                "EvidenceSource": first(row, ["Source", "SourceFile"]) or str(path),
            }
    return index


def load_network(path):
    reachable, silent = [], []
    if not path or not Path(path).is_file():
        return reachable, silent
    with Path(path).open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            host = norm_host(first(row, ["HostName", "Hostname", "Target", "ComputerName"]))
            if not host:
                continue
            status = clean(first(row, ["Reachability", "Status", "PingStatus"])).lower()
            source = first(row, ["Source", "SourceFile"]) or str(path)
            entry = {"HostName": host, "Reachability": status, "Source": source, "PopulationAuthority": "ad_registered"}
            if any(tok in status for tok in ("reach", "up", "open", "success", "online")):
                reachable.append(entry)
            elif any(tok in status for tok in ("silent", "down", "unreach", "timeout", "fail", "offline")):
                silent.append(entry)
    return reachable, silent


def load_serial(path):
    matched, unavailable = [], []
    if not path or not Path(path).is_file():
        return matched, unavailable
    with Path(path).open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            host = norm_host(first(row, ["HostName", "Hostname", "Target", "ObservedHostName", "resolved_hostname"]))
            if not host:
                continue
            serial = first(row, ["Serial", "ObservedSerial", "ResolvedSerial", "resolved_serial"])
            status = clean(first(row, ["ProbeStatus", "SerialProbeStatus", "serial_probe_status"])).lower()
            source = first(row, ["Source", "EvidenceSource", "evidence_source"]) or str(path)
            entry = {"HostName": host, "Serial": serial, "ProbeStatus": status, "Source": source, "PopulationAuthority": "ad_registered"}
            if any(tok in status for tok in ("match", "confirm", "found", "resolved")):
                matched.append(entry)
            elif any(tok in status for tok in ("unavail", "missing", "fail", "no_match", "unknown")) or not serial:
                unavailable.append(entry)
    return matched, unavailable


ad_rows = normalize_ad(ad_csv)
evidence = load_evidence(evidence_csv)
network_reachable, network_silent = load_network(network_csv)
serial_matched, serial_unavailable = load_serial(serial_csv)

ad_hosts = {r["HostName"] for r in ad_rows}
evidence_hosts = set(evidence.keys())

disabled, stale, missing_dns, duplicates = [], [], [], []
ad_only, evidence_only, matches = [], [], []
target_hostnames, target_dns = [], []

for row in ad_rows:
    host = row["HostName"]
    base = {k: row[k] for k in NORM_FIELDS}
    if not row["_enabled"]:
        row["ReconcileBucket"] = "disabled"
        disabled.append({**base, "Bucket": "ad_disabled", "Reason": "AD account disabled"})
        continue
    if row["_duplicate"]:
        row["ReconcileBucket"] = "duplicate"
        duplicates.append({**base, "Bucket": "ad_duplicates", "Reason": "Duplicate normalized hostname key"})
        continue
    if row["_stale"]:
        row["ReconcileBucket"] = "stale"
        stale.append({**base, "Bucket": "ad_stale", "Reason": f"LastLogonDate older than {stale_days} days"})
    if row["_missing_dns"]:
        row["ReconcileBucket"] = "missing_dns"
        missing_dns.append({**base, "Bucket": "ad_missing_dns", "Reason": "Missing DNSHostName"})
    if row["ReconcileBucket"] == "registered":
        target_hostnames.append(host)
        if row["DNSHostName"]:
            target_dns.append(row["DNSHostName"])
    if host in evidence_hosts:
        ev = evidence[host]
        matches.append({**base, **ev, "MatchStatus": "ad_evidence_match"})
        row["ReconcileBucket"] = "matched"
    elif row["ReconcileBucket"] in {"registered", "stale", "missing_dns"}:
        ad_only.append({**base, "Bucket": "ad_only", "Reason": "Registered in AD, absent from supplemental evidence"})

for host, ev in sorted(evidence.items()):
    if host not in ad_hosts:
        evidence_only.append({
            "HostName": host,
            "DNSHostName": "",
            "Bucket": "evidence_only",
            "Reason": "Present in supplemental evidence, absent from AD export",
            "PopulationAuthority": "ad_registered",
            "SourceFile": ev.get("EvidenceSource", ""),
            **{k: ev.get(k, "") for k in ("EvidenceHostName", "EvidenceDeviceType", "EvidenceSerial", "EvidenceSource")},
        })

normalized = [{k: row[k] for k in NORM_FIELDS} for row in ad_rows]
write_csv(out / "ad_registered_normalized.csv", NORM_FIELDS, normalized)
write_lines(out / "ad_targets_hostnames.txt", sorted(set(target_hostnames)))
write_lines(out / "ad_targets_dns.txt", sorted(set(target_dns)))
write_csv(out / "ad_evidence_matches.csv", MATCH_FIELDS, matches)
write_csv(out / "ad_only.csv", BUCKET_FIELDS, ad_only)
write_csv(out / "evidence_only.csv", BUCKET_FIELDS + ["EvidenceDeviceType", "EvidenceSerial", "EvidenceSource"],
          [{k: r.get(k, "") for k in BUCKET_FIELDS + ["EvidenceDeviceType", "EvidenceSerial", "EvidenceSource"]} for r in evidence_only])
write_csv(out / "ad_disabled.csv", BUCKET_FIELDS, disabled)
write_csv(out / "ad_stale.csv", BUCKET_FIELDS, stale)
write_csv(out / "ad_missing_dns.csv", BUCKET_FIELDS, missing_dns)
write_csv(out / "ad_duplicates.csv", BUCKET_FIELDS, duplicates)
write_csv(out / "network_reachable.csv", NET_FIELDS, network_reachable)
write_csv(out / "network_silent.csv", NET_FIELDS, network_silent)
write_csv(out / "live_serial_matched.csv", SERIAL_FIELDS, serial_matched)
write_csv(out / "live_serial_unavailable.csv", SERIAL_FIELDS, serial_unavailable)

summary = {
    "population_authority": "ad_registered",
    "source_ad_csv": str(ad_csv),
    "output_dir": str(out),
    "prefix_filter": prefix or None,
    "stale_days": stale_days,
    "generated_at": now.isoformat(),
    "counts": {
        "ad_registered_normalized": len(normalized),
        "ad_targets_hostnames": len(set(target_hostnames)),
        "ad_targets_dns": len(set(target_dns)),
        "ad_evidence_matches": len(matches),
        "ad_only": len(ad_only),
        "evidence_only": len(evidence_only),
        "ad_disabled": len(disabled),
        "ad_stale": len(stale),
        "ad_missing_dns": len(missing_dns),
        "ad_duplicates": len(duplicates),
        "network_reachable": len(network_reachable),
        "network_silent": len(network_silent),
        "live_serial_matched": len(serial_matched),
        "live_serial_unavailable": len(serial_unavailable),
    },
}
(out / "ad_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

readme = f"""AD Registered Population Reconcile Output
=========================================

Population authority: ad_registered
Source AD CSV: {ad_csv}
Generated: {summary['generated_at']}

Bucket files:
  ad_registered_normalized.csv  — full normalized AD population
  ad_targets_hostnames.txt      — approved hostname targets
  ad_targets_dns.txt            — approved DNS names
  ad_evidence_matches.csv       — AD rows matched to supplemental evidence
  ad_only.csv                   — AD without supplemental evidence
  evidence_only.csv             — supplemental evidence without AD row
  ad_disabled.csv               — disabled AD accounts
  ad_stale.csv                  — stale last-logon records (>{stale_days} days)
  ad_missing_dns.csv            — enabled hosts missing DNSHostName
  ad_duplicates.csv             — duplicate normalized hostname keys
  network_reachable.csv         — optional pre-validated reachability (reachable)
  network_silent.csv            — optional pre-validated reachability (silent)
  live_serial_matched.csv       — optional serial evidence (matched)
  live_serial_unavailable.csv   — optional serial evidence (unavailable)
  ad_summary.json               — machine-readable counts

This directory is local evidence only. Do not commit live exports.
See docs/AD_REGISTERED_POPULATION.md for doctrine.
"""
(out / "README.txt").write_text(readme, encoding="utf-8")

print(json.dumps(summary))
PY

log "Wrote AD reconcile outputs to $OUTPUT_DIR"

if [[ "$PASS_THRU" -eq 1 ]]; then
  cat "$OUTPUT_DIR/ad_summary.json"
fi
