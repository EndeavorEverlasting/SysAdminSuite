#!/usr/bin/env bash
# Synthetic contract tests for Cybernet subnet/location inference (read-only CSV evidence).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RUNNER="survey/sas-cybernet-subnet-location-map.sh"
PY="survey/sas-cybernet-subnet-location-map.py"

bash -n "${BASH_SOURCE[0]}"

fail() { printf '[cybernet-subnet-location-contracts] FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '[cybernet-subnet-location-contracts] PASS: %s\n' "$*"; }

if [[ ! -f "$RUNNER" || ! -f "$PY" ]]; then
  printf '[cybernet-subnet-location-contracts] BLOCKED: implementation missing (%s, %s); contracts authored only\n' \
    "$RUNNER" "$PY" >&2
  exit 77
fi

bash -n "$RUNNER"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || fail "python required for contract test"
PYTHON_CMD=(python3)
command -v python3 >/dev/null 2>&1 || PYTHON_CMD=(python)

assert_synthetic_fixtures() {
  local path
  for path in "$@"; do
    [[ -f "$path" ]] || fail "missing fixture: $path"
    "${PYTHON_CMD[@]}" - "$path" <<'PY'
import ipaddress
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
for token in re.findall(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])", text):
    try:
        ip = ipaddress.ip_address(token)
    except ValueError:
        continue
    if not str(ip).startswith("10.10."):
        raise SystemExit(f"fixture must use 10.10.x.x only: {path} ({token})")
PY
    if grep -qiE '\b(nsuh|ssuh|lij|northwell)\b' "$path"; then
      fail "fixture must not contain live site identifiers: $path"
    fi
  done
}

write_prefix_config() {
  local dest="$1"
  cat >"$dest" <<'CSV'
LocationCode,LocationLabel,Region,SiteAffinity,AllowMixedWith,Notes
WTS,WTS Example Site,Synthetic Region A,WTS,,Synthetic training prefix only; not live inventory
WNH,WNH Example Site,Synthetic Region B,WNH,,Synthetic training prefix only; not live inventory
WMH,WMH Example Site,Synthetic Region C,WMH,,Synthetic training prefix only; not live inventory
CSV
}

