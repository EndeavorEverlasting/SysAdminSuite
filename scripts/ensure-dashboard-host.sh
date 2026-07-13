#!/usr/bin/env bash
# Prepare the SysAdminSuite dashboard host for first use.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=0
CONFIGURATION="Release"
RUNTIME_IDENTIFIER="win-x64"
PUBLISH_DIR="${REPO_ROOT}/app/bin"
PROJECT="${REPO_ROOT}/src/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.csproj"

usage() {
  cat <<'USAGE'
Usage: bash scripts/ensure-dashboard-host.sh [--dry-run]

Ensures the dashboard host can run on this Windows workstation. Existing host
executables are reused. If the host is missing on a source checkout, the script
ensures the .NET 8 SDK, publishes the host into app/bin/, and ensures required
.NET 8 runtime frameworks are installed system-wide.

Options:
  --dry-run   Print planned actions only
  -h, --help  Show help
USAGE
}

log() { printf '[ensure-dashboard-host] %s\n' "$*" >&2; }
fail() { printf '[ensure-dashboard-host] ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

dotnet_cmd() {
  if command -v dotnet.exe >/dev/null 2>&1; then command -v dotnet.exe; return 0; fi
  if command -v dotnet >/dev/null 2>&1; then command -v dotnet; return 0; fi
  if [[ -x "/c/Program Files/dotnet/dotnet.exe" ]]; then printf '%s\n' "/c/Program Files/dotnet/dotnet.exe"; return 0; fi
  if [[ -x "/c/Program Files (x86)/dotnet/dotnet.exe" ]]; then printf '%s\n' "/c/Program Files (x86)/dotnet/dotnet.exe"; return 0; fi
  return 1
}

find_host() {
  local candidates=(
    "${REPO_ROOT}/app/bin/SysAdminSuite.DashboardHost.exe"
    "${REPO_ROOT}/dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe"
    "${REPO_ROOT}/tools/publish/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.exe"
    "${REPO_ROOT}/src/SysAdminSuite.DashboardHost/bin/Release/net8.0-windows/SysAdminSuite.DashboardHost.exe"
    "${REPO_ROOT}/src/SysAdminSuite.DashboardHost/bin/Release/net8.0-windows/win-x64/SysAdminSuite.DashboardHost.exe"
    "${REPO_ROOT}/src/SysAdminSuite.DashboardHost/bin/Release/net8.0-windows/win-x64/publish/SysAdminSuite.DashboardHost.exe"
    "${REPO_ROOT}/src/SysAdminSuite.DashboardHost/bin/Debug/net8.0-windows/SysAdminSuite.DashboardHost.exe"
    "${REPO_ROOT}/src/SysAdminSuite.DashboardHost/bin/Debug/net8.0-windows/win-x64/SysAdminSuite.DashboardHost.exe"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_runtime() {
  local args=()
  [[ "$DRY_RUN" -eq 1 ]] && args+=(--dry-run)
  bash "${SCRIPT_DIR}/ensure-dotnet-runtime.sh" "${args[@]}"
}

ensure_sdk() {
  local args=()
  [[ "$DRY_RUN" -eq 1 ]] && args+=(--dry-run)
  bash "${SCRIPT_DIR}/ensure-dotnet-sdk.sh" "${args[@]}"
}

publish_host() {
  local dotnet_bin
  [[ -f "$PROJECT" ]] || fail "Dashboard host project not found: $PROJECT" 3
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would publish dashboard host to $PUBLISH_DIR"
    log "DRY-RUN: dotnet publish $PROJECT -c $CONFIGURATION -r $RUNTIME_IDENTIFIER --self-contained false -o $PUBLISH_DIR"
    return 0
  fi
  dotnet_bin="$(dotnet_cmd)" || fail ".NET SDK install completed, but dotnet is still not visible" 3
  mkdir -p "$PUBLISH_DIR"
  log "Publishing dashboard host to app/bin for future first-run reuse..."
  "$dotnet_bin" publish "$PROJECT" -c "$CONFIGURATION" -r "$RUNTIME_IDENTIFIER" --self-contained false -o "$PUBLISH_DIR" \
    || fail "dotnet publish failed" 3
}

if host_path="$(find_host)"; then
  log "Found dashboard host: $host_path"
  ensure_runtime
  printf '%s\n' "$host_path"
  exit 0
fi

log "Dashboard host missing; preparing source checkout for first use."
ensure_sdk
publish_host
ensure_runtime

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "${PUBLISH_DIR}/SysAdminSuite.DashboardHost.exe"
  exit 0
fi

host_path="$(find_host)" || fail "Dashboard host could not be built or located" 3
printf '%s\n' "$host_path"
