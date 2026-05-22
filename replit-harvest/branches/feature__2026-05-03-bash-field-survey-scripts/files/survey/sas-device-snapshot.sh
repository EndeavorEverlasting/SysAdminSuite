#!/usr/bin/env bash
set -euo pipefail

# SysAdminSuite - Bash-on-Windows Device Snapshot
# Purpose: collect a quick read-only local workstation/network snapshot using Windows-native probes.

OUTPUT_DIR="logs"
OUTPUT_FILE=""
NO_LOG=0

usage() {
  cat <<'USAGE'
Usage:
  bash survey/sas-device-snapshot.sh [--output-dir <dir>] [--output-file <file>] [--no-log]

Description:
  Read-only Bash-on-Windows snapshot for field technicians.
  Runs Windows-native commands from Bash. Does not require PowerShell.

Options:
  --output-dir <dir>   Directory for timestamped log output. Default: logs
  --output-file <file> Exact output file path. Overrides --output-dir.
  --no-log            Print to console only.
  -h, --help          Show help.

Examples:
  bash survey/sas-device-snapshot.sh
  bash survey/sas-device-snapshot.sh --output-dir logs/nsuh
  bash survey/sas-device-snapshot.sh --output-file logs/device_survey.txt
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --output-file)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --no-log)
      NO_LOG=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "WARN: Required command not found in PATH: $command_name"
    return 1
  fi
  return 0
}

run_probe() {
  local title="$1"
  shift

  echo
  echo "======================================"
  echo "$title"
  echo "======================================"

  if "$@"; then
    return 0
  fi

  local exit_code=$?
  echo "WARN: Probe failed with exit code $exit_code: $*"
  return 0
}

print_snapshot() {
  echo "======================================"
  echo " SysAdminSuite - Device Snapshot"
  echo "======================================"
  echo "Runtime: Bash-on-Windows"
  echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

  require_command cmd.exe || true
  require_command hostname.exe || true
  require_command ping.exe || true
  require_command nslookup.exe || true

  run_probe "Hostname" hostname.exe
  run_probe "Current User" cmd.exe /c whoami
  run_probe "IP Configuration" cmd.exe /c ipconfig /all
  run_probe "MAC Address Survey" cmd.exe /c getmac /v /fo list
  run_probe "ARP Table" cmd.exe /c arp -a
  run_probe "Route Table" cmd.exe /c route print
  run_probe "Network Interfaces" cmd.exe /c netsh interface show interface
  run_probe "IP Interface Config" cmd.exe /c netsh interface ip show config

  echo
  echo "Survey complete."
}

if [[ "$NO_LOG" -eq 1 ]]; then
  print_snapshot
  exit 0
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/device_snapshot_$(date +%Y%m%d_%H%M%S).txt"
else
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

print_snapshot | tee "$OUTPUT_FILE"
echo
echo "Saved survey log: $OUTPUT_FILE"
