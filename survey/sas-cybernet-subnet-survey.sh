#!/usr/bin/env bash
# SysAdminSuite Cybernet serial-led subnet survey orchestrator.
# Authorized internal asset discovery only. Read-only. Local output only.
set -euo pipefail

VERSION="0.1.1"
SITE=""; MODE=""; RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUTPUT_ROOT="survey/output/cybernet_subnet_survey"; LOGS_ROOT="logs/nmap"; NETWORK_CTX_ROOT="logs/network_context"
MANIFEST=""; SUBNET_FILE=""; HOST_FILE=""; NMAP_XML=""; RESOLVER_OUTPUT=""; RESOLVER_DASHBOARD=""
CONFIRM_TOOL="nmap"; PORTS="135,445,3389"; RATE="50"; NAABU_PROFILE="keyports_cdn_json"
PIPE_FOLLOWUP=0; ALLOW_FULL_PORTS=0; NAABU_HOST=""; CIDRS=(); ALLOW_WIDE=0; ALLOW_PUBLIC=0; DRY_RUN=0; VERBOSE=0; MAX_HOSTS=256
RUN_DIR=""; HOSTS_DIR=""; RESOLVER_DIR=""; PLANNED_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage(){ cat <<'USAGE'
SysAdminSuite Cybernet Subnet Survey Runner

Authorized internal asset discovery only. Read-only. No endpoint mutation.
Modes: local-context-only, dns-list-only, discover, confirm-windows, resolve-only, parse-naabu-only, package-only

Usage:
  bash survey/sas-cybernet-subnet-survey.sh --site SITE --mode MODE [options]

Common options:
  --manifest PATH --cidr CIDR --subnet-file PATH --host-file PATH
  --output-root DIR --logs-root DIR --run-id ID
  --confirm-tool nmap|naabu --naabu-profile NAME --pipe-followup --udp-services
  --allow-full-ports --host URL --ports PORTS --rate N
  --nmap-xml PATH --resolver-output PATH --resolver-dashboard PATH
  --allow-wide --allow-public --dry-run --verbose
USAGE
}
log(){ printf '[cybernet-subnet-survey] %s\n' "$*" >&2; }
fail(){ printf '[cybernet-subnet-survey] ERROR: %s\n' "$*" >&2; exit 1; }
vlog(){ [[ "$VERBOSE" -eq 1 ]] && log "$@"; return 0; }
safe_site(){ SITE="$(printf '%s' "$SITE" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')"; [[ -n "$SITE" ]] || fail "--site is required"; }
safe_token(){ local raw="${1:-run}"; raw="$(printf '%s' "$raw" | tr './:' '____' | tr -cd '[:alnum:]_-')"; [[ -n "$raw" ]] || raw="run"; printf '%s' "$raw"; }
find_python(){ if command -v python3 >/dev/null 2>&1; then echo python3; elif command -v python >/dev/null 2>&1; then echo python; elif command -v py >/dev/null 2>&1; then echo "py -3"; else fail "Python 3 is required"; fi; }
nmap_bin(){ if command -v nmap.exe >/dev/null 2>&1; then command -v nmap.exe; else command -v nmap 2>/dev/null || true; fi; }

