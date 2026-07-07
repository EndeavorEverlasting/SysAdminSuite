#!/usr/bin/env bash
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/sas_registry_install_diff.sh --mode <Mode> [options]

Examples:
  ./scripts/sas_registry_install_diff.sh --mode ReconOnly --target localhost
  ./scripts/sas_registry_install_diff.sh --mode AnalyzeInstall --target localhost --software-id EXAMPLE-SOFTWARE-ID --dry-run

Argument mapping:
  --mode -> -Mode
  --target -> -Target
  --targets-csv -> -TargetsCsv
  --software-id -> -SoftwareId
  --source-config-path -> -SourceConfigPath
  --registry-watchlist-path -> -RegistryWatchlistPath
  --output-root -> -OutputRoot
  --dry-run -> -DryRun
  --installer-path -> -InstallerPath
  --installer-type -> -InstallerType
  --silent-args -> -SilentArgs
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if command -v pwsh >/dev/null 2>&1; then
  PS_BIN="pwsh"
elif command -v powershell >/dev/null 2>&1; then
  PS_BIN="powershell"
else
  echo "POWERSHELL_UNAVAILABLE_IN_ENVIRONMENT: required pwsh or powershell was not found in PATH." >&2
  exit 127
fi

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH="$REPO_ROOT/scripts/powershell/Invoke-RegistryInstallDiff.ps1"

if [[ ! -f "$ORCH" ]]; then
  echo "MissingDependency: $ORCH" >&2
  exit 3
fi

PS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) PS_ARGS+=("-Mode" "$2"); shift 2 ;;
    --target) PS_ARGS+=("-Target" "$2"); shift 2 ;;
    --targets-csv) PS_ARGS+=("-TargetsCsv" "$2"); shift 2 ;;
    --software-id) PS_ARGS+=("-SoftwareId" "$2"); shift 2 ;;
    --source-config-path) PS_ARGS+=("-SourceConfigPath" "$2"); shift 2 ;;
    --registry-watchlist-path) PS_ARGS+=("-RegistryWatchlistPath" "$2"); shift 2 ;;
    --output-root) PS_ARGS+=("-OutputRoot" "$2"); shift 2 ;;
    --dry-run) PS_ARGS+=("-DryRun"); shift ;;
    --installer-path) PS_ARGS+=("-InstallerPath" "$2"); shift 2 ;;
    --installer-type) PS_ARGS+=("-InstallerType" "$2"); shift 2 ;;
    --silent-args) PS_ARGS+=("-SilentArgs" "$2"); shift 2 ;;
    --approved-remediation) PS_ARGS+=("-ApprovedRemediation"); shift ;;
    -*) PS_ARGS+=("$1"); if [[ $# -gt 1 && "$2" != -* ]]; then PS_ARGS+=("$2"); shift 2; else shift; fi ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

exec "$PS_BIN" -NoProfile -ExecutionPolicy Bypass -File "$ORCH" "${PS_ARGS[@]}"
