#Requires -Version 5.1
<#
.SYNOPSIS
Operator-friendly AutoLogon launcher for field use.

.DESCRIPTION
Keeps canonical LocalSystem qualification available for a future materially different candidate,
and routes the supported field deployment through one AutoLogon-only transaction that owns
protected-network proof, canonical target resolution, interrupted probe-only recovery, S4U apply,
bounded restart observation, cleanup proof, persistent operator state, and terminal evidence.

Remote/S4U/Recover always execute from one stable, short, exact-HEAD field worktree at C:\SASAL.
The field transaction writes its ignored run tree under C:\SASAL\runs. This avoids recursive
OneDrive/backup path growth while preserving the existing repository-local `runs/` evidence contract
and monotonic prior-result discovery across source-code refreshes.
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
$fieldRuntimeRoot = 'C:\SASAL'

function Get-SasNormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
}

function Get-SasGitCommonDirectory {
    param([Parameter(Mandatory = $true)][string]$Root)
    $common = (& git -C $Root rev-parse --git-common-dir 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$common)) { return $null }
    $common = ([string]$common).Trim()
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Root $common }
    try { return (Get-SasNormalizedPath -Path $common) } catch { return $null }
}

function Invoke-SasAutoLogonShortRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRepoRoot,
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [AllowNull()][string]$RequestedComputerName
    )

    $sourceHead = (& git -C $SourceRepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$sourceHead)) {
        throw "Could not resolve the committed SysAdminSuite HEAD for the short field runtime: $SourceRepoRoot"
    }
    $sourceHead = ([string]$sourceHead).Trim()
    $sourceCommon = Get-SasGitCommonDirectory -Root $SourceRepoRoot
    if ([string]::IsNullOrWhiteSpace($sourceCommon)) {
        throw 'Could not resolve the source SysAdminSuite Git common directory.'
    }

    if (-not (Test-Path -LiteralPath $fieldRuntimeRoot -PathType Container)) {
        Write-Host "Creating stable short AutoLogon field worktree: $fieldRuntimeRoot" -ForegroundColor Cyan
        & git -C $SourceRepoRoot worktree add --detach $fieldRuntimeRoot $sourceHead | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the short AutoLogon field worktree at $fieldRuntimeRoot. The field lane requires a writable C:\ root or an existing valid owned worktree."
        }
    }

    $runtimeCommon = Get-SasGitCommonDirectory -Root $fieldRuntimeRoot
    if ([string]::IsNullOrWhiteSpace($runtimeCommon) -or
        -not $runtimeCommon.Equals($sourceCommon, [StringComparison]::OrdinalIgnoreCase)) {
        throw "C:\SASAL exists but is not an owned worktree of this SysAdminSuite checkout. Refusing to overwrite or remove it."
    }

    $runtimeDirty = @(& git -C $fieldRuntimeRoot status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not verify the short AutoLogon field worktree state.'
    }
    if (@($runtimeDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        throw "Short AutoLogon field worktree is dirty: $fieldRuntimeRoot. Refusing to overwrite or clean it automatically."
    }

    $runtimeHead = (& git -C $fieldRuntimeRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$runtimeHead)) {
        throw 'Could not resolve the short AutoLogon field runtime HEAD.'
    }
    $runtimeHead = ([string]$runtimeHead).Trim()

    if ($runtimeHead -ne $sourceHead) {
        Write-Host "Advancing owned short field worktree to source HEAD $sourceHead" -ForegroundColor Cyan
        & git -C $fieldRuntimeRoot checkout --detach $sourceHead | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Could not move the clean short field worktree to source HEAD $sourceHead"
        }
        $runtimeHead = (& git -C $fieldRuntimeRoot rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or ([string]$runtimeHead).Trim() -ne $sourceHead) {
            throw "Short AutoLogon field runtime did not converge to source HEAD $sourceHead"
        }
    }

    $runtimeScript = Join-Path $fieldRuntimeRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'
    if (-not (Test-Path -LiteralPath $runtimeScript -PathType Leaf)) {
        throw "Short AutoLogon field runtime is missing the canonical on-site launcher: $runtimeScript"
    }

    # Preserve the source checkout as a secondary evidence/config root. The short runtime remains
    # execution authority. SasNetworkGuard can therefore consume the source checkout's ignored local
    # network policy when C:\SASAL has no operator-local config file.
    $env:SAS_REPO_ROOT = $SourceRepoRoot

    Write-Host "Short AutoLogon field runtime ready: $fieldRuntimeRoot" -ForegroundColor Green
    Write-Host "Exact committed HEAD: $sourceHead" -ForegroundColor Green

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

$isShortRuntime = (Get-SasNormalizedPath -Path $repoRoot).Equals(
    (Get-SasNormalizedPath -Path $fieldRuntimeRoot),
    [StringComparison]::OrdinalIgnoreCase
)

# Field target actions always enter the stable short physical worktree before network/target work.
if ($Action -in @('Remote','S4U','Recover') -and -not $isShortRuntime) {
    Invoke-SasAutoLogonShortRuntime -SourceRepoRoot $repoRoot -RequestedAction $Action -RequestedComputerName $ComputerName
}

$requestDirectory = Join-Path $repoRoot 'survey\input\autologon-system-qualification'
$templatePath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification-request.example.json'
$qualificationScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonSystemQualification.ps1'
$fieldDeploymentScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
$networkGate = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$fieldOutputRoot = Join-Path $repoRoot 'runs'

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
        New-Item -ItemType Directory -Path $fieldOutputRoot -Force | Out-Null
        & $fieldDeploymentScript -Action Recover -ComputerName $target -OutputRoot $fieldOutputRoot
        exit $LASTEXITCODE
    }
    { $_ -in @('Remote','S4U') } {
        $target = Resolve-SasRemoteTarget -RequestedTarget $ComputerName
        New-Item -ItemType Directory -Path $fieldOutputRoot -Force | Out-Null
        & $fieldDeploymentScript -Action Remote -ComputerName $target -OutputRoot $fieldOutputRoot
        exit $LASTEXITCODE
    }
    'Evidence' {
        & $qualificationScript -Action OpenLatest
        return
    }
}
