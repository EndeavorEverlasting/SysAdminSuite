#!/usr/bin/env bash
# Contract tests for serial-first Cybernet survey progress reporting.
#
# All fixtures are synthetic (MEDTEST24-* serials, WTS001OPR* hostnames). The
# denominator for every progress metric must be unique Alejandro serials, never
# hostname rows. Ping/AD evidence is enrichment only; only IdentityCollected
# expands SurveyedSerials for an untracked serial.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DIFF_RUNNER="survey/sas-cybernet-tracker-diff.sh"
DIFF_PY="survey/sas-cybernet-tracker-diff.py"
[[ -f "$DIFF_RUNNER" ]] || { echo "missing tracker diff runner: $DIFF_RUNNER"; exit 1; }
[[ -f "$DIFF_PY" ]] || { echo "missing tracker diff python: $DIFF_PY"; exit 1; }
bash -n "$DIFF_RUNNER"

PYTHON_CMD=(python3)
command -v python3 >/dev/null 2>&1 || PYTHON_CMD=(python)
command -v "${PYTHON_CMD[0]}" >/dev/null 2>&1 || { echo "python required for progress contract test"; exit 1; }
"${PYTHON_CMD[@]}" -c 'import openpyxl' >/dev/null 2>&1 || { echo "openpyxl required for progress contract test (pip install openpyxl)"; exit 1; }

fail() { printf '[cybernet-progress-contracts] FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '[cybernet-progress-contracts] PASS: %s\n' "$*"; }

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

ALEJANDRO="$TMP_DIR/alejandro-progress.xlsx"
TRACKER="$TMP_DIR/tracker-progress.xlsx"
IDENTITY_CSV="$TMP_DIR/workstation_identity.csv"
PREFLIGHT_CSV="$TMP_DIR/network_preflight.csv"
AD_CSV="$TMP_DIR/ad_live_serial.csv"

# --- build synthetic fixtures ---
"${PYTHON_CMD[@]}" - "$ALEJANDRO" "$TRACKER" "$IDENTITY_CSV" "$PREFLIGHT_CSV" <<'PY'
import sys
from openpyxl import Workbook

alejandro, tracker, identity_csv, preflight_csv = sys.argv[1:5]

wb = Workbook()
wave = wb.active
wave.title = "AKBAR WAVE 1"
wave["A1"] = "MEDTEST24-TRK01"   # overlaps tracker -> surveyed via tracker
wave["A2"] = "MEDTEST24-SO01"    # serial-only, zero host -> review-required
po = wb.create_sheet("PO 1")
po["A1"] = "WTS001OPR501"        # exactly one host -> host-resolved / probe-ready
po["B1"] = "MEDTEST24-ONE01"
po["A2"] = "WTS001OPR601"        # ambiguous: two hosts, one serial
po["B2"] = "MEDTEST24-AMB01"
po["A3"] = "WTS001OPR602"
po["B3"] = "MEDTEST24-AMB01"
wb.save(alejandro)

twb = Workbook()
dep = twb.active
dep.title = "Deployments"
dep.append(["Device Type", "Cybernet Hostname", "Cybernet Serial", "Cybernet MAC", "Neuron S/N", "Deployed"])
dep.append(["Cybernet-Neuron", "WTS001OPR401", "MEDTEST24-TRK01", "000D050AA401", "NEU-TRK01", "Yes"])
twb.save(tracker)

with open(identity_csv, "w", newline="", encoding="utf-8") as fh:
    fh.write("Timestamp,Target,ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,TransportUsed,IdentityStatus,Notes\n")
    fh.write("2026-06-25T00:00:00Z,WTS001OPR501,10.0.0.5,Reachable,WTS001OPR501,WTS001OPR501,MEDTEST24-ONE01,000D050AA501,WMI,IdentityCollected,synthetic\n")

with open(preflight_csv, "w", newline="", encoding="utf-8") as fh:
    fh.write("Target,ResolvedAddress,PingStatus,Port,PortStatus,Timestamp\n")
    fh.write("WTS001OPR501,10.0.0.5,Reachable,445,Open,2026-06-25T00:00:00Z\n")
PY

# AD live-serial export evidence uses the exporter's real columns
# (ADHostname/DNSHostName/ADSerial). Row 1 resolves a host only from an FQDN
# DNSHostName; row 2 matches purely on ADSerial.
cat > "$AD_CSV" <<'CSV'
ADHostname,DNSHostName,ADSerial,ADMAC,ADEnabled,Notes
,WTS001OPR501.med.example.com,,,True,synthetic-ad-host
,,MEDTEST24-AMB01,,True,synthetic-ad-serial
CSV

json_field() {
  local path="$1" field="$2"
  "${PYTHON_CMD[@]}" - "$path" "$field" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data[sys.argv[2]])
PY
}

