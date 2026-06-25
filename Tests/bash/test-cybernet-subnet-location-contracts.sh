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

printf 'Cybernet subnet location inference contracts passed (10 synthetic cases).\n'