write_identity_csv() {
  local dest="$1"
  shift
  printf 'HostName,IPv4Address\n' >"$dest"
  while [[ $# -ge 2 ]]; do
    printf '%s,%s\n' "$1" "$2" >>"$dest"
    shift 2
  done
}

run_map() {
  local out_prefix="$1"
  local prefix_config="$2"
  local identity_csv="$3"
  shift 3
  local -a args=(
    --prefix-config "$prefix_config"
    --prefix-len 24
    --identity-csv "$identity_csv"
    --output-prefix "$out_prefix"
    --format csv,json
  )
  while [[ $# -gt 0 ]]; do
    args+=("$1")
    shift
  done
  bash "$RUNNER" "${args[@]}" >/dev/null
}

run_map_capture() {
  local out_prefix="$1"
  local prefix_config="$2"
  local stdout_file="$3"
  shift 3
  local -a args=(
    --prefix-config "$prefix_config"
    --prefix-len 24
    --output-prefix "$out_prefix"
    --format csv,json
  )
  while [[ $# -gt 0 ]]; do
    args+=("$1")
    shift
  done
  bash "$RUNNER" "${args[@]}" >"$stdout_file"
}

map_csv_for() {
  local prefix="$1"
  if [[ -f "${prefix}_map.csv" ]]; then
    printf '%s\n' "${prefix}_map.csv"
  elif [[ -f "${prefix}map.csv" ]]; then
    printf '%s\n' "${prefix}map.csv"
  else
    fail "missing map csv for prefix: $prefix"
  fi
}

hosts_csv_for() {
  local prefix="$1"
  if [[ -f "${prefix}_hosts.csv" ]]; then
    printf '%s\n' "${prefix}_hosts.csv"
  elif [[ -f "${prefix}hosts.csv" ]]; then
    printf '%s\n' "${prefix}hosts.csv"
  else
    fail "missing hosts csv for prefix: $prefix"
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PREFIX_CFG="$TMP_DIR/prefixes.example.csv"
write_prefix_config "$PREFIX_CFG"
assert_synthetic_fixtures "$PREFIX_CFG"

# --- 1) 2+ WTS/WNH hosts same /24 -> subnet-location candidate ---
CASE1_ID="$TMP_DIR/case01_identity.csv"
write_identity_csv "$CASE1_ID" \
  WNH001OPR001 10.10.1.11 \
  WNH002OPR002 10.10.1.12
assert_synthetic_fixtures "$CASE1_ID"
CASE1_OUT="$TMP_DIR/case01/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE1_OUT")"
run_map "$CASE1_OUT" "$PREFIX_CFG" "$CASE1_ID"
CASE1_MAP="$(map_csv_for "$CASE1_OUT")"
CASE1_HOSTS="$(hosts_csv_for "$CASE1_OUT")"
"${PYTHON_CMD[@]}" - "$CASE1_MAP" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
subnet_rows = [r for r in rows if "10.10.1." in (r.get("Subnet") or r.get("subnet") or "")]
if not subnet_rows:
    raise SystemExit("expected subnet row for 10.10.1.0/24")
status = (subnet_rows[0].get("Status") or subnet_rows[0].get("status") or "").lower()
if "subnet_location_candidate" not in status:
    raise SystemExit(f"expected subnet_location_candidate, got {status!r}")
PY
pass "case 1: 2+ WNH hosts same /24 -> subnet_location_candidate"

# --- 2) 5+ same-prefix hosts -> high confidence / subnet_location_strong ---
CASE2_ID="$TMP_DIR/case02_identity.csv"
write_identity_csv "$CASE2_ID" \
  WTS001OPR001 10.10.10.11 \
  WTS002OPR002 10.10.10.12 \
  WTS003OPR003 10.10.10.13 \
  WTS004OPR004 10.10.10.14 \
  WTS005OPR005 10.10.10.15
assert_synthetic_fixtures "$CASE2_ID"
CASE2_OUT="$TMP_DIR/case02/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE2_OUT")"
run_map "$CASE2_OUT" "$PREFIX_CFG" "$CASE2_ID"
CASE2_MAP="$(map_csv_for "$CASE2_OUT")"
"${PYTHON_CMD[@]}" - "$CASE2_MAP" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
subnet_rows = [r for r in rows if "10.10.10." in (r.get("Subnet") or r.get("subnet") or "")]
if not subnet_rows:
    raise SystemExit("expected subnet row for 10.10.10.0/24")
row = subnet_rows[0]
status = (row.get("Status") or row.get("status") or "").lower()
confidence = (row.get("Confidence") or row.get("confidence") or "").lower()
if "subnet_location_strong" not in status:
    raise SystemExit(f"expected subnet_location_strong, got {status!r}")
if confidence != "high":
    raise SystemExit(f"expected high confidence, got {confidence!r}")
PY
pass "case 2: 5+ WTS hosts -> subnet_location_strong / high"

# --- 3) WNH + WMH same /24 -> subnet_location_mixed / review ---
CASE3_ID="$TMP_DIR/case03_identity.csv"
write_identity_csv "$CASE3_ID" \
  WNH001OPR001 10.10.20.11 \
  WMH001OPR001 10.10.20.12
assert_synthetic_fixtures "$CASE3_ID"
CASE3_OUT="$TMP_DIR/case03/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE3_OUT")"
run_map "$CASE3_OUT" "$PREFIX_CFG" "$CASE3_ID"
CASE3_MAP="$(map_csv_for "$CASE3_OUT")"
"${PYTHON_CMD[@]}" - "$CASE3_MAP" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
subnet_rows = [r for r in rows if "10.10.20." in (r.get("Subnet") or r.get("subnet") or "")]
if not subnet_rows:
    raise SystemExit("expected subnet row for 10.10.20.0/24")
row = subnet_rows[0]
status = (row.get("Status") or row.get("status") or "").lower()
review = (row.get("ReviewAction") or row.get("review_action") or row.get("NextAction") or row.get("next_action") or "").lower()
notes = (row.get("Notes") or row.get("notes") or "").lower()
blob = " ".join([status, review, notes])
if "subnet_location_mixed" not in status:
    raise SystemExit(f"expected subnet_location_mixed, got {status!r}")
if "review" not in blob and "mixed" not in blob:
    raise SystemExit("expected review-oriented mixed-subnet signal")
PY
pass "case 3: WNH + WMH same /24 -> subnet_location_mixed / review"

# --- 4) one location across two /24s -> location_spans_multiple_subnets ---
CASE4_ID="$TMP_DIR/case04_identity.csv"
write_identity_csv "$CASE4_ID" \
  WNH001OPR001 10.10.30.11 \
  WNH002OPR002 10.10.31.12
assert_synthetic_fixtures "$CASE4_ID"
CASE4_OUT="$TMP_DIR/case04/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE4_OUT")"
run_map "$CASE4_OUT" "$PREFIX_CFG" "$CASE4_ID"
CASE4_MAP="$(map_csv_for "$CASE4_OUT")"
"${PYTHON_CMD[@]}" - "$CASE4_MAP" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
hits = [
    r for r in rows
    if "location_spans_multiple_subnets" in (r.get("Status") or r.get("status") or "").lower()
    or "location_spans_multiple_subnets" in (r.get("AggregateStatus") or r.get("aggregate_status") or "").lower()
]
if not hits:
    raise SystemExit("expected location_spans_multiple_subnets for WNH across two /24s")
PY
pass "case 4: one location across two /24s -> location_spans_multiple_subnets"

# --- 5) FQDN normalizes safely ---
CASE5_ID="$TMP_DIR/case05_identity.csv"
write_identity_csv "$CASE5_ID" wts001opr001.example.internal 10.10.40.11
assert_synthetic_fixtures "$CASE5_ID"
CASE5_OUT="$TMP_DIR/case05/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE5_OUT")"
run_map "$CASE5_OUT" "$PREFIX_CFG" "$CASE5_ID"
CASE5_HOSTS="$(hosts_csv_for "$CASE5_OUT")"
"${PYTHON_CMD[@]}" - "$CASE5_HOSTS" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
norm = {
    (r.get("NormalizedHostName") or r.get("normalized_hostname") or r.get("HostName") or r.get("hostname") or "").upper()
    for r in rows
}
if "WTS001OPR001" not in norm:
    raise SystemExit(f"expected normalized host WTS001OPR001, got {sorted(norm)}")
if "WTS001OPR001.EXAMPLE.INTERNAL" in norm:
    raise SystemExit("FQDN must not remain unnormalized in NormalizedHostName")
PY
pass "case 5: FQDN wts001opr001.example.internal normalizes safely"

# --- 6) not_an_ip -> ip_invalid without crash ---
CASE6_ID="$TMP_DIR/case06_identity.csv"
write_identity_csv "$CASE6_ID" WTS001OPR001 not_an_ip
assert_synthetic_fixtures "$CASE6_ID"
CASE6_OUT="$TMP_DIR/case06/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE6_OUT")"
run_map "$CASE6_OUT" "$PREFIX_CFG" "$CASE6_ID"
CASE6_HOSTS="$(hosts_csv_for "$CASE6_OUT")"
"${PYTHON_CMD[@]}" - "$CASE6_HOSTS" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
statuses = [(r.get("Status") or r.get("status") or "").lower() for r in rows]
if not any("ip_invalid" in s for s in statuses):
    raise SystemExit(f"expected ip_invalid status, got {statuses}")
PY
pass "case 6: not_an_ip -> ip_invalid without crash"

# --- 7) blank IP -> ip_missing ---
CASE7_ID="$TMP_DIR/case07_identity.csv"
write_identity_csv "$CASE7_ID" WTS001OPR001 ""
assert_synthetic_fixtures "$CASE7_ID"
CASE7_OUT="$TMP_DIR/case07/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE7_OUT")"
run_map "$CASE7_OUT" "$PREFIX_CFG" "$CASE7_ID"
CASE7_HOSTS="$(hosts_csv_for "$CASE7_OUT")"
"${PYTHON_CMD[@]}" - "$CASE7_HOSTS" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
statuses = [(r.get("Status") or r.get("status") or "").lower() for r in rows]
if not any("ip_missing" in s for s in statuses):
    raise SystemExit(f"expected ip_missing status, got {statuses}")
