#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$cachePath = Join-Path $stateRoot 'repo-root.txt'
$PathLengthThreshold = 100
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Test-SasRepoRoot {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $candidate = [IO.Path]::GetFullPath($Path.Trim()) } catch { return $false }
    return (
        (Test-Path -LiteralPath $candidate -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Run-AutoLogonOnsite.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Run-CybernetBatchConfiguration.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Deploy-CybernetSoftware.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Deploy-CybernetClinicalCore.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'scripts\SasNetworkGuard.psm1') -PathType Leaf)
    )
}

function Add-SasCandidate {
    param([System.Collections.Generic.List[string]]$List, [AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full = [IO.Path]::GetFullPath($Path.Trim()) } catch { return }
    if (-not $List.Contains($full)) { [void]$List.Add($full) }
}

function Resolve-SasRepoRoot {
    $candidates = New-Object 'System.Collections.Generic.List[string]'

    Add-SasCandidate -List $candidates -Path $env:SAS_REPO_ROOT

    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        try { Add-SasCandidate -List $candidates -Path ((Get-Content -LiteralPath $cachePath -Raw).Trim()) } catch {}
    }

    try {
        $gitRoot = (& git -C (Get-Location).Path rev-parse --show-toplevel 2>$null | Select-Object -First 1)
        Add-SasCandidate -List $candidates -Path $gitRoot
    }
    catch {}

    $roots = @(
        $env:USERPROFILE,
        $env:OneDrive,
        $env:OneDriveCommercial,
        $env:OneDriveConsumer
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($root in $roots) {
        foreach ($relative in @(
            'SysAdminSuite',
            'dev\SysAdminSuite',
            'Desktop\dev\SysAdminSuite',
            'OG Laptop Backup\Desktop\dev\SysAdminSuite'
        )) {
            Add-SasCandidate -List $candidates -Path (Join-Path $root $relative)
        }
    }

    foreach ($pattern in @(
        (Join-Path $env:USERPROFILE '*\Desktop\dev\SysAdminSuite'),
        (Join-Path $env:USERPROFILE '*\*\Desktop\dev\SysAdminSuite'),
        (Join-Path $env:USERPROFILE '*\*\*\Desktop\dev\SysAdminSuite')
    )) {
        try {
            foreach ($match in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue)) {
                Add-SasCandidate -List $candidates -Path $match.FullName
            }
        }
        catch {}
    }

    foreach ($candidate in $candidates) {
        if (Test-SasRepoRoot -Path $candidate) {
            Set-Content -LiteralPath $cachePath -Value $candidate -Encoding ASCII
            return $candidate
        }
    }

    throw @"
SysAdminSuite could not be located automatically for this Windows user.
Open the repository once and run Install-SasOperatorCommand.cmd. The installed `sas` command
will cache that user's repo location and rediscover common Desktop/dev and OneDrive layouts if it moves.
"@
}

function Get-SasAvailableSubstDrive {
    foreach ($letter in @('S','R','Q','P','O','N','M','L','K','J')) {
        $driveRoot = "${letter}:\"
        $existing = Get-PSDrive -Name $letter -ErrorAction SilentlyContinue
        if ($null -eq $existing -and -not (Test-Path -LiteralPath $driveRoot)) {
            return "${letter}:"
        }
    }
    throw 'No free temporary drive letter is available for the SysAdminSuite short-path alias.'
}

function Invoke-SasPortableRepoCommand {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [AllowNull()][string[]]$Arguments
    )

    $entryPoint = Join-Path $RepoRoot $RelativePath
    $isLocalDrivePath = $RepoRoot -match '^[A-Za-z]:\\'
    if (-not $isLocalDrivePath -or $RepoRoot.Length -lt $PathLengthThreshold) {
        & $entryPoint @Arguments
        return [int]$LASTEXITCODE
    }

    $drive = Get-SasAvailableSubstDrive
    $substExe = Join-Path $env:WINDIR 'System32\subst.exe'
    $created = $false
    $commandExit = 1
    try {
        & $substExe $drive $RepoRoot | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create temporary short-path alias $drive for the SysAdminSuite repository."
        }
        $created = $true
        $shortRoot = "$drive\"
        $shortEntryPoint = Join-Path $shortRoot $RelativePath
        Write-Host "Long repository path detected; using temporary short-path alias $drive for this command." -ForegroundColor Cyan
        & $shortEntryPoint @Arguments
        $commandExit = [int]$LASTEXITCODE
    }
    finally {
        if ($created) {
            & $substExe $drive '/D' | Out-Null
        }
    }
    return $commandExit
}

$repoRoot = Resolve-SasRepoRoot
$normalized = if ($Command) { $Command.Trim().ToLowerInvariant() } else { '' }

if ([string]::IsNullOrWhiteSpace($normalized)) {
    Write-Host 'SysAdminSuite portable operator command' -ForegroundColor Cyan
    Write-Host "Repo: $repoRoot"
    Write-Host ''
    Write-Host '  sas cybernet Deploy HOST            DEPLOY full Cybernet software profile; AutoLogon last; restart included'
    Write-Host '  sas autologon Remote HOST           DEPLOY AutoLogon only through Kerberos/S4U; restart included'
    Write-Host '  sas autologon                       AutoLogon on-site menu'
    Write-Host '  sas cybernet Plan HOST              Hardware-only Cybernet plan'
    Write-Host '  sas cybernet Apply HOST             Hardware-only Cybernet apply'
    Write-Host '  sas cybernet Validate HOST          Hardware-only Cybernet validation'
    Write-Host '  sas network                         Check/recheck approved Northwell network posture'
    Write-Host '  sas repo                            Print resolved repository path'
    Write-Host '  sas open                            Open repository in Explorer'
    Write-Host ''
    Write-Host 'Software deployment behavior:' -ForegroundColor Cyan
    Write-Host '  - Full Cybernet deployment installs the five clinical applications first.'
    Write-Host '  - AutoLogon is always the final software step.'
    Write-Host '  - AutoLogon deployment automatically restarts the target and waits for it to return.'
    Write-Host '  - Success: CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED or AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED.'
    Write-Host '  - Fixture/live-cert/runtime-proof loops are NOT prerequisites for deployment completion.' -ForegroundColor Green
    Write-Host '  - Runtime proof remains available only when explicitly requested; it must not delay deployment.' -ForegroundColor Cyan
    exit 0
}

switch ($normalized) {
    'repo' {
        Write-Output $repoRoot
        exit 0
    }
    'open' {
        Start-Process -FilePath 'explorer.exe' -ArgumentList @($repoRoot) | Out-Null
        exit 0
    }
    'network' {
        & (Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1') -Purpose 'manual SysAdminSuite operator check'
        exit $LASTEXITCODE
    }
    { $_ -in @('autologon','qualify') } {
        $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-AutoLogonOnsite.cmd' -Arguments $CommandArgs
        exit $exitCode
    }
    'cybernet' {
        $args = @($CommandArgs)
        if ($args.Count -gt 0 -and [string]$args[0] -and ([string]$args[0]).Trim().ToLowerInvariant() -eq 'deploy') {
            $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Deploy-CybernetSoftware.cmd' -Arguments $args
        }
        else {
            $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-CybernetBatchConfiguration.cmd' -Arguments $args
        }
        exit $exitCode
    }
    default {
        Write-Host "Unknown sas command: $Command" -ForegroundColor Red
        Write-Host 'Run sas with no arguments to see the bounded operator commands.'
        exit 2
    }
}
