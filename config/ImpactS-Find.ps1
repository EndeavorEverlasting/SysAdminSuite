# ImpactS-Find.ps1
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
if (-not $repoHost -and (Test-Path $hostFile)) { $repoHost = (Get-Content $hostFile | Select-Object -First 1).Trim() }
. $tools -RepoHost $repoHost

$clientsPath = Join-Path $here 'Clients.txt'
if (-not (Test-Path $clientsPath)) { throw "Missing Clients.txt at $clientsPath" }
$pcs = Get-Content $clientsPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }

$impact = Get-ImpactS -ComputerName $pcs
$csv = Join-Path $logs ("ImpactS-Inventory-{0}.csv" -f $stamp)
# Flatten for CSV
$rows = foreach($r in $impact){
  foreach($a in $r.ARP){
    [pscustomobject]@{ Computer=$r.ComputerName; Type='ARP'; Name=$a.DisplayName; Version=$a.Version; Path=$a.RegPath }
  }
  foreach($s in $r.Shortcuts){
    [pscustomobject]@{ Computer=$r.ComputerName; Type='Shortcut'; Name=(Split-Path $s.Shortcut -Leaf); Version=''; Path=$s.Target }
  }
}
$rows | Export-Csv $csv -NoType
Write-Host "Wrote ImpactS inventory: $csv" -ForegroundColor Green
Stop-Transcript | Out-Null
