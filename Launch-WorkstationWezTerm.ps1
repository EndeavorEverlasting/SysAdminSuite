<#
.SYNOPSIS
    Launcher for the SysAdminSuite developer workstation WezTerm workspace.
.DESCRIPTION
    Idempotently checks for WezTerm on the host. Launches the terminal inside the repository
    root workspace. Falls back to native PowerShell if WezTerm is unavailable.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "targets/README.md"))) {
    $repoRoot = (Get-Location).Path
}

Write-Host "SysAdminSuite Developer Workstation Launcher"
Write-Host "============================================="

# Detect WezTerm
$wezterm = Get-Command wezterm -ErrorAction SilentlyContinue
if ($wezterm) {
    Write-Host "[INFO] WezTerm detected at: $($wezterm.Source)"
    Write-Host "[INFO] Starting WezTerm workspace at: $repoRoot"
    
    # Launch WezTerm asynchronously pointing to repository root
    Start-Process -FilePath $wezterm.Source -ArgumentList "start", "--directory", $repoRoot -WindowStyle Hidden
} else {
    Write-Warning "WezTerm was not found on the PATH."
    Write-Host "[INFO] Falling back to native PowerShell session..."
    
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        Start-Process -FilePath $pwsh.Source -ArgumentList "-NoExit", "-Command", "Set-Location '$repoRoot'"
    } else {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", "Set-Location '$repoRoot'"
    }
}
