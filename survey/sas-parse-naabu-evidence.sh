#!/usr/bin/env bash
# Convert naabu TXT/JSON + optional followup JSONL into resolver-ready CSV.
set -euo pipefail

NAABU_OUTPUT=""
FOLLOWUP=""
OUTPUT="survey/output/naabu_identity_resolver.csv"
MANIFEST=""

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-parse-naabu-evidence.sh --naabu-output PATH [options]

Options:
  --naabu-output PATH   naabu -o file (.txt host:port or .json)
  --followup PATH       Optional followup JSONL from sas-cybernet-packet-followup.sh
  --manifest PATH       Optional manifest CSV to join
  --output PATH         Output CSV. Default: survey/output/naabu_identity_resolver.csv
  -h, --help            Show help
USAGE
}

fail(){ echo "[naabu-parser] ERROR: $*" >&2; exit 1; }
log(){ echo "[naabu-parser] $*" >&2; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --naabu-output) NAABU_OUTPUT="${2:?}"; shift 2 ;;
    --followup) FOLLOWUP="${2:?}"; shift 2 ;;
    --manifest) MANIFEST="${2:?}"; shift 2 ;;
    --output) OUTPUT="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$NAABU_OUTPUT" ]] || fail "--naabu-output is required"
[[ -f "$NAABU_OUTPUT" ]] || fail "Naabu output not found: $NAABU_OUTPUT"

py="$(find_python)"
$py - "$NAABU_OUTPUT" "$FOLLOWUP" "$MANIFEST" "$OUTPUT" <<'PY'
import csv, json, sys
from pathlib import Path

naabu_path, followup_path, manifest_path, out_path = sys.argv[1:5]
rows = []

def load_txt(path):
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        host, _, port = line.partition(":")
        if host and port:
            rows.append({"host": host, "port": port, "source": "naabu_txt"})

def load_json(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace").strip()
    if not text:
        return
    try:
        data = json.loads(text)
        items = data if isinstance(data, list) else [data]
    except json.JSONDecodeError:
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                items = [json.loads(line)]
            except json.JSONDecodeError:
                continue
            for item in items:
                host = item.get("host") or item.get("ip") or ""
                port = str(item.get("port", ""))
                if host and port:
                    rows.append({"host": host, "port": port, "source": "naabu_json"})
        return
    for item in items:
        host = item.get("host") or item.get("ip") or ""
        port = str(item.get("port", ""))
        if host and port:
            rows.append({"host": host, "port": port, "source": "naabu_json"})

p = Path(naabu_path)
if p.suffix.lower() == ".json":
    load_json(naabu_path)
else:
    load_txt(naabu_path)

signals = {}
if followup_path and Path(followup_path).is_file():
    for line in Path(followup_path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        key = f"{item.get('host','')}:{item.get('port','')}"
        signals[key] = item.get("cybernet_signal", "")

Path(out_path).parent.mkdir(parents=True, exist_ok=True)
with open(out_path, "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=["host", "port", "cybernet_signal", "source"])
    w.writeheader()
    for row in rows:
        key = f"{row['host']}:{row['port']}"
        row["cybernet_signal"] = signals.get(key, "")
        w.writerow(row)

print(f"Wrote {len(rows)} row(s) to {out_path}")
PY

log "Parse complete: $OUTPUT"
