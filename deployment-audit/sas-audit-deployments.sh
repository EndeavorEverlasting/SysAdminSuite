#!/usr/bin/env bash
# SysAdminSuite Bash deployment audit
# Reads an XLSX deployment tab directly and reports real duplicate deployments.
# Rule: a duplicate is real only when the same unique identifier appears on more than one Deployed=Yes row.
# Optional location check marks the same identifier in different deployment locations as a real conflict.
# This does not trust Excel conditional formatting.

set -euo pipefail

WORKBOOK=""
SHEET="Deployments"
OUTPUT_DIR="deployment-audit/output"
PASS_THRU=0
REQUIRE_DIFFERENT_LOCATION=1
KEYS="Cybernet Hostname,Cybernet Serial,Neuron Hostname,Neuron MAC,Neuron S/N,Cybernet MAC,Dialysis S/N,Anesthesia S/N,Medical Device S/N,Replaced Hostname,Old Hostname"
RESOLUTION_KEYS="Cybernet Hostname,Cybernet Serial,Cybernet MAC"

usage() {
  cat <<'USAGE'
SysAdminSuite Deployment Audit

Usage:
  ./deployment-audit/sas-audit-deployments.sh --workbook tracker.xlsx [options]

Options:
  --workbook PATH                 XLSX file to inspect
  --sheet NAME                    Worksheet name. Default: Deployments
  --keys CSV                      Comma-separated unique identifier headers to audit
  --resolution-keys CSV           Fields needed to resolve a duplicate without revisiting. Default: Cybernet Hostname,Cybernet Serial,Cybernet MAC
  --output-dir PATH               Output folder. Default: deployment-audit/output
  --allow-same-location-warning   Keep same-location deployed repeats as warnings instead of suppressing them
  --pass-thru                     Print real duplicate values after writing files
  -h, --help                      Show help

Real duplicate rule:
  1. Row must have Deployed = Yes.
  2. Identifier must be populated and not NA/N/A/#REF!/unknown.
  3. Same identifier must appear on more than one deployed row.
  4. By default, the rows must be in different locations.

Outputs:
  deployed_records_normalized.csv
  real_duplicate_values_deployed_yes.csv
  real_duplicate_pairs_deployed_yes.csv
  real_duplicate_clusters.csv
  survey_requests_duplicate_resolution.csv
  ref_errors.csv
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
    --resolution-keys) RESOLUTION_KEYS="${2:?missing value for --resolution-keys}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?missing value for --output-dir}"; shift 2 ;;
    --allow-same-location-warning) REQUIRE_DIFFERENT_LOCATION=0; shift ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$WORKBOOK" ]] || fail "--workbook is required"
[[ -f "$WORKBOOK" ]] || fail "Workbook not found: $WORKBOOK"
[[ "$WORKBOOK" == *.xlsx ]] || fail "Only .xlsx is supported"
has_cmd python3 || fail "python3 is required"
mkdir -p "$OUTPUT_DIR"

python3 - "$WORKBOOK" "$SHEET" "$KEYS" "$RESOLUTION_KEYS" "$OUTPUT_DIR" "$REQUIRE_DIFFERENT_LOCATION" <<'PY'
import csv, itertools, json, os, re, sys, zipfile, xml.etree.ElementTree as ET
from collections import Counter, defaultdict, deque

workbook, sheet_name, keys_csv, resolution_keys_csv, output_dir, require_diff_raw = sys.argv[1:7]
require_different_location = require_diff_raw == '1'
requested_keys = [k.strip() for k in keys_csv.split(',') if k.strip()]
resolution_keys = [k.strip() for k in resolution_keys_csv.split(',') if k.strip()]
ns = {'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main','r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships','p':'http://schemas.openxmlformats.org/package/2006/relationships'}
def q(k,t): return '{%s}%s' % (ns[k], t)
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
def is_deployed_yes(value): return str(value or '').strip().upper() == 'YES'
def shared_strings(z):
    if 'xl/sharedStrings.xml' not in z.namelist(): return []
    root=ET.fromstring(z.read('xl/sharedStrings.xml'))
    return [''.join(t.text or '' for t in si.iter(q('m','t'))) for si in root.findall(q('m','si'))]
def cell_value(cell, shared):
    typ=cell.attrib.get('t')
    if typ == 'inlineStr':
        node=cell.find(q('m','is'))
        return ''.join(t.text or '' for t in node.iter(q('m','t'))) if node is not None else ''
    v=cell.find(q('m','v'))
    if v is None: return ''
    raw=v.text or ''
    if typ == 's':
        try: return shared[int(raw)]
        except Exception: return raw
    return raw
def sheet_map(z):
    wb=ET.fromstring(z.read('xl/workbook.xml'))
    rels=ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
    rid={r.attrib['Id']:r.attrib['Target'] for r in rels.findall(q('p','Relationship'))}
    out={}
    for s in wb.find(q('m','sheets')).findall(q('m','sheet')):
        target=rid[s.attrib[q('r','id')]]
        if not target.startswith('xl/'): target='xl/'+target.lstrip('/')
        out[s.attrib['name']] = target
    return out
