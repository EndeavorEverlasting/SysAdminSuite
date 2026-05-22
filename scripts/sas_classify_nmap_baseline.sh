#!/usr/bin/env bash
# SysAdminSuite Nmap Baseline Classifier
# Shape: Recon -> Decide -> Act -> Log -> Export
# Reads a completed sas_nmap_baseline.sh run folder and exports advisory classifications.

set -Eeuo pipefail
RUN_DIR=""

usage() { cat <<'EOF'
Usage: bash scripts/sas_classify_nmap_baseline.sh --run-dir <baseline-run-folder>

Outputs:
  exports/classifications.csv
  exports/recommended_actions.md
  logs/classifier_events.jsonl
  logs/classifier_trace.log
EOF
}
fail() { echo "ERROR: $*" >&2; exit 1; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'; }
csv_escape() { local v="$1"; v="${v//\"/\"\"}"; printf '"%s"' "$v"; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) [[ $# -ge 2 ]] || fail "--run-dir requires value"; RUN_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$RUN_DIR" ]] || fail "--run-dir is required"
[[ -d "$RUN_DIR" ]] || fail "Run directory not found: $RUN_DIR"
EXPORT_DIR="$RUN_DIR/exports"; LOG_DIR="$RUN_DIR/logs"
OPEN_CSV="$EXPORT_DIR/open_ports_summary.csv"; INDEX_CSV="$EXPORT_DIR/scan_index.csv"
EVENT_LOG="$LOG_DIR/classifier_events.jsonl"; TRACE_LOG="$LOG_DIR/classifier_trace.log"
CLASS_CSV="$EXPORT_DIR/classifications.csv"; ACTIONS_MD="$EXPORT_DIR/recommended_actions.md"
mkdir -p "$EXPORT_DIR" "$LOG_DIR"
[[ -f "$OPEN_CSV" ]] || fail "Missing open ports summary: $OPEN_CSV"

log_event() {
  local stage="$1" level="$2" msg="$3" data="${4:-}" ts; ts="$(now_iso)"
  printf '{"timestamp":"%s","stage":"%s","level":"%s","message":"%s","data":"%s"}\n' \
    "$(json_escape "$ts")" "$(json_escape "$stage")" "$(json_escape "$level")" "$(json_escape "$msg")" "$(json_escape "$data")" >> "$EVENT_LOG"
  printf '[%s][%s] %s\n' "$stage" "$level" "$msg" | tee -a "$TRACE_LOG"
}

log_event START INFO "Nmap classifier started" "run_dir=$RUN_DIR"
log_event RECON INFO "Reading baseline artifacts"

TARGETS=()
if [[ -f "$INDEX_CSV" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == target,* || -z "$line" ]] && continue
    target="${line%%,*}"; target="${target#\"}"; target="${target%\"}"
    [[ -n "$target" ]] && TARGETS+=("$target")
  done < "$INDEX_CSV"
fi
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == target,* || -z "$line" ]] && continue
    target="${line%%,*}"; target="${target#\"}"; target="${target%\"}"
    [[ -n "$target" ]] && TARGETS+=("$target")
  done < "$OPEN_CSV"
fi

UNIQUE=()
for t in "${TARGETS[@]}"; do seen=0; for u in "${UNIQUE[@]}"; do [[ "$u" == "$t" ]] && seen=1 && break; done; [[ "$seen" -eq 0 ]] && UNIQUE+=("$t"); done
log_event DECIDE INFO "Classifying targets" "count=${#UNIQUE[@]}"

printf 'target,classification,confidence,signals,recommended_next_action\n' > "$CLASS_CSV"

classify() {
  local target="$1" lines="$2" classification="unknown_or_no_open_ports" confidence="low" action="Validate network posture, DNS, route, VLAN, firewall, and target freshness before changing product code." signals=()
  if grep -Eq '(^|[^0-9])9100/tcp[[:space:]]+open' <<< "$lines"; then classification="possible_printer_or_print_device"; confidence="medium"; action="Validate queue name, driver availability, TCP/IP port mapping, and print-server vs direct-IP path."; signals+=("9100/tcp open"); fi
  if grep -Eq '(^|[^0-9])(515|631)/(tcp|udp)[[:space:]]+open' <<< "$lines"; then [[ "$classification" == possible_printer_or_print_device ]] && confidence="high" || classification="possible_print_service"; signals+=("LPD/CUPS port open"); fi
  if grep -Eq '(^|[^0-9])445/tcp[[:space:]]+open' <<< "$lines"; then [[ "$classification" == unknown_or_no_open_ports ]] && classification="possible_windows_workstation_or_server" && confidence="medium" && action="Validate hostname, domain posture, SMB reachability, OU/GPO posture, and approved admin path."; signals+=("445/tcp open"); fi
  if grep -Eq '(^|[^0-9])3389/tcp[[:space:]]+open' <<< "$lines"; then [[ "$classification" == possible_windows_workstation_or_server ]] && confidence="high" || classification="possible_windows_remote_access_target"; signals+=("3389/tcp open"); fi
  if grep -Eq '(^|[^0-9])(5985|5986)/tcp[[:space:]]+open' <<< "$lines"; then [[ "$classification" == possible_windows_workstation_or_server ]] && confidence="high" || classification="possible_windows_management_endpoint"; signals+=("WinRM port open"); fi
  if grep -Eq '(^|[^0-9])(80|443)/tcp[[:space:]]+open' <<< "$lines"; then [[ "$classification" == unknown_or_no_open_ports ]] && classification="possible_web_admin_or_appliance_endpoint" && confidence="low" && action="Confirm device identity before browsing or changing configuration."; signals+=("web port open"); fi
  if [[ -z "$lines" ]]; then classification="no_open_ports_observed"; confidence="low"; signals+=("no open ports in summary"); fi
  signal_text="$(IFS='; '; echo "${signals[*]:-no direct signal}")"
  csv_escape "$target"; printf ','; csv_escape "$classification"; printf ','; csv_escape "$confidence"; printf ','; csv_escape "$signal_text"; printf ','; csv_escape "$action"; printf '\n'
}

for target in "${UNIQUE[@]}"; do
  lines="$(awk -v t="$target" 'NR==1{next}{raw=$0; first=raw; sub(/,.*/,"",first); gsub(/^"|"$/, "", first); if(first==t){sub(/^"[^"]+",/,"",raw); gsub(/^"|"$/, "", raw); gsub(/""/,"\"",raw); print raw}}' "$OPEN_CSV")"
  classify "$target" "$lines" >> "$CLASS_CSV"
done

cat > "$ACTIONS_MD" <<EOF
# SysAdminSuite Nmap Baseline Classifications

Source run:

\`$RUN_DIR\`

Classification CSV:

\`$CLASS_CSV\`

These classifications are advisory. They do not prove ownership, role, authorization, or health.
EOF

log_event EXPORT INFO "Classifier outputs exported" "csv=$CLASS_CSV md=$ACTIONS_MD"
log_event END INFO "Nmap classifier completed" "run_dir=$RUN_DIR"
echo "DONE"
echo "Classifications: $CLASS_CSV"
echo "Recommended Actions: $ACTIONS_MD"
