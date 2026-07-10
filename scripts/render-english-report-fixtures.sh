#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v pwsh >/dev/null 2>&1; then
  PS_BIN="pwsh"
elif command -v powershell.exe >/dev/null 2>&1; then
  PS_BIN="powershell.exe"
elif command -v powershell >/dev/null 2>&1; then
  PS_BIN="powershell"
else
  echo "[SAS][FAIL] PowerShell runtime not found. Install pwsh or run on Windows PowerShell." >&2
  exit 127
fi

mkdir -p survey/output/english-log

echo "[SAS] Rendering serial preflight fixture report"
"$PS_BIN" -NoProfile -File "$ROOT/scripts/Render-SasEnglishReport.ps1" \
  -SummaryJson "$ROOT/survey/fixtures/english-log/serial_preflight_summary.sample.json" \
  -ArtifactRegistry "$ROOT/survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json" \
  -Template serial-preflight \
  -OutputPath "$ROOT/survey/output/english-log/serial_preflight_report.md"

echo "[SAS] Rendering network preflight fixture report"
"$PS_BIN" -NoProfile -File "$ROOT/scripts/Render-SasEnglishReport.ps1" \
  -SummaryJson "$ROOT/survey/fixtures/english-log/network_preflight_summary.sample.json" \
  -ArtifactRegistry "$ROOT/survey/fixtures/english-log/network_preflight_artifact_registry.sample.json" \
  -Template network-preflight \
  -OutputPath "$ROOT/survey/output/english-log/network_preflight_report.md"

echo "[SAS] Reports written under survey/output/english-log/"