# --- Case A: no optional evidence (baseline serial-first denominator) ---
A_PREFIX="$TMP_DIR/a/cybernet"
bash "$DIFF_RUNNER" --alejandro "$ALEJANDRO" --tracker "$TRACKER" --output-prefix "$A_PREFIX" --device-type Cybernet >/dev/null
A_JSON="${A_PREFIX}_progress_summary.json"
A_CSV="${A_PREFIX}_progress_summary.csv"
[[ -f "$A_JSON" ]] || fail "missing progress JSON summary"
[[ -f "$A_CSV" ]] || fail "missing progress CSV summary"

# 1. denominator is unique Alejandro serial count (4 serials despite 5 hostname rows)
[[ "$(json_field "$A_JSON" TotalSerialTargets)" == "4" ]] || fail "TotalSerialTargets must equal unique Alejandro serials (4)"
[[ "$(json_field "$A_JSON" PopulationAuthority)" == "alejandro_serials" ]] || fail "PopulationAuthority must be alejandro_serials"

# 2 + 3 + 4. host-resolved / serial-only / ambiguous bucket counts
[[ "$(json_field "$A_JSON" HostResolvedSerials)" == "1" ]] || fail "exactly-one-host serial must count as host-resolved"
[[ "$(json_field "$A_JSON" SerialOnlyReviewRequired)" == "2" ]] || fail "zero-host serials must count as serial-only review-required"
[[ "$(json_field "$A_JSON" AmbiguousHostnameSerials)" == "1" ]] || fail "multi-host serial must count as ambiguous"

# 5. percent complete derived from serial targets (1 tracked / 4 total = 25.0), not hostname rows
[[ "$(json_field "$A_JSON" SurveyedSerials)" == "1" ]] || fail "baseline surveyed must equal tracker overlap (1)"
[[ "$(json_field "$A_JSON" PercentComplete)" == "25.0" ]] || fail "PercentComplete must be serial-based 25.0"

# 6. remaining count visible in summary output
[[ "$(json_field "$A_JSON" RemainingSerials)" == "3" ]] || fail "RemainingSerials must be visible and equal 3"
grep -q 'RemainingSerials' "$A_CSV" || fail "RemainingSerials must appear in CSV summary header"

