param(
  [string]$ListPath   = "C:\Temp\hostlist.txt",
  [string]$OutputPath = (Join-Path $PSScriptRoot 'Output\MachineInfo\MachineInfo_HostnameFirst_Output.csv'),
  [int]$Throttle      = 15,
  [switch]$PreflightPassed
)

if (-not $PreflightPassed) {
  throw "Direct execution is blocked. Run Get-MachineInfo-HostnameFirst.ps1 so the Northwell WAB preflight runs first."
}

$probeOrderScript = Join-Path $PSScriptRoot 'Test-MachineInfoHostnameProbeOrder.ps1'
if (Test-Path -LiteralPath $probeOrderScript) {
  $probeOrderOutput = Join-Path (Split-Path -Path $OutputPath -Parent) 'MachineInfo_HostnameFirst_ProbeOrder.csv'
  & $probeOrderScript -ListPath $ListPath -OutputPath $probeOrderOutput
} else {
  Write-Warning "Probe-order helper not found: $probeOrderScript"
}

$implementationScript = Join-Path $PSScriptRoot 'Get-MachineInfo-HostnameFirst.Implementation.ps1'
if (-not (Test-Path -LiteralPath $implementationScript)) {
  throw "Implementation script not found: $implementationScript"
}

& $implementationScript -ListPath $ListPath -OutputPath $OutputPath -Throttle $Throttle