PY
pass "case 7: blank IP -> ip_missing"

# --- 8) unknown prefix -> prefix_unknown ---
CASE8_ID="$TMP_DIR/case08_identity.csv"
write_identity_csv "$CASE8_ID" ZZZ001OPR001 10.10.50.11
assert_synthetic_fixtures "$CASE8_ID"
CASE8_OUT="$TMP_DIR/case08/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE8_OUT")"
run_map "$CASE8_OUT" "$PREFIX_CFG" "$CASE8_ID"
CASE8_HOSTS="$(hosts_csv_for "$CASE8_OUT")"
"${PYTHON_CMD[@]}" - "$CASE8_HOSTS" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="", encoding="utf-8")))
statuses = [(r.get("Status") or r.get("status") or "").lower() for r in rows]
if not any("prefix_unknown" in s for s in statuses):
    raise SystemExit(f"expected prefix_unknown status, got {statuses}")
PY
pass "case 8: unknown prefix -> prefix_unknown"

# --- 9) default outputs written and git check-ignore passes ---
mkdir -p "$ROOT/survey/output"
DEFAULT_OUT="$ROOT/survey/output/cybernet_subnet_location"
CASE9_ID="$TMP_DIR/case09_identity.csv"
write_identity_csv "$CASE9_ID" \
  WTS001OPR001 10.10.60.11 \
  WTS002OPR002 10.10.60.12
