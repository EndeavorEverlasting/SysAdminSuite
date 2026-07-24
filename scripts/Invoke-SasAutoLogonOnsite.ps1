#Requires -Version 5.1
<#
.SYNOPSIS
Operator-friendly AutoLogon launcher for field use.

.DESCRIPTION
Keeps request preparation and canonical SYSTEM qualification available, while also exposing a
separate interactive-token pilot for the currently approved no-argument package. All live target
activity remains gated on approved Northwell network posture.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Prepare','Validate','Pilot','Interactive','Evidence')]
    [string]$Action = 'Menu',
    [string]$ComputerName
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$requestDirectory = Join-Path $repoRoot 'survey\input\autologon-system-qualification'
$templatePath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification-request.example.json'
$qualificationScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonSystemQualification.ps1'
$interactiveScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonInteractivePilot.ps1'
$networkGate = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'

foreach ($required in @($templatePath,$qualificationScript,$interactiveScript,$networkGate)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing on-site AutoLogon dependency: $required"
    }
}

function Get-SasQualificationRequests {
    if (-not (Test-Path -LiteralPath $requestDirectory -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $requestDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

function New-SasLocalQualificationRequest {
    New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
    $destination = Join-Path $requestDirectory 'qualification-request.local.json'
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Copy-Item -LiteralPath $templatePath -Destination $destination
        Write-Host 'Created an operator-local qualification request from the tracked template.' -ForegroundColor Green
    }
    else {
        Write-Host 'Using the existing operator-local qualification request.' -ForegroundColor Cyan
    }
    Write-Host "Request: $destination"
    Write-Host 'This path is ignored by git. Replace every REPLACE/placeholder field with approved real values.' -ForegroundColor Yellow
    try { Start-Process -FilePath 'notepad.exe' -ArgumentList @($destination) | Out-Null }
    catch { Write-Warning "Could not open Notepad automatically: $($_.Exception.Message)" }
    return $destination
}

function Confirm-SasRequestExists {
    $requests = @(Get-SasQualificationRequests)
    if ($requests.Count -gt 0) { return $true }
    [void](New-SasLocalQualificationRequest)
    Write-Host ''
    Write-Host 'No live or validation action was started.' -ForegroundColor Yellow
    Write-Host 'Complete the request, save it, then rerun this launcher.'
    return $false
}

function Resolve-SasInteractiveTarget {
    param([string]$RequestedTarget)
    if (-not [string]::IsNullOrWhiteSpace($RequestedTarget)) { return $RequestedTarget.Trim() }
    $typed = (Read-Host 'Enter the exact authorized Cybernet hostname or FQDN').Trim()
    if ([string]::IsNullOrWhiteSpace($typed)) { throw 'An explicit target is required for the interactive AutoLogon pilot.' }
    return $typed
}

if ($Action -eq 'Menu') {
    Clear-Host
    Write-Host 'SysAdminSuite AutoLogon On-Site' -ForegroundColor Cyan
    Write-Host 'Canonical SYSTEM and interactive-token execution are separate proof lanes.' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '[1] Prepare/edit SYSTEM qualification request (guest-safe)'
    Write-Host '[2] Validate SYSTEM qualification request (guest-safe; no target contact)'
    Write-Host '[3] Run controlled LocalSystem qualification pilot (requires different candidate)'
    Write-Host '[4] Run current package in logged-on elevated interactive session'
    Write-Host '[5] Open latest SYSTEM qualification evidence'
    Write-Host '[Q] Quit'
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Prepare' }
        '2' { $Action = 'Validate' }
        '3' { $Action = 'Pilot' }
        '4' { $Action = 'Interactive' }
        '5' { $Action = 'Evidence' }
        'Q' { return }
        default { throw 'No valid on-site AutoLogon action was selected.' }
    }
}

switch ($Action) {
    'Prepare' {
        $requests = @(Get-SasQualificationRequests)
        if ($requests.Count -eq 0) {
            [void](New-SasLocalQualificationRequest)
        }
        elseif ($requests.Count -eq 1) {
            Write-Host "Opening request: $($requests[0].FullName)"
            Start-Process -FilePath 'notepad.exe' -ArgumentList @($requests[0].FullName) | Out-Null
        }
        else {
            Write-Host "Multiple requests exist under: $requestDirectory"
            Start-Process -FilePath 'explorer.exe' -ArgumentList @($requestDirectory) | Out-Null
        }
        return
    }
    'Validate' {
        if (-not (Confirm-SasRequestExists)) { exit 4 }
        & $qualificationScript -Action Plan
        return
    }
    'Pilot' {
        if (-not (Confirm-SasRequestExists)) { exit 4 }
        Write-Host ''
        Write-Host 'Checking local network posture before any target contact...' -ForegroundColor Cyan
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate -Purpose 'AutoLogon LocalSystem qualification pilot'
        $networkExit = $LASTEXITCODE
        if ($networkExit -ne 0) {
            Write-Host "AutoLogon SYSTEM pilot stopped by the network gate with exit code $networkExit." -ForegroundColor Yellow
            exit $networkExit
        }
        & $qualificationScript -Action Live
        return
    }
    'Interactive' {
        $target = Resolve-SasInteractiveTarget -RequestedTarget $ComputerName
        Write-Host ''
        Write-Host 'Checking local network posture before any target contact...' -ForegroundColor Cyan
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate -Purpose "AutoLogon interactive-token pilot for $target"
        $networkExit = $LASTEXITCODE
        if ($networkExit -ne 0) {
            Write-Host "AutoLogon interactive pilot stopped by the network gate with exit code $networkExit." -ForegroundColor Yellow
            exit $networkExit
        }
        & $interactiveScript -ComputerName $target
        return
    }
    'Evidence' {
        & $qualificationScript -Action OpenLatest
        return
    }
}
