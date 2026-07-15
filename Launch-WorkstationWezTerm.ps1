[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'scripts\Start-SasWindowsTmuxWorkspace.ps1') -LaunchGui -Confirm:$false
