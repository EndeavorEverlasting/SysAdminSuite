#Requires -Version 5.1
<#
.SYNOPSIS
Disable the Cybernet integrated-display Privacy/Menu and display power buttons through the canonical DDC/CI lane.

.DESCRIPTION
This is a thin hardware-module wrapper around scripts/Invoke-SasCybernetDisplayButtonControl.ps1.
It does not guess at a registry value, vendor service, configuration file, BIOS switch, or utility.
The canonical implementation requires MCCS 2.2 or later, readable VCP 0xCA, read-before-write,
readback of 0x0303, rollback on failed verification, and a generated restore manifest.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [ValidateRange(-1, 64)][int]$MonitorIndex = -1,
    [string]$OutputRoot,
    [ValidateRange(1, 25)][int]$MaxTargets = 25,
    [switch]$AllowTargetMutation,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($FixtureMode -and $AllowTargetMutation) {
    throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.'
}
if (-not $FixtureMode -and -not $WhatIfPreference -and -not $AllowTargetMutation) {
    throw 'Refusing Privacy/Menu button mutation without -AllowTargetMutation. Use -WhatIf or -FixtureMode first.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$core = Join-Path $repoRoot 'scripts\Invoke-SasCybernetDisplayButtonControl.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    throw "Missing canonical Cybernet display-button controller: $core"
}

$invoke = @{
    ComputerName = $ComputerName
    Operation = 'Apply'
    MonitorIndex = $MonitorIndex
    MaxTargets = $MaxTargets
}
if (-not [string]::IsNullOrWhiteSpace($TargetsCsv)) { $invoke.TargetsCsv = $TargetsCsv }
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $invoke.OutputRoot = $OutputRoot }
if ($FixtureMode) { $invoke.FixtureMode = $true }

if ($WhatIfPreference) {
    & $core @invoke -WhatIf
    exit $LASTEXITCODE
}
if (-not $FixtureMode) {
    $scope = if ($ComputerName.Count -gt 0) { $ComputerName -join ',' } else { $TargetsCsv }
    if (-not $PSCmdlet.ShouldProcess($scope, 'Set eligible MCCS VCP 0xCA controls to 0x0303 and verify readback')) {
        return
    }
    $invoke.AllowTargetMutation = $true
    & $core @invoke -Confirm:$false
    exit $LASTEXITCODE
}

& $core @invoke
exit $LASTEXITCODE