def read_rows(z, path, shared):
    root=ET.fromstring(z.read(path)); rows=[]; ref_errors=[]
    for row in root.iter(q('m','row')):
        rnum=int(row.attrib.get('r','0')); cells={}
        for c in row.findall(q('m','c')):
            idx=col_to_idx(c.attrib['r'])
            val=cell_value(c, shared)
            cells[idx] = val
            if '#REF!' in str(val): ref_errors.append((rnum, idx+1, val))
        if cells: rows.append((rnum, [cells.get(i,'') for i in range(max(cells)+1)]))
    return rows, ref_errors

with zipfile.ZipFile(workbook) as z:
    smap=sheet_map(z)
    if sheet_name not in smap:
        raise SystemExit('Sheet not found: %s. Available: %s' % (sheet_name, ', '.join(smap)))
    rows, ref_errors = read_rows(z, smap[sheet_name], shared_strings(z))
headers=rows[0][1]
header_idx={norm_header(h): i for i,h in enumerate(headers) if str(h).strip()}
key_cols=[]; missing=[]
for k in requested_keys:
    nk=norm_header(k)
    if nk in header_idx: key_cols.append((header_idx[nk], headers[header_idx[nk]]))
    else: missing.append(k)
resolution_cols=[]; missing_resolution=[]
for k in resolution_keys:
    nk=norm_header(k)
    if nk in header_idx: resolution_cols.append((header_idx[nk], headers[header_idx[nk]]))
    else: missing_resolution.append(k)
context_headers=['Device Type','Deployed','Installed','Spare','DupDeployed','Current Building','Install Building','Area/Unit/Dept','Room','Bay','PI_Result','Blocker Reason','Readiness (Auto)']
context_cols=[(header_idx[norm_header(h)], headers[header_idx[norm_header(h)]]) for h in context_headers if norm_header(h) in header_idx]
records=[]
for rnum,row in rows[1:]:
    if not any(str(x).strip() for x in row): continue
    rec={'ExcelRow':rnum}
    for idx,h in context_cols: rec[h]=row[idx] if idx < len(row) else ''
    rec['DeployedYes']=is_deployed_yes(rec.get('Deployed'))
    count=0
    for idx,h in key_cols:
        val=norm_value(h, row[idx] if idx < len(row) else '')
        rec[h]=val
        if val: count += 1
    for idx,h in resolution_cols:
        if h not in rec:
            rec[h]=norm_value(h, row[idx] if idx < len(row) else '')
    rec['IdentifierCount']=count
    rec['LocationKey']=' | '.join(str(rec.get(x,'')).strip() for x in ['Current Building','Install Building','Area/Unit/Dept','Room','Bay'] if str(rec.get(x,'')).strip())
    records.append(rec)
deployed=[r for r in records if r['DeployedYes']]
value_index=defaultdict(list)
for rec in deployed:
    for _,h in key_cols:
        value=rec.get(h,'')
        if value: value_index[(h,value)].append(rec)
dup_values=[]; pairs=[]; survey_requests=[]
for (field,value), rows_for_value in value_index.items():
    by_row={r['ExcelRow']:r for r in rows_for_value}
    if len(by_row) < 2: continue
    locs=sorted(set(r['LocationKey'] for r in by_row.values()))
    severity='RealDuplicate' if len(locs) > 1 else 'DuplicateSameLocation'
    if require_different_location and severity != 'RealDuplicate': continue
    dup_values.append({'Field':field,'Value':value,'Rows':';'.join(map(str,sorted(by_row))),'Count':len(by_row),'DistinctLocations':len(locs),'Severity':severity,'Locations':' || '.join(locs)})
    for rownum, rec in sorted(by_row.items()):
        missing_needed=[]
        present_needed=[]
        for _,rk in resolution_cols:
            if rec.get(rk): present_needed.append('%s=%s' % (rk, rec.get(rk)))
            else: missing_needed.append(rk)
        survey_requests.append({
            'ConflictField':field,
            'ConflictValue':value,
            'ExcelRow':rownum,
            'DeviceType':rec.get('Device Type',''),
            'CurrentBuilding':rec.get('Current Building',''),
            'InstallBuilding':rec.get('Install Building',''),
            'AreaUnitDept':rec.get('Area/Unit/Dept',''),
            'Room':rec.get('Room',''),
            'Bay':rec.get('Bay',''),
            'LocationKey':rec.get('LocationKey',''),
            'KnownResolutionIdentifiers':'; '.join(present_needed),
            'MissingResolutionIdentifiers':'; '.join(missing_needed),
            'RecommendedAction':'Remote survey Cybernet identifiers before physical revisit',
            'SurveyTargetHint':rec.get('Cybernet Hostname') or rec.get('Neuron Hostname') or rec.get('Neuron MAC') or rec.get('Neuron S/N') or value,
        })
    for a,b in itertools.combinations(sorted(by_row),2):
        ra, rb = by_row[a], by_row[b]
        different = ra['LocationKey'] != rb['LocationKey']
        if require_different_location and not different: continue
        pairs.append({'RowA':a,'RowB':b,'Field':field,'Value':value,'LocationA':ra['LocationKey'],'LocationB':rb['LocationKey'],'DifferentLocation':different})
