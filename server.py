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
  </style>
</head>
<body>
  <header>
    <div class="header-text">
      <h1>SysAdminSuite <span class="badge">v2.0</span></h1>
      <p>Consolidated SysAdmin toolkit &mdash; Bash-first for Northwell, PowerShell retained as reference.</p>
    </div>
    <span class="env-pill">Replit / Linux</span>
  </header>
  <main>
    <div class="alert">
      <strong>Environment Note:</strong> This project is a Windows-targeted SysAdmin toolkit.
      The PowerShell (.ps1) scripts and WinForms GUI require a Windows environment.
      On Replit (Linux), the <strong>Bash scripts</strong>, <strong>Python OCR tools</strong>,
      and <strong>.NET core library</strong> are the runnable components. See the commands below.
    </div>

    <div class="section-title">Tool Directories</div>
    <div class="grid">
      <div class="card">
        <h2><span class="icon">&#x1F4CB;</span>Survey Tools</h2>
        <ul>
          <li><code>sas-survey-targets.sh</code><span class="tag tag-bash">Bash</span></li>
          <li><code>sas-collect-cybernet-evidence.sh</code><span class="tag tag-bash">Bash</span></li>
        </ul>
      </div>
      <div class="card">
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

    <div class="section-title">Runnable on Linux (this environment)</div>
    <div class="cmd-block">
      <h2 class="section-title" style="border:none;margin-bottom:10px;">Bash Survey Tools</h2>
      <div class="cmd"><span class="comment"># Normalize Cybernet target identifiers from CSV/TXT/JSON</span><br>
./survey/sas-survey-targets.sh --device-type Cybernet --output ./survey/output/targets.csv WMH300OPR001</div>
      <div class="cmd"><span class="comment"># Audit deployment tracker workbook for duplicates</span><br>
./deployment-audit/sas-audit-deployments.sh --workbook data/raw/tracker.xlsx --output-dir data/outputs/audit</div>
      <div class="cmd"><span class="comment"># Python OCR: extract workstation/printer layout from floorplan images</span><br>
python3 OCR/locus_mapping_ocr.py --workstations ws.png --printers pr.png --out-prefix ls111</div>
    </div>

    <div class="section-title">Windows-Only (requires PowerShell / Windows)</div>
    <div class="cmd-block">
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
  <footer>SysAdminSuite &mdash; Consolidated v2.0 &mdash; Primary branch: <code>main</code></footer>
</body>
</html>
"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(HTML.encode("utf-8"))

    def log_message(self, format, *args):
        print(f"[{self.address_string()}] {format % args}")


if __name__ == "__main__":
    print(f"SysAdminSuite overview server starting on {HOST}:{PORT}")
    with socketserver.TCPServer((HOST, PORT), Handler) as httpd:
        httpd.allow_reuse_address = True
        print(f"Serving at http://{HOST}:{PORT}")
        httpd.serve_forever()
