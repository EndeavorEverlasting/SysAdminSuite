#Requires -Version 5.1
<#
.SYNOPSIS
Launch the canonical Northwell printer mapper without requiring the current shell to be inside SysAdminSuite.

.DESCRIPTION
This bootstrap is intentionally independent of the caller's current directory. It reuses only a complete,
clean local SysAdminSuite runtime that contains the required printer fix by Git ancestry. If no eligible local
runtime exists, it uses a dedicated LOCALAPPDATA Git cache, fetches main without force, proves the required
fix is contained in main, and creates a persistent detached printer runtime keyed by the fetched commit.

The bootstrap never resets, cleans, or checks out an arbitrary operator repository. A dedicated runtime is
left in place so the mapper's gitignored evidence remains available after the run.
#>
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$RequiredCommit = '5463c0ed3fedc4f9c5fe8048ead3cfc6bf2c434f',
    [string]$CacheRoot,
    [switch]$NoLaunch
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git'
$requiredRuntimePaths = @(
    'Map-NorthwellPrinter-SystemWide.cmd',
    'mapping\Start-NorthwellPrinterMapping.ps1',
    'mapping\Invoke-NorthwellPrinterMapping.ps1',
    'mapping\Modules\NorthwellPrinterMapping.Core.psm1',
    'scripts\SasTargetNameResolution.psm1',
    'scripts\SasNetworkGuard.psm1',
    'scripts\SasInteractionCache.psm1',
    'Config\interaction-cache-policy.json'
)

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
    throw 'Git for Windows is required to prove printer runtime commit ancestry and clean tracked state.'
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
    foreach ($relativePath in $script:requiredRuntimePaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $full $relativePath) -PathType Leaf)) { return $false }
    }
    return $true
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

