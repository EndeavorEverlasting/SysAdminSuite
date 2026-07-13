#!/usr/bin/env python3
"""Check Neuron name candidates against saved AD/DNS/name evidence."""
from __future__ import annotations

import argparse
import csv
import html
import re
from collections import Counter
from pathlib import Path

CANDIDATE_TYPES = {"AVAILABLE_GAP", "AVAILABLE_AFTER_HIGHEST"}
OUTPUT_FIELDS = ["ConventionPrefix","CandidateName","CandidateType","Suffix","Ordinal","DirectoryStatus","Recommendation","MatchedEvidence","EvidenceSource","Notes"]
SUMMARY_FIELDS = ["ConventionPrefix","FirstRecommendedName","FirstRecommendedType","ClearCandidateCount","BlockedCandidateCount","OccupiedCandidateCount","Notes"]

def clean(v: object) -> str: return str(v or "").strip()
def norm(v: str) -> str: return clean(v).upper()

def extract_names(text: str, prefixes: list[str]) -> list[str]:
    upper = norm(text); out=[]
    for prefix in prefixes:
        for m in re.finditer(rf"(?<![A-Z0-9])({re.escape(prefix)}[A-Z]+)(?![A-Z0-9])", upper):
            if m.group(1) not in out: out.append(m.group(1))
    return out

def load_detail(path: Path):
    candidates=[]; prefixes=[]; occupied=set()
    with path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            prefix=norm(row.get("ConventionPrefix","")); typ=clean(row.get("RecordType","")); name=norm(row.get("Name",""))
            if prefix and prefix not in prefixes: prefixes.append(prefix)
            if typ=="OCCUPIED" and name: occupied.add(name)
            if typ in CANDIDATE_TYPES and name: candidates.append(row)
    return candidates,prefixes,occupied

def load_evidence(path: Path, prefixes: list[str]):
    idx={}
    def add(value: str, note: str):
        for name in extract_names(value,prefixes): idx.setdefault(name,[]).append((clean(value),str(path),note))
    if path.suffix.lower()==".csv":
        with path.open(newline="",encoding="utf-8-sig",errors="replace") as f:
            for n,row in enumerate(csv.DictReader(f),start=2):
                for k,v in row.items(): add(clean(v),f"Row={n}; Field={clean(k)}")
    else:
        for n,line in enumerate(path.read_text(encoding="utf-8-sig",errors="replace").splitlines(),start=1): add(line,f"Line={n}")
    return idx

def merge(indexes):
    out={}
    for idx in indexes:
        for k,v in idx.items(): out.setdefault(k,[]).extend(v)
    return out

def check(candidates,occupied,directory):
    rows=[]
    for row in candidates:
        name=norm(row.get("Name","")); matches=directory.get(name,[])
        if name in occupied:
            status="OCCUPIED_IN_NETWORK_EVIDENCE"; rec="DO_NOT_USE"; matched="Occupied in naming detail"; source=clean(row.get("EvidenceSource","")) or "name_availability_detail"; notes="Candidate conflicts with occupied evidence."
        elif matches:
            status="BLOCKED_BY_DIRECTORY_EVIDENCE"; rec="DO_NOT_USE"; matched="; ".join(x[0] for x in matches[:5]); source="; ".join(sorted({x[1] for x in matches})); notes="; ".join(x[2] for x in matches[:5])
        else:
            status="CLEAR_IN_SUPPLIED_DIRECTORY_EVIDENCE"; rec="CANDIDATE_OK_PENDING_FINAL_REVIEW"; matched=""; source="supplied_directory_evidence"; notes="No matching AD/DNS/name evidence found in supplied files."
        rows.append({"ConventionPrefix":norm(row.get("ConventionPrefix","")),"CandidateName":name,"CandidateType":clean(row.get("RecordType","")),"Suffix":clean(row.get("Suffix","")),"Ordinal":clean(row.get("Ordinal","")),"DirectoryStatus":status,"Recommendation":rec,"MatchedEvidence":matched,"EvidenceSource":source,"Notes":notes})
    return rows

