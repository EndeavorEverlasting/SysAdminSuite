<#
.SYNOPSIS
    Disables local screensaver, display timeout, sleep, and optional hibernate behavior.

.DESCRIPTION
    Field-safe workstation readiness tool for Cybernet, Neuron, and shared clinical workstations.
    This script combines the legacy file-share batch behavior into a SysAdminSuite QRTask with:
      - Admin validation for machine power-policy changes
      - HKCU / loaded-user screensaver registry updates
      - JSON + TXT evidence artifacts
      - Dry-run support
      - Explicit tracker line for deployment records

    This does not replace OU / GPO work. If domain policy later re-enables screensaver settings,
    the proper fix is still the approved NoScreensaver OU / policy exception path.

.PARAMETER SkipPowerPolicy
    Only update screensaver registry settings. Do not run powercfg.

.PARAMETER DisableHibernateFile
    Runs powercfg /hibernate off. Omit this unless the deployment standard calls for it.

.PARAMETER IncludeLoadedUsers
    Also update all currently loaded non-system user hives under HKU. Requires elevation.

.PARAMETER WhatIf
    Preview intended changes without writing registry values or running powercfg.

.PARAMETER OutDir
    Output directory for TXT and JSON artifacts.

.EXAMPLE
    powershell.exe -NoP -EP Bypass -File .\QRTasks\Set-DisableScreensaver.ps1

.EXAMPLE
    powershell.exe -NoP -EP Bypass -File .\QRTasks\Set-DisableScreensaver.ps1 -IncludeLoadedUsers -DisableHibernateFile

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipPowerPolicy,
    [switch]$DisableHibernateFile,
    [switch]$IncludeLoadedUsers,
    [string]$OutDir,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-DirectorySafe {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Invoke-PowerCfgSafe {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Actions
    )

    $cmdText = "powercfg $($Arguments -join ' ')"
    if ($WhatIf) {
        $Lines.Add("WHATIF: $cmdText")
        $Actions.Add([pscustomobject]@{ Type = 'powercfg'; Target = $cmdText; Status = 'WHATIF' })
        return
    }

    try {
        $exe = Join-Path $env:WINDIR 'System32\powercfg.exe'
        $p = Start-Process -FilePath $exe -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            throw "Exit code $($p.ExitCode)"
        }
        $Lines.Add("OK: $cmdText")
        $Actions.Add([pscustomobject]@{ Type = 'powercfg'; Target = $cmdText; Status = 'OK' })
    } catch {
        $Lines.Add("FAIL: $cmdText :: $($_.Exception.Message)")
        $Actions.Add([pscustomobject]@{ Type = 'powercfg'; Target = $cmdText; Status = 'FAIL'; Error = $_.Exception.Message })
    }
}

function Set-RegistryValueSafe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Actions
    )

    $target = "$Path :: $Name = '$Value'"
    if ($WhatIf) {
        $Lines.Add("WHATIF: $target")
        $Actions.Add([pscustomobject]@{ Type = 'registry'; Target = $target; Status = 'WHATIF' })
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
        $Lines.Add("OK: $target")
        $Actions.Add([pscustomobject]@{ Type = 'registry'; Target = $target; Status = 'OK' })
    } catch {
        $Lines.Add("FAIL: $target :: $($_.Exception.Message)")
        $Actions.Add([pscustomobject]@{ Type = 'registry'; Target = $target; Status = 'FAIL'; Error = $_.Exception.Message })
    }
}

function Get-LoadedUserDesktopRegistryPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    $paths.Add('HKCU:\Control Panel\Desktop')

    if (-not $IncludeLoadedUsers) {
        return $paths
    }

    $loaded = Get-ChildItem -Path Registry::HKEY_USERS -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSChildName -match '^S-1-5-21-' -and
            $_.PSChildName -notmatch '_Classes$'
        }

    foreach ($hive in $loaded) {
        $paths.Add("Registry::HKEY_USERS\$($hive.PSChildName)\Control Panel\Desktop")
    }

    return $paths | Select-Object -Unique
}

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $OutDir = Join-Path $repoRoot 'GetInfo\Output\QRTasks'
}
New-DirectorySafe -Path $OutDir

$safeComputer = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'UNKNOWNHOST' }
$txtPath = Join-Path $OutDir "DisableScreensaver_$safeComputer.txt"
$jsonPath = Join-Path $OutDir "DisableScreensaver_$safeComputer.json"

