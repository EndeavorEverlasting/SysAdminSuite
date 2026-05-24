#!/usr/bin/env bash
# SysAdminSuite QR Field Command Capsule Launcher
#
# Core model:
#   QR -> profile -> approved survey lane -> evidence package
#
# A QR code should contain a short launcher command, not a giant script body.
# Example:
#   bash scripts/sas_qr_run.sh --profile neuron-hostname-survey --dry-run

set -Eeuo pipefail

PROFILE_ID=""
PROFILE_DIR="profiles"
OUTPUT_ROOT="${USERPROFILE:-${HOME:-.}}/SysAdminSuite/Runs"
DRY_RUN=0
PASSTHROUGH_ARGS=()

usage() {
  cat <<'EOF'
SysAdminSuite QR Field Command Capsule Launcher

Usage:
  bash scripts/sas_qr_run.sh --profile <profile-id> [options] [-- survey args]

Options:
  --profile <id>          Required. Example: neuron-hostname-survey
  --profile-dir <path>    Default: profiles
  --output-root <path>    Default: $USERPROFILE/SysAdminSuite/Runs
  --dry-run               Pass dry-run through to the survey lane.
  -h, --help              Show help.

Example QR payload:
  bash scripts/sas_qr_run.sh --profile neuron-hostname-survey --dry-run

Example with survey arguments:
  bash scripts/sas_qr_run.sh --profile neuron-hostname-survey -- --manifest GetInfo/Config/NeuronTargets.unresolved.csv --nmap-xml survey/artifacts/site_neuron_discovery.xml
EOF
}

