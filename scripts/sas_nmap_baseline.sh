#!/usr/bin/env bash
# SysAdminSuite Nmap Baseline Module
# Shape: Recon -> Decide -> Act -> Log -> Export
# Read-only diagnostic collector for authorized internal support work.

set -Eeuo pipefail

SCAN_MODE="common-ports"
TARGETS=()
TARGET_FILE=""
PORTS=""
TIMING="safe"
ALLOW_SUBNET=0
MAX_TARGETS=16
NO_SERVICE_DETECTION=0
DRY_RUN=0
OUTPUT_ROOT="${USERPROFILE:-${HOME:-.}}/SysAdminSuite/Runs"

usage() {
  cat <<'EOF'
Usage: bash scripts/sas_nmap_baseline.sh [options]

Options:
  --target <host-or-ip>          Add target. Repeatable.
  --targets <a,b,c>             Add comma-separated targets.
  --target-file <file>          Add targets from file. Blank lines and # comments ignored.
  --scan-mode <mode>            local-only | ping-only | common-ports | printer-ports | workstation-ports | custom-ports
  --ports <ports>               Required with custom-ports. Example: 80,443,9100
  --timing <safe|normal>        Default: safe.
  --allow-subnet                Permit CIDR targets. CIDR broader than /29 is blocked.
  --max-targets <n>             Default: 16.
  --no-service-detection        Skip -sV --version-light.
  --output-root <path>          Default: $USERPROFILE/SysAdminSuite/Runs.
  --dry-run                     Build reports without executing nmap.
  -h, --help                    Show help.
EOF
}