adj=defaultdict(set)
for p in pairs:
    adj[p['RowA']].add(p['RowB']); adj[p['RowB']].add(p['RowA'])
clusters=[]; seen=set()
for r in sorted(adj):
    if r in seen: continue
    qd=deque([r]); seen.add(r); comp=[]
    while qd:
        cur=qd.popleft(); comp.append(cur)
        for nxt in sorted(adj[cur]):
            if nxt not in seen: seen.add(nxt); qd.append(nxt)
    clusters.append(sorted(comp))
def write_csv(name, fields, data):
    path=os.path.join(output_dir, name)
    with open(path,'w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        w.writeheader(); w.writerows(data)
    return path
record_fields=['ExcelRow']+[h for _,h in context_cols]+['DeployedYes','IdentifierCount','LocationKey']+[h for _,h in key_cols]
records_csv=write_csv('deployed_records_normalized.csv', record_fields, deployed)
dup_values_csv=write_csv('real_duplicate_values_deployed_yes.csv', ['Field','Value','Rows','Count','DistinctLocations','Severity','Locations'], sorted(dup_values, key=lambda x:(x['Field'],x['Value'])))
dup_pairs_csv=write_csv('real_duplicate_pairs_deployed_yes.csv', ['RowA','RowB','Field','Value','LocationA','LocationB','DifferentLocation'], sorted(pairs, key=lambda x:(x['Field'],x['Value'],x['RowA'],x['RowB'])))
clusters_csv=write_csv('real_duplicate_clusters.csv', ['ClusterId','Rows','RowCount'], [{'ClusterId':i+1,'Rows':';'.join(map(str,c)),'RowCount':len(c)} for i,c in enumerate(clusters)])
survey_csv=write_csv('survey_requests_duplicate_resolution.csv', ['ConflictField','ConflictValue','ExcelRow','DeviceType','CurrentBuilding','InstallBuilding','AreaUnitDept','Room','Bay','LocationKey','KnownResolutionIdentifiers','MissingResolutionIdentifiers','RecommendedAction','SurveyTargetHint'], sorted(survey_requests, key=lambda x:(x['ConflictField'],x['ConflictValue'],x['ExcelRow'])))
ref_csv=write_csv('ref_errors.csv', ['ExcelRow','ColumnIndex','Header','Value'], [{'ExcelRow':r,'ColumnIndex':c,'Header':headers[c-1] if c-1 < len(headers) else '', 'Value':v} for r,c,v in ref_errors])
summary_txt=os.path.join(output_dir,'audit_summary.txt')
with open(summary_txt,'w',encoding='utf-8') as f:
    f.write('SysAdminSuite Deployment Audit - Deployed Logic\n')
    f.write('==============================================\n\n')
    f.write(f'Workbook: {workbook}\nSheet: {sheet_name}\nRows total: {len(records)}\nDeployed = Yes rows: {len(deployed)}\n')
    f.write(f'Unique identifier columns: {", ".join(h for _,h in key_cols)}\nMissing requested keys: {missing or "None"}\n')
    f.write(f'Resolution fields: {", ".join(h for _,h in resolution_cols)}\nMissing resolution fields: {missing_resolution or "None"}\n')
    f.write(f'Real duplicate values: {len(dup_values)}\nReal duplicate row pairs: {len(pairs)}\nReal duplicate clusters: {len(clusters)}\n')
    f.write(f'Survey requests generated: {len(survey_requests)}\n')
    f.write(f'#REF! cells in Deployments tab: {len(ref_errors)}\n\n')
    f.write(f'Deployed column counts: {dict(Counter(r.get("Deployed","") for r in records))}\n')
    f.write(f'DupDeployed column counts: {dict(Counter(r.get("DupDeployed","") for r in records))}\n')
    f.write(f'Deployed identifier completeness: {dict(Counter(r["IdentifierCount"] for r in deployed))}\n')
print(json.dumps({'sheet':sheet_name,'rows_total':len(records),'deployed_yes_rows':len(deployed),'real_duplicate_values':len(dup_values),'real_duplicate_pairs':len(pairs),'real_duplicate_clusters':len(clusters),'survey_requests':len(survey_requests),'ref_errors':len(ref_errors),'outputs':[records_csv,dup_values_csv,dup_pairs_csv,clusters_csv,survey_csv,ref_csv,summary_txt]}, indent=2))
PY

log "Audit complete: $OUTPUT_DIR"
if [[ "$PASS_THRU" -eq 1 ]]; then cat "$OUTPUT_DIR/real_duplicate_values_deployed_yes.csv"; fi
