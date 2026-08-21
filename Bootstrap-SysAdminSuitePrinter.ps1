#Requires -Version 5.1
<#
.SYNOPSIS
Launch the canonical Northwell printer mapper from the current origin branch head without requiring the caller to be inside SysAdminSuite.

.DESCRIPTION
The normal path is remote-authoritative: the bootstrap uses one dedicated machine-local Git cache, fetches the requested branch without force, resolves the exact origin branch head, and launches only a clean detached runtime at that exact commit. A clean but older C:\SASAL or operator checkout is never treated as current merely because it descends from an older required baseline.

The caller's current directory and dirty operator checkout are not repository authority. No arbitrary checkout is reset, cleaned, checked out, stashed, or committed. Unrelated local work therefore cannot block printer mapping and cannot be silently overwritten.

Superseded clean bootstrap-owned runtimes are retired after their mapping evidence is moved into the shared printer state root. Dirty or otherwise suspicious bootstrap-owned runtimes are preserved and reported instead of being destructively cleaned. The exact current runtime path never falls back to GUID-suffixed duplicates.

-UseLocalRuntimeOnly is an explicit offline/fixture escape hatch. It does not claim current-origin proof and is used only when the launcher/operator explicitly requests offline mode.
#>
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$RequiredCommit = '66d38dd45881692303f77267e29e4fa44b4a9351',
    [string]$CacheRoot,
    [ValidateSet('Quick','File')][string]$Mode = 'Quick',
    [switch]$NoLaunch,
    [switch]$UseLocalRuntimeOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git'
$requiredRuntimePaths = @(
    'Map-NorthwellPrinter-SystemWide.cmd',
    'mapping\Diagnose-NorthwellPrinterEvidence.ps1',
    'mapping\Start-NorthwellPrinterMapping.ps1',
    'mapping\Invoke-NorthwellPrinterState.ps1',
    'mapping\Modules\NorthwellPrinterMapping.Core.psm1',
    'mapping\Confirm-NorthwellPrinterActiveUserMaterialization.ps1',
    'mapping\Agents\Invoke-NorthwellPrinterActiveUserAgent.ps1',
    'scripts\SasNorthwellNetworkAuthority.psm1',
    'scripts\SasTargetNameResolution.psm1',
    'scripts\SasNetworkGuard.psm1',
    'scripts\SasInteractionCache.psm1',
    'Config\interaction-cache-policy.json'
)
if ($Mode -eq 'File') {
    $requiredRuntimePaths += @(
        'Map-NorthwellPrinters-FromFile.cmd',
        'Map-NorthwellPrinters-Batch.cmd',
        'mapping\Start-NorthwellPrinterBatch.ps1',
        'mapping\Confirm-NorthwellPrinterBatchActiveUserMaterialization.ps1',
        'mapping\Examples\NorthwellPrinterBatch.example.csv'
    )
}

