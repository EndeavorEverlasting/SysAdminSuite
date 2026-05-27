#!/usr/bin/env bash
# Extract hostname values from deployment/ticket tracker workbooks for naming evidence.
set -euo pipefail

WORKBOOK=""
TICKET_WORKBOOK=""
DEPLOYMENT_SHEET="Deployments"
TICKET_SHEET="General"
OUTPUT=""

usage(){ cat <<'USAGE'
SysAdminSuite Tracker Hostname Extract

Usage:
  bash survey/sas-extract-tracker-hostnames.sh \
    --workbook tracker.xlsx \
    [--ticket-workbook tickets.xlsx] \
    --output survey/artifacts/tracker_hostnames.csv

Options:
  --workbook PATH           Deployment tracker .xlsx (Deployments sheet).
  --ticket-workbook PATH    Ticket tracker .xlsx (Hostname Used on General sheet).
  --deployment-sheet NAME   Sheet name. Default: Deployments
  --ticket-sheet NAME       Ticket sheet. Default: General
  --output PATH             Output CSV (HostName, SourceColumn, SourceWorkbook)
  -h, --help                Show help

Read-only. Does not modify workbooks.
USAGE
}

fail(){ echo "[tracker-hostnames] ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workbook) WORKBOOK="${2:?}"; shift 2 ;;
    --ticket-workbook) TICKET_WORKBOOK="${2:?}"; shift 2 ;;
    --deployment-sheet) DEPLOYMENT_SHEET="${2:?}"; shift 2 ;;
    --ticket-sheet) TICKET_SHEET="${2:?}"; shift 2 ;;
    --output) OUTPUT="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$OUTPUT" ]] || fail "--output is required"
[[ -n "$WORKBOOK" || -n "$TICKET_WORKBOOK" ]] || fail "Supply --workbook and/or --ticket-workbook"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

mkdir -p "$(dirname "$OUTPUT")"

python3 - "$WORKBOOK" "$TICKET_WORKBOOK" "$DEPLOYMENT_SHEET" "$TICKET_SHEET" "$OUTPUT" <<'PY'
import csv, re, sys, zipfile, xml.etree.ElementTree as ET

deployment_wb, ticket_wb, dep_sheet, tix_sheet, output = sys.argv[1:6]
ns = {
    'm': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
    'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'p': 'http://schemas.openxmlformats.org/package/2006/relationships',
}

def q(k, t):
    return '{%s}%s' % (ns[k], t)

def norm_header(v):
    return re.sub(r'\s+', ' ', str(v or '').strip()).lower()

def col_to_idx(ref):
    letters = ''.join(c for c in ref if c.isalpha())
    out = 0
    for c in letters.upper():
        out = out * 26 + ord(c) - 64
    return out - 1

def norm_hostname(v):
    v = re.sub(r'\s+', '', str(v or '').strip())
    if not v or v.upper() in {'N/A', 'NA', 'NONE', 'NULL', 'TBD', '#N/A'}:
        return ''
    return v.upper()

def shared_strings(z):
    if 'xl/sharedStrings.xml' not in z.namelist():
        return []
    root = ET.fromstring(z.read('xl/sharedStrings.xml'))
    return [''.join(t.text or '' for t in si.iter(q('m', 't'))) for si in root.findall(q('m', 'si'))]

def cell_value(cell, shared):
    typ = cell.attrib.get('t')
    if typ == 'inlineStr':
        node = cell.find(q('m', 'is'))
        return ''.join(t.text or '' for t in node.iter(q('m', 't'))) if node is not None else ''
    v = cell.find(q('m', 'v'))
    if v is None:
        return ''
    raw = v.text or ''
    if typ == 's':
        try:
            return shared[int(raw)]
        except Exception:
            return raw
    return raw

def sheet_map(z):
    wb = ET.fromstring(z.read('xl/workbook.xml'))
    rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
    rid = {r.attrib['Id']: r.attrib['Target'] for r in rels.findall(q('p', 'Relationship'))}
    out = {}
    for s in wb.find(q('m', 'sheets')).findall(q('m', 'sheet')):
        target = rid[s.attrib[q('r', 'id')]]
        if not target.startswith('xl/'):
            target = 'xl/' + target.lstrip('/')
        out[s.attrib['name']] = target
    return out

def read_sheet(z, sheet_name, shared):
    paths = sheet_map(z)
    if sheet_name not in paths:
        return [], []
    root = ET.fromstring(z.read(paths[sheet_name]))
    rows = []
    for row in root.iter(q('m', 'row')):
        cells = {}
        for c in row.findall(q('m', 'c')):
            cells[col_to_idx(c.attrib['r'])] = cell_value(c, shared)
        if cells:
            rows.append([cells.get(i, '') for i in range(max(cells) + 1)])
    if not rows:
        return [], []
    headers = [norm_header(x) for x in rows[0]]
    data = []
    for raw in rows[1:]:
        rec = {}
        for i, h in enumerate(headers):
            if h:
                rec[h] = raw[i] if i < len(raw) else ''
        data.append(rec)
    return headers, data

DEPLOYMENT_COLUMNS = [
    'cybernet hostname',
    'neuron hostname',
    'replaced hostname',
    'old hostname',
]
TICKET_COLUMNS = ['hostname used']

rows_out = []

def add_host(value, column, workbook):
    for part in re.split(r'[\r\n;,]+', str(value or '')):
        host = norm_hostname(part)
        if host:
            rows_out.append({'HostName': host, 'SourceColumn': column, 'SourceWorkbook': workbook, 'EvidenceSource': 'deployment_tracker'})

def process_workbook(path, sheet, columns, label):
    if not path:
        return
    with zipfile.ZipFile(path) as z:
        shared = shared_strings(z)
        headers, data = read_sheet(z, sheet, shared)
        if not headers:
            return
        header_map = {h: i for i, h in enumerate(headers)}
        for rec in data:
            for col in columns:
                value = ''
                for hk, hv in rec.items():
                    if norm_header(hk) == col:
                        value = hv
                        break
                add_host(value, col, label)

process_workbook(deployment_wb, dep_sheet, DEPLOYMENT_COLUMNS, deployment_wb)
process_workbook(ticket_wb, tix_sheet, TICKET_COLUMNS, ticket_wb)

with open(output, 'w', newline='', encoding='utf-8') as handle:
    writer = csv.DictWriter(handle, fieldnames=['HostName', 'SourceColumn', 'SourceWorkbook', 'EvidenceSource'], lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows_out)

print(f"Wrote {len(rows_out)} tracker hostname rows: {output}")
PY

echo "[tracker-hostnames] Wrote: $OUTPUT" >&2