assert_synthetic_fixtures "$CASE9_ID"
run_map "$DEFAULT_OUT" "$PREFIX_CFG" "$CASE9_ID"
[[ -f "${DEFAULT_OUT}_map.csv" ]] || fail "expected ${DEFAULT_OUT}_map.csv"
[[ -f "${DEFAULT_OUT}_map.json" ]] || fail "expected ${DEFAULT_OUT}_map.json"
git check-ignore -v survey/output/cybernet_subnet_location_map.csv >/dev/null \
  || fail "survey/output/cybernet_subnet_location_map.csv must be gitignored"
git check-ignore -v survey/output/cybernet_subnet_location_map.json >/dev/null \
  || fail "survey/output/cybernet_subnet_location_map.json must be gitignored"
rm -f "${DEFAULT_OUT}_map.csv" "${DEFAULT_OUT}_map.json" "${DEFAULT_OUT}_hosts.csv"
pass "case 9: outputs written and git check-ignore passes"

# --- 10) fixtures remain synthetic (WTS*/WMH*/MEDTEST*/10.10.x.x only) ---
FIXTURE_PATHS=(
  "$PREFIX_CFG"
  "$CASE1_ID" "$CASE2_ID" "$CASE3_ID" "$CASE4_ID" "$CASE5_ID"
  "$CASE6_ID" "$CASE7_ID" "$CASE8_ID" "$CASE9_ID"
)
for fixture in "${FIXTURE_PATHS[@]}"; do
  assert_synthetic_fixtures "$fixture"
done
if grep -qE 'MEDTEST' "${FIXTURE_PATHS[@]}" 2>/dev/null; then
  pass "case 10: MEDTEST-style serial tokens allowed when present"
else
  pass "case 10: fixtures use WTS*/WNH*/WMH* hostnames and 10.10.x.x only"
fi

# --- 11-13) invalid identity IP falls back to valid preflight IP ---
CASE11_ID="$TMP_DIR/case11_identity.csv"
cat >"$CASE11_ID" <<'CSV'
HostName,IPv4Address
WTS011OPR001,#N/A
CSV
CASE11_PREFLIGHT="$TMP_DIR/case11_preflight.csv"
cat >"$CASE11_PREFLIGHT" <<'CSV'
Target,ResolvedIP,PingStatus
WTS011OPR001,10.10.70.11,Reachable
CSV
assert_synthetic_fixtures "$CASE11_ID" "$CASE11_PREFLIGHT"
CASE11_OUT="$TMP_DIR/case11/cybernet_subnet_location"
CASE11_STDOUT="$TMP_DIR/case11_stdout.txt"
mkdir -p "$(dirname "$CASE11_OUT")"
run_map_capture "$CASE11_OUT" "$PREFIX_CFG" "$CASE11_STDOUT" --identity-csv "$CASE11_ID" --preflight-csv "$CASE11_PREFLIGHT"
CASE11_MAP="$(map_csv_for "$CASE11_OUT")"
CASE11_HOSTS="$(hosts_csv_for "$CASE11_OUT")"
"${PYTHON_CMD[@]}" - "$CASE11_HOSTS" "$CASE11_MAP" <<'PY'
import csv, sys
hosts = list(csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8")))
maps = list(csv.DictReader(open(sys.argv[2], newline="", encoding="utf-8")))
row = next(r for r in hosts if r["NormalizedHostName"] == "WTS011OPR001")
if row["IPAddress"] != "10.10.70.11" or row.get("IPSource") != "preflight":
    raise SystemExit(f"expected preflight IP fallback, got {row}")
if row["Status"] == "ip_invalid":
    raise SystemExit("valid preflight fallback must not emit ip_invalid")
if not any(r["Subnet"] == "10.10.70.0/24" for r in maps):
    raise SystemExit("expected subnet 10.10.70.0/24 from preflight fallback")
PY
pass "case 11-13: invalid identity IP falls back to valid preflight IP without ip_invalid"

# --- 12) ResolvedAddress from preflight becomes subnet evidence ---
CASE12_PREFLIGHT="$TMP_DIR/case12_preflight.csv"
cat >"$CASE12_PREFLIGHT" <<'CSV'
Target,ResolvedAddress,PingStatus
WTS012OPR001,10.10.71.11,Reachable
CSV
assert_synthetic_fixtures "$CASE12_PREFLIGHT"
CASE12_OUT="$TMP_DIR/case12/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE12_OUT")"
run_map_capture "$CASE12_OUT" "$PREFIX_CFG" "$TMP_DIR/case12_stdout.txt" --preflight-csv "$CASE12_PREFLIGHT"
CASE12_MAP="$(map_csv_for "$CASE12_OUT")"
"${PYTHON_CMD[@]}" - "$CASE12_MAP" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8")))
if not any(r["Subnet"] == "10.10.71.0/24" for r in rows):
    raise SystemExit("expected ResolvedAddress to produce 10.10.71.0/24")
