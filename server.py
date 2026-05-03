#!/usr/bin/env python3
"""
SysAdminSuite - Simple web overview server for Replit environment.
Serves a documentation/overview page on port 5000.
"""

import http.server
import socketserver
import os
import subprocess
from pathlib import Path

PORT = 5000
HOST = "0.0.0.0"

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SysAdminSuite v2.0</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', system-ui, sans-serif;
      background: #0f1117;
      color: #e2e8f0;
      min-height: 100vh;
    }
    header {
      background: linear-gradient(135deg, #1a1f2e 0%, #16213e 100%);
      border-bottom: 1px solid #2d3748;
      padding: 24px 32px;
      display: flex;
      align-items: center;
      gap: 16px;
    }
    header h1 {
      font-size: 1.8rem;
      font-weight: 700;
      color: #63b3ed;
    }
    header .badge {
      background: #2b6cb0;
      color: #bee3f8;
      font-size: 0.75rem;
      padding: 2px 10px;
      border-radius: 999px;
      font-weight: 600;
    }
    header p {
      color: #a0aec0;
      font-size: 0.9rem;
      margin-top: 4px;
    }
    .header-text { flex: 1; }
    .env-pill {
      background: #276749;
      color: #9ae6b4;
      font-size: 0.75rem;
      padding: 4px 12px;
      border-radius: 6px;
      font-weight: 600;
    }
    main {
      max-width: 1100px;
      margin: 0 auto;
      padding: 32px;
    }
    .alert {
      background: #1a2744;
      border: 1px solid #2b4380;
      border-left: 4px solid #4299e1;
      border-radius: 8px;
      padding: 14px 18px;
      margin-bottom: 28px;
      color: #bee3f8;
      font-size: 0.9rem;
      line-height: 1.6;
    }
    .alert strong { color: #63b3ed; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
      gap: 20px;
      margin-bottom: 32px;
    }
    .card {
      background: #1a1f2e;
      border: 1px solid #2d3748;
      border-radius: 10px;
      padding: 20px;
    }
    .card h2 {
      font-size: 1rem;
      font-weight: 700;
      color: #90cdf4;
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card .icon {
      width: 28px; height: 28px;
      background: #2b6cb0;
      border-radius: 6px;
      display: flex; align-items: center; justify-content: center;
      font-size: 14px;
    }
    .card ul {
      list-style: none;
      padding: 0;
    }
    .card ul li {
      color: #a0aec0;
      font-size: 0.85rem;
      padding: 4px 0;
      border-bottom: 1px solid #2d374840;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card ul li:last-child { border-bottom: none; }
    .card ul li code {
      background: #2d3748;
      color: #f6ad55;
      font-size: 0.78rem;
      padding: 1px 6px;
      border-radius: 4px;
      font-family: 'Courier New', monospace;
    }
    .tag {
      font-size: 0.68rem;
      padding: 1px 7px;
      border-radius: 999px;
      font-weight: 600;
      margin-left: auto;
      flex-shrink: 0;
    }
    .tag-bash { background: #1d4044; color: #81e6d9; }
    .tag-ps   { background: #2a1f4e; color: #b794f4; }
    .tag-py   { background: #1a3a1a; color: #68d391; }
    .tag-net  { background: #2a3a1a; color: #f6e05e; }
    .section-title {
      font-size: 1.1rem;
      font-weight: 700;
      color: #e2e8f0;
      margin-bottom: 14px;
      padding-bottom: 8px;
      border-bottom: 1px solid #2d3748;
    }
    .cmd-block {
      background: #1a1f2e;
      border: 1px solid #2d3748;
      border-radius: 8px;
      padding: 20px;
      margin-bottom: 32px;
    }
    .cmd-block h2 { margin-bottom: 14px; }
    .cmd {
      background: #0d1117;
      border: 1px solid #30363d;
      border-radius: 6px;
      padding: 12px 16px;
      margin-bottom: 10px;
      font-family: 'Courier New', monospace;
      font-size: 0.83rem;
      color: #79c0ff;
      overflow-x: auto;
    }
    .cmd .comment { color: #6a737d; }
    .file-tree {
      background: #1a1f2e;
      border: 1px solid #2d3748;
      border-radius: 8px;
      padding: 20px;
      margin-bottom: 32px;
    }
    .tree-item {
      font-family: 'Courier New', monospace;
      font-size: 0.82rem;
      color: #a0aec0;
      line-height: 1.8;
    }
    .tree-item .dir { color: #63b3ed; font-weight: 600; }
    .tree-item .file { color: #a0aec0; }
    footer {
      text-align: center;
      color: #4a5568;
      font-size: 0.8rem;
      padding: 24px;
      border-top: 1px solid #2d3748;
      margin-top: 20px;
    }
    #tour-btn {
      background: #2b6cb0;
      color: #bee3f8;
      border: none;
      border-radius: 6px;
      padding: 6px 16px;
      font-size: 0.82rem;
      font-weight: 600;
      cursor: pointer;
      white-space: nowrap;
    }
    #tour-btn:hover { background: #2c5282; }
    #sas-ov-overlay {
      display: none;
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,.5);
      z-index: 8000;
      pointer-events: none;
    }
    #sas-ov-overlay.active { display: block; }
    #sas-ov-tooltip {
      display: none;
      position: fixed;
      z-index: 8100;
      width: 360px;
      max-width: calc(100vw - 24px);
      background: #1a2236;
      border: 1px solid #3a5080;
      border-radius: 10px;
      box-shadow: 0 8px 32px rgba(0,0,0,.7);
      color: #d8e6f8;
      font-family: 'Segoe UI', system-ui, sans-serif;
      font-size: 13px;
      line-height: 1.55;
    }
    #sas-ov-tooltip.active { display: block; }
    #sas-ov-header {
      display: flex; align-items: center;
      justify-content: space-between;
      padding: 10px 14px 0;
    }
    #sas-ov-counter { font-size: 11px; color: #6b8ab0; font-weight: 600; text-transform: uppercase; }
    #sas-ov-close {
      background: none; border: none; color: #6b8ab0;
      font-size: 15px; cursor: pointer; padding: 0 2px;
    }
    #sas-ov-close:hover { color: #d8e6f8; }
    #sas-ov-title { font-size: 15px; font-weight: 700; color: #90cdf4; padding: 6px 14px 2px; }
    #sas-ov-body { padding: 6px 14px 14px; color: #b8ccdf; font-size: 12.5px; }
    #sas-ov-body code {
      background: #0d1420; color: #f6ad55; padding: 1px 5px;
      border-radius: 3px; font-size: 11.5px; font-family: 'Courier New', monospace;
    }
    #sas-ov-body strong { color: #d8e6f8; }
    #sas-ov-footer {
      display: flex; align-items: center; gap: 8px;
      padding: 10px 14px 12px; border-top: 1px solid #2d4060;
    }
    #sas-ov-footer button {
      border: none; border-radius: 6px; padding: 6px 14px;
      font-size: 12px; font-weight: 600; cursor: pointer;
    }
    #sas-ov-prev { background: #253550; color: #90cdf4; }
    #sas-ov-prev:disabled { opacity: .35; cursor: default; }
    #sas-ov-skip { background: transparent; color: #6b8ab0; margin-right: auto; padding-left: 4px; font-weight: 400; }
    #sas-ov-skip:hover { color: #d8e6f8; }
    #sas-ov-next { background: #2b6cb0; color: #fff; margin-left: auto; }
    #sas-ov-next:hover { opacity: .85; }
    .sas-ov-hl {
      outline: 3px solid #4299e1 !important;
      outline-offset: 3px;
      border-radius: 6px;
      position: relative;
      z-index: 8050;
      box-shadow: 0 0 0 6px rgba(66,153,225,.18);
    }
  </style>
</head>
<body>
  <div id="sas-ov-overlay"></div>
  <div id="sas-ov-tooltip">
    <div id="sas-ov-header">
      <span id="sas-ov-counter"></span>
      <button id="sas-ov-close">&#x2715;</button>
    </div>
    <div id="sas-ov-title"></div>
    <div id="sas-ov-body"></div>
    <div id="sas-ov-footer">
      <button id="sas-ov-prev">&#x2190; Back</button>
      <button id="sas-ov-skip">Skip tour</button>
      <button id="sas-ov-next">Next &#x2192;</button>
    </div>
  </div>
  <header id="tour-header">
    <div class="header-text">
      <h1>SysAdminSuite <span class="badge">v2.0</span></h1>
      <p>Consolidated SysAdmin toolkit &mdash; Bash-first for Northwell; PowerShell is active production tooling for Windows environments (WMI, printer mapping, AD, deployment tracking, GUI).</p>
    </div>
    <button id="tour-btn" onclick="startOvTour()">&#x1F5FA; Tour</button>
    <span class="env-pill">Replit / Linux</span>
  </header>
  <main>
    <div class="alert">
      <strong>Environment Note:</strong> This project is a Windows-targeted SysAdmin toolkit.
      The PowerShell (.ps1) scripts and WinForms GUI require a Windows environment.
      On Replit (Linux), the <strong>Bash scripts</strong>, <strong>Python OCR tools</strong>,
      and <strong>.NET core library</strong> are the runnable components. See the commands below.
    </div>

    <div class="section-title" id="tour-dirs">Tool Directories</div>
    <div class="grid">
      <div class="card" id="tour-survey">
        <h2><span class="icon">&#x1F4CB;</span>Survey Tools</h2>
        <ul>
          <li><code>sas-survey-targets.sh</code><span class="tag tag-bash">Bash</span></li>
          <li><code>sas-collect-cybernet-evidence.sh</code><span class="tag tag-bash">Bash</span></li>
        </ul>
      </div>
      <div class="card" id="tour-audit">
        <h2><span class="icon">&#x1F50D;</span>Deployment Audit</h2>
        <ul>
          <li><code>sas-audit-deployments.sh</code><span class="tag tag-bash">Bash</span></li>
          <li><code>sas-reconcile-evidence.sh</code><span class="tag tag-bash">Bash</span></li>
          <li><code>sas-build-survey-manifest.sh</code><span class="tag tag-bash">Bash</span></li>
        </ul>
      </div>
      <div class="card">
        <h2><span class="icon">&#x1F5BC;</span>OCR / Floor Plan</h2>
        <ul>
          <li><code>locus_mapping_ocr.py</code><span class="tag tag-py">Python</span></li>
          <li><code>build_host_unc_csv.py</code><span class="tag tag-py">Python</span></li>
          <li><code>parse_printer_map.py</code><span class="tag tag-py">Python</span></li>
        </ul>
      </div>
      <div class="card">
        <h2><span class="icon">&#x1F5A8;</span>Printer Mapping</h2>
        <ul>
          <li><code>RPM-Recon.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Map-MachineWide.NoWinRM.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Run-WCC-Mapping.ps1</code><span class="tag tag-ps">PowerShell</span></li>
        </ul>
      </div>
      <div class="card">
        <h2><span class="icon">&#x1F4BB;</span>Hardware Info</h2>
        <ul>
          <li><code>Get-MachineInfo.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Get-RamInfo.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Get-KronosClockInfo.ps1</code><span class="tag tag-ps">PowerShell</span></li>
        </ul>
      </div>
      <div class="card">
        <h2><span class="icon">&#x1F5C2;</span>Active Directory</h2>
        <ul>
          <li><code>Add-Computers-To-PrintingGroup.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Compare-DeploymentToAd.ps1</code><span class="tag tag-ps">PowerShell</span></li>
        </ul>
      </div>
      <div class="card">
        <h2><span class="icon">&#x2699;</span>Config / Setup</h2>
        <ul>
          <li><code>Inventory-Software.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Run-Preflight.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>GoLiveTools.ps1</code><span class="tag tag-ps">PowerShell</span></li>
        </ul>
      </div>
      <div class="card">
        <h2><span class="icon">&#x1F9EA;</span>Managed (.NET)</h2>
        <ul>
          <li><code>SysAdminSuite.Core</code><span class="tag tag-net">.NET 8</span></li>
          <li><code>SysAdminSuite.Core.Tests</code><span class="tag tag-net">xUnit</span></li>
          <li><code>CommentLine.cs</code><span class="tag tag-net">.NET 8</span></li>
        </ul>
      </div>
      <div class="card">
        <h2><span class="icon">&#x1F4F1;</span>QR / Field Tasks</h2>
        <ul>
          <li><code>Invoke-TechTask.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Get-RAMProfile.ps1</code><span class="tag tag-ps">PowerShell</span></li>
          <li><code>Get-NetworkInfo.ps1</code><span class="tag tag-ps">PowerShell</span></li>
        </ul>
      </div>
    </div>

    <div class="section-title" id="tour-linux-title">Runnable on Linux (this environment)</div>
    <div class="cmd-block" id="tour-bash-cmds">
      <h2 class="section-title" style="border:none;margin-bottom:10px;">Bash Survey Tools</h2>
      <div class="cmd"><span class="comment"># Normalize Cybernet target identifiers from CSV/TXT/JSON</span><br>
./survey/sas-survey-targets.sh --device-type Cybernet --output ./survey/output/targets.csv WMH300OPR001</div>
      <div class="cmd"><span class="comment"># Audit deployment tracker workbook for duplicates</span><br>
./deployment-audit/sas-audit-deployments.sh --workbook data/raw/tracker.xlsx --output-dir data/outputs/audit</div>
      <div class="cmd"><span class="comment"># Python OCR: extract workstation/printer layout from floorplan images</span><br>
python3 OCR/locus_mapping_ocr.py --workstations ws.png --printers pr.png --out-prefix ls111</div>
    </div>

    <div class="section-title" id="tour-win-title">Windows-Only (requires PowerShell / Windows)</div>
    <div class="cmd-block" id="tour-win-cmds">
      <div class="cmd"><span class="comment"># Launch WinForms GUI (Windows + PowerShell 5.1+)</span><br>
powershell.exe -STA -File .\\GUI\\Start-SysAdminSuiteGui.ps1</div>
      <div class="cmd"><span class="comment"># Printer recon (read-only, no changes)</span><br>
pwsh -File .\\Mapping\\Controllers\\RPM-Recon.ps1 -HostsPath .\\Mapping\\Config\\hosts_smoke.txt</div>
      <div class="cmd"><span class="comment"># Run .NET managed tests</span><br>
dotnet test SysAdminSuite.sln -c Release</div>
    </div>

    <div class="file-tree">
      <div class="section-title">Repository Layout</div>
      <div class="tree-item">
        <span class="dir">survey/</span> &mdash; Bash-first target surveying (Cybernet, Neuron)<br>
        <span class="dir">deployment-audit/</span> &mdash; Bash audit tools for deployment tracker<br>
        <span class="dir">bash/</span> &mdash; General-purpose Bash utilities<br>
        <span class="dir">OCR/</span> &mdash; Python floorplan OCR + printer/workstation mapping<br>
        <span class="dir">src/</span> &mdash; .NET 8 core library (SysAdminSuite.Core)<br>
        <span class="dir">managed-tests/</span> &mdash; xUnit tests for managed code<br>
        <span class="dir">mapping/</span> &mdash; Printer mapping Controllers + Workers (PowerShell)<br>
        <span class="dir">GetInfo/</span> &mdash; Hardware/printer inventory scripts (PowerShell)<br>
        <span class="dir">GUI/</span> &mdash; WinForms control center (PowerShell, Windows only)<br>
        <span class="dir">Config/</span> &mdash; Environment setup &amp; software inventory (PowerShell)<br>
        <span class="dir">ActiveDirectory/</span> &mdash; AD group management (PowerShell)<br>
        <span class="dir">QRTasks/</span> &mdash; QR scan-to-run field diagnostic tasks (PowerShell)<br>
        <span class="dir">Utilities/</span> &mdash; Shared PS helper functions<br>
        <span class="dir">tools/</span> &mdash; Repo maintenance utilities<br>
        <span class="dir">data/</span> &mdash; Raw source files, outputs, experiments<br>
        <span class="dir">DeploymentTracker/</span> &mdash; Deployment tracker module (PowerShell)<br>
      </div>
    </div>
  </main>
  <footer id="tour-footer">SysAdminSuite &mdash; Consolidated v2.0 &mdash; Primary branch: <code>main</code></footer>
<script>
(function(){
  var TOUR_KEY = 'sas_ov_tour_v1_done';
  var steps = [
    {
      id: 'tour-header',
      title: 'Welcome to SysAdminSuite',
      body: 'This overview page is your starting point. It lists every tool in the suite, shows which ones run here on Linux, and explains which require Windows. Use the <strong>Tour</strong> button in the header to replay this guide anytime.'
    },
    {
      id: null,
      title: 'Environment Note',
      body: 'The blue banner describes the execution split: <strong>Bash scripts</strong> and <strong>Python OCR tools</strong> run directly on this Linux (Replit) environment. <strong>PowerShell scripts</strong> and the <strong>WinForms GUI</strong> require a Windows host. The tour covers both.'
    },
    {
      id: 'tour-survey',
      title: 'Survey Tools',
      body: '<code>sas-survey-targets.sh</code> normalises device identifiers (hostname, MAC, serial) from TXT/CSV/JSON and dispatches them by device type. Supported types: <strong>Cybernet</strong>, <strong>Neuron</strong>, <strong>Workstation</strong>, <strong>Unknown</strong>. Run <code>bash/sas-tutorial.sh --topic survey</code> for a full walkthrough.'
    },
    {
      id: 'tour-audit',
      title: 'Deployment Audit',
      body: '<code>sas-audit-deployments.sh</code> reads the Active Deployment Tracker (.xlsx) and checks every <strong>Deployed&nbsp;=&nbsp;Yes</strong> row for duplicate identifiers, location clashes, and #REF! errors. Outputs CSV reports + <code>audit_summary.txt</code>. Run <code>bash/sas-tutorial.sh --topic audit</code> for a full walkthrough.'
    },
    {
      id: 'tour-dirs',
      title: 'Tool Directories',
      body: 'This grid shows all nine tool directories. <strong>Cyan tags</strong> = Bash, <strong>purple tags</strong> = PowerShell, <strong>green tags</strong> = Python, <strong>yellow tags</strong> = .NET. Hover any card to see the scripts it contains.'
    },
    {
      id: 'tour-bash-cmds',
      title: 'Command Reference — Linux / Bash',
      body: 'These are ready-to-paste commands for the tools that run on this machine. Copy any command and paste it into a terminal to get started immediately. The <code>--output-dir</code> flag controls where CSVs land.'
    },
    {
      id: 'tour-win-cmds',
      title: 'Command Reference — Windows / PowerShell',
      body: 'These commands require a Windows host with PowerShell 5.1+. The WinForms GUI (<code>Start-SysAdminSuiteGui.ps1</code>) has its own built-in tutorial — press <strong>Ctrl+T</strong> or click <strong>Tutorial (Ctrl+T)</strong> in its status bar to launch it.'
    },
    {
      id: 'tour-footer',
      title: 'Visual Dashboard',
      body: 'For a visual interface, open the <strong>SysAdmin Suite Dashboard</strong> at <code>/dashboard/</code>. It ingests the CSV outputs produced by these scripts and displays them as searchable, filterable tables across five tabs. The dashboard also has its own interactive tour.'
    }
  ];

  var idx = 0;
  var prevHL = null;

  function clamp(v, lo, hi){ return Math.max(lo, Math.min(hi, v)); }

  function positionTooltip(el){
    var tt = document.getElementById('sas-ov-tooltip');
    var tw = 360, th = tt.offsetHeight || 260;
    var vw = window.innerWidth, vh = window.innerHeight;
    var top, left;
    if(el){
      var r = el.getBoundingClientRect();
      top = r.bottom + 12;
      left = r.left;
      if(top + th > vh - 12) top = r.top - th - 12;
      if(left + tw > vw - 12) left = vw - tw - 12;
    } else {
      top = clamp((vh - th)/2, 12, vh - th - 12);
      left = clamp((vw - tw)/2, 12, vw - tw - 12);
    }
    tt.style.top  = clamp(top,  12, vh - th - 12) + 'px';
    tt.style.left = clamp(left, 12, vw - tw - 12) + 'px';
  }

  function clearHL(){
    if(prevHL){ prevHL.classList.remove('sas-ov-hl'); prevHL = null; }
  }

  function showStep(i){
    var step = steps[i];
    var el = step.id ? document.getElementById(step.id) : null;
    clearHL();
    if(el){ el.classList.add('sas-ov-hl'); el.scrollIntoView({behavior:'smooth', block:'nearest'}); prevHL = el; }
    document.getElementById('sas-ov-counter').textContent = 'Step ' + (i+1) + ' of ' + steps.length;
    document.getElementById('sas-ov-title').textContent = step.title;
    document.getElementById('sas-ov-body').innerHTML = step.body;
    document.getElementById('sas-ov-prev').disabled = (i === 0);
    document.getElementById('sas-ov-next').textContent = (i === steps.length - 1) ? 'Finish \u2713' : 'Next \u2192';
    setTimeout(function(){ positionTooltip(el); }, 60);
  }

  function endOvTour(){
    localStorage.setItem(TOUR_KEY, '1');
    clearHL();
    document.getElementById('sas-ov-overlay').classList.remove('active');
    document.getElementById('sas-ov-tooltip').classList.remove('active');
  }

  window.startOvTour = function(){
    idx = 0;
    document.getElementById('sas-ov-overlay').classList.add('active');
    document.getElementById('sas-ov-tooltip').classList.add('active');
    showStep(idx);
  };

  document.addEventListener('DOMContentLoaded', function(){
    document.getElementById('sas-ov-close').addEventListener('click', endOvTour);
    document.getElementById('sas-ov-skip').addEventListener('click', endOvTour);
    document.getElementById('sas-ov-prev').addEventListener('click', function(){
      if(idx > 0){ idx--; showStep(idx); }
    });
    document.getElementById('sas-ov-next').addEventListener('click', function(){
      if(idx < steps.length - 1){ idx++; showStep(idx); }
      else { endOvTour(); }
    });
    window.addEventListener('resize', function(){
      if(document.getElementById('sas-ov-tooltip').classList.contains('active')){
        var el = steps[idx].id ? document.getElementById(steps[idx].id) : null;
        positionTooltip(el);
      }
    });
    if(!localStorage.getItem(TOUR_KEY)){ startOvTour(); }
  });
})();
</script>
</body>
</html>
"""


DASHBOARD_DIR = Path(__file__).parent / "dashboard"

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]

        # Serve dashboard files under /dashboard/
        if path == "/dashboard":
            # Redirect to trailing slash so relative URLs resolve correctly
            self.send_response(301)
            self.send_header("Location", "/dashboard/")
            self.end_headers()
            return
        if path == "/dashboard/":
            self._serve_file(DASHBOARD_DIR / "index.html")
            return
        if path.startswith("/dashboard/"):
            rel = path[len("/dashboard/"):]
            # Prevent path traversal: resolve and verify containment under DASHBOARD_DIR
            try:
                file_path = (DASHBOARD_DIR / rel).resolve()
                file_path.relative_to(DASHBOARD_DIR.resolve())  # raises ValueError if outside
            except ValueError:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden")
                return
            except Exception:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad request")
                return
            if file_path.is_file():
                self._serve_file(file_path)
                return
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        # Default: serve overview page
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(HTML.encode("utf-8"))

    def _serve_file(self, file_path: Path):
        if not file_path.exists():
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return
        ext = file_path.suffix.lower()
        mime = MIME_TYPES.get(ext, "application/octet-stream")
        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        print(f"[{self.address_string()}] {format % args}")


class ReplitTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

    def server_bind(self):
        import socket as _socket
        try:
            self.socket.setsockopt(_socket.SOL_SOCKET, _socket.SO_REUSEPORT, 1)
        except (AttributeError, OSError):
            pass
        super().server_bind()


if __name__ == "__main__":
    print(f"SysAdminSuite overview server starting on {HOST}:{PORT}")
    with ReplitTCPServer((HOST, PORT), Handler) as httpd:
        print(f"Serving at http://{HOST}:{PORT}")
        httpd.serve_forever()
