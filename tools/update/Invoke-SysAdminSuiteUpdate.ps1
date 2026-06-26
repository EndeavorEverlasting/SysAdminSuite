<#
.SYNOPSIS
    Check for, and optionally apply, approved SysAdminSuite updates.

.DESCRIPTION
    Supports two local install modes:

    - Git source clone: fetches origin/main and updates only clean local main
      via git pull --ff-only after approval.
    - ZIP / field package: reads a trusted update manifest, verifies package
      SHA256, backs up the current app/root content, then applies the package
      after approval.

    This helper never updates silently. Use -CheckOnly to report availability.
    Use -Apply -Approved only after a user explicitly approved the update.
#>
[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [ValidateSet('Auto', 'Git', 'Package')]
    [string]$Source = 'Auto',

    [Parameter(ParameterSetName = 'Check')]
    [switch]$CheckOnly,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Apply,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Approved,

    [string]$InstallRoot,
    [string]$ManifestPath,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExitNoUpdate = 0
$script:ExitError = 1
$script:ExitUpdateAvailable = 10
$script:ExitManualReview = 20

function Write-UpdateMessage {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Resolve-InstallRoot {
    if ($InstallRoot) {
        return (Resolve-Path -LiteralPath $InstallRoot).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

function Test-IsGitClone {
    param([string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root '.git'))
}

function Invoke-Git {
    param(
        [string]$Root,
        [string[]]$Arguments
    )
    $output = & git -C $Root @Arguments 2>&1
    $code = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = $code
        Output   = (($output | ForEach-Object { "$_" }) -join [Environment]::NewLine)
    }
}

function Get-GitUpdateState {
    param([string]$Root)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Safe            = $false
            UpdateAvailable = $false
            Reason          = 'git is not available on PATH.'
        }
    }

    $fetch = Invoke-Git -Root $Root -Arguments @('fetch', 'origin')
    if ($fetch.ExitCode -ne 0) {
        return [pscustomobject]@{
            Safe            = $false
            UpdateAvailable = $false
            Reason          = "git fetch origin failed. $($fetch.Output)"
        }
    }

    $branch = (Invoke-Git -Root $Root -Arguments @('branch', '--show-current')).Output.Trim()
    if ($branch -ne 'main') {
        return [pscustomobject]@{
            Safe            = $false
            UpdateAvailable = $false
            Reason          = "Current branch is '$branch'. Switch to main before updating."
        }
    }

    $status = (Invoke-Git -Root $Root -Arguments @('status', '--short')).Output.Trim()
    if ($status) {
        return [pscustomobject]@{
            Safe            = $false
            UpdateAvailable = $false
            Reason          = 'Working tree has local changes. Commit, stash, or discard them before updating.'
        }
    }

    $localOnly = (Invoke-Git -Root $Root -Arguments @('log', '--branches', '--not', '--remotes', '--oneline')).Output.Trim()
    if ($localOnly) {
        return [pscustomobject]@{
            Safe            = $false
            UpdateAvailable = $false
            Reason          = 'Local-only commits exist. Push or preserve them before updating.'
        }
    }

    $counts = (Invoke-Git -Root $Root -Arguments @('rev-list', '--left-right', '--count', 'main...origin/main')).Output.Trim()
    $parts = $counts -split '\s+'
    $ahead = [int]$parts[0]
    $behind = [int]$parts[1]

    if ($ahead -gt 0) {
        return [pscustomobject]@{
            Safe            = $false
            UpdateAvailable = $false
            Reason          = 'Local main is ahead of origin/main. Manual review required.'
        }
    }

    return [pscustomobject]@{
        Safe            = $true
        UpdateAvailable = ($behind -gt 0)
        Reason          = if ($behind -gt 0) { "origin/main is $behind commit(s) ahead." } else { 'Already up to date.' }
    }
}

function Invoke-GitUpdate {
    param([string]$Root)
    $pull = Invoke-Git -Root $Root -Arguments @('pull', '--ff-only', 'origin', 'main')
    if ($pull.ExitCode -ne 0) {
        throw "git pull --ff-only failed. $($pull.Output)"
    }
    Write-UpdateMessage 'SysAdminSuite source clone updated from origin/main.'
}

function Resolve-DefaultManifest {
    param([string]$Root)
    foreach ($candidate in @(
            (Join-Path $Root 'manifest\update-manifest.json'),
            (Join-Path $Root 'Config\update-manifest.json'))) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Read-Manifest {
    param([string]$Manifest)
    if (-not $Manifest) {
        return $null
    }

    if ($Manifest -match '^https?://') {
        $content = (Invoke-WebRequest -UseBasicParsing -Uri $Manifest).Content
    } else {
        if (-not (Test-Path -LiteralPath $Manifest)) {
            throw "Manifest not found: $Manifest"
        }
        $content = Get-Content -LiteralPath $Manifest -Raw
    }
    return $content | ConvertFrom-Json
}

function Get-PackagePath {
    param(
        [object]$Manifest,
        [string]$ManifestSource,
        [string]$DownloadDir
    )

    $packageUrl = $null
    if ($Manifest.PSObject.Properties.Name -contains 'packageUrl') {
        $packageUrl = $Manifest.packageUrl
    }
    if (-not $packageUrl -and ($Manifest.PSObject.Properties.Name -contains 'package')) {
        $packageUrl = $Manifest.package
    }
    if (-not $packageUrl) {
        throw 'Manifest must include packageUrl or package.'
    }

    $target = Join-Path $DownloadDir ([IO.Path]::GetFileName($packageUrl))
    if ($packageUrl -match '^https?://') {
        Invoke-WebRequest -UseBasicParsing -Uri $packageUrl -OutFile $target
        return $target
    }

    if ([IO.Path]::IsPathRooted($packageUrl)) {
        Copy-Item -LiteralPath $packageUrl -Destination $target -Force
        return $target
    }

    if ($ManifestSource -and -not ($ManifestSource -match '^https?://')) {
        $manifestDir = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestSource).Path
        $sourcePath = Join-Path $manifestDir $packageUrl
        Copy-Item -LiteralPath $sourcePath -Destination $target -Force
        return $target
    }

    throw 'Relative package path cannot be resolved for remote manifest. Use packageUrl.'
}

function Test-PackageUpdateAvailable {
    param([object]$Manifest)
    if (-not $Manifest) {
        return [pscustomobject]@{
            Safe            = $true
            UpdateAvailable = $false
            Reason          = 'No update manifest configured.'
        }
    }
    return [pscustomobject]@{
        Safe            = $true
        UpdateAvailable = $true
        Reason          = "Package update available: $($Manifest.version)"
    }
}

function Invoke-PackageUpdate {
    param(
        [string]$Root,
        [object]$Manifest,
        [string]$ManifestSource
    )

    $temp = Join-Path ([IO.Path]::GetTempPath()) ("SysAdminSuiteUpdate_" + [guid]::NewGuid().ToString('N'))
    $extract = Join-Path $temp 'extract'
    New-Item -ItemType Directory -Path $extract -Force | Out-Null

    try {
        $packagePath = Get-PackagePath -Manifest $Manifest -ManifestSource $ManifestSource -DownloadDir $temp
        $hash = (Get-FileHash -Path $packagePath -Algorithm SHA256).Hash
        if ($Manifest.checksumSha256 -and ($hash -ne $Manifest.checksumSha256)) {
            throw "Package checksum mismatch. Expected $($Manifest.checksumSha256), got $hash."
        }

        Expand-Archive -Path $packagePath -DestinationPath $extract -Force
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

        if (Test-Path -LiteralPath (Join-Path $extract 'app')) {
            $app = Join-Path $Root 'app'
            $backup = Join-Path $Root "app.previous.$timestamp"
            if (Test-Path -LiteralPath $app) {
                Move-Item -LiteralPath $app -Destination $backup -Force
            }
            Copy-Item -Path (Join-Path $extract 'app') -Destination $app -Recurse -Force
            Write-UpdateMessage "Package app folder updated. Backup: $backup"
            return
        }

        if ((Test-Path -LiteralPath (Join-Path $extract 'START-HERE-SysAdminSuite-Dashboard.bat')) -and
            (Test-Path -LiteralPath (Join-Path $extract 'app\bin\SysAdminSuite.DashboardHost.exe'))) {
            $parent = Split-Path -Parent $Root
            $leaf = Split-Path -Leaf $Root
            $backup = Join-Path $parent "$leaf.previous.$timestamp"
            Copy-Item -Path $Root -Destination $backup -Recurse -Force
            Copy-Item -Path (Join-Path $extract '*') -Destination $Root -Recurse -Force
            Write-UpdateMessage "Field package updated. Backup: $backup"
            return
        }

        throw 'Package layout is not recognized. Expected app/ or dashboard field-release root.'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    $root = Resolve-InstallRoot
    $isGit = Test-IsGitClone -Root $root
    $mode = $Source
    if ($mode -eq 'Auto') {
        $mode = if ($isGit) { 'Git' } else { 'Package' }
    }

    if ($Apply -and -not $Approved) {
        Write-Error 'Refusing to apply update without -Approved.'
        exit $script:ExitError
    }

    if ($mode -eq 'Git') {
        $state = Get-GitUpdateState -Root $root
        Write-UpdateMessage $state.Reason
        if (-not $state.Safe) {
            exit $script:ExitManualReview
        }
        if (-not $state.UpdateAvailable) {
            exit $script:ExitNoUpdate
        }
        if ($Apply) {
            Invoke-GitUpdate -Root $root
            exit $script:ExitNoUpdate
        }
        exit $script:ExitUpdateAvailable
    }

    $manifestSource = if ($ManifestPath) { $ManifestPath } else { Resolve-DefaultManifest -Root $root }
    $manifest = Read-Manifest -Manifest $manifestSource
    $state = Test-PackageUpdateAvailable -Manifest $manifest
    Write-UpdateMessage $state.Reason
    if (-not $state.UpdateAvailable) {
        exit $script:ExitNoUpdate
    }
    if ($Apply) {
        Invoke-PackageUpdate -Root $root -Manifest $manifest -ManifestSource $manifestSource
        exit $script:ExitNoUpdate
    }
    exit $script:ExitUpdateAvailable
} catch {
    Write-Error $_.Exception.Message
    exit $script:ExitError
}
