#Requires -Version 5.1
<#
.SYNOPSIS
Restore the Cybernet integrated-display button state recorded by a prior successful disable run.

.DESCRIPTION
Consumes the exact restore manifest emitted by the canonical DDC/CI Apply operation. It never invents a
factory value and refuses live mutation without explicit authorization and ShouldProcess confirmation.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [ValidateRange(-1, 64)][int]$MonitorIndex = -1,
    [string]$RestoreManifest,
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
if (-not $FixtureMode -and [string]::IsNullOrWhiteSpace($RestoreManifest)) {
    throw 'Enable-PrivacyButton requires -RestoreManifest from a prior successful Disable-PrivacyButton run.'
}
if (-not $FixtureMode -and -not $WhatIfPreference -and -not $AllowTargetMutation) {
    throw 'Refusing Privacy/Menu button restore without -AllowTargetMutation. Use -WhatIf or -FixtureMode first.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$core = Join-Path $repoRoot 'scripts\Invoke-SasCybernetDisplayButtonControl.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    throw "Missing canonical Cybernet display-button controller: $core"
}

$invoke = @{
    ComputerName = $ComputerName
    Operation = 'Restore'
    MonitorIndex = $MonitorIndex
    MaxTargets = $MaxTargets
}
if (-not [string]::IsNullOrWhiteSpace($TargetsCsv)) { $invoke.TargetsCsv = $TargetsCsv }
if (-not [string]::IsNullOrWhiteSpace($RestoreManifest)) { $invoke.RestoreManifest = $RestoreManifest }
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $invoke.OutputRoot = $OutputRoot }
if ($FixtureMode) { $invoke.FixtureMode = $true }

if ($WhatIfPreference) {
    & $core @invoke -WhatIf
    exit $LASTEXITCODE
}
if (-not $FixtureMode) {
    $scope = if ($ComputerName.Count -gt 0) { $ComputerName -join ',' } else { $TargetsCsv }
    if (-not $PSCmdlet.ShouldProcess($scope, 'Restore exact original MCCS VCP 0xCA values and verify readback')) {
        return
    }
    $invoke.AllowTargetMutation = $true
    & $core @invoke -Confirm:$false
    exit $LASTEXITCODE
}

& $core @invoke
exit $LASTEXITCODE
