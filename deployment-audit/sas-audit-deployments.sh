#!/usr/bin/env bash
# SysAdminSuite Bash deployment audit
# Reads an XLSX deployment tab directly and reports duplicate identifier clusters.
# It does not trust Excel conditional formatting.

set -euo pipefail

WORKBOOK=""
SHEET="Deployments"
OUTPUT_DIR="deployment-audit/output"
MIN_SHARED=1
PASS_THRU=0
KEYS="Cybernet Hostname,Cybernet Serial,Neuron Hostname,Neuron MAC,Neuron S/N,Cybernet MAC,Dialysis S/N,Anesthesia S/N,Medical Device S/N,Replaced Hostname,Serial Connector Cable 1,Serial Connector Cable 2,Serial Connector Cable 3,Serial Connector Cable 4,Serial Connector Cable 5,Old Hostname"

usage() {
  cat <<'USAGE'
SysAdminSuite Deployment Audit

Usage:
  ./deployment-audit/sas-audit-deployments.sh --workbook tracker.xlsx [options]

Options:
  --workbook PATH       XLSX file to inspect
  --sheet NAME          Worksheet name. Default: Deployments
  --keys CSV            Comma-separated identifier headers to audit
  --output-dir PATH     Output folder. Default: deployment-audit/output
  --min-shared N        Minimum shared identifiers for row-pair flag. Default: 1
  --pass-thru           Print duplicate pairs after writing files
  -h, --help            Show help

Outputs:
  records_normalized.csv
  duplicate_values.csv
  duplicate_pairs.csv
  duplicate_clusters.csv
  audit_summary.txt
USAGE
}

fail(){ printf '[deployment-audit] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[deployment-audit] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workbook) WORKBOOK="${2:?missing value for --workbook}"; shift 2 ;;
    --sheet) SHEET="${2:?missing value for --sheet}"; shift 2 ;;
    --keys) KEYS="${2:?missing value for --keys}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?missing value for --output-dir}"; shift 2 ;;
    --min-shared) MIN_SHARED="${2:?missing value for --min-shared}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$WORKBOOK" ]] || fail "--workbook is required"
[[ -f "$WORKBOOK" ]] || fail "Workbook not found: $WORKBOOK"
[[ "$WORKBOOK" == *.xlsx ]] || fail "Only .xlsx is supported"
[[ "$MIN_SHARED" =~ ^[0-9]+$ && "$MIN_SHARED" -ge 1 ]] || fail "--min-shared must be >= 1"
has_cmd python3 || fail "python3 is required"
mkdir -p "$OUTPUT_DIR"

python3 - "$WORKBOOK" "$SHEET" "$KEYS" "$OUTPUT_DIR" "$MIN_SHARED" <<'PY'
import csv, itertools, json, os, re, sys, zipfile, xml.etree.ElementTree as ET
from collections import Counter, defaultdict, deque

workbook, sheet_name, keys_csv, output_dir, min_shared_raw = sys.argv[1:6]
min_shared = int(min_shared_raw)
requested_keys = [k.strip() for k in keys_csv.split(',') if k.strip()]
ns = {
    'main':'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
    'rel':'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'pkgrel':'http://schemas.openxmlformats.org/package/2006/relationships'
}
def q(n,t): return '{%s}%s' % (ns[n], t)
def norm_header(v): return re.sub(r'\s+', ' ', str(v or '').strip()).lower()
def col_to_idx(ref):
    letters=''.join(c for c in ref if c.isalpha()); out=0
    for c in letters.upper(): out = out*26 + ord(c)-64
    return out-1
def norm_value(header, value):
    v = re.sub(r'\s+', ' ', str(value or '').strip())
    if not v or v.upper() in {'N/A','NA','NONE','NULL','TBD','UNKNOWN','#N/A','#REF!'}: return ''
    h = norm_header(header)
    if 'mac' in h:
        hx = re.sub(r'[^0-9A-Fa-f]', '', v).upper()
        return ':'.join(hx[i:i+2] for i in range(0,12,2)) if len(hx)==12 else v.upper()
    if 'hostname' in h or h in {'host','computername','computer name'}:
        return re.sub(r'\s+', '', v).upper()
    if 'serial' in h or 's/n' in h or 'device id' in h:
        return re.sub(r'\s+', '', v).upper()
    return v.upper()
