<#
.SYNOPSIS
    Reverts power schemes using the backup created by Set-PowerComfortDefaults.ps1.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module. Requires elevation.
#>
$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot 'Set-PowerComfortDefaults.ps1'
& $core -Revert
