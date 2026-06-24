// cybernet-os-preflight.js — adds an OS selector for Cybernet tutorial commands.
// This keeps Windows technicians from running Linux-style ping/DNS probes in Git Bash.
(function () {
  'use strict';

  const STORAGE_KEY = 'sasCybernetTutorialOs';
  const WINDOWS = 'windows-powershell';
  const BASH = 'bash-posix';

  const WINDOWS_PREFLIGHT = String.raw`$targets = Get-Content C:\Temp\sas-cybernet\targets.txt | Where-Object { $_.Trim() }
$out = "C:\Temp\sas-cybernet\network_preflight.csv"
$ports = 135,445,3389,9100
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$rows = foreach ($target in $targets) {
  $ip = (Resolve-DnsName $target -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -match '^\d+\.' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
  $pingOk = Test-Connection -ComputerName $target -Count 1 -Quiet
  foreach ($port in $ports) {
    $tcpOk = Test-NetConnection -ComputerName $target -Port $port -InformationLevel Quiet
    [pscustomobject]@{
      Target = $target
      ResolvedAddress = $ip
      PingStatus = if ($pingOk) { 'Reachable' } else { 'NoPing' }
      Port = $port
      PortStatus = if ($tcpOk) { 'Open' } else { 'Closed' }
      Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
      Notes = if (-not $pingOk) { 'Windows ICMP blocked or no ping response' } else { '' }
    }
  }
}
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $out`;

  const WINDOWS_IDENTITY = String.raw`$targets = Get-Content C:\Temp\sas-cybernet\targets.txt | Where-Object { $_.Trim() }
$out = "C:\Temp\sas-cybernet\workstation_identity.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$rows = foreach ($target in $targets) {
  $ip = (Resolve-DnsName $target -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -match '^\d+\.' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
  $pingOk = Test-Connection -ComputerName $target -Count 1 -Quiet
  [pscustomobject]@{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Target = $target
    ResolvedAddress = $ip
    PingStatus = if ($pingOk) { 'Reachable' } else { 'NoPing' }
    DnsName = $target
    ObservedHostName = ''
    ObservedSerial = ''
    ObservedMACs = ''
    TransportUsed = 'WindowsPing'
    IdentityStatus = if ($pingOk) { 'ReachableNeedsApprovedIdentityTransport' } else { 'UnreachableOrBlocked' }
    Notes = if ($pingOk) { 'Windows Test-Connection reachable; identity transport not run' } else { 'Windows Test-Connection failed or blocked' }
  }
}
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $out`;

  const BASH_PREFLIGHT = String.raw`bash bash/transport/sas-network-preflight.sh \
  --targets-file /tmp/sas-cybernet/targets.txt \
  --ports 135,445,3389,9100 \
  --output /tmp/sas-cybernet/network_preflight.csv --pass-thru`;

  const BASH_IDENTITY = String.raw`bash bash/transport/sas-workstation-identity.sh \
  --targets-file /tmp/sas-cybernet/targets.txt \
  --output /tmp/sas-cybernet/workstation_identity.csv --pass-thru`;

  const notes = {
    [WINDOWS]: 'Windows PowerShell mode avoids Git Bash ping/getent differences by using Resolve-DnsName, Test-Connection, and Test-NetConnection.',
    [BASH]: 'Bash mode is for Linux, macOS, WSL, or a Bash environment where ping/getent behave like the scripts expect.'
  };

  function selectedOs() {
    return localStorage.getItem(STORAGE_KEY) || WINDOWS;
  }

  function setSelectedOs(value) {
    localStorage.setItem(STORAGE_KEY, value);
  }

  function ensureOsCard(root) {
    if (!root || document.getElementById('cybernet-os-preflight')) return;
    const card = document.createElement('div');
    card.id = 'cybernet-os-preflight';
    card.className = 'cybernet-os-preflight';
    card.innerHTML = `
      <div class="cybernet-os-title">Preflight environment</div>
      <label for="cybernet-os-select">Choose the OS/shell that will run the commands:</label>
      <select id="cybernet-os-select">
        <option value="windows-powershell">Windows PowerShell / Windows admin box</option>
        <option value="bash-posix">Linux/macOS/WSL Bash</option>
      </select>
      <div class="cybernet-os-note" id="cybernet-os-note"></div>
    `;
    const stepCard = root.querySelector('.cybernet-step-card');
    root.insertBefore(card, stepCard || root.firstChild);

    const style = document.createElement('style');
    style.textContent = `
      .cybernet-os-preflight { margin: 12px 0; padding: 12px; border: 1px solid var(--border); border-radius: 10px; background: var(--bg2); display: grid; gap: 8px; }
      .cybernet-os-title { color: var(--accent); font-weight: 700; font-size: 13px; }
      .cybernet-os-preflight label { color: var(--text-dim); font-size: 12px; }
      .cybernet-os-preflight select { max-width: 420px; padding: 7px 10px; background: var(--bg3); color: var(--text); border: 1px solid var(--border); border-radius: 6px; }
      .cybernet-os-note { color: var(--text-muted); font-size: 12px; line-height: 1.4; }
    `;
    document.head.appendChild(style);

    const select = document.getElementById('cybernet-os-select');
    select.value = selectedOs();
    select.addEventListener('change', () => {
      setSelectedOs(select.value);
      patchCurrentStep();
    });
  }

  function patchCurrentStep() {
    const titleEl = document.getElementById('cybernet-step-title');
    const commandEl = document.getElementById('cybernet-step-command');
    const noteEl = document.getElementById('cybernet-step-note');
    const osNoteEl = document.getElementById('cybernet-os-note');
    if (!titleEl || !commandEl) return;

    const os = selectedOs();
    const title = titleEl.textContent.trim();
    if (osNoteEl) osNoteEl.textContent = notes[os] || '';

    if (title === 'Prove network posture first') {
      commandEl.value = os === WINDOWS ? WINDOWS_PREFLIGHT : BASH_PREFLIGHT;
      if (noteEl) noteEl.textContent = os === WINDOWS
        ? 'Run this in Windows PowerShell, then drag C:\\Temp\\sas-cybernet\\network_preflight.csv into the dashboard.'
        : 'Load network_preflight.csv into the Network tab after the command finishes.';
    }

    if (title === 'Acquire Cybernet identity evidence') {
      commandEl.value = os === WINDOWS ? WINDOWS_IDENTITY : BASH_IDENTITY;
      if (noteEl) noteEl.textContent = os === WINDOWS
        ? 'Run this in Windows PowerShell to avoid Git Bash ping/DNS mismatch, then drag C:\\Temp\\sas-cybernet\\workstation_identity.csv into the dashboard.'
        : 'Load workstation_identity.csv back into the dashboard for searchable protocol evidence.';
    }
  }

  function init() {
    const root = document.getElementById('cybernet-tutorial');
    if (!root) return;
    ensureOsCard(root);
    patchCurrentStep();
    root.addEventListener('click', () => setTimeout(patchCurrentStep, 0));
    const observer = new MutationObserver(() => patchCurrentStep());
    const titleEl = document.getElementById('cybernet-step-title');
    if (titleEl) observer.observe(titleEl, { childList: true, characterData: true, subtree: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
}());
