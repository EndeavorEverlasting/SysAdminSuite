# ImpactS-FixShortcuts.ps1
# --- bootstrap ---
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$logs   = Join-Path $here 'Logs'; New-Item -ItemType Directory -Force -Path $logs | Out-Null
$stamp  = (Get-Date -Format 'yyyyMMdd_HHmmss')
$log    = Join-Path $logs ("{0}-{1}.log" -f ($MyInvocation.MyCommand.Name -replace '\.ps1$',''), $stamp)
Start-Transcript -Path $log -Append | Out-Null
$tools = Join-Path $here 'GoLiveTools.ps1'
if (-not (Test-Path $tools)) { throw "Missing GoLiveTools.ps1 at $tools" }
$repoHost = $env:REPO_HOST
$hostFile = Join-Path $here 'RepoHost.txt'
if (-not $repoHost -and (Test-Path $hostFile)) {
  $line = Get-Content $hostFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
  if ($line) { $repoHost = $line.Trim() }
}
if ([string]::IsNullOrWhiteSpace($repoHost)) {
  throw "Repo host is empty. Set REPO_HOST or provide a non-empty value in $hostFile."
}
. $tools -RepoHost $repoHost

$clientsPath = Join-Path $here 'Clients.txt'
if (-not (Test-Path $clientsPath)) { throw "Missing Clients.txt at $clientsPath" }
$pcs = Get-Content $clientsPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
if (-not $pcs -or $pcs.Count -eq 0) {
  throw "No valid client names were found in $clientsPath."
}

$cfgPath = Join-Path $here 'ImpactS-Paths.psd1'
if (-not (Test-Path $cfgPath)) { throw "Missing ImpactS-Paths.psd1 at $cfgPath" }
$cfg = Import-PowerShellDataFile $cfgPath

# DRY RUN first; comment -WhatIf to commit
Fix-ImpactSShortcuts -ComputerName $pcs -OldDir $cfg.OldDir -NewDir $cfg.NewDir -WhatIf
Stop-Transcript | Out-Null