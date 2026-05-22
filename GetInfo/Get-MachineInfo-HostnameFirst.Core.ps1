param(
  [string]$ListPath   = "C:\Temp\hostlist.txt",
  [string]$OutputPath = (Join-Path $PSScriptRoot 'Output\MachineInfo\MachineInfo_HostnameFirst_Output.csv'),
  [int]$Throttle      = 15,
  [switch]$PreflightPassed
)

if (-not $PreflightPassed) {
  throw "Direct execution is blocked. Run Get-MachineInfo-HostnameFirst.ps1 so the Northwell WAB preflight runs first."
}

Write-Host "[CORE] Protected core started." -ForegroundColor Cyan
Write-Host "[CORE] ListPath: $ListPath" -ForegroundColor Gray
Write-Host "[CORE] OutputPath: $OutputPath" -ForegroundColor Gray

if (-not (Test-Path -Path $ListPath)) {
  throw "List file not found: $ListPath"
}

$hostCount = @(
  Get-Content -Path $ListPath |
    Where-Object { $_ -and $_.Trim() -ne '' } |
    ForEach-Object { $_.Trim() } |
    Sort-Object -Unique
).Count

Write-Host "[CORE] Loaded $hostCount hostname(s)." -ForegroundColor Cyan
Write-Host "[CORE] Phase 1 of 2: hostname probe-order checks." -ForegroundColor Cyan

$probeOrderScript = Join-Path $PSScriptRoot 'Test-MachineInfoHostnameProbeOrder.ps1'
if (Test-Path -LiteralPath $probeOrderScript) {
  $probeOrderOutput = Join-Path (Split-Path -Path $OutputPath -Parent) 'MachineInfo_HostnameFirst_ProbeOrder.csv'
  & $probeOrderScript -ListPath $ListPath -OutputPath $probeOrderOutput
  Write-Host "[CORE] Phase 1 complete. Probe-order output: $probeOrderOutput" -ForegroundColor Green
} else {
  Write-Warning "Probe-order helper not found: $probeOrderScript"
}

Write-Host "[CORE] Phase 2 of 2: machine identity collection." -ForegroundColor Cyan
Write-Host "[CORE] Some hosts may take longer when remote management ports do not respond." -ForegroundColor Yellow

$implementationScript = Join-Path $PSScriptRoot 'Get-MachineInfo-HostnameFirst.Implementation.ps1'
if (-not (Test-Path -LiteralPath $implementationScript)) {
  throw "Implementation script not found: $implementationScript"
}

& $implementationScript -ListPath $ListPath -OutputPath $OutputPath -Throttle $Throttle
$scriptExitCode = $LASTEXITCODE

Write-Host "[CORE] Phase 2 complete. Main output: $OutputPath" -ForegroundColor Green
Write-Host "[CORE] Protected core finished." -ForegroundColor Green

if ($scriptExitCode -and $scriptExitCode -ne 0) { exit $scriptExitCode }
