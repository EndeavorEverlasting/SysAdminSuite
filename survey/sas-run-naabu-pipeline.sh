#!/usr/bin/env bash
# CDN-safe naabu pipeline — approved targets only, silent output, local artifacts.
set -euo pipefail

VERSION="0.1.0"
SITE=""
PROFILE="keyports_cdn"
LIST=""
HOST=""
OUT=""
PROFILE_JSON=""
PIPE_FOLLOWUP=0
ALLOW_FULL_PORTS=0
ALLOW_PUBLIC=0
DRY_RUN=0
VERBOSE=0
PLANNED_FILE=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_JSON="${REPO_ROOT}/Config/cybernet-naabu-profiles.json"
FOLLOWUP_SCRIPT="${SCRIPT_DIR}/sas-cybernet-packet-followup.sh"
ENSURE_SCRIPT="${SCRIPT_DIR}/sas-ensure-naabu.sh"

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
  --list PATH              Approved target file (one IP/hostname per line)
  --host URL               Hostname/URL for -sa multi-A scan (hostname_all_ips profile)

Options:
  --profile NAME           Profile from Config/cybernet-naabu-profiles.json. Default: keyports_cdn
  --out PATH               Output file (txt or json per profile)
  --pipe-followup          Pipe naabu -silent stdout into sas-cybernet-packet-followup.sh
  --allow-full-ports       Permit full_ports_cdn_guarded profile (-p - -ec)
  --allow-public           Permit public IPs in target list
  --dry-run                Write planned command only; no packets
  --planned-file PATH      Append planned command to file
  --verbose                Log resolved argv
  -h, --help               Show help

Profiles: keyports_cdn, keyports_cdn_json, host_discovery_tcp80, udp_infrastructure,
          hostname_all_ips, full_ports_cdn_guarded, windows_selected

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

validate_target_file() {
  local file="$1" line n=0
  [[ -f "$file" ]] || fail "Target list not found: $file"
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
  $py - "$PROFILE_JSON" "$PROFILE" "$LIST" "$HOST" "$OUT" "$ALLOW_FULL_PORTS" <<'PY' > "$tmp"
import json, sys

profile_path, profile_id, list_path, host, out_path, allow_full = sys.argv[1:7]
allow_full = allow_full == "1"
with open(profile_path, encoding="utf-8") as fh:
    cfg = json.load(fh)
profiles = cfg.get("profiles", {})
if profile_id not in profiles:
    print(f"unknown profile: {profile_id}", file=sys.stderr)
    sys.exit(2)
p = profiles[profile_id]

if p.get("allowFullPorts") and not allow_full:
    print(f"profile {profile_id} requires --allow-full-ports", file=sys.stderr)
    sys.exit(3)

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
    --allow-public) ALLOW_PUBLIC=1; shift ;;
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

if [[ "$PROFILE" == "full_ports_cdn_guarded" && "$ALLOW_FULL_PORTS" -eq 0 ]]; then
  fail "Profile full_ports_cdn_guarded requires --allow-full-ports"
fi

run_pipeline