append_summary(){ local run_dir="$1"; { echo; echo "## $(date '+%Y-%m-%d %H:%M:%S') — mode=$MODE"; echo; printf '%s\n' "$2"; } >> "$run_dir/SUMMARY.md"; }
ensure_run_dir(){
  RUN_DIR="$OUTPUT_ROOT/${SITE}_${RUN_ID}"; HOSTS_DIR="$RUN_DIR/hosts"; RESOLVER_DIR="$RUN_DIR/resolver"; PLANNED_FILE="$RUN_DIR/planned_commands.txt"
  mkdir -p "$RUN_DIR" "$HOSTS_DIR" "$RESOLVER_DIR" "$LOGS_ROOT" "$NETWORK_CTX_ROOT"
  [[ -f "$RUN_DIR/SUMMARY.md" ]] || printf '# Cybernet Subnet Survey Run\n\nSite: %s\nRun ID: %s\nRun directory: %s\n\n' "$SITE" "$RUN_ID" "$RUN_DIR" > "$RUN_DIR/SUMMARY.md"
  cat > "$RUN_DIR/RUN_MANIFEST.env" <<EOF_MANIFEST
site=$SITE
mode=$MODE
run_id=$RUN_ID
run_dir=$RUN_DIR
logs_root=$LOGS_ROOT
network_context_root=$NETWORK_CTX_ROOT
output_root=$OUTPUT_ROOT
dry_run=$DRY_RUN
manifest=${MANIFEST:-}
host_file=${HOST_FILE:-}
naabu_host=${NAABU_HOST:-}
nmap_xml=${NMAP_XML:-}
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF_MANIFEST
}
run_cmd(){ local desc="$1"; shift; vlog "$desc"; if [[ "$DRY_RUN" -eq 1 ]]; then printf '%s\n' "$*" >> "$PLANNED_FILE"; log "DRY-RUN: $*"; else [[ -n "${1:-}" ]] || fail "Command not found for: $desc"; "$@"; fi; }

