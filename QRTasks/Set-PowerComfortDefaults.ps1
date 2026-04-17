<#
.SYNOPSIS
    Applies a "comfort" power preset on all power schemes, or reverts using the last backup.

.DESCRIPTION
    Apply mode: exports each scheme to .pow under GetInfo\Output\QRTasks, then sets display/sleep/disk/button/lid.
    Revert mode: imports those backups (replacing schemes by deleting prior GUIDs after switching active).

.PARAMETER Revert
    Restores power schemes from the last backup created by this script on this computer.

.PARAMETER DisableHibernateFile
    If set, runs 'powercfg /hibernate off' after apply. Not used with -Revert.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    Revert uses powercfg /import (new GUIDs) then /delete on old GUIDs; requires elevation.
#>
param(
    [switch]$Revert,

    [switch]$DisableHibernateFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-PowerCfg {
    param(
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $exe = Join-Path $env:WINDIR 'System32\powercfg.exe'
    $p = Start-Process -FilePath $exe -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "powercfg $($Arguments -join ' ') exited $($p.ExitCode)"
    }
}

function Invoke-PowerCfgWithOutput {
    param(
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $exe = Join-Path $env:WINDIR 'System32\powercfg.exe'
    $combined = & $exe @Arguments 2>&1 | Out-String
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        StdOut   = $combined
        StdErr   = ''
    }
}

function Get-PowerSchemeList {
    $schemes = [System.Collections.Generic.List[object]]::new()
    $list = & (Join-Path $env:WINDIR 'System32\powercfg.exe') '/list' 2>&1
    foreach ($line in $list) {
        if ($line -match 'Power Scheme GUID:\s*([a-f0-9-]+)\s+\(([^)]+)\)\s*(\*)?') {
            $schemes.Add([pscustomobject]@{
                    Guid   = $Matches[1]
                    Name   = $Matches[2]
                    Active = ($Matches[3] -eq '*')
                })
        }
    }
    return $schemes
}

function Get-ImportResultGuid {
    param([string]$Text)
    if ($Text -match '(?i)GUID:\s*([a-f0-9-]{36})') {
        return $Matches[1]
    }
    return $null
}

function Write-ComfortReport {
    param(
        [string]$OutFile,
        [System.Collections.Generic.List[string]]$Lines
    )
    $text = ($Lines -join [Environment]::NewLine)
    $text | Out-File -LiteralPath $OutFile -Encoding UTF8
    Write-Host $text
}

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$_outDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path -LiteralPath $_outDir)) {
    New-Item -ItemType Directory -Path $_outDir -Force | Out-Null
}
$outFile = Join-Path $_outDir "PowerComfort_$($env:COMPUTERNAME).txt"
$backupRoot = Join-Path $_outDir "PowerComfortBackup_$($env:COMPUTERNAME)"
$metaPath = Join-Path $backupRoot 'meta.json'

$powerButtonAction = '7648efa3-dd9c-4e3e-b566-50f929386280'