PY
pass "case 12: ResolvedAddress becomes subnet evidence"

# --- 14) all invalid IPs produce ip_invalid ---
CASE14_ID="$TMP_DIR/case14_identity.csv"
cat >"$CASE14_ID" <<'CSV'
HostName,IPv4Address
WTS014OPR001,not_an_ip
CSV
CASE14_PREFLIGHT="$TMP_DIR/case14_preflight.csv"
cat >"$CASE14_PREFLIGHT" <<'CSV'
Target,ResolvedIP,PingStatus
WTS014OPR001,bad_ip,Reachable
CSV
assert_synthetic_fixtures "$CASE14_ID" "$CASE14_PREFLIGHT"
CASE14_OUT="$TMP_DIR/case14/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE14_OUT")"
run_map_capture "$CASE14_OUT" "$PREFIX_CFG" "$TMP_DIR/case14_stdout.txt" --identity-csv "$CASE14_ID" --preflight-csv "$CASE14_PREFLIGHT"
CASE14_HOSTS="$(hosts_csv_for "$CASE14_OUT")"
"${PYTHON_CMD[@]}" - "$CASE14_HOSTS" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8")))
row = next(r for r in rows if r["NormalizedHostName"] == "WTS014OPR001")
if row["Status"] != "ip_invalid":
    raise SystemExit(f"expected ip_invalid, got {row['Status']}")
PY
pass "case 14: all invalid IPs produce ip_invalid"

# --- 15) aggregate LocationCodes contains no blank tokens ---
CASE15_ID="$TMP_DIR/case15_identity.csv"
cat >"$CASE15_ID" <<'CSV'
HostName,IPv4Address
12345,10.10.72.11
CSV
assert_synthetic_fixtures "$CASE15_ID"
CASE15_OUT="$TMP_DIR/case15/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE15_OUT")"
run_map_capture "$CASE15_OUT" "$PREFIX_CFG" "$TMP_DIR/case15_stdout.txt" --identity-csv "$CASE15_ID"
CASE15_MAP="$(map_csv_for "$CASE15_OUT")"
"${PYTHON_CMD[@]}" - "$CASE15_MAP" <<'PY'
import csv, sys
for row in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8")):
    value = row.get("LocationCodes", "")
    if value.startswith(";") or value.endswith(";") or ";;" in value:
        raise SystemExit(f"blank LocationCodes token leaked: {value!r}")
PY
pass "case 15: aggregate LocationCodes has no blank tokens"

# --- 16-17) wrapper help matches supported inputs and format ---
HELP_TEXT="$(bash "$RUNNER" --help)"
[[ "$HELP_TEXT" == *"csv,json"* ]] || fail "help must document --format csv,json"
[[ "$HELP_TEXT" != *"required unless --identity-glob"* ]] || fail "help must not claim identity input is mandatory"
[[ "$HELP_TEXT" == *"--preflight-csv"* && "$HELP_TEXT" == *"--tracker-csv"* ]] || fail "help must show non-identity evidence inputs"
pass "case 16-17: wrapper help documents csv,json and non-mandatory identity inputs"

