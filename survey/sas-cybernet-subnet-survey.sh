#!/usr/bin/env bash
# SysAdminSuite Cybernet serial-led subnet survey orchestrator.
# Authorized internal asset discovery only. Read-only. Local output only.
# Low-noise survey doctrine: this subnet path is discovery context, NOT the registered
# Cybernet population source. Prefer AD-derived host lists for confirm-windows reachability.
# See docs/LOW_NOISE_SURVEY_DOCTRINE.md. Default --naabu-profile keyports_cybernet_json
# validates full Cybernet key ports; web-only checks use the explicit web reachability profiles.

set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

VERSION="0.1.2"
SITE=""
MODE=""
RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUTPUT_ROOT="survey/output/cybernet_subnet_survey"
LOGS_ROOT="logs/nmap"
NETWORK_CTX_ROOT="logs/network_context"
MANIFEST=""
SUBNET_FILE=""
HOST_FILE=""
NMAP_XML=""
RESOLVER_OUTPUT=""
RESOLVER_DASHBOARD=""
CONFIRM_TOOL="nmap"
PORTS="135,445,3389"
RATE="50"
NAABU_PROFILE="keyports_cybernet_json"
PIPE_FOLLOWUP=0
ALLOW_FULL_PORTS=0
NAABU_PROFILE_JUSTIFIED=0
NAABU_APPROVED_SUBNET_SCOPE=0
NAABU_HOST=""
CIDRS=()
ALLOW_WIDE=0
ALLOW_PUBLIC=0
DRY_RUN=0
VERBOSE=0
MAX_HOSTS=256

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_INTAKE_HELPER="${SCRIPT_DIR}/lib/sas-target-intake.sh"

[[ -f "$TARGET_INTAKE_HELPER" ]] || { echo "[cybernet-subnet-survey] ERROR: Missing target intake helper: $TARGET_INTAKE_HELPER" >&2; exit 1; }
# shellcheck source=survey/lib/sas-target-intake.sh
source "$TARGET_INTAKE_HELPER"