function Test-SasTrackedRuntimeClean {
    param([Parameter(Mandatory = $true)][string]$Root)
    $result = Invoke-SasGit -Root $Root -Arguments @('status','--porcelain','--untracked-files=no') -FailureMessage 'Could not inspect local runtime tracked state.' -AllowFailure
    if ($result.ExitCode -ne 0) { return $false }
    return @($result.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0
}

function Add-SasCandidate {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List,
        [AllowNull()][string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    try { $full = [IO.Path]::GetFullPath($Value) } catch { return }
    if (-not $List.Contains($full)) { [void]$List.Add($full) }
}

function Get-SasPrinterRuntimeCandidates {
    $items = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $script:latestPointer -PathType Leaf) {
        $saved = [string](Get-Content -LiteralPath $script:latestPointer -Raw -ErrorAction SilentlyContinue)
        if (-not [string]::IsNullOrWhiteSpace($saved)) { Add-SasCandidate -List $items -Value $saved.Trim() }
    }
    Add-SasCandidate -List $items -Value $env:SAS_RUNTIME_ROOT
    Add-SasCandidate -List $items -Value 'C:\SASAL'
    Add-SasCandidate -List $items -Value $env:SAS_REPO_ROOT
    return $items.ToArray()
}

function Find-SasEligiblePrinterRuntime {
    param([Parameter(Mandatory = $true)][string]$Required)
    foreach ($candidate in @(Get-SasPrinterRuntimeCandidates)) {
        if (-not (Test-SasPrinterRuntimeRoot -Root $candidate)) { continue }
        if (-not (Test-SasTrackedRuntimeClean -Root $candidate)) { continue }
        $head = Get-SasRuntimeHead -Root $candidate
        if ([string]::IsNullOrWhiteSpace($head)) { continue }
        if (-not (Test-SasCommitAncestor -Root $candidate -Ancestor $Required -Descendant $head)) { continue }
        return [pscustomobject]@{ Root = $candidate; Head = $head }
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is required for the printer bootstrap state/cache.' }
$RequiredCommit = $RequiredCommit.Trim()
if ([string]::IsNullOrWhiteSpace($RequiredCommit)) { throw 'RequiredCommit cannot be blank.' }
$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\printer-bootstrap'
if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $stateRoot 'source' }
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
$runtimeParent = Join-Path $stateRoot 'runtimes'
$script:latestPointer = Join-Path $stateRoot 'latest-runtime.txt'
$script:SasGitExe = Resolve-SasGitExecutable

$selected = Find-SasEligiblePrinterRuntime -Required $RequiredCommit
$runtimeRoot = if ($null -ne $selected) { [string]$selected.Root } else { $null }
$runtimeHead = if ($null -ne $selected) { [string]$selected.Head } else { $null }

if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\SysAdminSuitePrinterBootstrapCache')
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(15)) }
        catch [System.Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) { throw 'Printer bootstrap cache is busy in another local process. No mapper was launched.' }

        # Another process may have completed a runtime while this process waited for the lock.
        $selected = Find-SasEligiblePrinterRuntime -Required $RequiredCommit
        if ($null -ne $selected) {
            $runtimeRoot = [string]$selected.Root
            $runtimeHead = [string]$selected.Head
        }
        else {
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
                Invoke-SasGit -Root $null -Arguments @('clone','--no-checkout','--origin','origin','--branch',$Branch,$repositoryUrl,$CacheRoot) -FailureMessage 'Could not create the dedicated SysAdminSuite printer bootstrap cache.' | Out-Null
            }

            Invoke-SasGit -Root $CacheRoot -Arguments @('fetch','--no-tags','origin',("refs/heads/{0}:refs/remotes/origin/{0}" -f $Branch)) -FailureMessage "Could not fetch origin/$Branch into the dedicated printer bootstrap cache." | Out-Null
            $remoteRef = "refs/remotes/origin/$Branch"
            $remoteHead = Get-SasGitScalar -Root $CacheRoot -Arguments @('rev-parse',$remoteRef) -FailureMessage "Could not resolve origin/$Branch."

            if (-not (Test-SasCommitAncestor -Root $CacheRoot -Ancestor $RequiredCommit -Descendant $remoteHead)) {
                Invoke-SasGit -Root $CacheRoot -Arguments @('fetch','--no-tags','origin',$RequiredCommit) -FailureMessage "Required printer fix commit $RequiredCommit is not available from origin." | Out-Null
                if (-not (Test-SasCommitAncestor -Root $CacheRoot -Ancestor $RequiredCommit -Descendant $remoteHead)) {
                    throw "Current origin/$Branch does not contain required printer fix commit $RequiredCommit. No mapper was launched."
                }
            }

            if (-not (Test-Path -LiteralPath $runtimeParent -PathType Container)) { New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null }
            $runtimeRoot = Join-Path $runtimeParent $remoteHead
            if (Test-Path -LiteralPath $runtimeRoot) {
                $existingHead = Get-SasRuntimeHead -Root $runtimeRoot
                if ($existingHead -ne $remoteHead -or -not (Test-SasTrackedRuntimeClean -Root $runtimeRoot) -or -not (Test-SasPrinterRuntimeRoot -Root $runtimeRoot)) {
                    $runtimeRoot = Join-Path $runtimeParent ($remoteHead + '-' + [guid]::NewGuid().ToString('N'))
                }
            }
            if (-not (Test-Path -LiteralPath $runtimeRoot)) {
                Invoke-SasGit -Root $CacheRoot -Arguments @('worktree','add','--detach',$runtimeRoot,$remoteHead) -FailureMessage 'Could not create the dedicated detached printer runtime.' | Out-Null
            }
            if (-not (Test-SasPrinterRuntimeRoot -Root $runtimeRoot)) { throw "Acquired runtime is incomplete for canonical printer mapping: $runtimeRoot" }
            if (-not (Test-SasTrackedRuntimeClean -Root $runtimeRoot)) { throw "Acquired runtime contains tracked modifications and will not be used: $runtimeRoot" }
            $runtimeHead = Get-SasRuntimeHead -Root $runtimeRoot
            if (-not (Test-SasCommitAncestor -Root $runtimeRoot -Ancestor $RequiredCommit -Descendant $runtimeHead)) {
                throw "Acquired runtime does not contain required printer fix commit $RequiredCommit."
            }
            Set-Content -LiteralPath $script:latestPointer -Value $runtimeRoot -Encoding UTF8
        }
    }
    finally {
        if ($lockTaken) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

Write-Host 'SysAdminSuite printer bootstrap' -ForegroundColor Cyan
Write-Host ("Runtime: {0}" -f $runtimeRoot)
Write-Host ("Commit:  {0}" -f $runtimeHead)
Write-Host ("Required fix: {0}" -f $RequiredCommit)
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