def summarize(rows):
    by={}
    for r in rows: by.setdefault(r["ConventionPrefix"],[]).append(r)
    out=[]
    for prefix,items in sorted(by.items()):
        counts=Counter(r["DirectoryStatus"] for r in items)
        clear=sorted((r for r in items if r["DirectoryStatus"]=="CLEAR_IN_SUPPLIED_DIRECTORY_EVIDENCE"),key=lambda r:int(r["Ordinal"] or 999999999))
        first=clear[0] if clear else None
        out.append({"ConventionPrefix":prefix,"FirstRecommendedName":first["CandidateName"] if first else "","FirstRecommendedType":first["CandidateType"] if first else "","ClearCandidateCount":str(counts.get("CLEAR_IN_SUPPLIED_DIRECTORY_EVIDENCE",0)),"BlockedCandidateCount":str(counts.get("BLOCKED_BY_DIRECTORY_EVIDENCE",0)),"OccupiedCandidateCount":str(counts.get("OCCUPIED_IN_NETWORK_EVIDENCE",0)),"Notes":"Lowest clear ordinal from supplied evidence; validate against production AD/DNS before rename."})
    return out

def write_csv(path,rows,fields):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields,quoting=csv.QUOTE_ALL,lineterminator="\n"); w.writeheader(); w.writerows(rows)
def e(v): return html.escape(str(v or ""))
def render(summary,rows):
    cards="".join(f'<article class="card"><h2>{e(r["ConventionPrefix"])}</h2><p>Recommended <strong>{e(r["FirstRecommendedName"])}</strong></p><p>Clear {e(r["ClearCandidateCount"])} | Blocked {e(r["BlockedCandidateCount"])}</p></article>' for r in summary)
    head="".join(f"<th>{e(x)}</th>" for x in OUTPUT_FIELDS); body="".join("<tr>"+"".join(f"<td>{e(r.get(x,''))}</td>" for x in OUTPUT_FIELDS)+"</tr>" for r in rows)
    return f'''<!doctype html><html><head><meta charset="utf-8"><title>SysAdminSuite Neuron Directory Name Check</title><style>body{{font-family:Segoe UI;background:#020617;color:#e5e7eb;margin:0}}header,main{{padding:24px}}.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:12px}}.card,.panel,.notice{{background:#0f172a;border:1px solid #334155;border-radius:16px;padding:16px;margin-bottom:16px}}table{{width:100%;border-collapse:collapse;min-width:1400px}}th,td{{padding:8px;border-bottom:1px solid #334155;text-align:left}}th{{color:#bfdbfe}}.wrap{{overflow:auto}}</style></head><body><header><h1>SysAdminSuite Neuron Directory Name Check</h1></header><main><div class="notice">Clear means clear in supplied evidence only. Validate production AD/DNS before renaming.</div><section class="cards">{cards}</section><section class="panel"><div class="wrap"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div></section></main></body></html>'''

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--detail",required=True); ap.add_argument("--directory-evidence",action="append",default=[]); ap.add_argument("--output",default="survey/output/neuron_name_directory_check.csv"); ap.add_argument("--summary-output",default="survey/output/neuron_name_directory_check_summary.csv"); ap.add_argument("--dashboard",default=""); a=ap.parse_args()
    detail=Path(a.detail); candidates,prefixes,occupied=load_detail(detail)
    indexes=[]
    for raw in a.directory_evidence:
        p=Path(raw)
        if not p.exists(): raise FileNotFoundError(f"Directory evidence not found: {p}")
        indexes.append(load_evidence(p,prefixes))
    rows=check(candidates,occupied,merge(indexes)); summary=summarize(rows)
    write_csv(Path(a.output),rows,OUTPUT_FIELDS); write_csv(Path(a.summary_output),summary,SUMMARY_FIELDS)
    print(f"Wrote directory check: {a.output}"); print(f"Wrote directory check summary: {a.summary_output}")
    if a.dashboard:
        p=Path(a.dashboard); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(render(summary,rows),encoding="utf-8"); print(f"Wrote directory check dashboard: {p}")
    return 0
if __name__=="__main__": raise SystemExit(main())