usage() {
  cat <<'USAGE'
SysAdminSuite Cybernet Subnet Survey Runner

Authorized internal asset discovery only.
Read-only. No endpoint mutation.
Use approved discovery and confirmation modes only.

Usage:
  bash survey/sas-cybernet-subnet-survey.sh --site SITE --mode MODE [options]

Modes:
  local-context-only   Run local subnet finder and copy network context
  dns-list-only        Nmap -sL list/DNS sanity check per CIDR (not host proof)
  discover             Nmap -sn discovery (no-DNS + system-DNS) per CIDR
  confirm-windows      Narrow Windows port confirmation against a host file, or approved Naabu --host mode
  resolve-only         Resolve manifest against existing Nmap XML evidence
  parse-naabu-only     Parse existing naabu JSON/txt + followup into resolver CSV
  package-only         Package run outputs into survey/artifacts/

Required:
  --site SITE          Site/run label (alphanumeric, dash, underscore)

Options:
  --mode MODE          One of the modes above (required)
  --manifest PATH      Target manifest CSV from approved intake/staging or generated SysAdminSuite output
  --cidr CIDR          Approved IPv4 CIDR. Repeatable
  --subnet-file PATH   Plain-text CIDR list from approved intake/staging
  --host-file PATH     Host list for confirm-windows from approved intake/staging
  --output-root DIR    Default: survey/output/cybernet_subnet_survey
  --logs-root DIR      Default: logs/nmap
  --run-id ID          Correlate multi-step runs. Default: timestamp
  --confirm-tool TOOL  nmap or naabu. Default: nmap
  --naabu-profile NAME Naabu profile when --confirm-tool naabu. Default: keyports_cybernet_json
  --pipe-followup      Pipe naabu silent stdout into sas-cybernet-packet-followup.sh
  --udp-services       Use udp_dns_snmp_json profile (DNS/SNMP UDP, justification ack'd)
  --host-discovery     Use host_discovery_web_syn_txt (-sn -pe -ps 80 -ec; subnet scope ack'd)
  --all-ports          Use allports_low_noise_json (-p - -ec; requires --allow-full-ports)
  --allow-full-ports   Permit naabu allports_low_noise_json profile (-p - -ec)
  --profile-justified  Acknowledge justification for justification-required naabu profiles
  --approved-subnet-scope Acknowledge approved subnet scope for host-discovery naabu profiles
  --host URL           Hostname/URL for naabu -sa scans (hostname_all_ips profile)
  --ports PORTS        Default: 135,445,3389 (nmap confirm only)
  --rate N             Naabu rate. Default: 50
  --nmap-xml PATH      Override Nmap XML for resolve-only
  --resolver-output PATH
  --resolver-dashboard PATH
  --allow-wide         Permit CIDRs broader than /24
  --allow-public       Permit non-RFC1918/public CIDRs
  --dry-run            Print planned commands; do not execute nmap/naabu/finder
  --verbose            Echo commands before execution
  -h, --help           Show help

Urgent path:
  1. local-context-only
  2. dns-list-only (--subnet-file from approved intake/staging)
  3. discover
  4. resolve-only (--manifest)
  5. confirm-windows (--host-file) optional
  6. parse-naabu-only (re-parse naabu artifacts without rescan)
  7. package-only

Generated output may contain operational network details. Do not commit it.
USAGE
}

log() { printf '[cybernet-subnet-survey] %s\n' "$*" >&2; }
fail() { printf '[cybernet-subnet-survey] ERROR: %s\n' "$*" >&2; exit 1; }
vlog() { [[ "$VERBOSE" -eq 1 ]] && log "$@"; return 0; }

safe_site() {
  SITE="$(printf '%s' "$SITE" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')"
  [[ -n "$SITE" ]] || fail "--site is required"
}

safe_cidr_token() {
  printf '%s' "$1" | tr './:' '____'
}

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  if command -v py >/dev/null 2>&1; then echo "py -3"; return 0; fi
  fail "Python 3 is required for CIDR validation"
}

validate_cidr() {
  local cidr="$1"
  local py allow_wide="$ALLOW_WIDE" allow_public="$ALLOW_PUBLIC"
  py="$(find_python)"
  $py - "$cidr" "$allow_wide" "$allow_public" <<'PY'
import ipaddress, sys
cidr, allow_wide, allow_public = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
try:
    net = ipaddress.ip_network(cidr, strict=False)
except ValueError as exc:
    print(f"invalid CIDR: {exc}", file=sys.stderr)
    sys.exit(2)
if net.version != 4:
    print("only IPv4 CIDRs are supported", file=sys.stderr)
    sys.exit(2)
if net.prefixlen < 24 and not allow_wide:
    print(f"CIDR {cidr} is broader than /24; pass --allow-wide", file=sys.stderr)
    sys.exit(3)
if not (net.is_private or net.is_loopback or net.is_link_local) and not allow_public:
    print(f"CIDR {cidr} is not RFC1918/private; pass --allow-public", file=sys.stderr)
    sys.exit(4)
PY
}

load_subnet_file() {
  local file="$1" line
  sas_target_require_input_file "$file" "subnet CIDR file" 1 "$REPO_ROOT" || exit 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    CIDRS+=("$line")
  done < "$file"
}

dedupe_cidrs() {
  local -a unique=()
  local c u seen=0
  for c in "${CIDRS[@]}"; do
    seen=0
    for u in "${unique[@]:-}"; do
      [[ "$u" == "$c" ]] && seen=1 && break
    done
    [[ "$seen" -eq 0 ]] && unique+=("$c")
  done
  CIDRS=("${unique[@]}")
}

append_summary() {
  local run_dir="$1"
  {
    echo
    echo "## $(date '+%Y-%m-%d %H:%M:%S') — mode=$MODE"
    echo
    printf '%s\n' "$2"
  } >> "$run_dir/SUMMARY.md"
}

write_manifest() {
  local run_dir="$1"
  cat > "$run_dir/RUN_MANIFEST.env" <<EOF
site=$SITE
mode=$MODE
run_id=$RUN_ID
run_dir=$run_dir
logs_root=$LOGS_ROOT
network_context_root=$NETWORK_CTX_ROOT
output_root=$OUTPUT_ROOT
dry_run=$DRY_RUN
manifest=${MANIFEST:-}
host_file=${HOST_FILE:-}
naabu_host=${NAABU_HOST:-}
nmap_xml=${NMAP_XML:-}
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

run_cmd() {
  local desc="$1"; shift
  vlog "$desc"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ -z "${1:-}" ]]; then
      printf 'nmap %s\n' "$*" >> "$PLANNED_FILE"
      log "DRY-RUN: nmap $*"
    else
      printf '%s\n' "$*" >> "$PLANNED_FILE"
      log "DRY-RUN: $*"
    fi
    return 0
  fi
  [[ -n "${1:-}" ]] || fail "Command not found for: $desc"
  "$@"
}