validate_cidr(){ local py; py="$(find_python)"; $py - "$1" "$ALLOW_WIDE" "$ALLOW_PUBLIC" <<'PY'
import ipaddress, sys
cidr, allow_wide, allow_public = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
net = ipaddress.ip_network(cidr, strict=False)
if net.version != 4: sys.exit("only IPv4 CIDRs are supported")
if net.prefixlen < 24 and not allow_wide: sys.exit(f"CIDR {cidr} is broader than /24; pass --allow-wide")
if not (net.is_private or net.is_loopback or net.is_link_local) and not allow_public: sys.exit(f"CIDR {cidr} is not RFC1918/private; pass --allow-public")
PY
}
load_subnet_file(){ local file="$1" line; [[ -f "$file" ]] || fail "Subnet file not found: $file"; while IFS= read -r line || [[ -n "$line" ]]; do line="${line%%#*}"; line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"; [[ -n "$line" ]] && CIDRS+=("$line"); done < "$file"; }
dedupe_cidrs(){ local -a out=(); local c u seen; for c in "${CIDRS[@]:-}"; do seen=0; for u in "${out[@]:-}"; do [[ "$u" == "$c" ]] && seen=1 && break; done; [[ "$seen" -eq 0 ]] && out+=("$c"); done; CIDRS=("${out[@]}"); }
collect_cidrs_for_scan(){ [[ -n "$SUBNET_FILE" ]] && load_subnet_file "$SUBNET_FILE"; dedupe_cidrs; [[ ${#CIDRS[@]} -gt 0 ]] || fail "No CIDRs supplied. Use --cidr and/or --subnet-file"; local c; for c in "${CIDRS[@]}"; do validate_cidr "$c"; done; }
validate_host_file(){
  [[ -n "$HOST_FILE" ]] || fail "confirm-windows requires --host-file for this lane"; [[ -f "$HOST_FILE" ]] || fail "Host file not found: $HOST_FILE"
  local line count=0; while IFS= read -r line || [[ -n "$line" ]]; do line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"; [[ -z "$line" || "$line" == \#* ]] && continue; [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] && fail "Host file must not contain CIDR/subnet lines: $line"; count=$((count+1)); done < "$HOST_FILE"
  [[ "$count" -gt 0 ]] || fail "Host file is empty: $HOST_FILE"; [[ "$count" -le "$MAX_HOSTS" || "$ALLOW_WIDE" -eq 1 ]] || fail "Host file has $count entries (cap $MAX_HOSTS). Pass --allow-wide to proceed"
}

naabu_followup_path(){ [[ "$1" == *.json ]] && printf '%s' "${1%.json}_followup.jsonl" || printf '%s' "${1%.*}_followup.jsonl"; }
pick_latest_naabu_output(){ local -a matches; shopt -s nullglob; matches=("$LOGS_ROOT"/${SITE}_*_windows_ports_naabu.json "$LOGS_ROOT"/${SITE}_*_windows_ports_naabu.txt); shopt -u nullglob; [[ ${#matches[@]} -gt 0 ]] || fail "No naabu output found under $LOGS_ROOT for site $SITE"; ls -t "${matches[@]}" | head -n 1; }
run_parse_naabu_evidence(){ local naabu_out="$1" followup_out="$2" csv_out="$3"; local -a args=(bash survey/sas-parse-naabu-evidence.sh --naabu-output "$naabu_out" --output "$csv_out"); [[ -n "$followup_out" ]] && args+=(--followup "$followup_out"); [[ -n "$MANIFEST" && -f "$MANIFEST" ]] && args+=(--manifest "$MANIFEST"); if [[ "$DRY_RUN" -eq 1 ]]; then printf '%s\n' "${args[@]}" >> "$PLANNED_FILE"; log "DRY-RUN: ${args[*]}"; else [[ -f "$naabu_out" ]] || fail "Naabu output not found for parse: $naabu_out"; [[ -z "$followup_out" || -f "$followup_out" ]] || fail "Followup output not found for parse: $followup_out"; mkdir -p "$(dirname "$csv_out")"; (cd "$REPO_ROOT" && "${args[@]}"); fi; }

mode_local_context_only(){ ensure_run_dir; local -a args=(bash survey/sas-find-local-subnets.sh --site "$SITE" --output-root survey/output/local_subnet_finder --run-id "$RUN_ID"); local c; for c in "${CIDRS[@]:-}"; do args+=(--cidr "$c"); done; [[ "$DRY_RUN" -eq 1 ]] && { printf '%s\n' "${args[@]}" >> "$PLANNED_FILE"; log "DRY-RUN: ${args[*]}"; } || (cd "$REPO_ROOT" && "${args[@]}"); append_summary "$RUN_DIR" "Local subnet finder planned/completed."; }
mode_dns_list_only(){ collect_cidrs_for_scan; ensure_run_dir; local nmap c safe out; nmap="$(nmap_bin)"; [[ -n "$nmap" || "$DRY_RUN" -eq 1 ]] || fail "nmap not found on PATH"; for c in "${CIDRS[@]}"; do safe="$(safe_token "$c")"; out="$LOGS_ROOT/${SITE}_${safe}_list_dns.txt"; run_cmd "dns-list $c" "$nmap" -sL "$c" -oN "$out"; append_summary "$RUN_DIR" "dns-list-only $c -> $out"; done; }
mode_discover(){ collect_cidrs_for_scan; ensure_run_dir; local nmap c safe prefix; nmap="$(nmap_bin)"; [[ -n "$nmap" || "$DRY_RUN" -eq 1 ]] || fail "nmap not found on PATH"; for c in "${CIDRS[@]}"; do safe="$(safe_token "$c")"; prefix="$LOGS_ROOT/${SITE}_${safe}_discovery_no_dns"; run_cmd "discover no-dns $c" "$nmap" -sn -n --reason -oA "$prefix" "$c"; prefix="$LOGS_ROOT/${SITE}_${safe}_discovery_dns"; run_cmd "discover dns $c" "$nmap" -sn --system-dns --reason -oA "$prefix" "$c"; append_summary "$RUN_DIR" "discover $c -> $LOGS_ROOT/${SITE}_${safe}_discovery_*"; done; }
mode_confirm_windows(){
  [[ "$CONFIRM_TOOL" == "nmap" || -z "$NAABU_HOST" ]] && validate_host_file
  ensure_run_dir; local target_label="${HOST_FILE:-$NAABU_HOST}" safe out; safe="$(safe_token "$(basename "$target_label")")"
  case "$CONFIRM_TOOL" in
    nmap) local nmap; nmap="$(nmap_bin)"; [[ -n "$nmap" || "$DRY_RUN" -eq 1 ]] || fail "nmap not found on PATH"; out="$LOGS_ROOT/${SITE}_${safe}_windows_ports"; run_cmd "confirm-windows nmap" "$nmap" -sT -Pn -p "$PORTS" --reason --open -iL "$HOST_FILE" -oA "$out"; append_summary "$RUN_DIR" "confirm-windows nmap host_file=$HOST_FILE out=$out" ;;
    naabu) local ext="txt" followup_out csv_out followup_label="no"; [[ "$NAABU_PROFILE" == *json* ]] && ext="json"; out="$LOGS_ROOT/${SITE}_${safe}_windows_ports_naabu.${ext}"; local -a args=(bash survey/sas-run-naabu-pipeline.sh --site "$SITE" --profile "$NAABU_PROFILE" --out "$out" --planned-file "$PLANNED_FILE" --rate "$RATE"); [[ -n "$NAABU_HOST" ]] && args+=(--host "$NAABU_HOST") || args+=(--list "$HOST_FILE"); [[ "$PIPE_FOLLOWUP" -eq 1 ]] && args+=(--pipe-followup); [[ "$ALLOW_FULL_PORTS" -eq 1 ]] && args+=(--allow-full-ports); [[ "$ALLOW_PUBLIC" -eq 1 ]] && args+=(--allow-public); [[ "$DRY_RUN" -eq 1 ]] && args+=(--dry-run); [[ "$DRY_RUN" -eq 1 ]] && run_cmd "confirm-windows naabu pipeline" "${args[@]}" || (cd "$REPO_ROOT" && "${args[@]}"); followup_out="$(naabu_followup_path "$out")"; csv_out="$RESOLVER_DIR/${SITE}_naabu_reachability.csv"; if [[ "$PIPE_FOLLOWUP" -eq 1 ]]; then followup_label="yes"; run_parse_naabu_evidence "$out" "$followup_out" "$csv_out"; else [[ -f "$followup_out" ]] && { followup_label="existing"; run_parse_naabu_evidence "$out" "$followup_out" "$csv_out"; } || run_parse_naabu_evidence "$out" "" "$csv_out"; fi; append_summary "$RUN_DIR" "confirm-windows naabu profile=$NAABU_PROFILE out=$out followup=$followup_label parser=$csv_out" ;;
    *) fail "Unsupported --confirm-tool: $CONFIRM_TOOL (use nmap or naabu)" ;;
  esac
  append_summary "$RUN_DIR" "confirm-windows via $CONFIRM_TOOL using ${HOST_FILE:-$NAABU_HOST}"; log "confirm-windows complete"
}
mode_resolve_only(){ [[ -n "$MANIFEST" && -f "$MANIFEST" ]] || fail "resolve-only requires --manifest"; ensure_run_dir; local xml="$NMAP_XML"; [[ -n "$xml" ]] || xml="$(ls -t "$LOGS_ROOT"/${SITE}_*_discovery_no_dns.xml 2>/dev/null | head -n 1 || true)"; [[ -f "$xml" ]] || fail "Nmap XML not found: ${xml:-none}"; [[ -z "$RESOLVER_OUTPUT" ]] && RESOLVER_OUTPUT="$RESOLVER_DIR/${SITE}_nmap_identity_resolver.csv"; [[ -z "$RESOLVER_DASHBOARD" ]] && RESOLVER_DASHBOARD="$RESOLVER_DIR/${SITE}_nmap_identity_resolver.html"; local -a args=(bash survey/sas-resolve-nmap-evidence.sh --manifest "$MANIFEST" --nmap-output "$xml" --output "$RESOLVER_OUTPUT" --dashboard "$RESOLVER_DASHBOARD"); [[ "$DRY_RUN" -eq 1 ]] && { printf '%s\n' "${args[@]}" >> "$PLANNED_FILE"; log "DRY-RUN: ${args[*]}"; } || (cd "$REPO_ROOT" && "${args[@]}"); append_summary "$RUN_DIR" "resolve-only manifest=$MANIFEST xml=$xml"; }
mode_parse_naabu_only(){ ensure_run_dir; local naabu_out followup_out csv_out; naabu_out="$(pick_latest_naabu_output)"; followup_out="$(naabu_followup_path "$naabu_out")"; [[ -f "$followup_out" ]] || followup_out=""; csv_out="$RESOLVER_DIR/${SITE}_naabu_reachability.csv"; run_parse_naabu_evidence "$naabu_out" "$followup_out" "$csv_out"; append_summary "$RUN_DIR" "parse-naabu-only naabu=$naabu_out followup=${followup_out:-none} csv=$csv_out"; }
mode_package_only(){ ensure_run_dir; local artifact_dir="$REPO_ROOT/survey/artifacts/${SITE}_${RUN_ID}" package_list="$artifact_dir/PACKAGE_MANIFEST.txt"; mkdir -p "$artifact_dir"; cp "$RUN_DIR/RUN_MANIFEST.env" "$RUN_DIR/SUMMARY.md" "$artifact_dir/" 2>/dev/null || true; { echo RUN_MANIFEST.env; echo SUMMARY.md; } | sort -u > "$package_list"; append_summary "$RUN_DIR" "package-only -> $artifact_dir"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?}"; shift 2 ;; --mode) MODE="${2:?}"; shift 2 ;; --manifest) MANIFEST="${2:?}"; shift 2 ;; --cidr) CIDRS+=("${2:?}"); shift 2 ;; --subnet-file) SUBNET_FILE="${2:?}"; shift 2 ;; --host-file) HOST_FILE="${2:?}"; shift 2 ;; --output-root) OUTPUT_ROOT="${2:?}"; shift 2 ;; --logs-root) LOGS_ROOT="${2:?}"; shift 2 ;; --run-id) RUN_ID="${2:?}"; shift 2 ;; --confirm-tool) CONFIRM_TOOL="${2:?}"; shift 2 ;; --naabu-profile) NAABU_PROFILE="${2:?}"; shift 2 ;; --pipe-followup) PIPE_FOLLOWUP=1; shift ;; --udp-services) NAABU_PROFILE="udp_infrastructure"; shift ;; --allow-full-ports) ALLOW_FULL_PORTS=1; shift ;; --host) NAABU_HOST="${2:?}"; shift 2 ;; --ports) PORTS="${2:?}"; shift 2 ;; --rate) RATE="${2:?}"; shift 2 ;; --nmap-xml) NMAP_XML="${2:?}"; shift 2 ;; --resolver-output) RESOLVER_OUTPUT="${2:?}"; shift 2 ;; --resolver-dashboard) RESOLVER_DASHBOARD="${2:?}"; shift 2 ;; --allow-wide) ALLOW_WIDE=1; shift ;; --allow-public) ALLOW_PUBLIC=1; shift ;; --dry-run) DRY_RUN=1; shift ;; --verbose) VERBOSE=1; shift ;; --version) echo "$VERSION"; exit 0 ;; -h|--help) usage; exit 0 ;; *) fail "Unknown argument: $1" ;;
  esac
done
[[ -n "$SITE" ]] || fail "--site is required"; [[ -n "$MODE" ]] || fail "--mode is required"; safe_site
case "$MODE" in local-context-only) mode_local_context_only ;; dns-list-only) mode_dns_list_only ;; discover) mode_discover ;; confirm-windows) mode_confirm_windows ;; resolve-only) mode_resolve_only ;; parse-naabu-only) mode_parse_naabu_only ;; package-only) mode_package_only ;; *) fail "Unknown mode: $MODE" ;; esac
