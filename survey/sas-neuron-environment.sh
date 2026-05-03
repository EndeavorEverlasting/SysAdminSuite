#!/usr/bin/env bash
set -euo pipefail

# SysAdminSuite - Bash-on-Windows Neuron Environment Survey
# Purpose: probe local network context and one target hostname/IP without using PowerShell.

TARGET=""
OUTPUT_DIR="logs"
OUTPUT_FILE=""
NO_LOG=0

usage() {
  cat <<'USAGE'
Usage:
  bash survey/sas-neuron-environment.sh --target <hostname-or-ip> [--output-dir <dir>] [--output-file <file>] [--no-log]

Description:
  Read-only Bash-on-Windows environment survey for Neuron/Cybernet field checks.
  Runs Windows-native commands from Bash. Does not require PowerShell.

Options:
  --target <value>     Neuron/Cybernet hostname or IP to probe. Required.
  --output-dir <dir>   Directory for timestamped log output. Default: logs
  --output-file <file> Exact output file path. Overrides --output-dir.
  --no-log            Print to console only.
  -h, --help          Show help.

Examples:
  bash survey/sas-neuron-environment.sh --target WNH270OPR123
  bash survey/sas-neuron-environment.sh --target 10.10.10.25 --output-dir logs/nsuh
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
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

if [[ -z "$TARGET" ]]; then
  echo "ERROR: --target is required." >&2
  usage >&2
  exit 2
fi

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

safe_name() {
  echo "$1" | tr -c 'A-Za-z0-9._-' '_'
}

print_survey() {
  echo "======================================"
  echo " SysAdminSuite - Neuron Environment Survey"
  echo "======================================"
  echo "Runtime: Bash-on-Windows"
  echo "Target: $TARGET"
  echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

  require_command cmd.exe || true
  require_command hostname.exe || true
  require_command ping.exe || true
  require_command nslookup.exe || true

  run_probe "Local Hostname" hostname.exe
  run_probe "Current User" cmd.exe /c whoami
  run_probe "Local IP Configuration" cmd.exe /c ipconfig /all
  run_probe "Local MAC Address Survey" cmd.exe /c getmac /v /fo list
  run_probe "Ping Target: $TARGET" ping.exe -n 4 "$TARGET"
  run_probe "DNS Lookup: $TARGET" nslookup.exe "$TARGET"
  run_probe "ARP Table After Probe" cmd.exe /c arp -a
  run_probe "Route Table" cmd.exe /c route print
  run_probe "Network Interfaces" cmd.exe /c netsh interface show interface

  echo
  echo "Neuron environment survey complete."
}

if [[ "$NO_LOG" -eq 1 ]]; then
  print_survey
  exit 0
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  TARGET_SAFE="$(safe_name "$TARGET")"
  OUTPUT_FILE="$OUTPUT_DIR/neuron_environment_${TARGET_SAFE}_$(date +%Y%m%d_%H%M%S).txt"
else
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

print_survey | tee "$OUTPUT_FILE"
echo
echo "Saved survey log: $OUTPUT_FILE"