nmap_bin() {
  if command -v nmap.exe >/dev/null 2>&1; then command -v nmap.exe; return; fi
  command -v nmap 2>/dev/null || true
}

naabu_bin() {
  local vend="$REPO_ROOT/bin/naabu.exe"
  [[ -x "$vend" ]] && { printf '%s' "$vend"; return; }
  [[ -f "$vend" ]] && { printf '%s' "$vend"; return; }
  if command -v naabu.exe >/dev/null 2>&1; then command -v naabu.exe; return; fi
  command -v naabu 2>/dev/null || true
}

naabu_followup_path() {
  local out="$1"
  if [[ "$out" == *.json ]]; then
    printf '%s' "${out%.json}_followup.jsonl"
  else
    printf '%s' "${out%.*}_followup.jsonl"
  fi
}

pick_latest_naabu_output() {
  local candidate
  shopt -s nullglob
  local -a matches=("$LOGS_ROOT"/${SITE}_*_windows_ports_naabu.json "$LOGS_ROOT"/${SITE}_*_windows_ports_naabu.txt)
  shopt -u nullglob
  if [[ ${#matches[@]} -eq 0 ]]; then
    fail "No naabu output found under $LOGS_ROOT for site $SITE"
  fi
  candidate="$(ls -t "${matches[@]}" 2>/dev/null | head -n 1 || true)"
  [[ -n "$candidate" ]] || fail "No naabu output found under $LOGS_ROOT for site $SITE"
  printf '%s' "$candidate"
}

run_parse_naabu_evidence() {
  local naabu_out="$1"
  local followup_out="$2"
  local csv_out="$3"
  local -a parse_args=(
    bash survey/sas-parse-naabu-evidence.sh
    --naabu-output "$naabu_out"
    --output "$csv_out"
  )
  [[ -n "$followup_out" ]] && parse_args+=(--followup "$followup_out")
  if [[ -n "$MANIFEST" && -f "$MANIFEST" ]]; then
    sas_target_require_manifest_file "$MANIFEST" "resolver manifest" "$REPO_ROOT" || exit 1
    parse_args+=(--manifest "$MANIFEST")
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' "${parse_args[@]}" >> "$PLANNED_FILE"
    log "DRY-RUN: ${parse_args[*]}"
    return 0
  fi
  [[ -f "$naabu_out" ]] || fail "Naabu output not found for parse: $naabu_out"
  [[ -z "$followup_out" || -f "$followup_out" ]] || fail "Followup output not found for parse: $followup_out"
  mkdir -p "$(dirname "$csv_out")"
  (cd "$REPO_ROOT" && "${parse_args[@]}")
}

ensure_run_dir() {
  RUN_DIR="$OUTPUT_ROOT/${SITE}_${RUN_ID}"
  HOSTS_DIR="$RUN_DIR/hosts"
  RESOLVER_DIR="$RUN_DIR/resolver"
  PLANNED_FILE="$RUN_DIR/planned_commands.txt"
  mkdir -p "$RUN_DIR" "$HOSTS_DIR" "$RESOLVER_DIR" "$LOGS_ROOT" "$NETWORK_CTX_ROOT"
  if [[ ! -f "$RUN_DIR/SUMMARY.md" ]]; then
    cat > "$RUN_DIR/SUMMARY.md" <<EOF
# Cybernet Subnet Survey Run

Site: $SITE
Run ID: $RUN_ID
Run directory: $RUN_DIR

EOF
  fi
  write_manifest "$RUN_DIR"
}

collect_cidrs_for_scan() {
  if [[ -n "$SUBNET_FILE" ]]; then
    load_subnet_file "$SUBNET_FILE"
  fi
  dedupe_cidrs
  [[ ${#CIDRS[@]} -gt 0 ]] || fail "No CIDRs supplied. Use --cidr and/or --subnet-file"
  local c
  for c in "${CIDRS[@]}"; do validate_cidr "$c"; done
}

validate_host_file() {
  [[ -n "$HOST_FILE" ]] || fail "confirm-windows requires --host-file"
  sas_target_require_input_file "$HOST_FILE" "confirm-windows host file" 1 "$REPO_ROOT" || exit 1
  local line count=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
      fail "Host file must not contain CIDR/subnet lines: $line"
    fi
    count=$((count + 1))
  done < "$HOST_FILE"
  [[ "$count" -gt 0 ]] || fail "Host file is empty: $HOST_FILE"
  if [[ "$count" -gt "$MAX_HOSTS" && "$ALLOW_WIDE" -eq 0 ]]; then
    fail "Host file has $count entries (cap $MAX_HOSTS). Pass --allow-wide to proceed"
  fi
}

extract_up_hosts() {
  local gnmap="$1" out="$2"
  [[ -f "$gnmap" ]] || return 0
  awk '/Status: Up/ {print $2}' "$gnmap" | sort -u > "$out" || true
}

mode_local_context_only() {
  ensure_run_dir
  local finder_args=(bash survey/sas-find-local-subnets.sh --site "$SITE" --output-root survey/output/local_subnet_finder --run-id "$RUN_ID")
  local c
  for c in "${CIDRS[@]}"; do finder_args+=(--cidr "$c"); done

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' "${finder_args[@]}" >> "$PLANNED_FILE"
    log "DRY-RUN: ${finder_args[*]}"
    LOCAL_FINDER_DIR="survey/output/local_subnet_finder/${SITE}_${RUN_ID}"
  else
    (cd "$REPO_ROOT" && "${finder_args[@]}")
    LOCAL_FINDER_DIR="$REPO_ROOT/survey/output/local_subnet_finder/${SITE}_${RUN_ID}"
    [[ -d "$LOCAL_FINDER_DIR" ]] || fail "Expected finder output missing: $LOCAL_FINDER_DIR"
  fi

  local ctx_dest="$NETWORK_CTX_ROOT/${SITE}_${RUN_ID}"
  if [[ "$DRY_RUN" -eq 0 && -d "$LOCAL_FINDER_DIR/context" ]]; then
    mkdir -p "$ctx_dest"
    cp -R "$LOCAL_FINDER_DIR/context/." "$ctx_dest/"
  fi

  {
    echo "LOCAL_FINDER_DIR=$LOCAL_FINDER_DIR"
    echo "NETWORK_CONTEXT_DIR=$ctx_dest"
  } >> "$RUN_DIR/RUN_MANIFEST.env"

  append_summary "$RUN_DIR" "Local subnet finder completed.
Finder directory: $LOCAL_FINDER_DIR
Network context copy: $ctx_dest"
  log "local-context-only complete. Run dir: $RUN_DIR"
}

mode_dns_list_only() {
  collect_cidrs_for_scan
  ensure_run_dir
  local nmap c safe out py classify_out classify_args
  nmap="$(nmap_bin)"
  [[ -n "$nmap" || "$DRY_RUN" -eq 1 ]] || fail "nmap not found on PATH"
  classify_out="$RUN_DIR/dns_infrastructure_classification.csv"
  classify_args=()
  for c in "${CIDRS[@]}"; do
    safe="$(safe_cidr_token "$c")"
    out="$LOGS_ROOT/${SITE}_${safe}_list_dns.txt"
    run_cmd "dns-list $c" "$nmap" -sL "$c" -oN "$out"
    append_summary "$RUN_DIR" "dns-list-only $c -> $out (DNS/list sanity check, not host proof)"
    if [[ "$DRY_RUN" -eq 0 && -f "$out" ]]; then
      classify_args+=(--input "$out" --subnet "$c")
    fi
  done
  if [[ "$DRY_RUN" -eq 0 && ${#classify_args[@]} -gt 0 ]]; then
    py="$(find_python)"
    classify_script="$SCRIPT_DIR/sas-classify-dns-list-output.py"
    run_cmd "classify dns-list" $py "$classify_script" "${classify_args[@]}" --output "$classify_out"
    append_summary "$RUN_DIR" "dns-list classification -> $classify_out"
  fi
  log "dns-list-only complete"
}

mode_discover() {
  collect_cidrs_for_scan
  ensure_run_dir
  local nmap c safe prefix
  nmap="$(nmap_bin)"
  [[ -n "$nmap" || "$DRY_RUN" -eq 1 ]] || fail "nmap not found on PATH"
  for c in "${CIDRS[@]}"; do
    safe="$(safe_cidr_token "$c")"
    prefix="$LOGS_ROOT/${SITE}_${safe}_discovery_no_dns"
    run_cmd "discover no-dns $c" "$nmap" -sn -n --reason -oA "$prefix" "$c"
    prefix="$LOGS_ROOT/${SITE}_${safe}_discovery_dns"
    run_cmd "discover dns $c" "$nmap" -sn --system-dns --reason -oA "$prefix" "$c"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      extract_up_hosts "$LOGS_ROOT/${SITE}_${safe}_discovery_no_dns.gnmap" "$HOSTS_DIR/${safe}_up.txt"
    fi
    append_summary "$RUN_DIR" "discover $c -> logs under $LOGS_ROOT/${SITE}_${safe}_discovery_*"
  done
  log "discover complete"
}

mode_confirm_windows() {
  if [[ "$CONFIRM_TOOL" == "nmap" || -z "$NAABU_HOST" ]]; then
    validate_host_file
  fi
  ensure_run_dir
  local safe out nmap naabu target_label
  target_label="${HOST_FILE:-$NAABU_HOST}"
  safe="$(safe_cidr_token "$(basename "$target_label")")"
  case "$CONFIRM_TOOL" in
    nmap)
      nmap="$(nmap_bin)"
      [[ -n "$nmap" || "$DRY_RUN" -eq 1 ]] || fail "nmap not found on PATH"
      out="$LOGS_ROOT/${SITE}_${safe}_windows_ports"
      run_cmd "confirm-windows nmap" "$nmap" -sT -Pn -p "$PORTS" --reason --open -iL "$HOST_FILE" -oA "$out"
      ;;
    naabu)
      local ext="txt" followup_label="no"
      [[ "$NAABU_PROFILE" == *json* ]] && ext="json"
      out="$LOGS_ROOT/${SITE}_${safe}_windows_ports_naabu.${ext}"
      if [[ -n "$NAABU_HOST" || "$PIPE_FOLLOWUP" -eq 1 ]]; then
        local pipeline_args=(
          bash survey/sas-run-naabu-pipeline.sh
          --site "$SITE"
          --profile "$NAABU_PROFILE"
          --out "$out"
          --planned-file "$PLANNED_FILE"
          --rate "$RATE"
        )
        [[ -n "$NAABU_HOST" ]] && pipeline_args+=(--host "$NAABU_HOST")
        [[ -z "$NAABU_HOST" ]] && pipeline_args+=(--list "$HOST_FILE")
        [[ "$PIPE_FOLLOWUP" -eq 1 ]] && pipeline_args+=(--pipe-followup)
        [[ "$ALLOW_FULL_PORTS" -eq 1 ]] && pipeline_args+=(--allow-full-ports)
        [[ "$NAABU_PROFILE_JUSTIFIED" -eq 1 ]] && pipeline_args+=(--profile-justified)
        [[ "$NAABU_APPROVED_SUBNET_SCOPE" -eq 1 ]] && pipeline_args+=(--approved-subnet-scope)
        [[ "$ALLOW_PUBLIC" -eq 1 ]] && pipeline_args+=(--allow-public)
        [[ "$DRY_RUN" -eq 1 ]] && pipeline_args+=(--dry-run)
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log "DRY-RUN: ${pipeline_args[*]}"
        fi
        (cd "$REPO_ROOT" && "${pipeline_args[@]}")
      else
        out="$LOGS_ROOT/${SITE}_${safe}_windows_ports_naabu.json"
        local packet_args=(
          bash survey/sas-run-packet-probe.sh
          --site "$SITE"
          --list "$HOST_FILE"
          --out "$out"
          --summary "${out}.summary.json"
          --planned-file "$PLANNED_FILE"
        )
        [[ "$ALLOW_PUBLIC" -eq 1 ]] && packet_args+=(--allow-public)
        [[ "$DRY_RUN" -eq 1 ]] && packet_args+=(--dry-run)
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log "DRY-RUN: ${packet_args[*]}"
        fi
        (cd "$REPO_ROOT" && "${packet_args[@]}")
      fi
      local followup_out csv_out
      followup_out="$(naabu_followup_path "$out")"
      csv_out="$RESOLVER_DIR/${SITE}_naabu_reachability.csv"
      if [[ "$PIPE_FOLLOWUP" -eq 1 ]]; then
        followup_label="yes"
        run_parse_naabu_evidence "$out" "$followup_out" "$csv_out"
      elif [[ -f "$followup_out" ]]; then
        followup_label="existing"
        run_parse_naabu_evidence "$out" "$followup_out" "$csv_out"
      else
        run_parse_naabu_evidence "$out" "" "$csv_out"
      fi
      append_summary "$RUN_DIR" "confirm-windows naabu profile=$NAABU_PROFILE out=$out followup=$followup_label parser=$csv_out"
      ;;
    *) fail "Unsupported --confirm-tool: $CONFIRM_TOOL (use nmap or naabu)" ;;
  esac
  append_summary "$RUN_DIR" "confirm-windows via $CONFIRM_TOOL using ${HOST_FILE:-$NAABU_HOST}"
  log "confirm-windows complete"
}

pick_default_nmap_xml() {
  local candidate
  candidate="$(ls -t "$LOGS_ROOT"/${SITE}_*_discovery_no_dns.xml 2>/dev/null | head -n 1 || true)"
  [[ -n "$candidate" ]] || fail "No discovery XML found under $LOGS_ROOT for site $SITE; pass --nmap-xml"
  printf '%s' "$candidate"
}

mode_resolve_only() {
  [[ -n "$MANIFEST" ]] || fail "resolve-only requires --manifest"
  sas_target_require_manifest_file "$MANIFEST" "resolve-only manifest" "$REPO_ROOT" || exit 1
  [[ -f "$MANIFEST" ]] || fail "Manifest not found: $MANIFEST"
  ensure_run_dir
  local xml="$NMAP_XML"
  [[ -n "$xml" ]] || xml="$(pick_default_nmap_xml)"
  [[ -f "$xml" ]] || fail "Nmap XML not found: $xml"
  [[ -z "$RESOLVER_OUTPUT" ]] && RESOLVER_OUTPUT="$RESOLVER_DIR/${SITE}_nmap_identity_resolver.csv"
  [[ -z "$RESOLVER_DASHBOARD" ]] && RESOLVER_DASHBOARD="$RESOLVER_DIR/${SITE}_nmap_identity_resolver.html"
  mkdir -p "$(dirname "$RESOLVER_OUTPUT")"

  local args=(
    bash survey/sas-resolve-nmap-evidence.sh
    --manifest "$MANIFEST"
    --nmap-output "$xml"
    --output "$RESOLVER_OUTPUT"
    --dashboard "$RESOLVER_DASHBOARD"
  )
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' "${args[@]}" >> "$PLANNED_FILE"
    log "DRY-RUN: ${args[*]}"
  else
    (cd "$REPO_ROOT" && "${args[@]}")
  fi
  append_summary "$RUN_DIR" "resolve-only manifest=$MANIFEST xml=$xml
resolver_csv=$RESOLVER_OUTPUT
resolver_html=$RESOLVER_DASHBOARD"
  log "resolve-only complete"
}

mode_parse_naabu_only() {
  ensure_run_dir
  local naabu_out followup_out csv_out
  naabu_out="$(pick_latest_naabu_output)"
  followup_out="$(naabu_followup_path "$naabu_out")"
  csv_out="$RESOLVER_DIR/${SITE}_naabu_reachability.csv"
  [[ -f "$followup_out" ]] || followup_out=""
  run_parse_naabu_evidence "$naabu_out" "$followup_out" "$csv_out"
  append_summary "$RUN_DIR" "parse-naabu-only naabu=$naabu_out followup=${followup_out:-none} csv=$csv_out"
  log "parse-naabu-only complete"
}

mode_package_only() {
  ensure_run_dir
  local artifact_dir="$REPO_ROOT/survey/artifacts/${SITE}_${RUN_ID}"
  local package_list="$artifact_dir/PACKAGE_MANIFEST.txt"
  PACKAGE_LIST="$(mktemp)"
  mkdir -p "$artifact_dir"

  local item
  for item in RUN_MANIFEST.env SUMMARY.md; do
    [[ -f "$RUN_DIR/$item" ]] && cp "$RUN_DIR/$item" "$artifact_dir/" && echo "$item" >> "$PACKAGE_LIST"
  done
  [[ -d "$RUN_DIR/hosts" ]] && mkdir -p "$artifact_dir/hosts" && cp -R "$RUN_DIR/hosts/." "$artifact_dir/hosts/" && echo "hosts/" >> "$PACKAGE_LIST"
  [[ -d "$RUN_DIR/resolver" ]] && mkdir -p "$artifact_dir/resolver" && cp -R "$RUN_DIR/resolver/." "$artifact_dir/resolver/" && echo "resolver/" >> "$PACKAGE_LIST"

  local ctx="$NETWORK_CTX_ROOT/${SITE}_${RUN_ID}"
  if [[ -d "$ctx" ]]; then
    mkdir -p "$artifact_dir/network_context"
    cp -R "$ctx/." "$artifact_dir/network_context/"
    echo "network_context/" >> "$PACKAGE_LIST"
  fi

  shopt -s nullglob
  local f
  for f in "$LOGS_ROOT/${SITE}_"*; do
    [[ -e "$f" ]] || continue
    cp "$f" "$artifact_dir/"
    echo "logs/$(basename "$f")" >> "$PACKAGE_LIST"
  done
  shopt -u nullglob

  if [[ -n "$MANIFEST" && -f "$MANIFEST" ]]; then
    sas_target_require_manifest_file "$MANIFEST" "package manifest" "$REPO_ROOT" || exit 1
    mkdir -p "$artifact_dir/manifests"
    cp "$MANIFEST" "$artifact_dir/manifests/$(basename "$MANIFEST")"
    echo "manifests/$(basename "$MANIFEST")" >> "$PACKAGE_LIST"
  fi

  for f in \
    "$RESOLVER_OUTPUT" \
    "$RESOLVER_DASHBOARD" \
    "$RUN_DIR/resolver/${SITE}_naabu_reachability.csv" \
    "$RUN_DIR/resolver/${SITE}_nmap_identity_resolver.csv" \
    "$RUN_DIR/resolver/${SITE}_nmap_identity_resolver.html" \
    "$REPO_ROOT/survey/output/${SITE}_nmap_identity_resolver.csv" \
    "$REPO_ROOT/survey/output/${SITE}_nmap_identity_resolver.html" \
    "$REPO_ROOT/survey/output/cybernet_targets_resolved.csv" \
    "$REPO_ROOT/survey/output/neuron_targets_resolved.csv"; do
    if [[ -f "$f" ]]; then
      mkdir -p "$artifact_dir/resolver"
      cp "$f" "$artifact_dir/resolver/$(basename "$f")"
      echo "resolver/$(basename "$f")" >> "$PACKAGE_LIST"
    fi
  done

  sort -u "$PACKAGE_LIST" > "$package_list"
  rm -f "$PACKAGE_LIST"
  append_summary "$RUN_DIR" "package-only -> $artifact_dir (see PACKAGE_MANIFEST.txt)"
  log "package-only complete: $artifact_dir"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?missing --site value}"; shift 2 ;;
    --mode) MODE="${2:?missing --mode value}"; shift 2 ;;
    --manifest) MANIFEST="${2:?missing --manifest value}"; shift 2 ;;
    --cidr) CIDRS+=("${2:?missing --cidr value}"); shift 2 ;;
    --subnet-file) SUBNET_FILE="${2:?missing --subnet-file value}"; shift 2 ;;
    --host-file) HOST_FILE="${2:?missing --host-file value}"; shift 2 ;;
    --output-root) OUTPUT_ROOT="${2:?missing --output-root value}"; shift 2 ;;
    --logs-root) LOGS_ROOT="${2:?missing --logs-root value}"; shift 2 ;;
    --run-id) RUN_ID="${2:?missing --run-id value}"; shift 2 ;;
    --confirm-tool) CONFIRM_TOOL="${2:?missing --confirm-tool value}"; shift 2 ;;
    --naabu-profile) NAABU_PROFILE="${2:?missing --naabu-profile value}"; shift 2 ;;
    --pipe-followup) PIPE_FOLLOWUP=1; shift ;;
    --udp-services) NAABU_PROFILE="udp_dns_snmp_json"; NAABU_PROFILE_JUSTIFIED=1; shift ;;
    --host-discovery) NAABU_PROFILE="host_discovery_web_syn_txt"; NAABU_APPROVED_SUBNET_SCOPE=1; shift ;;
    --all-ports) NAABU_PROFILE="allports_low_noise_json"; ALLOW_FULL_PORTS=1; NAABU_PROFILE_JUSTIFIED=1; shift ;;
    --allow-full-ports) ALLOW_FULL_PORTS=1; shift ;;
    --profile-justified) NAABU_PROFILE_JUSTIFIED=1; shift ;;
    --approved-subnet-scope) NAABU_APPROVED_SUBNET_SCOPE=1; shift ;;
    --host) NAABU_HOST="${2:?missing --host value}"; shift 2 ;;
    --ports) PORTS="${2:?missing --ports value}"; shift 2 ;;
    --rate) RATE="${2:?missing --rate value}"; shift 2 ;;
    --nmap-xml) NMAP_XML="${2:?missing --nmap-xml value}"; shift 2 ;;
    --resolver-output) RESOLVER_OUTPUT="${2:?missing --resolver-output value}"; shift 2 ;;
    --resolver-dashboard) RESOLVER_DASHBOARD="${2:?missing --resolver-dashboard value}"; shift 2 ;;
    --allow-wide) ALLOW_WIDE=1; shift ;;
    --allow-public) ALLOW_PUBLIC=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

[[ -n "$SITE" ]] || fail "--site is required"
[[ -n "$MODE" ]] || fail "--mode is required"
safe_site

case "$MODE" in
  local-context-only) mode_local_context_only ;;
  dns-list-only) mode_dns_list_only ;;
  discover) mode_discover ;;
  confirm-windows) mode_confirm_windows ;;
  resolve-only) mode_resolve_only ;;
  parse-naabu-only) mode_parse_naabu_only ;;
  package-only) mode_package_only ;;
  *) fail "Unknown mode: $MODE" ;;
esac