def shared_strings(z):
    if 'xl/sharedStrings.xml' not in z.namelist(): return []
    root=ET.fromstring(z.read('xl/sharedStrings.xml'))
    return [''.join(t.text or '' for t in si.iter(q('main','t'))) for si in root.findall(q('main','si'))]
def cell_value(cell, shared):
    typ=cell.attrib.get('t')
    if typ == 'inlineStr':
        node=cell.find(q('main','is'))
        return ''.join(t.text or '' for t in node.iter(q('main','t'))) if node is not None else ''
    v=cell.find(q('main','v'))
    if v is None: return ''
    raw=v.text or ''
    if typ == 's':
        try: return shared[int(raw)]
        except Exception: return raw
    return raw
def sheet_map(z):
    wb=ET.fromstring(z.read('xl/workbook.xml'))
    rels=ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
    rid={r.attrib['Id']:r.attrib['Target'] for r in rels.findall(q('pkgrel','Relationship'))}
    out={}
    for s in wb.find(q('main','sheets')).findall(q('main','sheet')):
        target=rid[s.attrib[q('rel','id')]]
        if not target.startswith('xl/'): target='xl/'+target.lstrip('/')
        out[s.attrib['name']] = target
    return out

def read_rows(z, path, shared):
    root=ET.fromstring(z.read(path)); rows=[]
    for row in root.iter(q('main','row')):
        rnum=int(row.attrib.get('r','0')); cells={}
        for c in row.findall(q('main','c')):
            cells[col_to_idx(c.attrib['r'])] = cell_value(c, shared)
        if cells:
            rows.append((rnum, [cells.get(i,'') for i in range(max(cells)+1)]))
    return rows

with zipfile.ZipFile(workbook) as z:
    smap=sheet_map(z)
    if sheet_name not in smap:
        raise SystemExit('Sheet not found: %s. Available: %s' % (sheet_name, ', '.join(smap)))
    rows=read_rows(z, smap[sheet_name], shared_strings(z))

headers=rows[0][1]
header_idx={norm_header(h): i for i,h in enumerate(headers) if str(h).strip()}
key_cols=[]; missing=[]
for k in requested_keys:
    nk=norm_header(k)
    if nk in header_idx: key_cols.append((header_idx[nk], headers[header_idx[nk]]))
    else: missing.append(k)

context_headers=['Device Type','Deployed','Installed','Spare','DesignationChanged','DupDeployed','Current Building','Install Building','Area/Unit/Dept','Room','PI_Result','Blocker Reason','Readiness (Auto)']
context_cols=[(header_idx[norm_header(h)], headers[header_idx[norm_header(h)]]) for h in context_headers if norm_header(h) in header_idx]
records=[]; ref_errors=[]
for rnum,row in rows[1:]:
    if not any(str(x).strip() for x in row): continue
    rec={'ExcelRow':rnum}
    for idx,h in context_cols:
        rec[h]=row[idx] if idx < len(row) else ''
    count=0
    for idx,h in key_cols:
        val=norm_value(h, row[idx] if idx < len(row) else '')
        rec[h]=val
        if val: count += 1
    rec['IdentifierCount']=count
    records.append(rec)
    for idx,val in enumerate(row):
        if '#REF!' in str(val): ref_errors.append((rnum, idx+1, headers[idx] if idx < len(headers) else '', val))

value_index=defaultdict(list)
for rec in records:
    for _,h in key_cols:
        v=rec.get(h,'')
        if v: value_index[(h,v)].append(rec['ExcelRow'])
dup_values=[(h,v,sorted(set(rs))) for (h,v),rs in value_index.items() if len(set(rs))>=2]
pairs=defaultdict(list)
for h,v,rs in dup_values:
    for a,b in itertools.combinations(rs,2): pairs[(a,b)].append('%s=%s' % (h,v))