fail() { echo "ERROR: $*" >&2; exit 1; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'; }
portable_hostname() { hostname.exe 2>/dev/null || hostname 2>/dev/null || echo unknown-host; }
portable_whoami() { whoami.exe 2>/dev/null || whoami 2>/dev/null || echo unknown-user; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || fail "--profile requires a value"
      PROFILE_ID="$2"
      shift 2
      ;;
    --profile-dir)
      [[ $# -ge 2 ]] || fail "--profile-dir requires a value"
      PROFILE_DIR="$2"
      shift 2
      ;;
    --output-root)
      [[ $# -ge 2 ]] || fail "--output-root requires a value"
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      PASSTHROUGH_ARGS+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      PASSTHROUGH_ARGS+=("$1")
      shift
      ;;
  esac
done

[[ -n "$PROFILE_ID" ]] || fail "--profile is required"
[[ "$PROFILE_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "Profile id contains unsafe characters: $PROFILE_ID"

PROFILE_PATH="$PROFILE_DIR/$PROFILE_ID.profile"
[[ -f "$PROFILE_PATH" ]] || fail "Profile not found: $PROFILE_PATH"

HOST="$(portable_hostname)"
STAMP="$(date +"%Y%m%d_%H%M%S")"
RUN_ID="SAS_QR_FIELD_CAPSULE_${PROFILE_ID}_${HOST}_${STAMP}"
RUN_DIR="$OUTPUT_ROOT/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
EXPORT_DIR="$RUN_DIR/exports"
mkdir -p "$LOG_DIR" "$EXPORT_DIR"
EVENT_LOG="$LOG_DIR/qr_capsule_events.jsonl"
TRACE_LOG="$LOG_DIR/qr_capsule_trace.log"
PROFILE_SNAPSHOT="$EXPORT_DIR/profile.snapshot"
CAPSULE_SUMMARY="$EXPORT_DIR/qr_capsule_summary.md"

log_event() {
  local stage="$1" level="$2" msg="$3" data="${4:-}" ts
  ts="$(now_iso)"
  printf '{"timestamp":"%s","run_id":"%s","stage":"%s","level":"%s","message":"%s","data":"%s"}\n' \
    "$(json_escape "$ts")" \
    "$(json_escape "$RUN_ID")" \
    "$(json_escape "$stage")" \
    "$(json_escape "$level")" \
    "$(json_escape "$msg")" \
    "$(json_escape "$data")" >> "$EVENT_LOG"
  printf '[%s][%s] %s\n' "$stage" "$level" "$msg" | tee -a "$TRACE_LOG"
}

get_profile_value() {
  local key="$1"
  awk -F '=' -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    NF >= 2 {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      if ($1 == k) {
        $1=""
        sub(/^=/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }' "$PROFILE_PATH"
}

log_event START INFO "QR field command capsule started" "profile=$PROFILE_ID"

cp "$PROFILE_PATH" "$PROFILE_SNAPSHOT"
SCRIPT_PATH="$(get_profile_value script)"
PROFILE_ID_DECLARED="$(get_profile_value profile_id)"
MUTATION_ALLOWED="$(get_profile_value mutation_allowed)"
REQUIRES_MANIFEST="$(get_profile_value requires_manifest)"
REQUIRES_NMAP="$(get_profile_value requires_nmap)"

[[ "$PROFILE_ID_DECLARED" == "$PROFILE_ID" ]] || fail "Profile id mismatch: requested $PROFILE_ID but file declares $PROFILE_ID_DECLARED"
[[ -n "$SCRIPT_PATH" ]] || fail "Profile missing script= entry"
[[ -f "$SCRIPT_PATH" ]] || fail "Profile script not found: $SCRIPT_PATH"
[[ "${MUTATION_ALLOWED,,}" == "false" ]] || fail "QR field command capsules must be non-mutating by default. Profile mutation_allowed must be false."

log_event RECON INFO "Field capsule context captured" "host=$HOST user=$(portable_whoami) profile=$PROFILE_ID"
log_event DECIDE INFO "Profile validated" "script=$SCRIPT_PATH requires_manifest=$REQUIRES_MANIFEST requires_nmap=$REQUIRES_NMAP"

SURVEY_ARGS=("--output-root" "$OUTPUT_ROOT")
if [[ "$DRY_RUN" -eq 1 ]]; then
  SURVEY_ARGS+=("--dry-run")
fi
SURVEY_ARGS+=("${PASSTHROUGH_ARGS[@]}")

log_event ACT INFO "Launching approved survey lane" "script=$SCRIPT_PATH args=${SURVEY_ARGS[*]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  bash "$SCRIPT_PATH" "${SURVEY_ARGS[@]}" | tee "$LOG_DIR/survey_stdout.txt"
else
  bash "$SCRIPT_PATH" "${SURVEY_ARGS[@]}" | tee "$LOG_DIR/survey_stdout.txt"
fi
SURVEY_EXIT=${PIPESTATUS[0]}

if [[ "$SURVEY_EXIT" -ne 0 ]]; then
  log_event END ERROR "Survey lane failed" "exit_code=$SURVEY_EXIT"
  exit "$SURVEY_EXIT"
fi

cat > "$CAPSULE_SUMMARY" <<EOF
# QR Field Command Capsule Summary

## Capsule

| Field | Value |
|---|---|
| Run ID | $RUN_ID |
| Profile | $PROFILE_ID |
| Host | $HOST |
| User | $(portable_whoami) |
| Started | $STAMP |
| Profile Snapshot | \`$PROFILE_SNAPSHOT\` |
| Survey Script | \`$SCRIPT_PATH\` |
| Dry Run | $DRY_RUN |

## Core Insight

A QR code in SysAdminSuite is a **field command capsule**.

It launches a governed profile that can survey a whole operational target set, such as Neurons, not just run a one-off local shortcut.

## Evidence

| Artifact | Path |
|---|---|
| Capsule Events | \`$EVENT_LOG\` |
| Capsule Trace | \`$TRACE_LOG\` |
| Survey Stdout | \`$LOG_DIR/survey_stdout.txt\` |

EOF

log_event EXPORT INFO "QR field command capsule summary exported" "summary=$CAPSULE_SUMMARY"
log_event END INFO "QR field command capsule completed" "run_dir=$RUN_DIR"

echo "DONE"
echo "QR Capsule Run Directory: $RUN_DIR"
echo "QR Capsule Summary: $CAPSULE_SUMMARY"
