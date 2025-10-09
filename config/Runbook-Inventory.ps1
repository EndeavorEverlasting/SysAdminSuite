<# Runbook-Inventory.ps1
   Inventory installed software on source/target → Repo\inventory\<HOST>\*.csv|html + software_superset.csv
#>

[CmdletBinding()]
param(
  [string]   $RepoHost     = $env:REPO_HOST   ?? 'LPW003ASI037',
  [string[]] $ComputerName = @('LPW003ASI037','LPW003ASI173')
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

# 0) Tools + repo
. .\GoLiveTools.ps1 -RepoHost $RepoHost
Preflight-Repo -RepoRoot $RepoRoot | Out-Null
"Using RepoRoot: $RepoRoot"

# 1) Hygiene
Get-ChildItem *.ps1 | Unblock-File | Out-Null
New-Item -ItemType Directory -Force .\Logs | Out-Null
$ts = ".\Logs\INV-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)
Start-Transcript -Path $ts -Append | Out-Null

# 2) Guard: fix the old '$cn:' interpolation if present
$inv = Join-Path $here 'Inventory-Software.patched.ps1'
if (-not (Test-Path $inv)) { $inv = Join-Path $here 'Inventory-Software.ps1' }
if (-not (Test-Path $inv)) { throw "Inventory script not found in $here" }
$raw = Get-Content -Raw $inv
if ($raw -match 'Failed to inventory \$cn:') {
  $raw = $raw -replace 'Failed to inventory \$cn:', 'Failed to inventory $($cn):'
  $raw | Set-Content -Encoding UTF8 $inv
  Write-Host "Patched interpolation in $(Split-Path -Leaf $inv)" -ForegroundColor Yellow
}

# 3) Run inventory
Write-Host "Inventorying: $($ComputerName -join ', ')" -ForegroundColor Cyan
& $inv -ComputerName $ComputerName -RepoHost $RepoHost -Verbose

Stop-Transcript | Out-Null

# 4) Show outputs
$invRoot = Join-Path $RepoRoot 'inventory'
$paths = @(
  Join-Path $invRoot "$($ComputerName[0])\installed_software_$($ComputerName[0]).csv",
  Join-Path $invRoot "$($ComputerName[0])\installed_software_$($ComputerName[0]).html",
  Join-Path $invRoot 'software_superset.csv'
)
$paths | ForEach-Object {
  if (Test-Path $_) { Write-Host "✓ $_" -ForegroundColor Green } else { Write-Warning "Missing: $_" }
}
Write-Host "Transcript: $ts"
