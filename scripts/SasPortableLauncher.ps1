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
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Test-SasRepoRoot {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $candidate = [IO.Path]::GetFullPath($Path.Trim()) } catch { return $false }
    return (
        (Test-Path -LiteralPath $candidate -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Run-AutoLogonOnsite.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Run-CybernetBatchConfiguration.cmd') -PathType Leaf) -and
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

$repoRoot = Resolve-SasRepoRoot
$normalized = if ($Command) { $Command.Trim().ToLowerInvariant() } else { '' }

if ([string]::IsNullOrWhiteSpace($normalized)) {
    Write-Host 'SysAdminSuite portable operator command' -ForegroundColor Cyan
    Write-Host "Repo: $repoRoot"
    Write-Host ''
    Write-Host '  sas autologon              AutoLogon on-site request/qualification menu'
    Write-Host '  sas cybernet Plan HOST     Local Cybernet plan'
    Write-Host '  sas cybernet Apply HOST    Network-gated Cybernet apply'
    Write-Host '  sas cybernet Validate HOST Network-gated Cybernet validation'
    Write-Host '  sas network                Check/recheck approved Northwell network posture'
    Write-Host '  sas repo                   Print resolved repository path'
    Write-Host '  sas open                   Open repository in Explorer'
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
        & (Join-Path $repoRoot 'Run-AutoLogonOnsite.cmd') @CommandArgs
        exit $LASTEXITCODE
    }
    'cybernet' {
        & (Join-Path $repoRoot 'Run-CybernetBatchConfiguration.cmd') @CommandArgs
        exit $LASTEXITCODE
    }
    default {
        Write-Host "Unknown sas command: $Command" -ForegroundColor Red
        Write-Host 'Run sas with no arguments to see the bounded operator commands.'
        exit 2
    }
}
