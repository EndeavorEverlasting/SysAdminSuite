#Requires -Version 5.1
<#
.SYNOPSIS
Set the Windows physical power-button action to Do nothing on targeted Cybernets.

.DESCRIPTION
Thin wrapper around the merged, evidence-producing scripts/Invoke-SasCybernetPowerHardening.ps1 authority.
It does not alter sleep, display, disk, lid, hibernate enablement, Start-menu power action, or DDC/CI controls.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
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
    throw 'Refusing power-button mutation without -AllowTargetMutation. Use -WhatIf or -FixtureMode first.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$core = Join-Path $repoRoot 'scripts\Invoke-SasCybernetPowerHardening.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    throw "Missing canonical Cybernet power-hardening controller: $core"
}

$invoke = @{
    ComputerName = $ComputerName
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
    if (-not $PSCmdlet.ShouldProcess($scope, 'Set and verify physical power-button action Do nothing for AC and DC')) {
        return
    }
    $invoke.AllowTargetMutation = $true
    & $core @invoke -Confirm:$false
    exit $LASTEXITCODE
}

& $core @invoke
exit $LASTEXITCODE
