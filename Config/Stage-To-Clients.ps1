∩╗┐# Stage-To-Clients.ps1
# Mirrors the depot to target PCs (uses Clients.txt)
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
Copy-SoftwareToClients -RepoRoot $RepoRoot -ComputerName $pcs -MaxParallel 8
Stop-Transcript | Out-Null