function Resolve-SasGitExecutable {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { $command = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1 }
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
    throw 'Git for Windows is required to prove the current printer runtime.'
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
    $stdout = @()
    $exitCode = 1
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
        try {
            $stderrRaw = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
            if ($null -ne $stderrRaw) { $stderr = [string]$stderrRaw }
        }
        finally { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    }

    $lines = @()
    foreach ($item in @($stdout)) {
        if ($null -ne $item) { $lines += [string]$item }
    }
    $stdoutText = if ($lines.Count -gt 0) { [string]::Join([Environment]::NewLine,[string[]]$lines) } else { '' }
    $detail = (@($stdoutText,$stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = '(git produced no diagnostic text)' }
        throw "$FailureMessage (git exit $exitCode)`n$detail"
    }
    return [pscustomobject]@{ ExitCode=$exitCode; Lines=$lines; Text=$detail }
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

function Test-SasCommitAncestor {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Ancestor,
        [Parameter(Mandatory = $true)][string]$Descendant
    )
    $result = Invoke-SasGit -Root $Root -Arguments @('merge-base','--is-ancestor',$Ancestor,$Descendant) -FailureMessage 'Could not compare SysAdminSuite commit ancestry.' -AllowFailure
    return ($result.ExitCode -eq 0)
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

function Test-SasTrackedRuntimeClean {
    param([Parameter(Mandatory = $true)][string]$Root)
    $statusArguments = @('status','--porcelain','--untracked-files=no','--')
    $statusArguments += @($script:requiredRuntimePaths)
    $result = Invoke-SasGit -Root $Root -Arguments $statusArguments -FailureMessage 'Could not inspect printer-owned runtime tracked state.' -AllowFailure
    if ($result.ExitCode -ne 0) { return $false }
    return @($result.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0
}

function Test-SasDedicatedCacheRoot {
    param([Parameter(Mandatory = $true)][string]$Root)
    if (-not (Test-Path -LiteralPath (Join-Path $Root '.git') -PathType Container)) { return $false }
    $inside = Invoke-SasGit -Root $Root -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage 'Could not inspect dedicated printer bootstrap cache.' -AllowFailure
    if ($inside.ExitCode -ne 0) { return $false }
    $value = [string]($inside.Lines | Select-Object -First 1)
    return (-not [string]::IsNullOrWhiteSpace($value) -and $value.Trim().Equals('true',[System.StringComparison]::OrdinalIgnoreCase))
}

function Test-SasExpectedOrigin {
    param([Parameter(Mandatory = $true)][string]$Url)
    $normalized = $Url.Trim().TrimEnd('/').ToLowerInvariant()
    return $normalized -in @(
        'https://github.com/endeavoreverlasting/sysadminsuite.git',
        'https://github.com/endeavoreverlasting/sysadminsuite',
        'git@github.com:endeavoreverlasting/sysadminsuite.git'
    )
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

function Find-SasEligibleLocalPrinterRuntime {
    param([Parameter(Mandatory = $true)][string]$Required)
    foreach ($candidate in @(Get-SasPrinterRuntimeCandidates)) {
        if (-not (Test-SasPrinterRuntimeRoot -Root $candidate)) { continue }
        if (-not (Test-SasTrackedRuntimeClean -Root $candidate)) { continue }
        $head = Get-SasRuntimeHead -Root $candidate
        if ([string]::IsNullOrWhiteSpace($head)) { continue }
        if (-not (Test-SasCommitAncestor -Root $candidate -Ancestor $Required -Descendant $head)) { continue }
        return [pscustomobject]@{ Root=$candidate; Head=$head }
    }
    return $null
}

function Resolve-SasPrinterStateRoot {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($base in @($env:SAS_RUNTIME_ROOT,'C:\SASAL')) {
        if ([string]::IsNullOrWhiteSpace([string]$base)) { continue }
        try { $fullBase = [IO.Path]::GetFullPath([string]$base) } catch { continue }
        if ($fullBase -notmatch '^[A-Za-z]:\\' -or -not (Test-Path -LiteralPath $fullBase -PathType Container)) { continue }
        $candidate = Join-Path $fullBase '.state\printer-bootstrap'
        if (-not $candidates.Contains($candidate)) { [void]$candidates.Add($candidate) }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:ProgramData)) {
        $candidate = Join-Path $env:ProgramData 'SysAdminSuite\printer-bootstrap'
        if (-not $candidates.Contains($candidate)) { [void]$candidates.Add($candidate) }
    }
    foreach ($candidate in $candidates) {
        try {
            New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
            $probe = Join-Path $candidate ('.write-probe-' + [guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($probe,'ok')
            Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
            return [IO.Path]::GetFullPath($candidate)
        }
        catch {}
    }
    if ([string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) {
        throw 'No writable machine-local printer state root is available, and LOCALAPPDATA fallback is unavailable.'
    }
    $fallback = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\printer-bootstrap'
    New-Item -ItemType Directory -Path $fallback -Force -ErrorAction Stop | Out-Null
    Write-Warning 'Machine-local printer state was not writable; using current-user compatibility state. Run the universal installer elevated to restore shared machine state.'
    return [IO.Path]::GetFullPath($fallback)
}

function Test-SasPathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $fullPath = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $fullRoot = ([IO.Path]::GetFullPath($Root)).TrimEnd('\')
    return $fullPath.StartsWith($fullRoot + '\',[System.StringComparison]::OrdinalIgnoreCase)
}

function Move-SasPrinterRuntimeEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$StateRoot
    )
    $source = Join-Path $RuntimeRoot 'mapping\Logs'
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return $null }
    $items = @(Get-ChildItem -LiteralPath $source -Force -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) { return $null }

    $evidenceRoot = Join-Path $StateRoot 'evidence'
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    $runtimeName = Split-Path -Leaf $RuntimeRoot
    $destination = Join-Path $evidenceRoot ("{0}-{1}" -f $runtimeName,(Get-Date -Format 'yyyyMMdd-HHmmssfff'))
    Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
    return $destination
}

function Remove-SasSupersededPrinterRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$RuntimeParent,
        [Parameter(Mandatory = $true)][string]$CacheRoot,
        [Parameter(Mandatory = $true)][string]$StateRoot
    )
    if (-not (Test-SasPathInsideRoot -Path $RuntimeRoot -Root $RuntimeParent)) {
        Write-Warning "Refusing to retire printer runtime outside bootstrap-owned root: $RuntimeRoot"
        return $false
    }
    if (-not (Test-SasTrackedRuntimeClean -Root $RuntimeRoot)) {
        Write-Warning "Preserving superseded printer runtime because tracked printer files are modified: $RuntimeRoot"
        return $false
    }

    $archive = $null
    try { $archive = Move-SasPrinterRuntimeEvidence -RuntimeRoot $RuntimeRoot -StateRoot $StateRoot }
    catch {
        Write-Warning "Preserving superseded printer runtime because evidence could not be archived: $RuntimeRoot :: $($_.Exception.Message)"
        return $false
    }

    $remove = Invoke-SasGit -Root $CacheRoot -Arguments @('worktree','remove','--force',$RuntimeRoot) -FailureMessage "Could not retire superseded bootstrap-owned printer runtime: $RuntimeRoot" -AllowFailure
    if ($remove.ExitCode -ne 0) {
        Write-Warning "Could not retire superseded printer runtime; it remains preserved: $RuntimeRoot :: $($remove.Text)"
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$archive)) { Write-Host "Preserved superseded printer evidence: $archive" -ForegroundColor DarkGray }
    Write-Host "Retired superseded printer runtime: $RuntimeRoot" -ForegroundColor DarkGray
    return $true
}

