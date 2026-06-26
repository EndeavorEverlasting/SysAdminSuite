#!/usr/bin/env bash
# Build sas-packet-probe binary into repo bin/ (gitignored).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULE_DIR="${REPO_ROOT}/probe/packet-expenditure"
OUT="${REPO_ROOT}/bin/sas-packet-probe"
[[ "${OS:-}" == "Windows_NT" ]] && OUT="${OUT}.exe"
TAGS="${SAS_PACKET_PROBE_TAGS:-}"

if ! command -v go >/dev/null 2>&1; then
  echo "[build-packet-probe] ERROR: go not found in PATH" >&2
  exit 1
fi

mkdir -p "${REPO_ROOT}/bin"
cd "$MODULE_DIR"

if [[ -n "$TAGS" ]]; then
  echo "[build-packet-probe] building with tags: $TAGS"
  go mod tidy
  go build -tags "$TAGS" -o "$OUT" ./cmd/sas-packet-probe
else
  go build -o "$OUT" ./cmd/sas-packet-probe
fi

echo "[build-packet-probe] built $OUT"