# untracked manifest keeps serial-first identifier discipline
A_UNTRACKED="${A_PREFIX}_alejandro_untracked.csv"
"${PYTHON_CMD[@]}" - "$A_UNTRACKED" <<'PY'
import csv, sys
rows = {r["Serial"]: r for r in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8"))}
one = rows.get("MEDTEST24-ONE01") or {}
if one.get("IdentifierType") != "HostName" or not one.get("HostName"):
    raise SystemExit("exactly-one-host serial must be probe-ready HostName in untracked manifest")
so = rows.get("MEDTEST24-SO01") or {}
if so.get("IdentifierType") != "Serial" or so.get("HostName"):
    raise SystemExit("zero-host serial must stay Serial-keyed (review-required)")
amb = rows.get("MEDTEST24-AMB01") or {}
if amb.get("IdentifierType") != "Serial" or amb.get("HostName"):
    raise SystemExit("multi-host serial must stay Serial-keyed (no arbitrary host pick)")
if "ambiguous_hostnames" not in amb.get("Source", ""):
    raise SystemExit("ambiguous serial must surface review candidates in Source")
PY
pass "serial-first denominator and bucket classification (Total=4, host/serial-only/ambiguous)"

# 7. progress output is self-contained: console line carries percent + bar + remaining
CONSOLE_OUT="$(bash "$DIFF_RUNNER" --alejandro "$ALEJANDRO" --tracker "$TRACKER" --output-prefix "$TMP_DIR/c/cybernet" --device-type Cybernet)"
echo "$CONSOLE_OUT" | grep -q '%' || fail "console output must show a percentage"
echo "$CONSOLE_OUT" | grep -q '\[#' || fail "console output must show a progress bar"
echo "$CONSOLE_OUT" | grep -qi 'remaining' || fail "console output must show remaining serials without reading logs"

# --no-progress suppresses the bar line but still writes summary files
NP_OUT="$(bash "$DIFF_RUNNER" --alejandro "$ALEJANDRO" --tracker "$TRACKER" --output-prefix "$TMP_DIR/np/cybernet" --device-type Cybernet --no-progress)"
echo "$NP_OUT" | grep -q '\[#' && fail "--no-progress must suppress the progress bar line"
[[ -f "$TMP_DIR/np/cybernet_progress_summary.json" ]] || fail "--no-progress must still write JSON summary"
pass "tech-visible console progress (percent + bar + remaining) and --no-progress toggle"

# --- Case B: identity evidence expands SurveyedSerials for an untracked serial ---
B_PREFIX="$TMP_DIR/b/cybernet"
bash "$DIFF_RUNNER" --alejandro "$ALEJANDRO" --tracker "$TRACKER" --output-prefix "$B_PREFIX" \
  --device-type Cybernet --identity-csv "$IDENTITY_CSV" >/dev/null
B_JSON="${B_PREFIX}_progress_summary.json"
[[ "$(json_field "$B_JSON" SurveyedSerials)" == "2" ]] || fail "IdentityCollected must expand surveyed to 2"
[[ "$(json_field "$B_JSON" PercentComplete)" == "50.0" ]] || fail "identity-confirmed serial must lift percent to 50.0"
[[ "$(json_field "$B_JSON" NeedsPrivilegedIdentity)" == "0" ]] || fail "identity-confirmed reachable serial must not need privileged identity"
pass "identity evidence expands surveyed serials (serial-first, not hostname-first)"

# --- Case C: ping reachability is a candidate signal, never serial proof ---
C_PREFIX="$TMP_DIR/d/cybernet"
bash "$DIFF_RUNNER" --alejandro "$ALEJANDRO" --tracker "$TRACKER" --output-prefix "$C_PREFIX" \
  --device-type Cybernet --preflight-csv "$PREFLIGHT_CSV" >/dev/null
C_JSON="${C_PREFIX}_progress_summary.json"
[[ "$(json_field "$C_JSON" PingReachableCandidates)" == "1" ]] || fail "reachable host must count as ping candidate"
[[ "$(json_field "$C_JSON" NeedsPrivilegedIdentity)" == "1" ]] || fail "reachable-but-unconfirmed serial must need privileged identity"
[[ "$(json_field "$C_JSON" SurveyedSerials)" == "1" ]] || fail "ping reachability alone must not mark a serial surveyed"
[[ "$(json_field "$C_JSON" PercentComplete)" == "25.0" ]] || fail "ping-only evidence must not raise percent complete"
pass "ping reachability stays candidate-only (not serial proof)"

# --- Case D: AD live-serial export feeds ADCandidateSerials (exporter columns) ---
D_PREFIX="$TMP_DIR/e/cybernet"
bash "$DIFF_RUNNER" --alejandro "$ALEJANDRO" --tracker "$TRACKER" --output-prefix "$D_PREFIX" \
  --device-type Cybernet --ad-serial-csv "$AD_CSV" >/dev/null
D_JSON="${D_PREFIX}_progress_summary.json"
# ADHostname/DNSHostName/ADSerial aliases must be read (host from FQDN + serial)
[[ "$(json_field "$D_JSON" ADCandidateSerials)" == "2" ]] || fail "AD evidence (ADHostname/DNSHostName/ADSerial) must yield 2 AD candidate serials"
# AD evidence is candidate-only and must never confirm a serial as surveyed
[[ "$(json_field "$D_JSON" SurveyedSerials)" == "1" ]] || fail "AD candidates must not mark a serial surveyed"
[[ "$(json_field "$D_JSON" PercentComplete)" == "25.0" ]] || fail "AD candidate evidence must not raise percent complete"
pass "AD live-serial export populates AD candidates (exporter schema, candidate-only)"

# 8. generated operational progress output is gitignored under survey/output/
OUT_PREFIX="survey/output/progress_contract_cybernet"
bash "$DIFF_RUNNER" --alejandro "$ALEJANDRO" --tracker "$TRACKER" --output-prefix "$OUT_PREFIX" --device-type Cybernet >/dev/null
PROGRESS_JSON="${OUT_PREFIX}_progress_summary.json"
PROGRESS_CSV="${OUT_PREFIX}_progress_summary.csv"
git check-ignore -v "$PROGRESS_JSON" >/dev/null || { rm -f "${OUT_PREFIX}"_*; fail "generated progress JSON must be gitignored"; }
git check-ignore -v "$PROGRESS_CSV" >/dev/null || { rm -f "${OUT_PREFIX}"_*; fail "generated progress CSV must be gitignored"; }
rm -f "${OUT_PREFIX}"_*
pass "generated progress summaries are gitignored operational output"

printf 'Cybernet serial-first progress contracts passed.\n'
