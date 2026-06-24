#!/usr/bin/env bash
# Convert naabu TXT/JSON + optional followup JSONL into resolver-ready CSV.
# Local evidence transformation only under low-noise survey doctrine.
# See docs/LOW_NOISE_SURVEY_DOCTRINE.md.
set -euo pipefail

NAABU_OUTPUT=""
FOLLOWUP=""
OUTPUT="survey/output/naabu_identity_resolver.csv"
MANIFEST=""

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-parse-naabu-evidence.sh --naabu-output PATH [options]

Options:
  --naabu-output PATH   naabu -o file (.txt host:port or .json / JSONL)
  --followup PATH       Optional followup JSONL from sas-cybernet-packet-followup.sh
  --manifest PATH       Optional manifest CSV to join (best-effort host match)
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

def add_row(host, port, source):
    if host and port:
        rows.append({"host": host, "port": str(port), "source": source})

def load_txt(path):
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        host, _, port = line.partition(":")
        add_row(host, port, "naabu_txt")

def load_json(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace").strip()
    if not text:
        return
    items = []
    try:
        data = json.loads(text)
        items = data if isinstance(data, list) else [data]
    except json.JSONDecodeError:
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                items.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    for item in items:
        host = item.get("host") or item.get("ip") or ""
        port = item.get("port", "")
        add_row(host, port, "naabu_json")

followup_meta = {}
if followup_path and Path(followup_path).is_file():
    for line in Path(followup_path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        host = str(item.get("host", ""))
        port = str(item.get("port", ""))
        key = f"{host}:{port}"
        followup_meta[key] = {
            "cybernet_signal": item.get("cybernet_signal", ""),
            "site": item.get("site", ""),
            "timestamp": item.get("timestamp", ""),
        }

manifest_hosts = set()
if manifest_path and Path(manifest_path).is_file():
    with open(manifest_path, newline="", encoding="utf-8", errors="replace") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            for col in row.values():
                if col:
                    manifest_hosts.add(col.strip().lower())

p = Path(naabu_path)
if p.suffix.lower() in (".json", ".jsonl"):
    load_json(naabu_path)
else:
    load_txt(naabu_path)

fieldnames = ["host", "port", "cybernet_signal", "site", "timestamp", "manifest_match", "source"]
Path(out_path).parent.mkdir(parents=True, exist_ok=True)
with open(out_path, "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=fieldnames)
    w.writeheader()
    for row in rows:
        key = f"{row['host']}:{row['port']}"
        meta = followup_meta.get(key, {})
        row["cybernet_signal"] = meta.get("cybernet_signal", "")
        row["site"] = meta.get("site", "")
        row["timestamp"] = meta.get("timestamp", "")
        row["manifest_match"] = "yes" if row["host"].lower() in manifest_hosts else ""
        w.writerow(row)

print(f"Wrote {len(rows)} row(s) to {out_path}")
PY

log "Parse complete: $OUTPUT"
