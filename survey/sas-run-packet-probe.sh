#!/usr/bin/env bash
# Enforced low-noise Naabu packet probe wrapper. Local output only; no target writes.
set -euo pipefail

SITE=""
LIST=""
OUT=""
SUMMARY=""
PROFILE="Config/cybernet-packet-profile.json"
PLANNED_FILE=""
DRY_RUN=0
VERBOSE=0
ALLOW_PUBLIC=0

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-run-packet-probe.sh --site SITE --list PATH --out PATH [options]

Runs the Go sas-packet-probe wrapper with doctrine-enforced Naabu flags:
  -ec -silent -json -duc -tp 1000 -c 50 -rate 3000 -ss -pt 20

Options:
  --site SITE       Site label (required)
  --list PATH       Approved target file, one host/IP per line (required)
  --out PATH        Naabu JSONL output path (required)
  --summary PATH    Summary JSON path. Default: OUT.summary.json
  --profile PATH    Packet profile JSON. Default: Config/cybernet-packet-profile.json
  --planned-file PATH
                    Append dry-run planned command to PATH
  --allow-public    Permit public IP targets (explicit override)
  --dry-run         Print planned command only; no packets
  --verbose         Print resolved probe command
  -h, --help        Show help
USAGE
}

fail() { printf '[packet-probe] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[packet-probe] %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?}"; shift 2 ;;
    --list) LIST="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --summary) SUMMARY="${2:?}"; shift 2 ;;
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --planned-file) PLANNED_FILE="${2:?}"; shift 2 ;;
    --allow-public) ALLOW_PUBLIC=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$SITE" ]] || fail "--site is required"
[[ -n "$LIST" ]] || fail "--list is required"
[[ -n "$OUT" ]] || fail "--out is required"
[[ -f "$LIST" ]] || fail "target list not found: $LIST"
[[ -f "$PROFILE" ]] || fail "profile not found: $PROFILE"
[[ -n "$SUMMARY" ]] || SUMMARY="${OUT}.summary.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBE_BIN="$REPO_ROOT/bin/sas-packet-probe"
[[ "${OS:-}" == "Windows_NT" ]] && PROBE_BIN="${PROBE_BIN}.exe"

log "building sas-packet-probe"
(cd "$REPO_ROOT/probe/packet-expenditure" && go build -o "$PROBE_BIN" ./cmd/sas-packet-probe)

args=(
  "$PROBE_BIN"
  -site "$SITE"
  -list "$LIST"
  -out "$OUT"
  -summary "$SUMMARY"
  -profile "$PROFILE"
)
[[ "$ALLOW_PUBLIC" -eq 1 ]] && args+=(-allow-public)
[[ "$DRY_RUN" -eq 1 ]] && args+=(-dry-run)
[[ "$VERBOSE" -eq 1 ]] && args+=(-verbose)

mkdir -p "$(dirname "$OUT")" "$(dirname "$SUMMARY")"
if [[ "$DRY_RUN" -eq 1 && -n "$PLANNED_FILE" ]]; then
  "${args[@]}" | tee -a "$PLANNED_FILE"
else
  "${args[@]}"
fi