function Remove-SasSupersededPrinterRuntimes {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRuntime,
        [Parameter(Mandatory = $true)][string]$RuntimeParent,
        [Parameter(Mandatory = $true)][string]$CacheRoot,
        [Parameter(Mandatory = $true)][string]$StateRoot
    )
    if (-not (Test-Path -LiteralPath $RuntimeParent -PathType Container)) { return }
    $currentFull = [IO.Path]::GetFullPath($CurrentRuntime)
    foreach ($directory in @(Get-ChildItem -LiteralPath $RuntimeParent -Directory -Force -ErrorAction SilentlyContinue)) {
        $candidate = [IO.Path]::GetFullPath($directory.FullName)
        if ($candidate.Equals($currentFull,[System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void](Remove-SasSupersededPrinterRuntime -RuntimeRoot $candidate -RuntimeParent $RuntimeParent -CacheRoot $CacheRoot -StateRoot $StateRoot)
    }
    [void](Invoke-SasGit -Root $CacheRoot -Arguments @('worktree','prune') -FailureMessage 'Could not prune stale bootstrap-owned printer worktree metadata.' -AllowFailure)
}

$RequiredCommit = $RequiredCommit.Trim()
if ([string]::IsNullOrWhiteSpace($RequiredCommit)) { throw 'RequiredCommit cannot be blank.' }
$stateRoot = Resolve-SasPrinterStateRoot
if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $stateRoot 'source' }
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
$runtimeParent = Join-Path $stateRoot 'runtimes'
$script:latestPointer = Join-Path $stateRoot 'latest-runtime.txt'
$script:SasGitExe = Resolve-SasGitExecutable
$runtimeRoot = $null
$runtimeHead = $null
$remoteHead = $null
$authority = $null

