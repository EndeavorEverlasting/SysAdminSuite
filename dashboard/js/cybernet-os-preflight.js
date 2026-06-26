// cybernet-os-preflight.js — adds an OS selector for Cybernet tutorial commands.
// This keeps Windows technicians from running Linux-style ping/DNS probes in Git Bash.
(function () {
  'use strict';

  const STORAGE_KEY = 'sasCybernetTutorialOs';
  const AUTO = 'auto-mixed';
  const WINDOWS = 'windows-powershell';
  const GIT_BASH = 'windows-gitbash';
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

  const GIT_BASH_PREFLIGHT = String.raw`bash bash/transport/sas-network-preflight.sh \
  --targets-file /tmp/sas-cybernet/targets.txt \
  --ports 135,445,3389,9100 \
  --ping-mode windows \
  --output /tmp/sas-cybernet/network_preflight.csv --pass-thru`;

  const BASH_PREFLIGHT = String.raw`bash bash/transport/sas-network-preflight.sh \
  --targets-file /tmp/sas-cybernet/targets.txt \
  --ports 135,445,3389,9100 \
  --ping-mode linux \
  --output /tmp/sas-cybernet/network_preflight.csv --pass-thru`;

  const BASH_IDENTITY = String.raw`bash bash/transport/sas-workstation-identity.sh \
  --targets-file /tmp/sas-cybernet/targets.txt \
  --output /tmp/sas-cybernet/workstation_identity.csv --pass-thru`;

  const notes = {
    [AUTO]: 'Auto / mixed mode: do not choose target OS up front. Use the section for the admin shell you are standing at; the results will tell you what the target looks like.',
    [WINDOWS]: 'Windows PowerShell mode uses Resolve-DnsName, Test-Connection, and Test-NetConnection.',
    [GIT_BASH]: 'Windows Git Bash mode keeps Bash output paths but forces Windows ping.exe syntax to avoid false NoPing results.',
    [BASH]: 'Linux/macOS/WSL Bash mode uses POSIX ping flags. Do not use this for Git Bash on a Windows admin box.'
  };

  function normalizeOs(value) {
    return value === AUTO || value === WINDOWS || value === GIT_BASH || value === BASH ? value : AUTO;
  }

  function selectedOs() {
    try {
      return normalizeOs(localStorage.getItem(STORAGE_KEY));
    } catch (_) {
      return AUTO;
    }
  }

  function setSelectedOs(value) {
    try {
      localStorage.setItem(STORAGE_KEY, normalizeOs(value));
    } catch (_) {
      // Storage can be unavailable for local files or locked-down browsers.
    }
  }

  function ensureOsCard(root) {
    if (!root || document.getElementById('cybernet-os-preflight')) return;
    const card = document.createElement('div');
    card.id = 'cybernet-os-preflight';
    card.className = 'cybernet-os-preflight';
    card.innerHTML = `
      <div class="cybernet-os-title">Optional command filter</div>
      <label for="cybernet-os-select">Leave this on Auto for mixed sites. Pick one only if you already know which admin shell will run the command:</label>
      <select id="cybernet-os-select">
        <option value="auto-mixed">Auto / mixed environment — show Windows PowerShell + Bash</option>
        <option value="windows-powershell">Windows PowerShell / Windows admin box</option>
        <option value="windows-gitbash">Windows Git Bash / Windows ping.exe</option>
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
      const os = normalizeOs(select.value);
      select.value = os;
      setSelectedOs(os);
      patchCurrentStep();
    });
  }

  function preflightCommandFor(os) {
    if (os === AUTO) {
      return [
        '# Auto / mixed site: do not choose target OS yet.',
        '# Copy and run ONE section below from the admin shell you are using.',
        '',
        '# --- Windows PowerShell admin box ---',
        WINDOWS_PREFLIGHT,
        '',
        '# --- Windows Git Bash admin box ---',
        GIT_BASH_PREFLIGHT,
        '',
        '# --- Linux/macOS/WSL Bash admin box ---',
        BASH_PREFLIGHT
      ].join('\n');
    }
    if (os === WINDOWS) return WINDOWS_PREFLIGHT;
    if (os === GIT_BASH) return GIT_BASH_PREFLIGHT;
    return BASH_PREFLIGHT;
  }

  function identityCommandFor(os) {
    if (os === AUTO) {
      return [
        '# Auto / mixed site: do not choose target OS yet.',
        '# Copy and run ONE section below from the admin shell you are using.',
        '',
        '# --- Windows PowerShell admin box ---',
        WINDOWS_IDENTITY,
        '',
        '# --- Bash admin box ---',
        BASH_IDENTITY
      ].join('\n');
    }
    return os === WINDOWS ? WINDOWS_IDENTITY : BASH_IDENTITY;
  }

  function patchCurrentStep() {
    const titleEl = document.getElementById('cybernet-step-title');
    const commandEl = document.getElementById('cybernet-step-command');
    const noteEl = document.getElementById('cybernet-step-note');
    const osNoteEl = document.getElementById('cybernet-os-note');
    if (!titleEl || !commandEl) return;

    const os = selectedOs();
    const title = titleEl.textContent.trim();
    if (osNoteEl) osNoteEl.textContent = notes[os] || notes[AUTO];

    if (title === 'Prove network posture first') {
      commandEl.value = preflightCommandFor(os);
      if (noteEl) noteEl.textContent = os === AUTO
        ? 'Run one matching section outside the dashboard, then drag network_preflight.csv back into Load Evidence.'
        : os === WINDOWS
        ? 'Run this in Windows PowerShell, then drag C:\\Temp\\sas-cybernet\\network_preflight.csv into the dashboard.'
        : 'Load network_preflight.csv into the Network tab after the command finishes.';
    }

    if (title === 'Acquire Cybernet identity evidence') {
      commandEl.value = identityCommandFor(os);
      if (noteEl) noteEl.textContent = os === AUTO
        ? 'Run one matching section outside the dashboard, then drag workstation_identity.csv back into Load Evidence.'
        : os === WINDOWS
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