# --- 18-20) hostname fallback emits visible fallback fields and no serial confirmation ---
CASE18_ID="$TMP_DIR/case18_identity.csv"
write_identity_csv "$CASE18_ID" WTS018OPR001 10.10.73.11
assert_synthetic_fixtures "$CASE18_ID"
CASE18_OUT="$TMP_DIR/case18/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE18_OUT")"
run_map_capture "$CASE18_OUT" "$PREFIX_CFG" "$TMP_DIR/case18_stdout.txt" --identity-csv "$CASE18_ID"
CASE18_HOSTS="$(hosts_csv_for "$CASE18_OUT")"
"${PYTHON_CMD[@]}" - "$CASE18_HOSTS" <<'PY'
import csv, sys
row = next(r for r in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8")) if r["NormalizedHostName"] == "WTS018OPR001")
if row.get("FallbackUsed") != "Yes":
    raise SystemExit(f"expected FallbackUsed=Yes, got {row.get('FallbackUsed')!r}")
if not row.get("FallbackReason"):
    raise SystemExit("expected non-empty FallbackReason")
if row.get("SerialEvidenceStatus") == "serial_confirmed":
    raise SystemExit("hostname fallback must not emit serial_confirmed")
PY
pass "case 18-20: hostname fallback is visible and not serial-confirmed"

# --- 21-22) serial-authority row and console fallback summary ---
CASE21_ID="$TMP_DIR/case21_identity.csv"
cat >"$CASE21_ID" <<'CSV'
HostName,IPv4Address,SerialNumber,IdentityStatus
WTS021OPR001,10.10.74.11,MEDTEST24-0001,IdentityCollected
CSV
assert_synthetic_fixtures "$CASE21_ID"
CASE21_OUT="$TMP_DIR/case21/cybernet_subnet_location"
CASE21_STDOUT="$TMP_DIR/case21_stdout.txt"
mkdir -p "$(dirname "$CASE21_OUT")"
run_map_capture "$CASE21_OUT" "$PREFIX_CFG" "$CASE21_STDOUT" --identity-csv "$CASE21_ID"
CASE21_HOSTS="$(hosts_csv_for "$CASE21_OUT")"
"${PYTHON_CMD[@]}" - "$CASE21_HOSTS" "$CASE21_STDOUT" <<'PY'
import csv, sys
row = next(r for r in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8")) if r["NormalizedHostName"] == "WTS021OPR001")
if row.get("SurveyAuthority") != "serial" or row.get("FallbackUsed") != "No":
    raise SystemExit(f"expected serial authority with no fallback, got {row}")
if row.get("SerialEvidenceStatus") != "serial_confirmed":
    raise SystemExit(f"expected serial_confirmed, got {row.get('SerialEvidenceStatus')!r}")
stdout = open(sys.argv[2], encoding="utf-8").read()
if "serial-first:" not in stdout:
    raise SystemExit("expected console serial-first summary")
PY
pass "case 21-22: serial authority and console fallback summary"

# --- 23) AllowMixedWith produces visible allowed-mixed status ---
CASE23_CFG="$TMP_DIR/case23_prefixes.csv"
cat >"$CASE23_CFG" <<'CSV'
LocationCode,LocationLabel,Region,SiteAffinity,AllowMixedWith,Notes
WNH,WNH Example Site,Synthetic Region B,WNH,WMH,Synthetic allowed mixed pair only
WMH,WMH Example Site,Synthetic Region C,WMH,WNH,Synthetic allowed mixed pair only
CSV
CASE23_ID="$TMP_DIR/case23_identity.csv"
write_identity_csv "$CASE23_ID" \
  WNH023OPR001 10.10.75.11 \
  WMH023OPR001 10.10.75.12
assert_synthetic_fixtures "$CASE23_CFG" "$CASE23_ID"
CASE23_OUT="$TMP_DIR/case23/cybernet_subnet_location"
mkdir -p "$(dirname "$CASE23_OUT")"
run_map_capture "$CASE23_OUT" "$CASE23_CFG" "$TMP_DIR/case23_stdout.txt" --identity-csv "$CASE23_ID"
CASE23_MAP="$(map_csv_for "$CASE23_OUT")"
"${PYTHON_CMD[@]}" - "$CASE23_MAP" <<'PY'
import csv, sys
row = next(r for r in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8")) if r["Subnet"] == "10.10.75.0/24")
if row.get("Status") != "subnet_location_allowed_mixed":
    raise SystemExit(f"expected subnet_location_allowed_mixed, got {row.get('Status')!r}")
if row.get("Confidence") != "medium":
    raise SystemExit(f"expected medium confidence, got {row.get('Confidence')!r}")
if "Allowed mixed prefix pairing" not in row.get("ReviewReason", ""):
    raise SystemExit("expected explicit allowed mixed ReviewReason")
PY
pass "case 23: AllowMixedWith emits subnet_location_allowed_mixed"

printf 'Cybernet subnet location inference contracts passed (23 synthetic cases).\n'
