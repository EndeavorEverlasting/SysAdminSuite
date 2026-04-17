<#
.SYNOPSIS
    Runs the QRTasks power comfort preset (single entry point from EnvSetup).

.DESCRIPTION
    Delegates to QRTasks\Set-PowerComfortDefaults.ps1. Pass -DisableHibernateFile to also run powercfg /hibernate off.
    Pass -Revert to restore from the last backup.
#>
param(
    [switch]$DisableHibernateFile,

    [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot '..\QRTasks\Set-PowerComfortDefaults.ps1'
if (-not (Test-Path -LiteralPath $core)) {
    throw "Missing script: $core"
}
& $core @PSBoundParameters
