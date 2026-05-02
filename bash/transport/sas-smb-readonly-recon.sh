#!/usr/bin/env bash
# SysAdminSuite SMB read-only recon adapter
# Purpose: verify approved admin-share reachability and optionally list/read approved evidence paths.
# No writes. No staging. No scheduled tasks. No deletion.

set -euo pipefail

TARGETS=()
TARGET_FILE=""
OUTPUT="bash/transport/output/smb_readonly_recon.csv"
TIMEOUT=8
SHARE="C$"
APPROVED_PATHS="ProgramData/SysAdminSuite,ProgramData/SysAdminSuite/Mapping,ProgramData/SysAdminSuite/Mapping/logs"
ALLOW_LIST=0
ALLOW_READ=0
SMB_USER=""
SMB_PASS=""
SMB_DOMAIN=""
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite SMB Read-Only Recon

Usage:
  ./bash/transport/sas-smb-readonly-recon.sh [options] TARGET...

Options:
  --target VALUE        Add hostname/IP target
  --targets-file PATH   TXT/CSV-ish file with targets, one per line or first comma field
  --output PATH         Output CSV path
  --timeout SEC         SMB command timeout. Default: 8
  --share NAME          SMB share. Default: C$
  --approved-paths CSV  Approved paths under the share to inspect
  --allow-list          Permit directory listing of approved paths
  --allow-read          Permit read-only fetch test of files under approved paths when explicitly listed later
  --smb-user USER       Optional SMB username. Prefer SAS_SMB_USER
  --smb-pass PASS       Optional SMB password. Prefer SAS_SMB_PASS
  --smb-domain DOMAIN   Optional SMB domain. Prefer SAS_SMB_DOMAIN
  --pass-thru           Print CSV after writing
  -h, --help            Show help

Environment variables:
  SAS_SMB_USER
  SAS_SMB_PASS
  SAS_SMB_DOMAIN

Output columns:
  Timestamp,Target,Share,ApprovedPath,Reachable,ListStatus,ReadStatus,Evidence,ReconStatus,Notes

Safety:
  - Read-only.
  - Does not create directories.
  - Does not copy files to the target.
  - Does not create scheduled tasks.
  - Does not delete or modify remote files.
  - Credentials are not written to output.

Known limitations:
  - Requires smbclient.
  - Admin shares may be disabled or blocked by firewall/policy.
  - Listing may be denied even when the host is online.
  - Read checks are intentionally conservative in this first adapter.
USAGE
}

fail(){ printf '[smb-recon] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[smb-recon] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
trim(){ local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
csv_escape(){ local s="${1:-}"; s="${s//"/""}"; printf '"%s"' "$s"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGETS+=("${2:?missing value for --target}"); shift 2 ;;
    --targets-file) TARGET_FILE="${2:?missing value for --targets-file}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --share) SHARE="${2:?missing value for --share}"; shift 2 ;;
    --approved-paths) APPROVED_PATHS="${2:?missing value for --approved-paths}"; shift 2 ;;
    --allow-list) ALLOW_LIST=1; shift ;;
    --allow-read) ALLOW_READ=1; shift ;;
    --smb-user) SMB_USER="${2:?missing value for --smb-user}"; shift 2 ;;
    --smb-pass) SMB_PASS="${2:?missing value for --smb-pass}"; shift 2 ;;
    --smb-domain) SMB_DOMAIN="${2:?missing value for --smb-domain}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done ;;
    -*) fail "Unknown option: $1" ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

SMB_USER="${SMB_USER:-${SAS_SMB_USER:-}}"
SMB_PASS="${SMB_PASS:-${SAS_SMB_PASS:-}}"
SMB_DOMAIN="${SMB_DOMAIN:-${SAS_SMB_DOMAIN:-}}"
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 ]] || fail "--timeout must be positive integer"
if [[ -n "$TARGET_FILE" ]]; then
  [[ -f "$TARGET_FILE" ]] || fail "targets file not found: $TARGET_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"; [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line%%,*}"; line="$(trim "$line")"; [[ -n "$line" ]] && TARGETS+=("$line")
  done < "$TARGET_FILE"
