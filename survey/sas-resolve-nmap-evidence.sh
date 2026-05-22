#!/usr/bin/env bash
set -euo pipefail

MANIFEST=""
NMAP_INPUT=""
NMAP_FORMAT="auto"
OUTPUT="survey/output/nmap_identity_resolver.csv"
DASHBOARD=""
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Nmap Identity Resolver

Usage:
  bash survey/sas-resolve-nmap-evidence.sh --manifest targets.csv --nmap-output scan.xml [options]

Options:
  --manifest PATH       Manifest/tracker export CSV
  --nmap-output PATH    Existing Nmap output artifact, XML or normal text
  --nmap-format FORMAT  auto, xml, or normal. Default: auto
  --output PATH         Resolver CSV output
  --dashboard PATH      Resolver dashboard HTML output
  --pass-thru           Print resolver CSV after writing

This wrapper does not run Nmap. It converts an existing Nmap artifact into resolver evidence,
then feeds that evidence into sas-live-serial-probe.sh.

Generated CSV/HTML may contain operational identifiers. Do not commit generated outputs.
USAGE
}

fail(){ echo "[nmap-identity-resolver] ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?missing --manifest value}"; shift 2 ;;
    --nmap-output) NMAP_INPUT="${2:?missing --nmap-output value}"; shift 2 ;;
    --nmap-format) NMAP_FORMAT="${2:?missing --nmap-format value}"; shift 2 ;;
    --output) OUTPUT="${2:?missing --output value}"; shift 2 ;;
    --dashboard) DASHBOARD="${2:?missing --dashboard value}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$MANIFEST" ]] || fail "--manifest is required"
[[ -f "$MANIFEST" ]] || fail "Manifest not found: $MANIFEST"
[[ -n "$NMAP_INPUT" ]] || fail "--nmap-output is required"
[[ -f "$NMAP_INPUT" ]] || fail "Nmap output not found: $NMAP_INPUT"

mkdir -p "$(dirname "$OUTPUT")"
EVIDENCE_CSV="$(dirname "$OUTPUT")/nmap_identity_evidence.csv"
[[ -z "$DASHBOARD" ]] && DASHBOARD="$(dirname "$OUTPUT")/nmap_identity_resolver.html"

python3 survey/sas-nmap-evidence-export.py \
  --input "$NMAP_INPUT" \
  --format "$NMAP_FORMAT" \
  --output "$EVIDENCE_CSV"

# Existing resolver consumes generic identity evidence. The Nmap evidence preserves
# ProbeMethod values such as nmap_reverse_dns and nmap_mac_or_ip_observed.
bash survey/sas-live-serial-probe.sh \
  --manifest "$MANIFEST" \
  --identity-csv "$EVIDENCE_CSV" \
  --output "$OUTPUT" \
  --dashboard "$DASHBOARD" \
  $([[ "$PASS_THRU" -eq 1 ]] && echo --pass-thru)
