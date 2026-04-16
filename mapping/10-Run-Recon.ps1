#requires -version 5.1
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$csvDir = Join-Path $root 'csv'
$hosts  = Join-Path $csvDir 'hosts_reachable.txt'
if (!(Test-Path $hosts)) { throw "Missing: $hosts (run 00-Build-HostSets.ps1 first)" }

$run164 = Join-Path $root 'Run-164.ps1'
if (!(Test-Path $run164)) { throw "Missing: $run164" }

$runArgs = @{
  HostsPath           = (Resolve-Path -LiteralPath $hosts).Path
  BatchSize           = 24
  MaxParallel         = 12
  MaxWaitSeconds      = 60
  PollSeconds         = 3
  DelayBetweenBatches = 20
}
& $run164 @runArgs

# Open latest report + show totals
$logs = Join-Path $root 'logs'
$latest = Get-ChildItem $logs -Directory | ? Name -like 'recon-*' | Sort LastWriteTime -Desc | Select -First 1
if ($latest) {
  ii (Join-Path $latest.FullName 'index.html') | Out-Null
  $ok = (Select-String -Path (Join-Path $latest.FullName 'controller.log') -Pattern 'COLLECTED').Count
  $total = (Get-Content -LiteralPath $hosts).Count
  "Collected: $ok / $total"
}
