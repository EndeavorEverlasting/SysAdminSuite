#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies that on-site tooling paths referenced by the field matrix still exist in this repo clone.

.DESCRIPTION
    Run from the repo (for example after git pull) before going on site. Does not execute probes or contact remote hosts.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'mapping\Controllers\RPM-Recon.ps1'
    'mapping\Workers\Map-MachineWide.ps1'
    'QRTasks\Invoke-TechTask.ps1'
    'QRTasks\Get-NeuronTrace.ps1'
    'QRTasks\Get-WindowsOptionalFeatures.ps1'
    'Config\Inventory-Software.ps1'
    'GUI\Start-SysAdminSuiteGui.ps1'
    'EnvSetup\Deploy-Shortcuts.ps1'
    'EnvSetup\Deploy-Shortcuts.config.psd1'
)
$failed = $false
foreach ($rel in $required) {
    $full = Join-Path $repoRoot $rel
    if (Test-Path -LiteralPath $full) {
        Write-Host "OK  $rel"
    } else {
        Write-Host "MISSING  $rel"
        $failed = $true
    }
}
if ($failed) {
    Write-Error 'Smoke-OnsiteMatrix: one or more expected files are missing.'
    exit 1
}
Write-Host 'Smoke-OnsiteMatrix: all expected paths present.'
exit 0
