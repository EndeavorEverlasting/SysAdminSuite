#!/usr/bin/env bash
# CDN-safe naabu pipeline — approved targets only, silent output, local artifacts.
# Low-noise survey doctrine: AD-derived targets first, -silent/-ec defaults, JSON for
# parsers, no target-side writes. See docs/LOW_NOISE_SURVEY_DOCTRINE.md. Runtime profiles
# live in Config/cybernet-naabu-profiles.json (doctrine contract: survey/naabu_profiles.json).
set -euo pipefail

VERSION="0.1.1"
SITE=""
PROFILE="keyports_cybernet_json"
LIST=""
HOST=""
OUT=""
PROFILE_JSON=""
PIPE_FOLLOWUP=0
ALLOW_FULL_PORTS=0
ALLOW_PUBLIC=0
PROFILE_JUSTIFIED=0
APPROVED_SUBNET_SCOPE=0
DRY_RUN=0
VERBOSE=0
RATE=""
PLANNED_FILE=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_JSON="${REPO_ROOT}/Config/cybernet-naabu-profiles.json"
FOLLOWUP_SCRIPT="${SCRIPT_DIR}/sas-cybernet-packet-followup.sh"
ENSURE_SCRIPT="${SCRIPT_DIR}/sas-ensure-naabu.sh"
TARGET_INTAKE_HELPER="${SCRIPT_DIR}/lib/sas-target-intake.sh"
[[ -f "$TARGET_INTAKE_HELPER" ]] || { echo "[naabu-pipeline] ERROR: Missing target intake helper: $TARGET_INTAKE_HELPER" >&2; exit 1; }
# shellcheck source=survey/lib/sas-target-intake.sh
source "$TARGET_INTAKE_HELPER"

usage() {
  cat <<'USAGE'
SysAdminSuite Naabu CDN-Safe Pipeline

Authorized internal asset discovery only. Read-only. Local output only.
Naabu always runs with -silent. CDN/cloud targets use -ec (exclude CDN).

Usage:
  bash survey/sas-run-naabu-pipeline.sh --site SITE [options]

Required:
  --site SITE              Site label

Target input (one required unless --dry-run with --host):
  --list PATH              Approved target file from targets/local, logs/targets, or normalized survey/input
  --host URL               Hostname/URL for -sa multi-A scan (hostname_all_ips profile)

Options:
  --profile NAME           Profile from Config/cybernet-naabu-profiles.json. Default: keyports_cybernet_json
  --out PATH               Output file (txt or json per profile; generated roots only)
  --pipe-followup          Pipe naabu -silent stdout into sas-cybernet-packet-followup.sh
  --allow-full-ports       Permit allports_low_noise_json profile (-p - -ec)
  --profile-justified      Acknowledge justification for justification-required profiles (UDP, all-ports)
  --approved-subnet-scope  Acknowledge approved subnet scope for host-discovery profiles
  --allow-public           Permit public IPs in target list
  --rate N                 Optional naabu -rate value
  --dry-run                Write planned command only; no packets
  --planned-file PATH      Append planned command to file (generated roots only)
  --verbose                Log resolved argv
  -h, --help               Show help

Profiles (doctrine: survey/naabu_profiles.json):
  keyports_cybernet_json (default), keyports_cybernet_pipe, web_reachability_only_json,
  web_reachability_only, allports_low_noise_json, udp_dns_snmp_json,
  host_discovery_web_syn_txt, load_balanced_hostname_all_ips_json

Backward-compatible aliases: keyports_cdn, keyports_cdn_json, windows_selected,
  host_discovery_tcp80, udp_infrastructure, hostname_all_ips, full_ports_cdn_guarded

Generated output may contain operational network details. Do not commit it.
USAGE
}

log() { printf '[naabu-pipeline] %s\n' "$*" >&2; }
fail() { printf '[naabu-pipeline] ERROR: %s\n' "$*" >&2; exit 1; }
vlog() { [[ "$VERBOSE" -eq 1 ]] && log "$@"; return 0; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required"
}

safe_site() {
  SITE="$(printf '%s' "$SITE" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')"
  [[ -n "$SITE" ]] || fail "--site is required"
}

