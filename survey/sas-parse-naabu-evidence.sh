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
  --manifest PATH       Optional manifest CSV to join (best-effort normalized host/IP/MAC/serial match)
  --output PATH         Output CSV. Default: survey/output/naabu_identity_resolver.csv
  -h, --help            Show help
USAGE
}

fail(){ echo "[naabu-parser] ERROR: $*" >&2; exit 1; }
log(){ echo "[naabu-parser] $*" >&2; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  if command -v py >/dev/null 2>&1; then echo "py -3"; return 0; fi
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
if [[ -n "$FOLLOWUP" && ! -f "$FOLLOWUP" ]]; then
  fail "Followup file not found: $FOLLOWUP"
fi
if [[ -n "$MANIFEST" && ! -f "$MANIFEST" ]]; then
  fail "Manifest file not found: $MANIFEST"
fi

py="$(find_python)"
$py - "$NAABU_OUTPUT" "$FOLLOWUP" "$MANIFEST" "$OUTPUT" <<'PY'
import csv, ipaddress, json, re, sys
from pathlib import Path
from urllib.parse import urlparse

naabu_path, followup_path, manifest_path, out_path = sys.argv[1:5]
rows = []

HOST_COLS = {"hostname", "host", "computername", "computer", "name", "target", "identifier"}
IP_COLS = {"ip", "ipaddress", "address", "resolvedaddress", "dnsips"}
MAC_COLS = {"mac", "macaddress", "ethernetmac", "wifimac"}
SERIAL_COLS = {"serial", "serialnumber", "servicetag", "assetserial"}

def clean(value):
    return str(value or "").strip()

def strip_url(value):
    text = clean(value)
    if "://" in text:
        parsed = urlparse(text)
        text = parsed.hostname or text
    return text.strip("[]")

def short_host(value):
    text = strip_url(value).lower()
    return text.split(".", 1)[0] if text else ""

def norm_mac(value):
    hx = re.sub(r"[^0-9A-Fa-f]", "", clean(value)).upper()
    if len(hx) == 12:
        return ":".join(hx[i:i+2] for i in range(0, 12, 2))
    return clean(value).upper()

def norm_serial(value):
    return re.sub(r"\s+", "", clean(value)).upper()

def add_row(host, port, source):
    host = strip_url(host)
    port = clean(port)
    if host and port:
        rows.append({"host": host, "port": port, "source": source})

def split_host_port(line):
    line = clean(line)
    if not line:
        return "", ""
    if line.startswith("[") and "]:" in line:
        host, port = line.rsplit(":", 1)
        return host.strip("[]"), port
    if ":" not in line:
        return line, ""
    try:
        ipaddress.ip_address(line)
        return line, ""
    except ValueError:
        pass
    host, port = line.rsplit(":", 1)
    return host, port

def load_txt(path):
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        host, port = split_host_port(line)
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
        if not isinstance(item, dict):
            continue
        host = item.get("host") or item.get("ip") or ""
        port = item.get("port", "")
        add_row(host, port, "naabu_json")

followup_meta = {}
if followup_path:
    for line in Path(followup_path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        host = strip_url(item.get("host", ""))
        port = clean(item.get("port", ""))
        key = f"{host}:{port}"
        followup_meta[key] = {
            "cybernet_signal": item.get("cybernet_signal", ""),
            "site": item.get("site", ""),
            "timestamp": item.get("timestamp", ""),
        }

manifest_tokens = set()
if manifest_path:
    with open(manifest_path, newline="", encoding="utf-8-sig", errors="replace") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            for key, value in row.items():
                value = clean(value)
                if not value:
                    continue
                col = clean(key).lower()
                values = re.split(r"[;,| ]+", value) if col in IP_COLS else [value]
                for item in values:
                    item = clean(item)
                    if not item:
                        continue
                    if col in HOST_COLS:
                        manifest_tokens.add(strip_url(item).lower())
                        manifest_tokens.add(short_host(item))
                    elif col in IP_COLS:
                        manifest_tokens.add(item.lower())
                    elif col in MAC_COLS:
                        manifest_tokens.add(norm_mac(item))
                    elif col in SERIAL_COLS:
                        manifest_tokens.add(norm_serial(item))

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
        host_tokens = {row["host"].lower(), short_host(row["host"])}
        row["manifest_match"] = "yes" if host_tokens & manifest_tokens else ""
        w.writerow(row)

print(f"Wrote {len(rows)} row(s) to {out_path}")
PY

log "Parse complete: $OUTPUT"
