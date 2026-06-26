#!/usr/bin/env bash
# Write dashboard/toolbox-status.json from sas-probe-toolbox.sh output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${REPO_ROOT}/dashboard/toolbox-status.json"
DRY_RUN=0
UPDATE_STATE="${SAS_UPDATE_STATE:-}"
UPDATE_MODE="${SAS_UPDATE_MODE:-}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/sas-write-toolbox-status.sh [--out PATH] [--dry-run]
       [--update-state STATE] [--update-mode MODE]

Runs sas-probe-toolbox.sh, adds actionNeeded/summary, writes JSON for the dashboard.

Options:
  --out PATH           Output file (default: dashboard/toolbox-status.json)
  --dry-run            Print JSON to stdout only; do not write file
  --update-state STATE Override SAS_UPDATE_STATE for repo probe
  --update-mode MODE   Override SAS_UPDATE_MODE for repo probe
  -h, --help           Show help
USAGE
}

log() { printf '[sas-write-toolbox-status] %s\n' "$*" >&2; }
fail() { printf '[sas-write-toolbox-status] ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --update-state) UPDATE_STATE="$2"; shift 2 ;;
    --update-mode) UPDATE_MODE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required to build toolbox status JSON" 1
}

export SAS_UPDATE_STATE="${UPDATE_STATE:-${SAS_UPDATE_STATE:-unknown}}"
export SAS_UPDATE_MODE="${UPDATE_MODE:-${SAS_UPDATE_MODE:-unknown}}"

PROBE_JSON="$(bash "${SCRIPT_DIR}/sas-probe-toolbox.sh" --dry-run)" || fail "Probe failed" 1

PY="$(find_python)"
FINAL_JSON="$("$PY" - "$PROBE_JSON" <<'PY'
import json, sys

raw = json.loads(sys.argv[1])
tools = raw.get("tools", [])

ACTION_STATUSES = {"missing", "outdated", "blocked", "available", "manual_review"}
REQUIRED_TIERS = {"required", "workflow"}

issues = []
for tool in tools:
    status = tool.get("status", "unknown")
    tier = tool.get("tier", "recommended")
    if status in ACTION_STATUSES and tier in REQUIRED_TIERS:
        issues.append(tool)
    elif tool.get("id") == "repo" and status in ("available", "manual_review"):
        issues.append(tool)

action_needed = len(issues) > 0
summary = {
    "total": len(tools),
    "ok": sum(1 for t in tools if t.get("status") == "ok"),
    "notApplicable": sum(1 for t in tools if t.get("status") == "not_applicable"),
    "needsAction": len(issues),
    "missing": sum(1 for t in tools if t.get("status") == "missing"),
    "outdated": sum(1 for t in tools if t.get("status") == "outdated"),
    "blocked": sum(1 for t in tools if t.get("status") == "blocked"),
    "unknown": sum(1 for t in tools if t.get("status") == "unknown"),
}

raw["actionNeeded"] = action_needed
raw["summary"] = summary
print(json.dumps(raw, indent=2))
PY
)" || fail "Failed to enrich probe JSON" 1

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "$FINAL_JSON"
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$FINAL_JSON" > "$OUT"
log "Wrote $OUT"
exit 0