fail() { echo "ERROR: $*" >&2; exit 1; }
trim() { local v="$*"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'; }
safe_token() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
portable_hostname() { hostname.exe 2>/dev/null || hostname 2>/dev/null || echo unknown-host; }
portable_whoami() { whoami.exe 2>/dev/null || whoami 2>/dev/null || echo unknown-user; }
command_path() { command -v "$1" 2>/dev/null || true; }

add_target() { local t; t="$(trim "$1")"; [[ -n "$t" ]] && TARGETS+=("$t"); }
add_csv_targets() { local old="$IFS"; IFS=',' read -r -a parts <<< "$1"; IFS="$old"; for p in "${parts[@]}"; do add_target "$p"; done; }
load_targets() { local line; [[ -f "$1" ]] || fail "Target file not found: $1"; while IFS= read -r line || [[ -n "$line" ]]; do line="$(trim "$line")"; [[ -z "$line" || "$line" == \#* ]] && continue; add_target "$line"; done < "$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) [[ $# -ge 2 ]] || fail "--target requires value"; add_target "$2"; shift 2 ;;
    --targets) [[ $# -ge 2 ]] || fail "--targets requires value"; add_csv_targets "$2"; shift 2 ;;
    --target-file) [[ $# -ge 2 ]] || fail "--target-file requires value"; TARGET_FILE="$2"; shift 2 ;;
    --scan-mode) [[ $# -ge 2 ]] || fail "--scan-mode requires value"; SCAN_MODE="$2"; shift 2 ;;
    --ports) [[ $# -ge 2 ]] || fail "--ports requires value"; PORTS="$2"; shift 2 ;;
    --timing) [[ $# -ge 2 ]] || fail "--timing requires value"; TIMING="$2"; shift 2 ;;
    --allow-subnet) ALLOW_SUBNET=1; shift ;;
    --max-targets) [[ $# -ge 2 ]] || fail "--max-targets requires value"; MAX_TARGETS="$2"; shift 2 ;;
    --no-service-detection) NO_SERVICE_DETECTION=1; shift ;;
    --output-root) [[ $# -ge 2 ]] || fail "--output-root requires value"; OUTPUT_ROOT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$TARGET_FILE" ]] && load_targets "$TARGET_FILE"
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=("127.0.0.1")
[[ "$MAX_TARGETS" =~ ^[0-9]+$ ]] || fail "--max-targets must be numeric"
[[ ${#TARGETS[@]} -le "$MAX_TARGETS" ]] || fail "Target count ${#TARGETS[@]} exceeds cap $MAX_TARGETS"
case "$SCAN_MODE" in local-only|ping-only|common-ports|printer-ports|workstation-ports|custom-ports) ;; *) fail "Unsupported scan mode: $SCAN_MODE" ;; esac
case "$TIMING" in safe|normal) ;; *) fail "Unsupported timing: $TIMING" ;; esac

HOST="$(portable_hostname)"
STAMP="$(date +"%Y%m%d_%H%M%S")"
RUN_ID="SAS_NMAP_BASELINE_${HOST}_${STAMP}"
RUN_DIR="$OUTPUT_ROOT/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"; RAW_DIR="$RUN_DIR/raw"; LOCAL_DIR="$RAW_DIR/local"; EXPORT_DIR="$RUN_DIR/exports"
mkdir -p "$LOG_DIR" "$LOCAL_DIR" "$EXPORT_DIR"
EVENT_LOG="$LOG_DIR/events.jsonl"; TRACE_LOG="$LOG_DIR/trace.log"

log_event() {
  local stage="$1" level="$2" msg="$3" data="${4:-}" ts; ts="$(now_iso)"
  printf '{"timestamp":"%s","run_id":"%s","stage":"%s","level":"%s","message":"%s","data":"%s"}\n' \
    "$(json_escape "$ts")" "$(json_escape "$RUN_ID")" "$(json_escape "$stage")" "$(json_escape "$level")" "$(json_escape "$msg")" "$(json_escape "$data")" >> "$EVENT_LOG"
  printf '[%s][%s] %s\n' "$stage" "$level" "$msg" | tee -a "$TRACE_LOG"
}

capture() {
  local label="$1" out="$2"; shift 2
  { echo "# $label"; echo "# command: $*"; echo "# captured_at: $(now_iso)"; echo; } > "$out"
  if [[ "$DRY_RUN" -eq 1 ]]; then echo "DRY RUN" >> "$out"; echo "# exit_code: 0" >> "$out"; return 0; fi
  set +e; "$@" >> "$out" 2>&1; code=$?; set -e
  echo; echo "# exit_code: $code"
  } >> "$out"
}

log_event START INFO "Nmap baseline started"
log_event RECON INFO "Collecting local baseline"

NMAP_BIN="$(command_path nmap.exe)"; [[ -z "$NMAP_BIN" ]] && NMAP_BIN="$(command_path nmap)"
capture hostname "$LOCAL_DIR/hostname.txt" hostname.exe
capture whoami "$LOCAL_DIR/whoami.txt" whoami.exe
capture windows-version "$LOCAL_DIR/windows_version.txt" cmd.exe /c ver
capture ipconfig "$LOCAL_DIR/ipconfig_all.txt" cmd.exe /c ipconfig /all
capture getmac "$LOCAL_DIR/getmac.txt" cmd.exe /c getmac /v /fo list
capture arp "$LOCAL_DIR/arp_a.txt" cmd.exe /c arp -a
capture route "$LOCAL_DIR/route_print.txt" cmd.exe /c route print
capture netsh-interface "$LOCAL_DIR/netsh_interface.txt" cmd.exe /c netsh interface show interface
if [[ -n "$NMAP_BIN" ]]; then capture nmap-version "$LOCAL_DIR/nmap_version.txt" "$NMAP_BIN" --version; else echo "nmap not found" > "$LOCAL_DIR/nmap_version.txt"; fi

log_event DECIDE INFO "Evaluating guardrails"
case "$SCAN_MODE" in
  local-only|ping-only) : ;;
  common-ports) PORTS="22,80,135,139,443,445,3389,5985,5986,9100" ;;
  printer-ports) PORTS="80,443,515,631,9100,161" ;;
  workstation-ports) PORTS="135,139,445,3389,5985,5986" ;;
  custom-ports) [[ -n "$PORTS" ]] || fail "--ports required for custom-ports" ;;
esac

for target in "${TARGETS[@]}"; do
  if [[ "$target" =~ /([0-9]{1,2})$ ]]; then
    [[ "$ALLOW_SUBNET" -eq 1 ]] || fail "CIDR target requires --allow-subnet: $target"
    [[ "${BASH_REMATCH[1]}" -ge 29 ]] || fail "CIDR broader than /29 blocked: $target"
  fi
done

TIMING_ARGS=("-T2" "--max-retries" "2" "--host-timeout" "90s")
[[ "$TIMING" == "normal" ]] && TIMING_ARGS=("-T3" "--max-retries" "3" "--host-timeout" "120s")
SCAN_ARGS=(); WILL_RUN=0; BLOCKED=""
if [[ "$SCAN_MODE" == "local-only" ]]; then BLOCKED="local-only mode";
elif [[ -z "$NMAP_BIN" ]]; then BLOCKED="nmap not found";
else
  WILL_RUN=1
  if [[ "$SCAN_MODE" == "ping-only" ]]; then SCAN_ARGS=("-sn" "${TIMING_ARGS[@]}");
  else
    SCAN_ARGS=("-Pn" "-p" "$PORTS")
    [[ "$NO_SERVICE_DETECTION" -eq 1 ]] || SCAN_ARGS+=("-sV" "--version-light")
    SCAN_ARGS+=("${TIMING_ARGS[@]}")
  fi
fi

cat > "$EXPORT_DIR/run_context.env" <<EOF
run_id=$RUN_ID
hostname=$HOST
user=$(portable_whoami)
scan_mode=$SCAN_MODE
targets=${TARGETS[*]}
nmap_bin=${NMAP_BIN:-NOT_FOUND}
will_run_nmap=$WILL_RUN
blocked_reason=$BLOCKED
EOF

OPEN_CSV="$EXPORT_DIR/open_ports_summary.csv"; INDEX_CSV="$EXPORT_DIR/scan_index.csv"
printf 'target,port_state_line\n' > "$OPEN_CSV"
printf 'target,exit_code,duration_seconds,normal_output,xml_output,stdout_output\n' > "$INDEX_CSV"

if [[ "$WILL_RUN" -eq 1 ]]; then
  for target in "${TARGETS[@]}"; do
    token="$(safe_token "$target")"; normal="$RAW_DIR/nmap_${token}.nmap"; xml="$RAW_DIR/nmap_${token}.xml"; stdout="$RAW_DIR/nmap_${token}.stdout.txt"
    args=("${SCAN_ARGS[@]}" "-oN" "$normal" "-oX" "$xml" "$target")
    log_event ACT INFO "Running Nmap" "target=$target args=${args[*]}"
    start=$(date +%s)
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "DRY RUN: $NMAP_BIN ${args[*]}" > "$stdout"; touch "$normal" "$xml"; code=0; else set +e; "$NMAP_BIN" "${args[@]}" > "$stdout" 2>&1; code=$?; set -e; fi
    dur=$(( $(date +%s) - start ))
    printf '"%s",%s,%s,"%s","%s","%s"\n' "$target" "$code" "$dur" "$normal" "$xml" "$stdout" >> "$INDEX_CSV"
    [[ -s "$normal" ]] && awk -v target="$target" '/^[0-9]+\/(tcp|udp)[[:space:]]+open/ {gsub(/"/,"\"\""); printf "\"%s\",\"%s\"\n", target, $0}' "$normal" >> "$OPEN_CSV"
  done
else
  log_event ACT WARN "Nmap scan skipped" "$BLOCKED"
fi

REPORT="$EXPORT_DIR/baseline_report.md"; JSON="$EXPORT_DIR/baseline_report.json"
cat > "$REPORT" <<EOF
# SysAdminSuite Nmap Baseline Report

| Field | Value |
|---|---|
| Run ID | $RUN_ID |
| Hostname | $HOST |
| User | $(portable_whoami) |
| Scan Mode | $SCAN_MODE |
| Targets | ${TARGETS[*]} |
| Nmap Available | $([[ -n "$NMAP_BIN" ]] && echo true || echo false) |
| Nmap Path | ${NMAP_BIN:-NOT_FOUND} |
| Will Run Nmap | $WILL_RUN |
| Blocked Reason | ${BLOCKED:-none} |

## Artifacts

- Local baseline: \`$LOCAL_DIR\`
- Scan index: \`$INDEX_CSV\`
- Open ports summary: \`$OPEN_CSV\`
- Raw output: \`$RAW_DIR\`
- Event log: \`$EVENT_LOG\`
EOF
cat > "$JSON" <<EOF
{"run_id":"$(json_escape "$RUN_ID")","hostname":"$(json_escape "$HOST")","scan_mode":"$(json_escape "$SCAN_MODE")","targets":"$(json_escape "${TARGETS[*]}")","will_run_nmap":$([[ "$WILL_RUN" -eq 1 ]] && echo true || echo false),"run_dir":"$(json_escape "$RUN_DIR")"}
EOF
log_event EXPORT INFO "Reports exported" "report=$REPORT"
log_event END INFO "Nmap baseline completed" "run_dir=$RUN_DIR"

echo "DONE"
echo "Run Directory: $RUN_DIR"
echo "Report: $REPORT"