# ── Revert ──────────────────────────────────────────────────────────
if ($Revert) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Power comfort REVERT -- $env:COMPUTERNAME -- $timestamp")
    $lines.Add(('=' * 80))
    $lines.Add('')

    if (-not (Test-IsAdmin)) {
        $lines.Add('ERROR: Run PowerShell as Administrator.')
        $lines.Add("TRACKER: $env:COMPUTERNAME | PowerComfortRevert | FAIL | Not elevated | $timestamp")
        Write-ComfortReport -OutFile $outFile -Lines $lines
        exit 1
    }

    if (-not (Test-Path -LiteralPath $metaPath)) {
        $lines.Add("ERROR: No backup found. Expected: $metaPath")
        $lines.Add('Run the apply preset first (without -Revert) to create a backup.')
        $lines.Add("TRACKER: $env:COMPUTERNAME | PowerComfortRevert | FAIL | No backup | $timestamp")
        Write-ComfortReport -OutFile $outFile -Lines $lines
        exit 1
    }

    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $schemeEntries = @($meta.schemes)
    if ($meta.version -ne 1 -or $schemeEntries.Count -eq 0) {
        $lines.Add('ERROR: Backup meta.json is missing version or schemes.')
        Write-ComfortReport -OutFile $outFile -Lines $lines
        exit 1
    }

    $errors = New-Object System.Collections.Generic.List[string]
    $guidMap = @{}

    foreach ($entry in $schemeEntries) {
        $powPath = Join-Path $backupRoot $entry.file
        if (-not (Test-Path -LiteralPath $powPath)) {
            $errors.Add("Missing backup file: $powPath")
            continue
        }
        $r = Invoke-PowerCfgWithOutput -Arguments @('/import', $powPath)
        if ($r.ExitCode -ne 0) {
            $errors.Add("import $($entry.file): exit $($r.ExitCode) $($r.StdErr)")
            continue
        }
        $newGuid = Get-ImportResultGuid -Text ($r.StdOut + $r.StdErr)
        if (-not $newGuid) {
            $errors.Add("import $($entry.file): could not parse new GUID from output: $($r.StdOut)")
            continue
        }
        $guidMap[$entry.guid] = $newGuid
    }

    if ($guidMap.Count -eq 0) {
        $lines.Add('ERROR: No schemes were imported.')
        foreach ($e in $errors) { $lines.Add("  $e") }
        Write-ComfortReport -OutFile $outFile -Lines $lines
        exit 1
    }

    $oldActive = [string]$meta.activeSchemeGuid
    if ($guidMap.ContainsKey($oldActive)) {
        try {
            Invoke-PowerCfg -Arguments @('/setactive', $guidMap[$oldActive])
        } catch {
            $errors.Add("setactive $($guidMap[$oldActive]): $($_.Exception.Message)")
        }
    } else {
        $errors.Add("Active scheme GUID $oldActive was not in backup map; left selection unchanged.")
    }

    foreach ($entry in $schemeEntries) {
        $oldG = $entry.guid
        if (-not $guidMap.ContainsKey($oldG)) { continue }
        try {
            Invoke-PowerCfg -Arguments @('/delete', $oldG)
        } catch {
            $errors.Add("delete $oldG : $($_.Exception.Message)")
        }
    }

    if ($meta.hibernateFileDisabledByApply -eq $true) {
        try {
            $hib = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\powercfg.exe') -ArgumentList '/hibernate', 'on' -Wait -PassThru -NoNewWindow
            if ($hib.ExitCode -ne 0) {
                $errors.Add("powercfg /hibernate on exited $($hib.ExitCode)")
            }
        } catch {
            $errors.Add("hibernate on :: $($_.Exception.Message)")
        }
    }

    $lines.Add("Restored from backup dated $($meta.exportedAt)")
    $lines.Add("Schemes re-imported: $($guidMap.Count)")
    if ($errors.Count -gt 0) {
        $lines.Add('Warnings:')
        foreach ($e in $errors) { $lines.Add("  $e") }
        $lines.Add('')
    }
    $summary = "OK: $env:COMPUTERNAME | PowerComfortRevert | $timestamp"
    if ($errors.Count -gt 0) {
        $summary = "PARTIAL: $env:COMPUTERNAME | PowerComfortRevert | errors=$($errors.Count) | $timestamp"
    }
    $lines.Add("TRACKER: $summary")
    $lines.Add('')
    $lines.Add(('=' * 80))
    $lines.Add("Output: $outFile")
    Write-ComfortReport -OutFile $outFile -Lines $lines
    if ($errors.Count -gt 0) { exit 2 }
    exit 0
}

# ── Apply (comfort preset) ───────────────────────────────────────────
if (-not (Test-IsAdmin)) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Power comfort preset -- $env:COMPUTERNAME -- $timestamp")
    $lines.Add(('=' * 80))
    $lines.Add('')
    $lines.Add('ERROR: Run PowerShell as Administrator. powercfg changes require elevation.')
    $lines.Add('')
    $lines.Add("TRACKER: $env:COMPUTERNAME | PowerComfort | FAIL | Not elevated | $timestamp")
    Write-ComfortReport -OutFile $outFile -Lines $lines
    exit 1
}

$errors = New-Object System.Collections.Generic.List[string]
$schemes = Get-PowerSchemeList
if ($schemes.Count -eq 0) {
    $errors.Add('No power schemes parsed from powercfg /list.')
}

$active = $schemes | Where-Object { $_.Active } | Select-Object -First 1
$activeGuid = if ($active) { $active.Guid } else { $null }