if ($UseLocalRuntimeOnly) {
    $selected = Find-SasEligibleLocalPrinterRuntime -Required $RequiredCommit
    if ($null -eq $selected) {
        throw 'No clean local printer runtime contains the required baseline. Local-only mode cannot continue.'
    }
    $runtimeRoot = [string]$selected.Root
    $runtimeHead = [string]$selected.Head
    $authority = 'EXPLICIT_LOCAL_ONLY_NO_ORIGIN_CURRENTNESS_CLAIM'
}
else {
    $mutex = New-Object System.Threading.Mutex($false,'Local\SysAdminSuitePrinterBootstrapCache')
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(20)) }
        catch [System.Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) { throw 'Printer bootstrap cache is busy in another local process. No mapper was launched.' }

        if (Test-Path -LiteralPath $CacheRoot) {
            if (-not (Test-SasDedicatedCacheRoot -Root $CacheRoot)) {
                throw "Printer bootstrap cache path already exists but is not the dedicated Git worktree. Nothing was changed: $CacheRoot"
            }
            $origin = Get-SasGitScalar -Root $CacheRoot -Arguments @('remote','get-url','origin') -FailureMessage 'Could not inspect dedicated printer bootstrap origin.'
            if (-not (Test-SasExpectedOrigin -Url $origin)) {
                throw "Printer bootstrap cache origin is unexpected. Nothing was changed: $origin"
            }
        }
        else {
            $parent = Split-Path -Parent $CacheRoot
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Invoke-SasGit -Root $null -Arguments @('clone','--no-checkout','--origin','origin','--branch',$Branch,$repositoryUrl,$CacheRoot) -FailureMessage 'Could not create the dedicated SysAdminSuite printer bootstrap cache.' | Out-Null
        }

        Write-Host "Fetching current origin/$Branch for printer runtime authority..." -ForegroundColor Cyan
        Invoke-SasGit -Root $CacheRoot -Arguments @('fetch','--no-tags','--prune','origin',("refs/heads/{0}:refs/remotes/origin/{0}" -f $Branch)) -FailureMessage "Could not fetch current origin/$Branch. Stale local printer code will not be launched. If GitHub is intentionally unavailable on the protected path, use 'sas printer offline'." | Out-Null
        $remoteRef = "refs/remotes/origin/$Branch"
        $remoteHead = Get-SasGitScalar -Root $CacheRoot -Arguments @('rev-parse',$remoteRef) -FailureMessage "Could not resolve current origin/$Branch."

        if (-not (Test-SasCommitAncestor -Root $CacheRoot -Ancestor $RequiredCommit -Descendant $remoteHead)) {
            Invoke-SasGit -Root $CacheRoot -Arguments @('fetch','--no-tags','origin',$RequiredCommit) -FailureMessage "Required printer baseline $RequiredCommit is not available from origin." | Out-Null
            if (-not (Test-SasCommitAncestor -Root $CacheRoot -Ancestor $RequiredCommit -Descendant $remoteHead)) {
                throw "Current origin/$Branch does not contain required printer baseline $RequiredCommit. No mapper was launched."
            }
        }

        if (-not (Test-Path -LiteralPath $runtimeParent -PathType Container)) { New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null }
        $runtimeRoot = Join-Path $runtimeParent $remoteHead
        if (Test-Path -LiteralPath $runtimeRoot) {
            $existingHead = Get-SasRuntimeHead -Root $runtimeRoot
            if ($existingHead -ne $remoteHead -or -not (Test-SasTrackedRuntimeClean -Root $runtimeRoot) -or -not (Test-SasPrinterRuntimeRoot -Root $runtimeRoot)) {
                throw "Exact current printer runtime path exists but is invalid or modified. It was preserved and no duplicate runtime was created: $runtimeRoot"
            }
        }
        else {
            Invoke-SasGit -Root $CacheRoot -Arguments @('worktree','add','--detach',$runtimeRoot,$remoteHead) -FailureMessage 'Could not create the exact current printer runtime.' | Out-Null
        }
        if (-not (Test-SasPrinterRuntimeRoot -Root $runtimeRoot)) { throw "Current branch runtime is incomplete for canonical printer mapping: $runtimeRoot" }
        if (-not (Test-SasTrackedRuntimeClean -Root $runtimeRoot)) { throw "Current branch runtime contains tracked printer modifications and will not be used: $runtimeRoot" }
        $runtimeHead = Get-SasRuntimeHead -Root $runtimeRoot
        if ($runtimeHead -ne $remoteHead) { throw "Printer runtime HEAD mismatch. Expected current origin/$Branch $remoteHead; got $runtimeHead" }
        Set-Content -LiteralPath $script:latestPointer -Value $runtimeRoot -Encoding UTF8
        Remove-SasSupersededPrinterRuntimes -CurrentRuntime $runtimeRoot -RuntimeParent $runtimeParent -CacheRoot $CacheRoot -StateRoot $stateRoot
        $authority = 'CURRENT_ORIGIN_BRANCH_HEAD_PROVEN'
    }
    finally {
        if ($lockTaken) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

Write-Host 'SysAdminSuite printer bootstrap' -ForegroundColor Cyan
Write-Host ("Runtime: {0}" -f $runtimeRoot)
Write-Host ("Commit:  {0}" -f $runtimeHead)
if (-not [string]::IsNullOrWhiteSpace([string]$remoteHead)) { Write-Host ("origin/{0}: {1}" -f $Branch,$remoteHead) }
Write-Host ("Required baseline: {0}" -f $RequiredCommit)
Write-Host ("Runtime authority: {0}" -f $authority)
Write-Host ("Mode: {0}" -f $Mode)
Write-Host ("State root: {0}" -f $stateRoot)
Write-Host 'Current directory and dirty operator checkouts are not repository authority.' -ForegroundColor DarkGray

if ($NoLaunch) {
    Write-Host 'PASS: printer runtime resolved; launcher not executed (-NoLaunch).' -ForegroundColor Green
    exit 0
}

$launcherName = if ($Mode -eq 'File') { 'Map-NorthwellPrinters-FromFile.cmd' } else { 'Map-NorthwellPrinter-SystemWide.cmd' }
$launcher = Join-Path $runtimeRoot $launcherName
Write-Host ("Launching Northwell printer mapper from {0}: {1}" -f $authority,$Mode) -ForegroundColor Green
& $launcher
exit ([int]$LASTEXITCODE)
