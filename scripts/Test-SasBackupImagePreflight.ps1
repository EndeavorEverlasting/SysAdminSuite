#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only preflight for a Windows system-image backup target.
.DESCRIPTION
    Verifies source/target identity separation, expected target label, NTFS target,
    disk/volume health, repeated target visibility, source free-space headroom, and
    target raw-capacity headroom. It does not format, repair, delete, resize, mount,
    dismount, encrypt, decrypt, or otherwise mutate a disk or volume.
#>
[CmdletBinding()]
param(
    [string]$SourceDrive = 'C',

    [Parameter(Mandatory = $true)]
    [string]$TargetDrive,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedTargetLabel,

    [ValidateRange(1, 1024)]
    [double]$MinimumSourceFreeGB = 20,

    [ValidateRange(0, 1024)]
    [double]$MinimumTargetHeadroomGB = 20,

    [ValidateRange(1, 120)]
    [int]$StabilitySamples = 5,

    [ValidateRange(0, 60)]
    [int]$StabilityDelaySeconds = 2,

    [string]$OutputJson
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'SasBackupImagePreflight.psm1'
Import-Module $modulePath -Force

$result = Invoke-SasBackupImagePreflight `
    -SourceDrive $SourceDrive `
    -TargetDrive $TargetDrive `
    -ExpectedTargetLabel $ExpectedTargetLabel `
    -MinimumSourceFreeGB $MinimumSourceFreeGB `
    -MinimumTargetHeadroomGB $MinimumTargetHeadroomGB `
    -StabilitySamples $StabilitySamples `
    -StabilityDelaySeconds $StabilityDelaySeconds

Write-Host ''
Write-Host '=== SAS BACKUP IMAGE PREFLIGHT ===' -ForegroundColor Cyan
Write-Host ('Safety mode:       {0}' -f $result.SafetyMode)
Write-Host ('Decision:          {0}' -f $result.Decision)
Write-Host ('Source:            {0}: disk {1}, {2} GB used, {3} GB free' -f $result.Source.DriveLetter, $result.Source.DiskNumber, $result.Source.UsedGB, $result.Source.FreeGB)
Write-Host ('Target:            {0}: disk {1}, label "{2}", {3}, {4} GB free' -f $result.Target.DriveLetter, $result.Target.DiskNumber, $result.Target.Label, $result.Target.FileSystem, $result.Target.FreeGB)
Write-Host ('Target stability:  {0}/{1} samples' -f $result.Stability.SamplesPassed, $result.Stability.Samples)
Write-Host ('Raw headroom:      {0} GB' -f $result.Capacity.RawHeadroomGB)

if ($result.Reasons.Count -gt 0) {
    Write-Host 'Blocking reasons:' -ForegroundColor Yellow
    foreach ($reason in $result.Reasons) {
        Write-Host ('  - {0}' -f $reason) -ForegroundColor Yellow
    }
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $parent = Split-Path -Parent $OutputJson
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        throw "OutputJson parent directory does not exist: $parent"
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputJson -Encoding UTF8
    Write-Host ('Evidence JSON:     {0}' -f $OutputJson)
}

if ($result.Decision -ne 'READY') {
    exit 2
}
exit 0
