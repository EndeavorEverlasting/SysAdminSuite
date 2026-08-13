#Requires -Version 5.1
<#
.SYNOPSIS
Operator-friendly AutoLogon launcher for field use.

.DESCRIPTION
Keeps canonical LocalSystem qualification available for a future materially different candidate,
and routes the supported field deployment through one AutoLogon-only transaction that owns
protected-network proof, canonical target resolution, interrupted probe-only recovery, S4U apply,
bounded restart observation, cleanup proof, persistent operator state, and terminal evidence.

Long physical repository paths are never used as the runtime root for Remote/S4U/Recover. The
launcher materializes an exact-HEAD detached worktree under LOCALAPPDATA and re-enters itself from
that short physical path before any target-facing field transaction starts. This keeps every nested
run/evidence path under the Windows PowerShell 5.1 path budget without changing product semantics.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Prepare','Validate','Pilot','Remote','S4U','Recover','Evidence')]
    [string]$Action = 'Menu',
    [string]$ComputerName
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$FieldPathThreshold = 80

function Invoke-SasAutoLogonShortRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRepoRoot,
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [AllowNull()][string]$RequestedComputerName
    )

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is required for the short AutoLogon field runtime.'
    }

    $sourceHead = (& git -C $SourceRepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$sourceHead)) {
        throw "Could not resolve the committed SysAdminSuite HEAD for short field runtime: $SourceRepoRoot"
    }
    $sourceHead = ([string]$sourceHead).Trim()

    $runtimeParent = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-runtime\autologon'
    $runtimeRoot = Join-Path $runtimeParent $sourceHead.Substring(0,12)
    New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null

    if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
        Write-Host "Long repository path detected; materializing exact-HEAD field runtime: $runtimeRoot" -ForegroundColor Cyan
        & git -C $SourceRepoRoot worktree add --detach $runtimeRoot $sourceHead | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the exact-HEAD short AutoLogon field worktree at $runtimeRoot"
        }
    }

    $runtimeHead = (& git -C $runtimeRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or ([string]$runtimeHead).Trim() -ne $sourceHead) {
        throw "Short AutoLogon field runtime HEAD does not match source HEAD $sourceHead. Refusing target operation."
    }

    $runtimeDirty = @(& git -C $runtimeRoot status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not verify the short AutoLogon field runtime worktree state.'
    }
    if (@($runtimeDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        throw "Short AutoLogon field runtime is dirty: $runtimeRoot. Refusing to overwrite or clean it automatically."
    }

    $runtimeScript = Join-Path $runtimeRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'
    if (-not (Test-Path -LiteralPath $runtimeScript -PathType Leaf)) {
        throw "Short AutoLogon field runtime is missing the canonical on-site launcher: $runtimeScript"
    }

    # Preserve the source checkout as a secondary evidence/config root. The executing short worktree
    # remains code authority, while ignored operator-local network policy can still be read from the
    # source checkout by SasNetworkGuard's documented fallback.
    $env:SAS_REPO_ROOT = $SourceRepoRoot

    Write-Host "Short AutoLogon field runtime ready at exact HEAD $sourceHead" -ForegroundColor Green
    $childArgs = @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass',
        '-File',$runtimeScript,
        '-Action',$RequestedAction
    )
    if (-not [string]::IsNullOrWhiteSpace($RequestedComputerName)) {
        $childArgs += @('-ComputerName',$RequestedComputerName)
    }

    & powershell.exe @childArgs
    exit $LASTEXITCODE
}

# Remote field lanes can create several nested evidence trees. Re-enter from a short physical
# worktree before those paths exist. Non-target local qualification/help actions stay in place.
if ($Action -in @('Remote','S4U','Recover') -and $repoRoot.Length -gt $FieldPathThreshold) {
    Invoke-SasAutoLogonShortRuntime -SourceRepoRoot $repoRoot -RequestedAction $Action -RequestedComputerName $ComputerName
}

$requestDirectory = Join-Path $repoRoot 'survey\input\autologon-system-qualification'
$templatePath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification-request.example.json'
$qualificationScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonSystemQualification.ps1'
$fieldDeploymentScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
$networkGate = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'

foreach ($required in @($templatePath,$qualificationScript,$fieldDeploymentScript,$networkGate)) {
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

function Resolve-SasRemoteTarget {
    param([string]$RequestedTarget)
    if (-not [string]::IsNullOrWhiteSpace($RequestedTarget)) {
        return $RequestedTarget.Trim()
    }
    $typed = (Read-Host 'Enter the exact authorized Cybernet hostname or FQDN').Trim()
    if ([string]::IsNullOrWhiteSpace($typed)) {
        throw 'An explicit target is required for the remote AutoLogon deployment.'
    }
    return $typed
}

if ($Action -eq 'Menu') {
    Clear-Host
    Write-Host 'SysAdminSuite AutoLogon On-Site' -ForegroundColor Cyan
    Write-Host 'Remote Kerberos/S4U is the supported field deployment lane; LocalSystem qualification remains a separate future-candidate lane.' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '[1] Deploy AutoLogon: canonicalize target, converge safe probe recovery, apply once, restart, verify cleanup'
    Write-Host '[2] Recover safely recorded interrupted probe-only runs without installing AutoLogon'
    Write-Host '[3] Prepare/edit LocalSystem qualification request for a different candidate'
    Write-Host '[4] Validate LocalSystem qualification request (no target contact)'
    Write-Host '[5] Run controlled LocalSystem qualification pilot (requires different candidate)'
    Write-Host '[6] Open latest LocalSystem qualification evidence'
    Write-Host '[Q] Quit'
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Remote' }
        '2' { $Action = 'Recover' }
        '3' { $Action = 'Prepare' }
        '4' { $Action = 'Validate' }
        '5' { $Action = 'Pilot' }
        '6' { $Action = 'Evidence' }
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
        & $qualificationScript -Action Live
        exit $LASTEXITCODE
    }
    'Recover' {
        $target = Resolve-SasRemoteTarget -RequestedTarget $ComputerName
        & $fieldDeploymentScript -Action Recover -ComputerName $target
        exit $LASTEXITCODE
    }
    { $_ -in @('Remote','S4U') } {
        $target = Resolve-SasRemoteTarget -RequestedTarget $ComputerName
        & $fieldDeploymentScript -Action Remote -ComputerName $target
        exit $LASTEXITCODE
    }
    'Evidence' {
        & $qualificationScript -Action OpenLatest
        return
    }
}
