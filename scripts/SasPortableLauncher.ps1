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
        (Test-Path -LiteralPath (Join-Path $candidate 'Probe-CybernetSoftware.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Deploy-CybernetSoftware.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Deploy-CybernetClinicalCore.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Deploy-CybernetProfiledClinicalCore.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Find-SasEvidence.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Refresh-SasOperatorCommand.cmd') -PathType Leaf) -and
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
            'SysAdminSuite-portable-onsite',
            'SysAdminSuite-Live',
            'dev\SysAdminSuite',
            'dev\SysAdminSuite-portable-onsite',
            'dev\SysAdminSuite-Live',
            'Desktop\dev\SysAdminSuite',
            'Desktop\dev\SysAdminSuite-portable-onsite',
            'Desktop\dev\SysAdminSuite-Live',
            'OG Laptop Backup\Desktop\dev\SysAdminSuite',
            'OG Laptop Backup\Desktop\dev\SysAdminSuite-portable-onsite',
            'OG Laptop Backup\Desktop\dev\SysAdminSuite-Live'
        )) {
            Add-SasCandidate -List $candidates -Path (Join-Path $root $relative)
        }
    }

    foreach ($pattern in @(
        (Join-Path $env:USERPROFILE '*\Desktop\dev\SysAdminSuite*'),
        (Join-Path $env:USERPROFILE '*\*\Desktop\dev\SysAdminSuite*'),
        (Join-Path $env:USERPROFILE '*\*\*\Desktop\dev\SysAdminSuite*')
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
    Write-Host '  sas refresh                          GUEST-SAFE: sync origin/main into isolated field-ready checkout and refresh sas'
    Write-Host '  sas cybernet Probe HOST             READ-ONLY: one-target low-noise deployment readiness'
    Write-Host '  sas network HOST                    Alias for the same one-target deployment readiness probe'
    Write-Host '  sas cybernet Core HOST              DEPLOY five clinical apps only; profile before/after; AutoLogon untouched; no reboot'
    Write-Host '  sas cybernet Deploy HOST            DEPLOY full Cybernet software profile; readiness included; AutoLogon last; restart included'
    Write-Host '  sas autologon Remote HOST           DEPLOY AutoLogon only through Kerberos/S4U; restart included'
    Write-Host '  sas evidence                        OFFLINE: find newest deployment/runtime evidence and next action'
    Write-Host '  sas evidence All                    OFFLINE: list recent evidence across known SysAdminSuite checkouts'
    Write-Host '  sas evidence Open                   OFFLINE: find newest evidence and open its folder'
    Write-Host '  sas autologon                       AutoLogon on-site menu'
    Write-Host '  sas cybernet Plan HOST              Hardware-only Cybernet plan'
    Write-Host '  sas cybernet Apply HOST             Hardware-only Cybernet apply'
    Write-Host '  sas cybernet Validate HOST          Hardware-only Cybernet validation'
    Write-Host '  sas network                         Check/recheck approved Northwell network posture only'
    Write-Host '  sas repo                            Print resolved repository path'
    Write-Host '  sas open                            Open repository in Explorer'
    Write-Host ''
    Write-Host 'Field sequence:' -ForegroundColor Cyan
    Write-Host '  1. On Guest/Internet: sas refresh' -ForegroundColor Green
    Write-Host '  2. Verify the refresh reports SAS_OPERATOR_REFRESH_READY.' -ForegroundColor Green
    Write-Host '  3. Move to the approved protected network.' -ForegroundColor Green
    Write-Host '  4. Use sas cybernet Core HOST when AutoLogon must remain untouched, or sas cybernet Deploy HOST for the full profile.' -ForegroundColor Green
    Write-Host '  5. If the terminal closes, run sas evidence before any retry.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Software deployment behavior:' -ForegroundColor Cyan
    Write-Host '  - Core is Windows-native and does not require Git Bash or Python.' -ForegroundColor Green
    Write-Host '  - Core captures before/after Cybernet profile observations, including AutoLogon state and observational Imprivata state.'
    Write-Host '  - Core installs the five clinical applications only, never enables AutoLogon, and never reboots.'
    Write-Host '  - Full deployment automatically runs the narrow Kerberos SMB plus Task Scheduler readiness chain first.'
    Write-Host '  - Full deployment installs the five clinical applications first and AutoLogon last.'
    Write-Host '  - Full AutoLogon deployment automatically restarts the target and waits for it to return.'
    Write-Host '  - If the terminal closes or crashes, run `sas evidence`; do not redeploy just to recreate console output.' -ForegroundColor Yellow
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
    'refresh' {
        $refresh = Join-Path $repoRoot 'scripts\Refresh-SasOperatorCommand.ps1'
        if (-not (Test-Path -LiteralPath $refresh -PathType Leaf)) { throw "Current checkout is missing the refresh workflow: $refresh" }
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $refresh -RepositoryRoot $repoRoot
        exit $LASTEXITCODE
    }
    'evidence' {
        $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Find-SasEvidence.cmd' -Arguments $CommandArgs
        exit $exitCode
    }
    'network' {
        $args = @($CommandArgs)
        if ($args.Count -eq 0) {
            & (Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1') -Purpose 'manual SysAdminSuite operator check'
            exit $LASTEXITCODE
        }
        if ($args.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$args[0])) {
            $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Probe-CybernetSoftware.cmd' -Arguments @('Probe', [string]$args[0])
            exit $exitCode
        }
        Write-Host 'Usage: sas network  OR  sas network HOST' -ForegroundColor Red
        exit 2
    }
    { $_ -in @('autologon','qualify') } {
        $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-AutoLogonOnsite.cmd' -Arguments $CommandArgs
        exit $exitCode
    }
    'cybernet' {
        $args = @($CommandArgs)
        if ($args.Count -gt 0 -and [string]$args[0]) {
            $mode = ([string]$args[0]).Trim().ToLowerInvariant()
            if ($mode -eq 'probe') {
                $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Probe-CybernetSoftware.cmd' -Arguments $args
                exit $exitCode
            }
            if ($mode -in @('core','profiled-core')) {
                if ($args.Count -ne 2 -or [string]::IsNullOrWhiteSpace([string]$args[1])) {
                    Write-Host 'Usage: sas cybernet Core HOST' -ForegroundColor Red
                    exit 2
                }
                $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Deploy-CybernetProfiledClinicalCore.cmd' -Arguments @([string]$args[1])
                exit $exitCode
            }
            if ($mode -eq 'deploy') {
                $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Deploy-CybernetSoftware.cmd' -Arguments $args
                exit $exitCode
            }
        }
        $exitCode = Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-CybernetBatchConfiguration.cmd' -Arguments $args
        exit $exitCode
    }
    default {
        Write-Host "Unknown sas command: $Command" -ForegroundColor Red
        Write-Host 'Run sas with no arguments to see the bounded operator commands.'
        exit 2
    }
}
