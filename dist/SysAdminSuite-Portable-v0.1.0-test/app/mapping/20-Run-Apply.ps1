#requires -version 5.1
param(
  [string]$PlanCsv  # optional: mapping plan path
)
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$csvDir = Join-Path $root 'csv'
$hosts  = Join-Path $csvDir 'hosts_reachable.txt'
if (!(Test-Path $hosts)) { throw "Missing: $hosts (run 00-Build-HostSets.ps1 first)" }

$recon = Join-Path $root 'RPM-Recon.ps1'
if (!(Test-Path $recon)) { throw "Missing: $recon" }

$hp = (Resolve-Path -LiteralPath $hosts).Path
$workerArgs =
  if ($PlanCsv) { '-Apply -Plan "{0}"' -f (Resolve-Path -LiteralPath $PlanCsv).Path }
  else          { '-Apply' }

& $recon -HostsPath $hp -MaxParallel 8 -MaxWaitSeconds 120 -PollSeconds 4 -WorkerArgs $workerArgs
