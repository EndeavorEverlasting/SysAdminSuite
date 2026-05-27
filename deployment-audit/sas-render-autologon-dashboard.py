#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, datetime as dt, html, json
from collections import Counter
from pathlib import Path

COLS = [
    "OverallStatus", "HostName", "Reachability", "AdminShareOk",
    "PostInstall_SetAutoLogon", "Winlogon_AutoAdminLogon", "Winlogon_DefaultUserName",
    "Hostname_User_Match", "AD_User_Found", "AD_Computer_OU", "Legacy_OU_Warning",
    "AssessmentStage", "ProbeMethod", "EvidenceDetail", "RevisitRecommendation",
]
LABEL = {
    "autologon_ready": "Auto-logon Ready",
    "shared_device": "Shared Device",
    "intent_only": "Intent Only",
    "account_missing": "Account Missing",
    "setup_incomplete": "Setup Incomplete",
    "ou_mismatch": "OU Mismatch",
    "unreachable": "Unreachable",
    "probe_failed": "Probe Failed",
}
ROW = {
    "autologon_ready": "good",
    "shared_device": "info",
    "intent_only": "warn",
    "account_missing": "bad",
    "setup_incomplete": "warn",
    "ou_mismatch": "bad",
    "unreachable": "off",
    "probe_failed": "bad",
}
BUCKETS = [
    "autologon_ready", "shared_device", "intent_only", "account_missing",
    "setup_incomplete", "ou_mismatch", "unreachable", "probe_failed",
]


def e(v):
    return html.escape(str(v or ""))


