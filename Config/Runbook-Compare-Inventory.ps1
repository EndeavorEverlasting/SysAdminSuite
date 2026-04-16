<# Runbook-Compare-Inventory.ps1
   Compare source vs target hosts for:
   - support file share inventory (\\HOST\c$\support)
   - installed software inventory
   Outputs CSV + HTML under Repo\inventory\comparisons\run_*
#>

[CmdletBinding()]
param(
  [string]$RepoHost = $env:REPO_HOST,
  [Parameter(Mandatory)][string]$SourceHost,
  [Parameter(Mandatory)][string[]]$TargetHost,
  [switch]$SkipSupportFiles,
  [switch]$SkipSoftware,
  [switch]$SkipFileHash
)

if ([string]::IsNullOrWhiteSpace($RepoHost)) { $RepoHost = $SourceHost }

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

# 0) Tools + repo
. .\GoLiveTools.ps1 -RepoHost $RepoHost
Preflight-Repo -RepoRoot $RepoRoot | Out-Null
Write-Host "Using RepoRoot: $RepoRoot" -ForegroundColor Cyan

# 1) Hygiene
Get-ChildItem *.ps1 | Unblock-File | Out-Null
New-Item -ItemType Directory -Force .\Logs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ts = ".\Logs\RUNBOOK-COMPARE-{0}.log" -f $stamp
Start-Transcript -Path $ts -Append | Out-Null

try {
  # 2) Run compare module
  $compareScript = Join-Path $here 'Compare-HostInventory.ps1'
  if (-not (Test-Path -LiteralPath $compareScript)) {
    throw "Compare script not found: $compareScript"
  }

  Write-Host "Comparing source [$SourceHost] to targets [$($TargetHost -join ', ')]" -ForegroundColor Cyan
  & $compareScript `
    -SourceHost $SourceHost `
    -TargetHost $TargetHost `
    -RepoRoot $RepoRoot `
    -SkipSupportFiles:$SkipSupportFiles `
    -SkipSoftware:$SkipSoftware `
    -SkipFileHash:$SkipFileHash

  # 3) Show outputs
  $compareRoot = Join-Path $RepoRoot 'inventory\comparisons'
  $latestRun = Get-ChildItem -Path $compareRoot -Directory -Filter 'run_*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1

  if ($latestRun) {
    Write-Host "Latest comparison run: $($latestRun.FullName)" -ForegroundColor Green
    Get-ChildItem -Path $latestRun.FullName -File -ErrorAction SilentlyContinue |
      Sort-Object Name |
      ForEach-Object { Write-Host ("[OUT] {0}" -f $_.FullName) -ForegroundColor Green }
  } else {
    Write-Warning "No comparison run folder found at $compareRoot"
  }
}
finally {
  Stop-Transcript | Out-Null
}

Write-Host "Transcript: $ts"
