#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PS_SCRIPT="$REPO_ROOT/scripts/Invoke-SasAutoLogonStateDelta.ps1"

MODE=""
MANIFEST=""
COMPUTER=""
RUN_ID=""
OUTPUT_ROOT=""
TECHNICIAN_LABEL=""
MAX_TARGETS="25"
FIXTURE_MODE=0

usage() {
  cat <<'USAGE'
Usage:
  bash survey/sas-autologon-state-delta.sh --mode before|after|assess [options]

Options:
  --manifest <csv>             Approved target CSV with ComputerName, HostName, Hostname, or Target.
  --computer <hostname>        One explicit workstation. Use --manifest for batches.
  --run-id <id>                Required for after mode; reuse the before run ID.
  --output-root <path>         Approved local SysAdminSuite output root.
  --technician-label <text>    Assignment label only; does not prove actor identity.
  --max-targets <1-25>         Bounded target cap. Default: 25.
  --fixture-mode               Offline synthetic proof; performs no network activity.
  -h, --help                   Show this help.

Examples:
  bash survey/sas-autologon-state-delta.sh \
    --mode before \
    --manifest targets/local/autologon-pilot.csv \
    --technician-label "Pilot batch A"

  bash survey/sas-autologon-state-delta.sh \
    --mode after \
    --run-id autologon-delta-20260713-170000-1a2b3c4d \
    --manifest targets/local/autologon-pilot.csv \
    --technician-label "Pilot batch A"
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

resolve_powershell() {
  local candidate
  for candidate in pwsh.exe powershell.exe pwsh powershell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

to_windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --manifest)
      MANIFEST="${2:-}"
      shift 2
      ;;
    --computer)
      COMPUTER="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --output-root)
      OUTPUT_ROOT="${2:-}"
      shift 2
      ;;
    --technician-label)
      TECHNICIAN_LABEL="${2:-}"
      shift 2
      ;;
    --max-targets)
      MAX_TARGETS="${2:-}"
      shift 2
      ;;
    --fixture-mode)
      FIXTURE_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

case "${MODE,,}" in
  before) PS_MODE="Before" ;;
  after)  PS_MODE="After" ;;
  assess) PS_MODE="Assess" ;;
  *) fail "--mode must be before, after, or assess" ;;
esac

[[ -f "$PS_SCRIPT" ]] || fail "PowerShell collector not found: $PS_SCRIPT"
[[ "$MAX_TARGETS" =~ ^[0-9]+$ ]] || fail "--max-targets must be an integer"
(( MAX_TARGETS >= 1 && MAX_TARGETS <= 25 )) || fail "--max-targets must be between 1 and 25"

if [[ -n "$MANIFEST" && -n "$COMPUTER" ]]; then
  fail "Use either --manifest or --computer, not both"
fi
if [[ -z "$MANIFEST" && -z "$COMPUTER" && "$PS_MODE" != "After" ]]; then
  fail "Supply --manifest or --computer"
fi
if [[ "$PS_MODE" == "After" && -z "$RUN_ID" ]]; then
  fail "after mode requires --run-id from the before capture"
fi
if [[ -n "$MANIFEST" && ! -f "$MANIFEST" ]]; then
  fail "Manifest not found: $MANIFEST"
fi

PS_EXE="$(resolve_powershell)" || fail "PowerShell 5.1+ or PowerShell 7 was not found"
PS_SCRIPT_WIN="$(to_windows_path "$PS_SCRIPT")"

args=(-NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN" -Mode "$PS_MODE" -MaxTargets "$MAX_TARGETS")

if [[ -n "$MANIFEST" ]]; then
  args+=(-TargetsCsv "$(to_windows_path "$MANIFEST")")
fi
if [[ -n "$COMPUTER" ]]; then
  args+=(-ComputerName "$COMPUTER")
fi
if [[ -n "$RUN_ID" ]]; then
  args+=(-RunId "$RUN_ID")
fi
if [[ -n "$OUTPUT_ROOT" ]]; then
  args+=(-OutputRoot "$(to_windows_path "$OUTPUT_ROOT")")
fi
if [[ -n "$TECHNICIAN_LABEL" ]]; then
  args+=(-TechnicianLabel "$TECHNICIAN_LABEL")
fi
if [[ "$FIXTURE_MODE" -eq 1 ]]; then
  args+=(-FixtureMode)
fi

exec "$PS_EXE" "${args[@]}"