def rows(p):
    with open(p, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def chip(v, cls="chip"):
    v = str(v or "")
    return f'<span class="{cls} {e(v).replace("_", "-")}">{e(v)}</span>'


def table(rs, title, tid):
    head = "".join(f"<th>{e(c)}</th>" for c in COLS)
    body = []
    for r in rs:
        cells = []
        for c in COLS:
            v = r.get(c, "")
            if c == "OverallStatus":
                cells.append(f'<td>{chip(LABEL.get(v, v), "status-label")}</td>')
            elif c == "ProbeMethod":
                cells.append(f'<td>{chip(v, "method-chip")}</td>')
            else:
                cells.append(f"<td>{e(v)}</td>")
        body.append(f'<tr class="{ROW.get(r.get("OverallStatus", ""), "")}">' + "".join(cells) + "</tr>")
    return (
        f'<section class="panel"><div class="panel-head"><h2>{e(title)}</h2>'
        f'<span class="count-chip">{len(rs)} rows</span></div>'
        f'<input class="filter" data-table="{tid}" placeholder="Filter {e(title)}">'
        f'<div class="table-wrap"><table id="{tid}"><thead><tr>{head}</tr></thead>'
        f"<tbody>{''.join(body)}</tbody></table></div></section>"
    )


def cards(rs):
    chosen = [
        r for r in rs
        if r.get("OverallStatus") in {"autologon_ready", "intent_only", "setup_incomplete", "ou_mismatch"}
    ][:8]
    body = []
    for r in chosen:
        cls = ROW.get(r.get("OverallStatus", ""), "info")
        body.append(
            f'<article class="workstation-card {cls}">'
            f'<div>{chip(r.get("OverallStatus"), "status-label")}</div>'
            f'<h3>{e(r.get("HostName"))}</h3>'
            f'<p><b>PostInstall:</b> {e(r.get("PostInstall_SetAutoLogon"))}</p>'
            f'<p><b>Winlogon user:</b> {e(r.get("Winlogon_DefaultUserName"))}</p>'
            f'<p><b>Hostname match:</b> {chip(r.get("Hostname_User_Match"), "match-chip")}</p>'
            f'<p><b>AD user:</b> {e(r.get("AD_User_Found"))}</p>'
            f'<p><b>Next:</b> {e(r.get("RevisitRecommendation"))}</p>'
            f"</article>"
        )
    return (
        '<section class="panel"><div class="panel-head"><h2>Glowing Workstation Cards</h2>'
        f'<span class="count-chip">{len(body)} cards</span></div>'
        f'<div class="workstation-grid">{"".join(body)}</div></section>'
    )


def render(rs, src):
    cc = Counter(r.get("OverallStatus", "probe_failed") or "probe_failed" for r in rs)
    mc = Counter(r.get("ProbeMethod", "unknown") or "unknown" for r in rs)
    intent = sum(1 for r in rs if r.get("OverallStatus") in {"intent_only", "setup_incomplete", "account_missing"})
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Total Workstations</span><strong>{len(rs)}</strong></article>'
        f'<article class="metric good"><span>Auto-logon Ready</span><strong>{cc.get("autologon_ready", 0)}</strong></article>'
        f'<article class="metric info"><span>Shared Devices</span><strong>{cc.get("shared_device", 0)}</strong></article>'
        f'<article class="metric warn"><span>Intent / Setup Pending</span><strong>{intent}</strong></article>'
        f'<article class="metric bad"><span>Blocked / Failed</span><strong>{cc.get("unreachable", 0) + cc.get("probe_failed", 0) + cc.get("account_missing", 0) + cc.get("ou_mismatch", 0)}</strong></article>'
        "</section>"
    )
    meth = "".join(f"<li>{chip(k, 'method-chip')}<b>{v}</b></li>" for k, v in mc.items())
    panels = (
        '<section class="dashboard-grid">'
        f"<article class=\"panel\"><h2>Probe Methods</h2><ul>{meth}</ul></article>"
        '<article class="panel"><h2>Operating Rule</h2>'
        "<p>PostInstall Autologon_YES declares intent. Winlogon + AD user + Managed_Shared OU must align before marking autologon_ready.</p>"
        "</article>"
        '<article class="panel"><h2>Safety</h2>'
        "<p>Read-only assessment. Do not commit CSV/HTML containing real hostnames, usernames, or OU paths.</p>"
        "</article></section>"
    )
    sections = cards(rs) + "".join(
        table([r for r in rs if r.get("OverallStatus") == c], LABEL.get(c, c), "t_" + c)
        for c in BUCKETS if cc.get(c, 0)
    )
    summary = e(json.dumps({
        "source": str(src),
        "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
        "status_counts": dict(cc),
        "method_counts": dict(mc),
    }, indent=2))
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SysAdminSuite Auto-logon Assessment Dashboard</title><style>:root{{--bg:#050816;--panel:#0f172a;--text:#e5e7eb;--muted:#94a3b8;--cyan:#22d3ee;--green:#22c55e;--yellow:#facc15;--red:#f87171;--violet:#a78bfa}}*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(circle at top left,rgba(34,211,238,.18),transparent 34%),linear-gradient(180deg,#020617,#0f172a,#020617);color:var(--text);font-family:Segoe UI,Arial,sans-serif}}header{{padding:26px 34px;background:rgba(2,6,23,.9);border-bottom:1px solid rgba(96,165,250,.3);box-shadow:0 0 34px rgba(34,211,238,.12)}}main{{padding:24px 34px 70px}}.notice,.panel,.metric,.workstation-card{{border:1px solid rgba(96,165,250,.28);background:rgba(15,23,42,.86);border-radius:18px;padding:16px;box-shadow:0 0 28px rgba(34,211,238,.09)}}.metrics,.workstation-grid,.dashboard-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px;margin-bottom:18px}}.metric strong{{font-size:32px;display:block}}.good{{border-color:rgba(34,197,94,.55);box-shadow:0 0 28px rgba(34,197,94,.14)}}.warn{{border-color:rgba(250,204,21,.55);box-shadow:0 0 28px rgba(250,204,21,.14)}}.bad{{border-color:rgba(248,113,113,.6);box-shadow:0 0 28px rgba(248,113,113,.14)}}.glow{{border-color:rgba(167,139,250,.7);box-shadow:0 0 34px rgba(167,139,250,.22)}}.info{{border-color:rgba(34,211,238,.45);box-shadow:0 0 24px rgba(34,211,238,.12)}}.off{{border-color:rgba(100,116,139,.55);opacity:.82}}.chip,.method-chip,.match-chip,.status-label,.count-chip{{display:inline-block;border-radius:999px;padding:6px 10px;border:1px solid rgba(148,163,184,.35);background:#020617;color:var(--text);font-size:12px}}.autologon-ready{{border-color:rgba(34,197,94,.65);color:#bbf7d0}}.shared-device{{border-color:rgba(34,211,238,.65);color:#cffafe}}.intent-only,.setup-incomplete{{border-color:rgba(250,204,21,.7);color:#fef3c7}}.account-missing,.ou-mismatch,.probe-failed{{border-color:rgba(248,113,113,.7);color:#fecaca}}.filter{{width:100%;margin:0 0 12px;padding:10px;border-radius:12px;background:#020617;color:var(--text);border:1px solid rgba(96,165,250,.28)}}.table-wrap{{overflow:auto;max-height:580px;border:1px solid rgba(51,65,85,.8);border-radius:14px}}table{{width:100%;min-width:1500px;border-collapse:collapse}}th,td{{padding:9px 10px;border-bottom:1px solid rgba(51,65,85,.75);text-align:left;vertical-align:top;font-size:13px}}th{{position:sticky;top:0;background:#020617;color:#bfdbfe}}ul{{list-style:none;padding:0}}li{{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px solid rgba(51,65,85,.7)}}pre{{white-space:pre-wrap;overflow:auto;background:#020617;border-radius:12px;padding:14px}}</style></head><body><header><h1>SysAdminSuite Auto-logon Assessment Dashboard</h1><p>Generated {e(dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))} from {e(src)}</p></header><main><div class="notice">Local operational artifact. Do not commit dashboards or CSVs containing real hostnames, usernames, OU paths, or assessment evidence from live runs.</div>{metrics}{panels}{sections}<details class="panel"><summary>Dashboard Summary JSON</summary><pre>{summary}</pre></details></main><script>for(const i of document.querySelectorAll('.filter')){{i.addEventListener('input',()=>{{const t=document.getElementById(i.dataset.table);const n=i.value.toLowerCase();for(const r of t.querySelectorAll('tbody tr'))r.style.display=r.innerText.toLowerCase().includes(n)?'':'none'}})}}</script></body></html>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    rs = rows(Path(args.input))
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(rs, Path(args.input)), encoding="utf-8")
    print(f"Wrote auto-logon assessment dashboard: {out}")


if __name__ == "__main__":
    main()