filtered_pairs={k:v for k,v in pairs.items() if len(v) >= min_shared}
adj=defaultdict(set)
for (a,b),hits in filtered_pairs.items(): adj[a].add(b); adj[b].add(a)
clusters=[]; seen=set()
for r in sorted(adj):
    if r in seen: continue
    qd=deque([r]); seen.add(r); comp=[]
    while qd:
        x=qd.popleft(); comp.append(x)
        for y in sorted(adj[x]):
            if y not in seen: seen.add(y); qd.append(y)
    clusters.append(sorted(comp))

def write_csv(name, fields, rows_out):
    path=os.path.join(output_dir, name)
    with open(path,'w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        w.writeheader(); w.writerows(rows_out)
    return path

record_fields=['ExcelRow']+[h for _,h in context_cols]+['IdentifierCount']+[h for _,h in key_cols]
records_csv=write_csv('records_normalized.csv', record_fields, records)
dup_values_csv=os.path.join(output_dir,'duplicate_values.csv')
with open(dup_values_csv,'w',newline='',encoding='utf-8') as f:
    w=csv.writer(f); w.writerow(['Field','Value','Rows','Count'])
    for h,v,rs in sorted(dup_values): w.writerow([h,v,';'.join(map(str,rs)),len(rs)])
dup_pairs_csv=os.path.join(output_dir,'duplicate_pairs.csv')
with open(dup_pairs_csv,'w',newline='',encoding='utf-8') as f:
    w=csv.writer(f); w.writerow(['RowA','RowB','SharedCount','SharedIdentifiers'])
    for (a,b),hits in sorted(filtered_pairs.items()): w.writerow([a,b,len(hits),'; '.join(hits)])
clusters_csv=os.path.join(output_dir,'duplicate_clusters.csv')
with open(clusters_csv,'w',newline='',encoding='utf-8') as f:
    w=csv.writer(f); w.writerow(['ClusterId','Rows','RowCount'])
    for i,c in enumerate(clusters,1): w.writerow([i,';'.join(map(str,c)),len(c)])
summary_txt=os.path.join(output_dir,'audit_summary.txt')
complete=Counter(r['IdentifierCount'] for r in records)
dup_by_field=Counter(h for h,_,_ in dup_values)
with open(summary_txt,'w',encoding='utf-8') as f:
    f.write('SysAdminSuite Deployment Audit\n')
    f.write('===============================\n\n')
    f.write(f'Workbook: {workbook}\nSheet: {sheet_name}\nRows inspected: {len(records)}\n')
    f.write(f'Identifier columns active: {len(key_cols)}\nMissing requested keys: {missing or "None"}\n')
    f.write(f'Duplicate identifier values: {len(dup_values)}\nDuplicate row pairs: {len(filtered_pairs)}\nDuplicate clusters: {len(clusters)}\n')
    f.write(f'#REF! cells in deployment tab: {len(ref_errors)}\n\n')
    f.write('Identifier completeness distribution:\n')
    for k in sorted(complete): f.write(f'  {k}: {complete[k]} rows\n')
    f.write('\nDuplicate values by field:\n')
    for field,count in dup_by_field.most_common(): f.write(f'  {field}: {count}\n')
    f.write('\n#REF! cells:\n')
    for r,c,h,v in ref_errors: f.write(f'  row {r}, col {c}, header {h}: {v}\n')

print(json.dumps({
    'sheet': sheet_name,
    'rows_inspected': len(records),
    'identifier_columns': [h for _,h in key_cols],
    'missing_keys': missing,
    'duplicate_values': len(dup_values),
    'duplicate_pairs': len(filtered_pairs),
    'duplicate_clusters': len(clusters),
    'ref_errors': len(ref_errors),
    'outputs': [records_csv, dup_values_csv, dup_pairs_csv, clusters_csv, summary_txt]
}, indent=2))
PY

log "Audit complete: $OUTPUT_DIR"
if [[ "$PASS_THRU" -eq 1 ]]; then cat "$OUTPUT_DIR/duplicate_pairs.csv"; fi