validate_output_paths() {
  if [[ -n "$OUT" ]]; then
    sas_target_require_output_path "$OUT" "Naabu output file" "$REPO_ROOT" || exit 1
  fi
  if [[ -n "$PLANNED_FILE" ]]; then
    sas_target_require_output_path "$PLANNED_FILE" "Naabu planned command file" "$REPO_ROOT" || exit 1
  fi
}

validate_target_file() {
  local file="$1" line n=0
  sas_target_require_input_file "$file" "Naabu target list" 1 "$REPO_ROOT" || exit 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    if [[ "$line" == *"/"* ]]; then
      fail "Target list must not contain CIDR lines: $line"
    fi
    n=$((n + 1))
  done < "$file"
  [[ "$n" -gt 0 ]] || fail "Target list is empty: $file"
  echo "$n"
}

preflight_public_ips() {
  local file="$1" allow_public="$2"
  local py
  py="$(find_python)"
  $py - "$file" "$allow_public" <<'PY'
import ipaddress, sys
path, allow_public = sys.argv[1], int(sys.argv[2])
public = []
with open(path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.split("#", 1)[0].strip()
        if not line or "/" in line:
            continue
        try:
            ip = ipaddress.ip_address(line)
        except ValueError:
            continue
        if not (ip.is_private or ip.is_loopback or ip.is_link_local):
            public.append(str(ip))
if public and not allow_public:
    print("public IPs in target list require --allow-public: " + ", ".join(public[:5]), file=sys.stderr)
    sys.exit(1)
PY
}

build_naabu_argv() {
  local py tmp
  py="$(find_python)"
  tmp="$(mktemp)"
  $py - "$PROFILE_JSON" "$PROFILE" "$LIST" "$HOST" "$OUT" "$ALLOW_FULL_PORTS" "$PROFILE_JUSTIFIED" "$APPROVED_SUBNET_SCOPE" "$RATE" <<'PY' > "$tmp"
import json, os, sys

profile_path, profile_id, list_path, host, out_path, allow_full, justified, subnet_scope, rate = sys.argv[1:10]
allow_full = allow_full == "1"
justified = justified == "1"
subnet_scope = subnet_scope == "1"
with open(profile_path, encoding="utf-8") as fh:
    cfg = json.load(fh)
posture_path = os.path.join(os.path.dirname(profile_path), "operational-posture.json")
max_rate = 3000
if os.path.exists(posture_path):
    with open(posture_path, encoding="utf-8") as fh:
        posture = json.load(fh)
    max_rate = int(posture.get("defaults", {}).get("naabuMaxRate", max_rate))
profile_id = cfg.get("profileAliases", {}).get(profile_id, profile_id)
profiles = cfg.get("profiles", {})
if profile_id not in profiles:
    print(f"unknown profile: {profile_id}", file=sys.stderr)
    sys.exit(2)
p = profiles[profile_id]

if p.get("allowFullPorts") and not allow_full:
    print(f"profile {profile_id} requires --allow-full-ports", file=sys.stderr)
    sys.exit(3)

# Justification-required profiles (UDP, all-ports). --allow-full-ports counts as the
# explicit justification for the all-ports profile.
if p.get("requiresJustification") and not (justified or (p.get("allowFullPorts") and allow_full)):
    print(f"profile {profile_id} requires --profile-justified (justification required)", file=sys.stderr)
    sys.exit(6)

# Host-discovery against a subnet requires an explicit approved-scope acknowledgement.
if p.get("requiresApprovedSubnetScope") and not subnet_scope:
    print(f"profile {profile_id} requires --approved-subnet-scope (approved subnet scope required)", file=sys.stderr)
    sys.exit(7)

argv = []
if p.get("requiresHost"):
    if not host:
        print(f"profile {profile_id} requires --host", file=sys.stderr)
        sys.exit(4)
    argv += ["-host", host]
elif list_path:
    argv += ["-list", list_path]
else:
    print("either --list or --host is required", file=sys.stderr)
    sys.exit(5)

if p.get("hostDiscoveryOnly"):
    argv += ["-sn"]
    if p.get("probeIcmpEcho"):
        argv += ["-pe"]
    for port in p.get("probeTcpSynPorts") or []:
        argv += ["-ps", str(port)]
elif p.get("ports"):
    argv += ["-p", str(p["ports"])]

if p.get("excludeCdn"):
    argv += ["-ec"]
if p.get("scanAllIps"):
    argv += ["-sa"]
if p.get("udpProbes"):
    argv += ["-uP"]
if p.get("silent", True):
    argv += ["-silent"]
if p.get("disableUpdateCheck", True):
    argv += ["-duc"]
if rate:
    if not str(rate).isdigit() or int(rate) <= 0:
        print("--rate must be a positive integer", file=sys.stderr)
        sys.exit(8)
    if int(rate) > max_rate:
        print(f"--rate must be <= {max_rate} per operational posture", file=sys.stderr)
        sys.exit(9)
    argv += ["-rate", str(rate)]

fmt = p.get("outputFormat", "txt")
if out_path:
    if fmt == "json":
        argv += ["-json", "-o", out_path]
    else:
        argv += ["-o", out_path]

for part in argv:
    print(part)
PY
  mapfile -t NAABU_ARGS < "$tmp"
  local i
  for i in "${!NAABU_ARGS[@]}"; do
    NAABU_ARGS[$i]="${NAABU_ARGS[$i]//$'\r'/}"
  done
  rm -f "$tmp"
}

run_pipeline() {
  local naabu_bin followup_out count
  validate_output_paths
  naabu_bin="$(bash "$ENSURE_SCRIPT" ${DRY_RUN:+--dry-run})"
  vlog "naabu binary: $naabu_bin"

  if [[ -n "$LIST" ]]; then
    count="$(validate_target_file "$LIST")"
    preflight_public_ips "$LIST" "$ALLOW_PUBLIC"
    vlog "target count: $count"
  fi

  build_naabu_argv

  local cmd_display="$naabu_bin ${NAABU_ARGS[*]}"
  if [[ "$PIPE_FOLLOWUP" -eq 1 ]]; then
    followup_out="${OUT%.txt}_followup.jsonl"
    [[ "$OUT" == *.json ]] && followup_out="${OUT%.json}_followup.jsonl"
    [[ -z "$OUT" ]] && followup_out="logs/nmap/${SITE}_followup.jsonl"
    cmd_display="${cmd_display} | bash ${FOLLOWUP_SCRIPT} --site ${SITE} --stdin --cybernet-detect > ${followup_out}"
  fi

  if [[ -n "$PLANNED_FILE" ]]; then
    printf '%s\n' "$cmd_display" >> "$PLANNED_FILE"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: $cmd_display"
    return 0
  fi

  log "Running: $naabu_bin ${NAABU_ARGS[*]}"
  if [[ "$PIPE_FOLLOWUP" -eq 1 ]]; then
    mkdir -p "$(dirname "$followup_out")"
    "$naabu_bin" "${NAABU_ARGS[@]}" | bash "$FOLLOWUP_SCRIPT" --site "$SITE" --stdin --cybernet-detect > "$followup_out"
    log "Followup JSONL: $followup_out"
  else
    "$naabu_bin" "${NAABU_ARGS[@]}"
  fi
  log "naabu pipeline complete"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?}"; shift 2 ;;
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --list) LIST="${2:?}"; shift 2 ;;
    --host) HOST="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --pipe-followup) PIPE_FOLLOWUP=1; shift ;;
    --allow-full-ports) ALLOW_FULL_PORTS=1; shift ;;
    --profile-justified) PROFILE_JUSTIFIED=1; shift ;;
    --approved-subnet-scope) APPROVED_SUBNET_SCOPE=1; shift ;;
    --allow-public) ALLOW_PUBLIC=1; shift ;;
    --rate) RATE="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --planned-file) PLANNED_FILE="${2:?}"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$SITE" ]] || fail "--site is required"
safe_site
[[ -f "$PROFILE_JSON" ]] || fail "Missing $PROFILE_JSON"

resolve_profile_alias() {
  local py resolved
  py="$(find_python)"
  resolved="$($py - "$PROFILE_JSON" "$PROFILE" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    cfg = json.load(fh)
print(cfg.get("profileAliases", {}).get(sys.argv[2], sys.argv[2]))
PY
)"
  [[ -n "$resolved" ]] && PROFILE="$resolved"
}
resolve_profile_alias

if [[ "$PROFILE" == "allports_low_noise_json" && "$ALLOW_FULL_PORTS" -eq 0 ]]; then
  fail "Profile allports_low_noise_json requires --allow-full-ports"
fi

run_pipeline
