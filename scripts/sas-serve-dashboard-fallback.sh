#!/usr/bin/env bash
# sas-serve-dashboard-fallback.sh
#
# Local-only dashboard server FALLBACK for Windows field workstations.
#
# The primary dashboard front door is the .NET tray host started by
# Launch-SysAdminSuiteDashboard.Host.bat. When that host cannot be built or
# located (no .NET SDK, blocked Microsoft downloads, build failure), a
# double-click would otherwise dead-end and push technicians toward raw CLI.
# This script bridges that gap by serving the SAME dashboard from the repo's
# own server.py over http://127.0.0.1:5000/dashboard/.
#
# This is an internal launcher fallback, not user-facing guidance: the
# double-click .bat remains the front door and the .NET host stays primary.
# It is the suite's own server.py, not a raw "python -m http.server".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVER_PY="${REPO_ROOT}/server.py"

BIND="${SAS_DASHBOARD_BIND:-127.0.0.1}"
PORT="${SAS_DASHBOARD_PORT:-5000}"

log() { printf '[sas-serve-dashboard-fallback] %s\n' "$*" >&2; }
fail() { printf '[sas-serve-dashboard-fallback] ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }

usage() {
  cat <<'USAGE'
Usage: bash scripts/sas-serve-dashboard-fallback.sh [--bind ADDR] [--port N]

Serves the SysAdminSuite dashboard from server.py as a local-only fallback when
the .NET dashboard host is unavailable. Defaults: 127.0.0.1:5000.

Options:
  --bind ADDR   Bind address (default: 127.0.0.1; env: SAS_DASHBOARD_BIND)
  --port N      Port (default: 5000; env: SAS_DASHBOARD_PORT)
  -h, --help    Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bind) BIND="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -f "$SERVER_PY" ]] || fail "server.py not found at $SERVER_PY" 1

# Find a REAL Python. The Windows Store "python"/"python3" aliases under
# WindowsApps are non-functional stubs that exit without serving, so every
# candidate is verified with --version before it is trusted.
find_python() {
  local candidate
  for candidate in "py -3" "python3" "python" "py"; do
    if $candidate --version >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

PY="$(find_python)" || fail "No working Python found for the dashboard fallback server." 2

export SAS_DASHBOARD_BIND="$BIND"
export SAS_DASHBOARD_PORT="$PORT"

log "Starting dashboard fallback server on http://${BIND}:${PORT}/dashboard/ via ${PY}"
# Run from the repo root and hand the launcher a plain relative filename.
# The Windows "py" launcher cannot open an MSYS-style absolute path
# (e.g. /c/Users/.../server.py), so a cwd-relative name is used instead.
cd "$REPO_ROOT"
# shellcheck disable=SC2086
exec $PY "$(basename "$SERVER_PY")"