$lines = New-Object System.Collections.Generic.List[string]
$actions = New-Object System.Collections.Generic.List[object]
$lines.Add("Disable screensaver readiness -- $safeComputer -- $timestamp")
$lines.Add(('=' * 80))
$lines.Add('')
$lines.Add("User: $env:USERNAME")
$lines.Add("Admin: $(Test-IsAdmin)")
$lines.Add("Mode: $(if ($WhatIf) { 'WHATIF' } else { 'APPLY' })")
$lines.Add('')

if (-not $SkipPowerPolicy -and -not (Test-IsAdmin)) {
    $lines.Add('ERROR: Power-policy changes require Administrator. Registry-only mode can run without elevation for HKCU.')
    $lines.Add("TRACKER: $safeComputer | DisableScreensaver | FAIL | Not elevated for power policy | $timestamp")
    ($lines -join [Environment]::NewLine) | Set-Content -LiteralPath $txtPath -Encoding UTF8
    [pscustomobject]@{ ComputerName = $safeComputer; Status = 'FAIL'; Reason = 'Not elevated'; Timestamp = $timestamp; Actions = @($actions) } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-Host ($lines -join [Environment]::NewLine)
    exit 1
}

$desktopPaths = Get-LoadedUserDesktopRegistryPaths
$lines.Add('Screensaver registry targets:')
foreach ($p in $desktopPaths) { $lines.Add("  $p") }
$lines.Add('')

foreach ($path in $desktopPaths) {
    Set-RegistryValueSafe -Path $path -Name 'ScreenSaveActive' -Value '0' -Lines $lines -Actions $actions
    Set-RegistryValueSafe -Path $path -Name 'ScreenSaveTimeOut' -Value '0' -Lines $lines -Actions $actions
    Set-RegistryValueSafe -Path $path -Name 'ScreenSaverIsSecure' -Value '0' -Lines $lines -Actions $actions
    Set-RegistryValueSafe -Path $path -Name 'SCRNSAVE.EXE' -Value '' -Lines $lines -Actions $actions
}

if (-not $SkipPowerPolicy) {
    $lines.Add('')
    $lines.Add('Power policy updates:')
    Invoke-PowerCfgSafe -Arguments @('/change', 'standby-timeout-ac', '0') -Lines $lines -Actions $actions
    Invoke-PowerCfgSafe -Arguments @('/change', 'standby-timeout-dc', '0') -Lines $lines -Actions $actions
    Invoke-PowerCfgSafe -Arguments @('/change', 'monitor-timeout-ac', '0') -Lines $lines -Actions $actions
    Invoke-PowerCfgSafe -Arguments @('/change', 'monitor-timeout-dc', '0') -Lines $lines -Actions $actions
    Invoke-PowerCfgSafe -Arguments @('/setacvalueindex', 'scheme_current', 'sub_buttons', 'pbuttonaction', '0') -Lines $lines -Actions $actions
    Invoke-PowerCfgSafe -Arguments @('/setdcvalueindex', 'scheme_current', 'sub_buttons', 'pbuttonaction', '0') -Lines $lines -Actions $actions
    Invoke-PowerCfgSafe -Arguments @('/setactive', 'scheme_current') -Lines $lines -Actions $actions

    if ($DisableHibernateFile) {
        Invoke-PowerCfgSafe -Arguments @('/hibernate', 'off') -Lines $lines -Actions $actions
    } else {
        $lines.Add('SKIP: hibernate file unchanged. Use -DisableHibernateFile when required.')
    }
}

$failures = @($actions | Where-Object { $_.Status -eq 'FAIL' })
$status = if ($failures.Count -gt 0) { 'PARTIAL' } else { 'OK' }
$lines.Add('')
$lines.Add("TRACKER: $safeComputer | DisableScreensaver | $status | actions=$($actions.Count) | failures=$($failures.Count) | $timestamp")
$lines.Add('')
$lines.Add(('=' * 80))
$lines.Add("TXT:  $txtPath")
$lines.Add("JSON: $jsonPath")

($lines -join [Environment]::NewLine) | Set-Content -LiteralPath $txtPath -Encoding UTF8
[pscustomobject]@{
    ComputerName = $safeComputer
    UserName     = $env:USERNAME
    IsAdmin      = Test-IsAdmin
    Status       = $status
    Timestamp    = $timestamp
    WhatIf       = [bool]$WhatIf
    Actions      = @($actions)
    TxtPath      = $txtPath
    JsonPath     = $jsonPath
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host ($lines -join [Environment]::NewLine)
if ($failures.Count -gt 0) { exit 2 }
exit 0
