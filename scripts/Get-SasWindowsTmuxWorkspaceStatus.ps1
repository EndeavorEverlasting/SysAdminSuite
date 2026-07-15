[CmdletBinding()]
param([string]$UserConfigDir = $env:USERPROFILE, [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\workstation'), [string]$FixturePath, [string]$OutputPath)
& (Join-Path $PSScriptRoot 'Invoke-SasWindowsTmuxWorkspace.ps1') -Action Status @PSBoundParameters
