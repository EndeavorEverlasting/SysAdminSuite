#!/usr/bin/env bash
# SysAdminSuite OU/GPO Indicator Collector
# Shape: Recon -> Decide -> Act -> Log -> Export
# Read-only evidence collector. No gpupdate, no AD writes, no registry writes.

set -Eeuo pipefail
OUTPUT_ROOT="${USERPROFILE:-${HOME:-.}}/SysAdminSuite/Runs"
TARGET_HINT="local"
INCLUDE_REGISTRY=1
DRY_RUN=0

usage() { cat <<'EOF'
Usage: bash scripts/sas_ou_gpo_indicators.sh [options]

Options:
  --target-hint <label>     Optional run label/reference host context.
  --output-root <path>      Default: $USERPROFILE/SysAdminSuite/Runs.
  --no-registry             Skip read-only Group Policy registry-state capture.
  --dry-run                 Build command plan without executing evidence commands.
  -h, --help                Show help.
EOF
}
fail() { echo "ERROR: $*" >&2; exit 1; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'; }
csv_escape() { local v="$1"; v="${v//"/""}"; printf '"%s"' "$v"; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
portable_hostname() { hostname.exe 2>/dev/null || hostname 2>/dev/null || echo unknown-host; }
portable_whoami() { whoami.exe 2>/dev/null || whoami 2>/dev/null || echo unknown-user; }
normalize_file() { [[ -f "$1" ]] && tr -d '\r' < "$1" || true; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-hint) [[ $# -ge 2 ]] || fail "--target-hint requires value"; TARGET_HINT="$2"; shift 2 ;;
    --output-root) [[ $# -ge 2 ]] || fail "--output-root requires value"; OUTPUT_ROOT="$2"; shift 2 ;;
    --no-registry) INCLUDE_REGISTRY=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

HOST="$(portable_hostname)"; STAMP="$(date +"%Y%m%d_%H%M%S")"
RUN_ID="SAS_OU_GPO_INDICATORS_${HOST}_${STAMP}"
RUN_DIR="$OUTPUT_ROOT/$RUN_ID"; LOG_DIR="$RUN_DIR/logs"; RAW_DIR="$RUN_DIR/raw"; EXPORT_DIR="$RUN_DIR/exports"
mkdir -p "$LOG_DIR" "$RAW_DIR" "$EXPORT_DIR"
EVENT_LOG="$LOG_DIR/ou_gpo_events.jsonl"; TRACE_LOG="$LOG_DIR/ou_gpo_trace.log"; PLAN="$EXPORT_DIR/command_plan.txt"
INDICATORS="$EXPORT_DIR/ou_gpo_indicators.csv"; SUMMARY="$EXPORT_DIR/ou_gpo_summary.env"; REPORT="$EXPORT_DIR/ou_gpo_report.md"; ACTIONS="$EXPORT_DIR/ou_gpo_recommended_actions.md"; JSON="$EXPORT_DIR/ou_gpo_report.json"
: > "$PLAN"

log_event() {
  local stage="$1" level="$2" msg="$3" data="${4:-}" ts; ts="$(now_iso)"
  printf '{"timestamp":"%s","run_id":"%s","stage":"%s","level":"%s","message":"%s","data":"%s"}\n' \
    "$(json_escape "$ts")" "$(json_escape "$RUN_ID")" "$(json_escape "$stage")" "$(json_escape "$level")" "$(json_escape "$msg")" "$(json_escape "$data")" >> "$EVENT_LOG"
  printf '[%s][%s] %s\n' "$stage" "$level" "$msg" | tee -a "$TRACE_LOG"
}

capture() {
  local label="$1" out="$2"; shift 2
  { echo "# $label"; echo "# command: $*"; echo "# captured_at: $(now_iso)"; echo; } > "$out"
  printf '%s\n' "$*" >> "$PLAN"
  if [[ "$DRY_RUN" -eq 1 ]]; then echo "DRY RUN" >> "$out"; echo "# exit_code: 0" >> "$out"; return 0; fi
  set +e; "$@" >> "$out" 2>&1; code=$?; set -e
  echo; echo "# exit_code: $code"
  } >> "$out"
}

extract_env() { normalize_file "$1" | awk -F '=' -v k="$2" 'tolower($1)==tolower(k){print $2; exit}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true; }
extract_wmic() { normalize_file "$1" | awk -F '=' -v k="$2" 'tolower($1)==tolower(k){print $2; exit}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true; }
extract_dn() { normalize_file "$1" | grep -E '^[[:space:]]*(CN|OU)=[^,]+,.*DC=' | head -n 1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true; }
ou_from_dn() { printf '%s' "$1" | awk -F ',' '{c=0; for(i=1;i<=NF;i++){x=$i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); if(x ~ /^OU=/){sub(/^OU=/,"",x); ou[++c]=x}} for(i=c;i>=1;i--) printf "%s%s", ou[i], (i==1?"":"/") }'; }
first_match() { normalize_file "$1" | grep -E "$2" | head -n 1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true; }

extract_gpos() {
  normalize_file "$1" | awk '
    /Applied Group Policy Objects/ {cap=1; next}
    /The following GPOs were not applied|The computer is a part of|The user is a part of|Resultant Set Of Policies/ {cap=0}
    cap==1 {line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if(line!="" && line!~ /^[-]+$/ && line!~ /^N\/A$/) print line}' | sort -u || true
}
extract_groups() {
  { normalize_file "$1"; normalize_file "$2"; normalize_file "$3" | awk -F ':' '/Group Name/ {print $2}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; } \
    | awk 'NF' | sort -u || true
}
write_indicator() { csv_escape "$1" >> "$INDICATORS"; printf ',' >> "$INDICATORS"; csv_escape "$2" >> "$INDICATORS"; printf ',' >> "$INDICATORS"; csv_escape "$3" >> "$INDICATORS"; printf ',' >> "$INDICATORS"; csv_escape "$4" >> "$INDICATORS"; printf ',' >> "$INDICATORS"; csv_escape "$5" >> "$INDICATORS"; printf '\n' >> "$INDICATORS"; }

log_event START INFO "OU/GPO indicator collector started" "target_hint=$TARGET_HINT"
log_event RECON INFO "Collecting raw evidence"

capture hostname "$RAW_DIR/hostname.txt" hostname.exe
capture whoami "$RAW_DIR/whoami.txt" whoami.exe
capture whoami-user "$RAW_DIR/whoami_user.txt" whoami.exe /user /fo list
capture whoami-groups "$RAW_DIR/whoami_groups.txt" whoami.exe /groups /fo list
capture whoami-fqdn "$RAW_DIR/whoami_fqdn.txt" whoami.exe /fqdn
capture environment "$RAW_DIR/environment_set.txt" cmd.exe /c set
capture computer-domain "$RAW_DIR/wmic_computersystem_domain.txt" wmic.exe computersystem get domain,partofdomain /format:list
capture gpresult-computer "$RAW_DIR/gpresult_computer.txt" gpresult.exe /r /scope computer
capture gpresult-user "$RAW_DIR/gpresult_user.txt" gpresult.exe /r /scope user
USERDNSDOMAIN="$(extract_env "$RAW_DIR/environment_set.txt" USERDNSDOMAIN)"
if [[ -n "$USERDNSDOMAIN" ]]; then capture nltest "$RAW_DIR/nltest_dsgetdc.txt" nltest.exe "/dsgetdc:$USERDNSDOMAIN"; else echo "USERDNSDOMAIN unavailable" > "$RAW_DIR/nltest_dsgetdc.txt"; fi
if [[ "$INCLUDE_REGISTRY" -eq 1 ]]; then
  capture gp-reg-machine "$RAW_DIR/reg_gp_state_machine.txt" reg.exe query "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\State\\Machine" /s
  capture gp-reg-user "$RAW_DIR/reg_gp_state_user.txt" reg.exe query "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\State" /s
else
  echo "Registry capture skipped" > "$RAW_DIR/reg_gp_state_machine.txt"; echo "Registry capture skipped" > "$RAW_DIR/reg_gp_state_user.txt"
fi

log_event DECIDE INFO "Parsing indicators"
DOMAIN="$(extract_wmic "$RAW_DIR/wmic_computersystem_domain.txt" Domain)"
PART="$(extract_wmic "$RAW_DIR/wmic_computersystem_domain.txt" PartOfDomain)"
USERDOMAIN="$(extract_env "$RAW_DIR/environment_set.txt" USERDOMAIN)"
LOGONSERVER="$(extract_env "$RAW_DIR/environment_set.txt" LOGONSERVER)"
COMP_DN="$(extract_dn "$RAW_DIR/gpresult_computer.txt")"
USER_DN="$(extract_dn "$RAW_DIR/whoami_fqdn.txt")"
COMP_OU="$(ou_from_dn "$COMP_DN")"; USER_OU="$(ou_from_dn "$USER_DN")"
DC_HINT="$(first_match "$RAW_DIR/gpresult_computer.txt" 'Group Policy was applied from|Group Policy was applied from:')"
[[ -z "$DC_HINT" ]] && DC_HINT="$(first_match "$RAW_DIR/nltest_dsgetdc.txt" 'DC:|Address:|Dom Name:')"
POSTURE="unknown"; [[ "${PART,,}" == true ]] && POSTURE="domain_joined"; [[ "${PART,,}" == false ]] && POSTURE="not_domain_joined_or_unavailable"

COMP_GPOS="$EXPORT_DIR/applied_computer_gpos.txt"; USER_GPOS="$EXPORT_DIR/applied_user_gpos.txt"; GROUPS="$EXPORT_DIR/security_groups.txt"
extract_gpos "$RAW_DIR/gpresult_computer.txt" > "$COMP_GPOS"
extract_gpos "$RAW_DIR/gpresult_user.txt" > "$USER_GPOS"
extract_groups "$RAW_DIR/gpresult_computer.txt" "$RAW_DIR/gpresult_user.txt" "$RAW_DIR/whoami_groups.txt" > "$GROUPS"
COMP_GPO_COUNT=$(grep -cve '^$' "$COMP_GPOS" || true); USER_GPO_COUNT=$(grep -cve '^$' "$USER_GPOS" || true); GROUP_COUNT=$(grep -cve '^$' "$GROUPS" || true)

log_event ACT INFO "Writing indicators"
printf 'indicator,value,confidence,source,note\n' > "$INDICATORS"
write_indicator hostname "$HOST" high hostname.exe "Local computer name."
write_indicator target_hint "$TARGET_HINT" medium operator "Run label, not authoritative."
write_indicator current_user "$(portable_whoami)" high whoami.exe "Current security context."
write_indicator domain_posture "$POSTURE" medium "wmic computersystem" "Best-effort local posture."
write_indicator domain "${DOMAIN:-${USERDNSDOMAIN:-unknown}}" medium "wmic/environment" "WMIC first, environment fallback."
write_indicator user_domain "${USERDOMAIN:-unknown}" medium environment "USERDOMAIN value."
write_indicator user_dns_domain "${USERDNSDOMAIN:-unknown}" medium environment "USERDNSDOMAIN value."
write_indicator logon_server "${LOGONSERVER:-unknown}" medium environment "Logon server hint."
write_indicator domain_controller_indicator "${DC_HINT:-unknown}" medium "gpresult/nltest" "Best-effort DC source hint."
write_indicator computer_distinguished_name "${COMP_DN:-unknown}" medium gpresult "Computer DN if exposed."
write_indicator computer_ou_path_hint "${COMP_OU:-unknown}" medium parsed_dn "Computer OU hint, not AD truth."
write_indicator user_distinguished_name "${USER_DN:-unknown}" medium "whoami /fqdn" "User DN, not computer OU."
write_indicator user_ou_path_hint "${USER_OU:-unknown}" medium parsed_dn "Keep separate from computer OU."
write_indicator applied_computer_gpo_count "$COMP_GPO_COUNT" medium gpresult "Parsed applied computer GPO count."
write_indicator applied_user_gpo_count "$USER_GPO_COUNT" medium gpresult "Parsed applied user GPO count."
write_indicator security_group_count "$GROUP_COUNT" low "gpresult/whoami" "Noisy, advisory only."

cat > "$SUMMARY" <<EOF
run_id=$RUN_ID
hostname=$HOST
target_hint=$TARGET_HINT
current_user=$(portable_whoami)
domain_posture=$POSTURE
domain=${DOMAIN:-${USERDNSDOMAIN:-unknown}}
user_domain=${USERDOMAIN:-unknown}
user_dns_domain=${USERDNSDOMAIN:-unknown}
logon_server=${LOGONSERVER:-unknown}
domain_controller_indicator=${DC_HINT:-unknown}
computer_distinguished_name=${COMP_DN:-unknown}
computer_ou_path_hint=${COMP_OU:-unknown}
user_distinguished_name=${USER_DN:-unknown}
user_ou_path_hint=${USER_OU:-unknown}
applied_computer_gpo_count=$COMP_GPO_COUNT
applied_user_gpo_count=$USER_GPO_COUNT
security_group_count=$GROUP_COUNT
EOF

log_event EXPORT INFO "Writing reports"
cat > "$REPORT" <<EOF
# SysAdminSuite OU/GPO Indicator Report

| Field | Value |
|---|---|
| Run ID | $RUN_ID |
| Hostname | $HOST |
| Current User | $(portable_whoami) |
| Target Hint | $TARGET_HINT |
| Domain Posture | $POSTURE |
| Domain | ${DOMAIN:-${USERDNSDOMAIN:-unknown}} |
| Logon Server | ${LOGONSERVER:-unknown} |
| Computer OU Path Hint | ${COMP_OU:-unknown} |
| User OU Path Hint | ${USER_OU:-unknown} |
| Applied Computer GPO Count | $COMP_GPO_COUNT |
| Applied User GPO Count | $USER_GPO_COUNT |

## Artifacts

- Indicators: \`$INDICATORS\`
- Summary: \`$SUMMARY\`
- Applied computer GPOs: \`$COMP_GPOS\`
- Applied user GPOs: \`$USER_GPOS\`
- Security groups: \`$GROUPS\`
- Raw evidence: \`$RAW_DIR\`
EOF
cat > "$ACTIONS" <<EOF
# OU/GPO Recommended Actions

- Compare target evidence against a known-good reference host.
- Keep computer OU and user OU separate.
- If computer OU path is missing, review raw gpresult and authorized AD/ServiceNow tooling.
- Do not run gpupdate or mutate policy from this collector.
- Treat incomplete evidence as incomplete evidence, not product failure.
EOF
cat > "$JSON" <<EOF
{"run_id":"$(json_escape "$RUN_ID")","hostname":"$(json_escape "$HOST")","domain_posture":"$(json_escape "$POSTURE")","computer_ou_path_hint":"$(json_escape "${COMP_OU:-unknown}")","user_ou_path_hint":"$(json_escape "${USER_OU:-unknown}")","run_dir":"$(json_escape "$RUN_DIR")"}
EOF
log_event END INFO "OU/GPO indicator collector completed" "run_dir=$RUN_DIR"
echo "DONE"
echo "Run Directory: $RUN_DIR"
echo "Report: $REPORT"
