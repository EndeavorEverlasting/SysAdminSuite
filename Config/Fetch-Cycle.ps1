∩╗┐# Fetch-Cycle.ps1
# Rebuild -> test -> fetch -> hash -> fill types
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

Preflight-Repo   -RepoRoot $RepoRoot
Rebuild-FetchMap -RepoRoot $RepoRoot
$r = Test-FetchMap -RepoRoot $RepoRoot -HeadOnly
$r.Results | Sort-Object Status | Format-Table Name,Status,FinalUrl,Error -Auto
Invoke-Fetch      -RepoRoot $RepoRoot -MaxParallel 4
New-RepoChecksums -RepoRoot $RepoRoot
Fill-PackagesTypes -RepoRoot $RepoRoot
Stop-Transcript | Out-Null