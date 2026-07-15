[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string]$UserConfigDir = $env:USERPROFILE, [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\workstation'), [string]$FixturePath, [string]$OutputPath, [switch]$AllowTargetMutation, [switch]$LaunchGui)
& (Join-Path $PSScriptRoot 'Invoke-SasWindowsTmuxWorkspace.ps1') -Action Repair @PSBoundParameters
