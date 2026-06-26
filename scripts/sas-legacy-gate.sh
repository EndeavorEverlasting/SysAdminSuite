#!/usr/bin/env bash
# Fail-closed gate for preserved legacy deployment/mapping tools.
set -euo pipefail

TOOL_PATH=""
ALLOW_LEGACY=0
POSTURE_JSON="${SAS_OPERATIONAL_POSTURE_JSON:-Config/operational-posture.json}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/sas-legacy-gate.sh --tool PATH [--allow-legacy]

Legacy deployment tools are disabled by default. Enable only for an authorized
deployment/mapping lane with either --allow-legacy or SAS_ALLOW_LEGACY_TOOLS=1.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL_PATH="${2:?missing --tool value}"; shift 2 ;;
    --allow-legacy) ALLOW_LEGACY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'LEGACY_GATE_ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ -n "$TOOL_PATH" ]] || { printf 'LEGACY_GATE_ERROR: --tool is required\n' >&2; exit 64; }

if [[ "$ALLOW_LEGACY" -eq 1 || "${SAS_ALLOW_LEGACY_TOOLS:-0}" == "1" ]]; then
  printf 'LEGACY_TOOLS_ENABLED: %s\n' "$TOOL_PATH" >&2
  exit 0
fi

classification="LEGACY_TOOLS_DISABLED"
if command -v python3 >/dev/null 2>&1 && [[ -f "$POSTURE_JSON" ]]; then
  classification="$(python3 - "$POSTURE_JSON" <<'PY' 2>/dev/null || printf 'LEGACY_TOOLS_DISABLED'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("defaults", {}).get("legacyDisabledClassification", "LEGACY_TOOLS_DISABLED"))
PY
)"
fi

cat >&2 <<EOF
${classification}: ${TOOL_PATH}
Legacy deployment/mapping tools are preserved but disabled by default for low-waste posture control.
Use --allow-legacy or set SAS_ALLOW_LEGACY_TOOLS=1 only for authorized deployment lanes.
See docs/OPERATIONAL_POSTURE.md and docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md.
EOF
exit 42
