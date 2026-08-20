#Requires -Version 5.1
<#
.SYNOPSIS
Launch the canonical Northwell printer mapper without requiring the current shell to be inside SysAdminSuite.

.DESCRIPTION
This bootstrap is intentionally independent of the caller's current directory. It first reuses an explicit or
canonical local SysAdminSuite runtime when that runtime already contains the required commit. If no eligible
local runtime exists, it uses a dedicated LOCALAPPDATA Git cache, fetches the configured default-branch ref
without force, proves that RequiredCommit is an ancestor of that ref, and creates a persistent detached
printer runtime keyed by the fetched commit.

The bootstrap never resets, cleans, or checks out an arbitrary operator repository. A dedicated runtime is
left in place so the mapper's gitignored evidence remains available after the run.
#>
[CmdletBinding()]
param(
    [string]$RepositoryUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git',
    [string]$Branch = 'main',
    [string]$RequiredCommit,
    [string]$CacheRoot,
    [switch]$NoLaunch
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Resolve-SasGitExecutable {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [IO.Path]::GetFullPath([string]$command.Source)
    }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath([string]$candidate)
        }
    }
    throw 'Git for Windows is required only when no eligible local SysAdminSuite printer runtime is already available.'
}

function Invoke-SasGit {
    param(
        [AllowNull()][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$AllowFailure
    )

    $stderrPath = Join-Path $env:TEMP ('sas-printer-bootstrap-git-' + [guid]::NewGuid().ToString('N') + '.err')
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $LASTEXITCODE = 0
        if ([string]::IsNullOrWhiteSpace($Root)) {
            $stdout = @(& $script:SasGitExe @Arguments 2> $stderrPath)
        }
        else {
            $stdout = @(& $script:SasGitExe -C $Root @Arguments 2> $stderrPath)
        }
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $stderr = ''
    if (Test-Path -LiteralPath $stderrPath) {
        try { $stderr = ([string](Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)).Trim() }
        finally { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    }
    $lines = @($stdout | ForEach-Object { [string]$_ })
    $stdoutText = ($lines -join [Environment]::NewLine).Trim()
    $detail = @($stdoutText,$stderr | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = '(git produced no diagnostic text)' }
        throw "$FailureMessage (git exit $exitCode)`n$detail"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines = $lines
        Text = $detail
    }
}

function Get-SasGitScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $result = Invoke-SasGit -Root $Root -Arguments $Arguments -FailureMessage $FailureMessage
    $value = [string]($result.Lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$FailureMessage (empty git output)" }
    return $value.Trim()
}

function Test-SasPrinterRuntimeRoot {
    param([AllowNull()][string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    try { $full = [IO.Path]::GetFullPath($Root) } catch { return $false }
    return (Test-Path -LiteralPath (Join-Path $full 'Map-NorthwellPrinter-SystemWide.cmd') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $full 'mapping\Start-NorthwellPrinterMapping.ps1') -PathType Leaf)
}

function Get-SasRuntimeHead {
    param([Parameter(Mandatory = $true)][string]$Root)
    $result = Invoke-SasGit -Root $Root -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not inspect local runtime HEAD.' -AllowFailure
    if ($result.ExitCode -ne 0) { return $null }
    $value = [string]($result.Lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value.Trim()
}

function Test-SasCommitAncestor {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Ancestor,
        [Parameter(Mandatory = $true)][string]$Descendant
    )
    $result = Invoke-SasGit -Root $Root -Arguments @('merge-base','--is-ancestor',$Ancestor,$Descendant) -FailureMessage 'Could not compare SysAdminSuite commit ancestry.' -AllowFailure
    return ($result.ExitCode -eq 0)
}

function Add-SasCandidate {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$List,
        [AllowNull()][string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    try { $full = [IO.Path]::GetFullPath($Value) } catch { return }
    if (-not $List.Contains($full)) { $List.Add($full) }
}

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is required for the printer bootstrap state/cache.' }
$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\printer-bootstrap'
if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $stateRoot 'source' }
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
$runtimeParent = Join-Path $stateRoot 'runtimes'
$latestPointer = Join-Path $stateRoot 'latest-runtime.txt'

$script:SasGitExe = Resolve-SasGitExecutable

$candidates = New-Object 'System.Collections.Generic.List[string]'
if (Test-Path -LiteralPath $latestPointer -PathType Leaf) {
    Add-SasCandidate -List $candidates -Value ([string](Get-Content -LiteralPath $latestPointer -Raw -ErrorAction SilentlyContinue)).Trim()
}
Add-SasCandidate -List $candidates -Value $env:SAS_RUNTIME_ROOT
Add-SasCandidate -List $candidates -Value 'C:\SASAL'
Add-SasCandidate -List $candidates -Value $env:SAS_REPO_ROOT

$runtimeRoot = $null
$runtimeHead = $null
foreach ($candidate in $candidates) {
    if (-not (Test-SasPrinterRuntimeRoot -Root $candidate)) { continue }
    $head = Get-SasRuntimeHead -Root $candidate
    if ([string]::IsNullOrWhiteSpace($head)) { continue }
    if (-not [string]::IsNullOrWhiteSpace($RequiredCommit) -and -not (Test-SasCommitAncestor -Root $candidate -Ancestor $RequiredCommit.Trim() -Descendant $head)) {
        continue
    }
    $runtimeRoot = $candidate
    $runtimeHead = $head
    break
}

if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
    if (Test-Path -LiteralPath $CacheRoot) {
        $inside = Invoke-SasGit -Root $CacheRoot -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage 'Dedicated printer bootstrap cache is not a Git worktree.' -AllowFailure
        if ($inside.ExitCode -ne 0) {
            throw "Printer bootstrap cache path already exists but is not a Git worktree. Nothing was changed: $CacheRoot"
        }
        $origin = Get-SasGitScalar -Root $CacheRoot -Arguments @('remote','get-url','origin') -FailureMessage 'Could not inspect dedicated printer bootstrap origin.'
        if ($origin -notmatch '(?i)github\.com[:/]+EndeavorEverlasting/SysAdminSuite(?:\.git)?/?$') {
            throw "Printer bootstrap cache origin is unexpected. Nothing was changed: $origin"
        }
    }
    else {
        $parent = Split-Path -Parent $CacheRoot
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Invoke-SasGit -Root $null -Arguments @('clone','--no-checkout','--origin','origin','--branch',$Branch,$RepositoryUrl,$CacheRoot) -FailureMessage 'Could not create the dedicated SysAdminSuite printer bootstrap cache.' | Out-Null
    }

    Invoke-SasGit -Root $CacheRoot -Arguments @('fetch','--no-tags','origin',("refs/heads/{0}:refs/remotes/origin/{0}" -f $Branch)) -FailureMessage "Could not fetch origin/$Branch into the dedicated printer bootstrap cache." | Out-Null
    $remoteRef = "refs/remotes/origin/$Branch"
    $remoteHead = Get-SasGitScalar -Root $CacheRoot -Arguments @('rev-parse',$remoteRef) -FailureMessage "Could not resolve origin/$Branch."

    if (-not [string]::IsNullOrWhiteSpace($RequiredCommit)) {
        $required = $RequiredCommit.Trim()
        if (-not (Test-SasCommitAncestor -Root $CacheRoot -Ancestor $required -Descendant $remoteHead)) {
            Invoke-SasGit -Root $CacheRoot -Arguments @('fetch','--no-tags','origin',$required) -FailureMessage "Required printer fix commit $required is not available from origin." | Out-Null
            if (-not (Test-SasCommitAncestor -Root $CacheRoot -Ancestor $required -Descendant $remoteHead)) {
                throw "Current origin/$Branch does not contain required printer fix commit $required. No mapper was launched."
            }
        }
    }

    if (-not (Test-Path -LiteralPath $runtimeParent -PathType Container)) { New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null }
    $runtimeRoot = Join-Path $runtimeParent $remoteHead
    if (Test-Path -LiteralPath $runtimeRoot) {
        $existingHead = Get-SasRuntimeHead -Root $runtimeRoot
        $tracked = Invoke-SasGit -Root $runtimeRoot -Arguments @('status','--porcelain','--untracked-files=no') -FailureMessage 'Could not inspect existing dedicated printer runtime.' -AllowFailure
        if ([string]::IsNullOrWhiteSpace($existingHead) -or $existingHead -ne $remoteHead -or @($tracked.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
            $runtimeRoot = Join-Path $runtimeParent ($remoteHead + '-' + [guid]::NewGuid().ToString('N'))
        }
    }
    if (-not (Test-Path -LiteralPath $runtimeRoot)) {
        Invoke-SasGit -Root $CacheRoot -Arguments @('worktree','add','--detach',$runtimeRoot,$remoteHead) -FailureMessage 'Could not create the dedicated detached printer runtime.' | Out-Null
    }
    if (-not (Test-SasPrinterRuntimeRoot -Root $runtimeRoot)) { throw "Acquired runtime is missing the canonical printer launcher: $runtimeRoot" }
    $runtimeHead = Get-SasRuntimeHead -Root $runtimeRoot
    Set-Content -LiteralPath $latestPointer -Value $runtimeRoot -Encoding UTF8
}

Write-Host 'SysAdminSuite printer bootstrap' -ForegroundColor Cyan
Write-Host ("Runtime: {0}" -f $runtimeRoot)
Write-Host ("Commit:  {0}" -f $runtimeHead)
Write-Host 'Current directory is not used as repository authority.' -ForegroundColor DarkGray

if ($NoLaunch) {
    Write-Host 'PASS: printer runtime resolved; launcher not executed (-NoLaunch).' -ForegroundColor Green
    exit 0
}

$launcher = Join-Path $runtimeRoot 'Map-NorthwellPrinter-SystemWide.cmd'
Write-Host 'Launching Northwell system-wide printer mapper...' -ForegroundColor Green
& $launcher
$exitCode = [int]$LASTEXITCODE
exit $exitCode