fi
[[ ${#TARGETS[@]} -gt 0 ]] || fail "No targets provided"
mkdir -p "$(dirname "$OUTPUT")"
IFS=',' read -r -a PATH_ARRAY <<< "$APPROVED_PATHS"

smb_auth_args(){
  local args=()
  if [[ -n "$SMB_USER" ]]; then
    args+=(-U "${SMB_USER}%${SMB_PASS}")
  else
    args+=(-N)
  fi
  [[ -n "$SMB_DOMAIN" ]] && args+=(-W "$SMB_DOMAIN")
  printf '%s\0' "${args[@]}"
}

run_smb(){
  local target="$1" command="$2" args=() part
  if ! has_cmd smbclient; then printf 'SMBCLIENT_MISSING'; return 127; fi
  while IFS= read -r -d '' part; do args+=("$part"); done < <(smb_auth_args)
  if has_cmd timeout; then
    timeout "$TIMEOUT" smbclient "//$target/$SHARE" "${args[@]}" -c "$command" 2>&1 || true
  else
    smbclient "//$target/$SHARE" "${args[@]}" -c "$command" 2>&1 || true
  fi
}

classify(){
  local out="$1"
  if [[ "$out" == "SMBCLIENT_MISSING" ]]; then printf 'ClientMissing'; return; fi
  if printf '%s' "$out" | grep -Eiq 'NT_STATUS_ACCESS_DENIED|LOGON_FAILURE|Authentication'; then printf 'AccessDenied'; return; fi
  if printf '%s' "$out" | grep -Eiq 'NT_STATUS_BAD_NETWORK_NAME|NT_STATUS_HOST_UNREACHABLE|Connection.*failed|timed out|NT_STATUS_IO_TIMEOUT'; then printf 'UnreachableOrBlocked'; return; fi
  if printf '%s' "$out" | grep -Eiq 'NT_STATUS_OBJECT_NAME_NOT_FOUND|No such file|ERRDOS'; then printf 'PathMissing'; return; fi
  if printf '%s' "$out" | grep -Eiq 'blocks of size|Disk|\s+D\s+|\s+A\s+'; then printf 'OK'; return; fi
  printf 'Unknown'
}

{
  printf 'Timestamp,Target,Share,ApprovedPath,Reachable,ListStatus,ReadStatus,Evidence,ReconStatus,Notes\n'
  for target in "${TARGETS[@]}"; do
    for raw_path in "${PATH_ARRAY[@]}"; do
      path="$(trim "$raw_path")"; [[ -z "$path" ]] && continue
      path="${path//\\//}"
      path="${path#/}"
      path="${path%/}"
      reachable="NotChecked"; list_status="Skipped"; read_status="Skipped"; evidence=""; notes=()
      if [[ "$ALLOW_LIST" -eq 1 ]]; then
        cmd="cd \"$path\"; dir"
      else
        cmd="cd \"$path\"; pwd"
      fi
      out="$(run_smb "$target" "$cmd")"
      status="$(classify "$out")"
      case "$status" in
        OK) reachable="Yes"; list_status=$([[ "$ALLOW_LIST" -eq 1 ]] && printf 'Listed' || printf 'PathReachable') ;;
        ClientMissing) reachable="Unknown"; list_status="NotChecked"; notes+=("smbclient not installed") ;;
        AccessDenied) reachable="Unknown"; list_status="AccessDenied"; notes+=("SMB/auth denied") ;;
        UnreachableOrBlocked) reachable="No"; list_status="UnreachableOrBlocked"; notes+=("SMB blocked or host unreachable") ;;
        PathMissing) reachable="Yes"; list_status="PathMissing"; notes+=("Approved path missing") ;;
        *) reachable="Unknown"; list_status="Unknown"; notes+=("Unclassified smbclient response") ;;
      esac
      if [[ "$ALLOW_LIST" -eq 1 && "$status" == "OK" ]]; then
        evidence="$(printf '%s' "$out" | sed -E 's/[[:cntrl:]]//g' | head -n 12 | paste -sd ' ' - | cut -c1-240)"
      fi
      if [[ "$ALLOW_READ" -eq 1 ]]; then
        read_status="DeferredNoFileSpecified"
        notes+=("Read mode requires a future explicit file allowlist; not implemented as broad read")
      fi
      recon="ReviewRequired"
      [[ "$list_status" == "Listed" || "$list_status" == "PathReachable" ]] && recon="EvidencePathReachable"
      [[ "$list_status" == "AccessDenied" ]] && recon="NeedsApprovedCredentialsOrPolicy"
      [[ "$list_status" == "UnreachableOrBlocked" ]] && recon="SMBUnavailable"
      [[ "$list_status" == "PathMissing" ]] && recon="EvidencePathMissing"
      csv_escape "$(date '+%Y-%m-%d %H:%M:%S')"; printf ','; csv_escape "$target"; printf ','; csv_escape "$SHARE"; printf ','; csv_escape "$path"; printf ','; csv_escape "$reachable"; printf ','; csv_escape "$list_status"; printf ','; csv_escape "$read_status"; printf ','; csv_escape "$evidence"; printf ','; csv_escape "$recon"; printf ','; csv_escape "$(IFS='; '; echo "${notes[*]:-}")"; printf '\n'
    done
  done
} > "$OUTPUT"
log "Wrote SMB read-only recon CSV: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