# Backup current schemes (overwrite prior backup folder)
if (Test-Path -LiteralPath $backupRoot) {
    Remove-Item -LiteralPath $backupRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

$metaSchemes = New-Object System.Collections.Generic.List[object]
foreach ($s in $schemes) {
    $fileName = "$($s.Guid).pow"
    $powPath = Join-Path $backupRoot $fileName
    try {
        Invoke-PowerCfg -Arguments @('/export', $powPath, $s.Guid)
        $metaSchemes.Add([pscustomobject]@{
                guid = $s.Guid
                name = $s.Name
                file = $fileName
            })
    } catch {
        $errors.Add("export $($s.Guid): $($_.Exception.Message)")
    }
}

$metaObj = [pscustomobject]@{
    version                      = 1
    computerName                 = $env:COMPUTERNAME
    exportedAt                   = $timestamp
    activeSchemeGuid             = $activeGuid
    hibernateFileDisabledByApply = [bool]$DisableHibernateFile
    schemes                      = @($metaSchemes)
}
$metaObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metaPath -Encoding UTF8

if ($metaSchemes.Count -eq 0) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Power comfort preset -- $env:COMPUTERNAME -- $timestamp")
    $lines.Add(('=' * 80))
    $lines.Add('ERROR: Backup failed; no schemes exported. Aborting without applying preset.')
    foreach ($e in $errors) { $lines.Add("  $e") }
    $lines.Add("TRACKER: $env:COMPUTERNAME | PowerComfort | FAIL | No backup | $timestamp")
    Write-ComfortReport -OutFile $outFile -Lines $lines
    exit 1
}

foreach ($s in $schemes) {
    $g = $s.Guid
    $ops = @(
        @('/setacvalueindex', $g, 'SUB_VIDEO', 'VIDEOIDLE', '0'),
        @('/setdcvalueindex', $g, 'SUB_VIDEO', 'VIDEOIDLE', '0'),
        @('/setacvalueindex', $g, 'SUB_SLEEP', 'STANDBYIDLE', '0'),
        @('/setdcvalueindex', $g, 'SUB_SLEEP', 'STANDBYIDLE', '0'),
        @('/setacvalueindex', $g, 'SUB_SLEEP', 'HIBERNATEIDLE', '0'),
        @('/setdcvalueindex', $g, 'SUB_SLEEP', 'HIBERNATEIDLE', '0'),
        @('/setacvalueindex', $g, 'SUB_DISK', 'DISKIDLE', '0'),
        @('/setdcvalueindex', $g, 'SUB_DISK', 'DISKIDLE', '0'),
        @('/setacvalueindex', $g, 'SUB_BUTTONS', $powerButtonAction, '0'),
        @('/setdcvalueindex', $g, 'SUB_BUTTONS', $powerButtonAction, '0'),
        @('/setacvalueindex', $g, 'SUB_BUTTONS', 'LIDACTION', '0'),
        @('/setdcvalueindex', $g, 'SUB_BUTTONS', 'LIDACTION', '0')
    )
    foreach ($pcArgs in $ops) {
        try {
            Invoke-PowerCfg -Arguments $pcArgs
        } catch {
            $errors.Add("$g :: $($pcArgs -join ' ') :: $($_.Exception.Message)")
        }
    }
}

if ($activeGuid) {
    try {
        Invoke-PowerCfg -Arguments @('/setactive', $activeGuid)
    } catch {
        $errors.Add("setactive $activeGuid :: $($_.Exception.Message)")
    }
}

if ($DisableHibernateFile) {
    try {
        $hib = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\powercfg.exe') -ArgumentList '/hibernate', 'off' -Wait -PassThru -NoNewWindow
        if ($hib.ExitCode -ne 0) {
            $errors.Add("powercfg /hibernate off exited $($hib.ExitCode)")
        }
    } catch {
        $errors.Add("hibernate off :: $($_.Exception.Message)")
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Power comfort preset -- $env:COMPUTERNAME -- $timestamp")
$lines.Add(('=' * 80))
$lines.Add('')
$lines.Add("Backup: $backupRoot")
$lines.Add("Schemes updated: $($schemes.Count)")
$lines.Add("Active scheme GUID (re-applied): $activeGuid")
$lines.Add('Preset: display off=never, sleep=never, hibernate after=never, disk off=never, power button=do nothing, lid=do nothing')
if ($DisableHibernateFile) {
    $lines.Add('Hibernate file: disabled (powercfg /hibernate off)')
} else {
    $lines.Add('Hibernate file: unchanged (omit -DisableHibernateFile to leave default OS behavior)')
}
$lines.Add('')
if ($errors.Count -gt 0) {
    $lines.Add('Warnings / partial failures:')
    foreach ($e in $errors) { $lines.Add("  $e") }
    $lines.Add('')
}

$summary = "OK: $env:COMPUTERNAME | PowerComfort | schemes=$($schemes.Count) | $timestamp"
if ($errors.Count -gt 0) {
    $summary = "PARTIAL: $env:COMPUTERNAME | PowerComfort | schemes=$($schemes.Count) | errors=$($errors.Count) | $timestamp"
}
$lines.Add("TRACKER: $summary")
$lines.Add('')
$lines.Add(('=' * 80))
$lines.Add("Output: $outFile")

Write-ComfortReport -OutFile $outFile -Lines $lines
if ($errors.Count -gt 0) { exit 2 }
exit 0
