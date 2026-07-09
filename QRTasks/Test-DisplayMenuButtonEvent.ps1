#Requires -Version 5.1
<#
.SYNOPSIS
    Field probe for whether a physical display/menu button is visible to Windows.

.DESCRIPTION
    This read-only QRTask opens a short observation window, asks the technician to press the physical
    display/menu button once, then captures relevant Windows event log entries created during that
    window. It does not change power policy, firmware, registry, services, scheduled tasks, or logs.

    Classification is evidence only:
      - OBSERVED_WINDOWS_EVENT means Windows logged something plausibly related during the press window.
      - NO_WINDOWS_EVENT_OBSERVED means Windows did not log a related event during this run; the button
        may be firmware-only / display-OSD controlled, or it may require a different observation method.

.PARAMETER PressWindowSeconds
    Seconds to observe after the prompt appears. Default: 20.

.PARAMETER LookbackMinutes
    Extra minutes of context to include in the report header. Default: 2.

.PARAMETER MaxEvents
    Maximum matching events to include in the report. Default: 40.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    Requires only local Windows event log read access. No target-side writes beyond the local report file.
#>
param(
    [ValidateRange(5, 300)]
    [int]$PressWindowSeconds = 20,

    [ValidateRange(1, 60)]
    [int]$LookbackMinutes = 2,

    [ValidateRange(1, 200)]
    [int]$MaxEvents = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-Line {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $Lines.Add($Text)
}

function Get-RelevantEventMatches {
    param(
        [Parameter(Mandatory = $true)][datetime]$StartTime,
        [Parameter(Mandatory = $true)][datetime]$EndTime,
        [Parameter(Mandatory = $true)][int]$Limit
    )

    $logs = @(
        'System',
        'Application',
        'Microsoft-Windows-Kernel-Power/Thermal-Operational',
        'Microsoft-Windows-DriverFrameworks-UserMode/Operational',
        'Microsoft-Windows-UserModePowerService/Operational',
        'Microsoft-Windows-Diagnostics-Performance/Operational'
    )

    $providerPattern = '(?i)(kernel-power|usermodepowerservice|power-troubleshooter|display|dxgkrnl|monitor|kernel-pnp|driverframeworks|hid|button)'
    $messagePattern = '(?i)(power|display|monitor|screen|button|lid|sleep|standby|hibernate|video|pnp|hid|device|disconnect|connect)'
    $matches = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($log in $logs) {
        try {
            $events = Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $StartTime; EndTime = $EndTime } -ErrorAction Stop
            foreach ($event in $events) {
                $providerName = [string]$event.ProviderName
                $message = [string]$event.Message
                if ($providerName -match $providerPattern -or $message -match $messagePattern) {
                    $matches.Add([pscustomobject]@{
                        TimeCreated  = $event.TimeCreated
                        LogName      = $log
                        ProviderName = $providerName
                        Id           = $event.Id
                        LevelDisplay = $event.LevelDisplayName
                        Message      = ($message -replace '\s+', ' ').Trim()
                    })
                    if ($matches.Count -ge $Limit) {
                        return [pscustomobject]@{ Events = @($matches); Errors = @($errors) }
                    }
                }
            }
        } catch {
            $errors.Add("$log :: $($_.Exception.Message)")
        }
    }

    return [pscustomobject]@{ Events = @($matches); Errors = @($errors) }
}

$timestamp = Get-Date
$timestampText = $timestamp.ToString('yyyy-MM-dd HH:mm:ss')
$outDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$outFile = Join-Path $outDir "DisplayMenuButtonProbe_$($env:COMPUTERNAME)_$($timestamp.ToString('yyyyMMdd_HHmmss')).txt"

$lines = New-Object System.Collections.Generic.List[string]
Add-Line -Lines $lines -Text "Display/menu button Windows-event probe -- $env:COMPUTERNAME -- $timestampText"
Add-Line -Lines $lines -Text ('=' * 80)
Add-Line -Lines $lines -Text ''
Add-Line -Lines $lines -Text 'Purpose: determine whether the physical display/menu button produces a Windows-observable event.'
Add-Line -Lines $lines -Text 'This is read-only evidence capture. It does not apply or revert power settings.'
Add-Line -Lines $lines -Text ''
Add-Line -Lines $lines -Text "Operator action: press the physical display/menu button once during the next $PressWindowSeconds seconds."
Add-Line -Lines $lines -Text 'Do not press the physical power button during this probe unless that is the specific button under test.'

Write-Host ''
Write-Host "Display/menu button Windows-event probe" -ForegroundColor Cyan
Write-Host "Press the physical display/menu button once during the next $PressWindowSeconds seconds." -ForegroundColor Yellow
Write-Host "Report will be written to: $outFile" -ForegroundColor DarkGray
Write-Host ''

$pressStart = Get-Date
Start-Sleep -Seconds $PressWindowSeconds
$pressEnd = Get-Date
$queryStart = $pressStart.AddMinutes(-1 * $LookbackMinutes)

$result = Get-RelevantEventMatches -StartTime $queryStart -EndTime $pressEnd -Limit $MaxEvents
$events = @($result.Events)
$eventCount = $events.Count
$class = if ($eventCount -gt 0) { 'OBSERVED_WINDOWS_EVENT' } else { 'NO_WINDOWS_EVENT_OBSERVED' }

Add-Line -Lines $lines -Text ''
Add-Line -Lines $lines -Text "Observation window: $($pressStart.ToString('yyyy-MM-dd HH:mm:ss')) through $($pressEnd.ToString('yyyy-MM-dd HH:mm:ss'))"
Add-Line -Lines $lines -Text "Context lookback start: $($queryStart.ToString('yyyy-MM-dd HH:mm:ss'))"
Add-Line -Lines $lines -Text "Classification: $class"
Add-Line -Lines $lines -Text "Matching events captured: $eventCount"
Add-Line -Lines $lines -Text ''

if ($eventCount -gt 0) {
    Add-Line -Lines $lines -Text 'Events:'
    foreach ($event in $events) {
        Add-Line -Lines $lines -Text "- $($event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')) | $($event.LogName) | $($event.ProviderName) | Id=$($event.Id) | $($event.LevelDisplay)"
        if ($event.Message) {
            Add-Line -Lines $lines -Text "  $($event.Message)"
        }
    }
} else {
    Add-Line -Lines $lines -Text 'No matching Windows events were observed during this run.'
    Add-Line -Lines $lines -Text 'Interpretation: the physical display/menu button may be firmware-only / OSD-controlled, or it may not emit a Windows event under this observation method.'
}

$readErrors = @($result.Errors)
if ($readErrors.Count -gt 0) {
    Add-Line -Lines $lines -Text ''
    Add-Line -Lines $lines -Text 'Read warnings:'
    foreach ($errorText in $readErrors) {
        Add-Line -Lines $lines -Text "  $errorText"
    }
}

Add-Line -Lines $lines -Text ''
Add-Line -Lines $lines -Text "TRACKER: $env:COMPUTERNAME | DisplayMenuButtonProbe | $class | events=$eventCount | $timestampText"
Add-Line -Lines $lines -Text ''
Add-Line -Lines $lines -Text ('=' * 80)
Add-Line -Lines $lines -Text "Output: $outFile"

$text = $lines -join [Environment]::NewLine
$text | Out-File -LiteralPath $outFile -Encoding UTF8
Write-Host $text

if ($readErrors.Count -gt 0 -and $eventCount -eq 0) { exit 2 }
exit 0
