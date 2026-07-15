[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$UserConfigDir = $env:USERPROFILE, [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\workstation'), [string]$FixturePath, [string]$OutputPath, [switch]$LaunchGui)
& (Join-Path $PSScriptRoot 'Invoke-SasWindowsTmuxWorkspace.ps1') -Action Start @PSBoundParameters
