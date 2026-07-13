<#
.SYNOPSIS
    Inspects locally saved Bluetooth driver flush backups.

.DESCRIPTION
    Technician utility to list backup folders and display target identity,
    manifest properties, and verification summaries. All information is shown
    locally without external transmission.
#>
param(
    [string]$BackupPath = (Join-Path $env:APPDATA 'BT_Flush_Backups'),
    [string]$Timestamp
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BackupPath)) {
    Write-Host "No backup root folder found at $BackupPath" -ForegroundColor Yellow
    return
}

# List all subfolders if no timestamp specified
if ($null -eq $Timestamp -or $Timestamp -eq '') {
    $folders = Get-ChildItem -Path $BackupPath -Directory | Sort-Object LastWriteTime -Descending
    if ($folders.Count -eq 0) {
        Write-Host "No backup runs found in $BackupPath" -ForegroundColor Yellow
        return
    }
    Write-Host "`n=== Available Bluetooth Eviction Backups ===" -ForegroundColor Cyan
    $folders | ForEach-Object {
        $runCtxFile = Join-Path $_.FullName 'run-context.json'
        $mode = "Unknown"
        $target = "None"
        if (Test-Path $runCtxFile) {
            try {
                $ctx = Get-Content $runCtxFile -Raw | ConvertFrom-Json
                $mode = $ctx.mode
                if ($ctx.target_selectors) {
                    $target = $ctx.target_selectors.TargetDeviceName
                }
            } catch {}
        }
        [PSCustomObject]@{
            Folder = $_.Name
            Created = $_.LastWriteTime
            Mode = $mode
            Target = $target
        }
    } | Format-Table | Out-Host
    return
}

# Inspect specific run
$runDir = Join-Path $BackupPath $Timestamp
if (-not (Test-Path $runDir)) {
    Write-Host "Backup folder not found: $runDir" -ForegroundColor Red
    return
}

Write-Host "`n=== Inspecting Backup Run: $Timestamp ===" -ForegroundColor Cyan
Write-Host "Path: $runDir"

# Read run-context
$runCtxFile = Join-Path $runDir 'run-context.json'
if (Test-Path $runCtxFile) {
    Write-Host "`n[Run Context]" -ForegroundColor Green
    Get-Content $runCtxFile -Raw | ConvertFrom-Json | Format-List | Out-Host
}

# Read target-identity-before
$idFile = Join-Path $runDir 'target-identity-before.json'
if (Test-Path $idFile) {
    Write-Host "`n[Target Identity (Before)]" -ForegroundColor Green
    $id = Get-Content $idFile -Raw | ConvertFrom-Json
    [PSCustomObject]@{
        FriendlyName = $id.FriendlyName
        MAC          = $id.MAC
        Class        = $id.Class
        Status       = $id.Status
        Present      = $id.Present
        Driver       = $id.DriverInfPath
    } | Format-List | Out-Host
}

# List files in the backup directory with sizes and status
Write-Host "`n[Backup Files Manifest]" -ForegroundColor Green
Get-ChildItem -Path $runDir -File | ForEach-Object {
    $isValidJson = "N/A"
    if ($_.Extension -eq '.json') {
        try {
            $null = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $isValidJson = "Valid"
        } catch {
            $isValidJson = "Corrupt"
        }
    }
    [PSCustomObject]@{
        FileName   = $_.Name
        SizeBytes  = $_.Length
        JSONStatus = $isValidJson
    }
} | Format-Table -AutoSize | Out-Host
