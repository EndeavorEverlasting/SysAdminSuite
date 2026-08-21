#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$resolverPath = Join-Path $repoRoot 'scripts\Resolve-SasAutoLogonManifestAuthority.ps1'
if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
    throw "Missing AutoLogon manifest authority resolver: $resolverPath"
}

$auditSource = Get-Content -LiteralPath $resolverPath -Raw -Encoding UTF8
foreach ($forbidden in @('& git','git.exe','Invoke-Command','Test-NetConnection','Invoke-WebRequest','Start-BitsTransfer')) {
    if ($auditSource.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Manifest authority resolver contains forbidden field/network surface: $forbidden"
    }
}
foreach ($required in @(
    '.git\sas-autologon-short-runtime.json',
    '.git\HEAD',
    'Get-SasRuntimeDetachedHeadCommit',
    'CURRENT_USER_LEGACY',
    'BOUNDED_PROFILE_LEGACY',
    'RUNTIME_LOCAL',
    'AUTOLOGON_MANIFEST_AUTHORITY_READY',
    'AUTOLOGON_MANIFEST_AMBIGUOUS',
    'runtime_head_commit',
    'tracked_runtime_mutation_performed = $false',
    'network_activity_performed = $false',
    'target_contact_performed = $false',
    'target_mutation_performed = $false'
)) {
    if ($auditSource.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
        throw "Manifest authority resolver is missing required contract marker: $required"
    }
}

function Invoke-ResolverChild {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$CurrentStateRoot,
        [Parameter(Mandatory = $true)][string]$LegacySearchRoot,
        [string]$ExpectedCommit,
        [switch]$RequireManifest
    )
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $resolverPath + '"'),
        '-RuntimeRoot',('"' + $RuntimeRoot + '"'),
        '-CurrentStateRoot',('"' + $CurrentStateRoot + '"'),
        '-LegacySearchRoot',('"' + $LegacySearchRoot + '"')
    )
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit)) {
        $arguments += @('-ExpectedCommit',('"' + $ExpectedCommit + '"'))
    }
    if ($RequireManifest) { $arguments += '-RequireManifest' }

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $powershell
    $start.Arguments = ($arguments -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ exit_code=[int]$process.ExitCode; stdout=$stdout; stderr=$stderr }
}

function New-TestManifest {
    param([Parameter(Mandatory = $true)][string]$RuntimeRoot,[Parameter(Mandatory = $true)][string]$Commit)
    return [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-short-runtime/v2'
        runtime_root = $RuntimeRoot
        source_root = $RuntimeRoot
        prepared_commit = $Commit
        prepared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        preparation_network_classification = 'GUEST_INTERNET'
        preparation_network_label = 'fixture'
        runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'
        runtime_remotes_removed = $true
        protected_bootstrap_git_network_allowed = $false
        tracked_file_hash_algorithm = 'SHA256'
        tracked_file_count = 1
        tracked_file_hashes = @([pscustomobject][ordered]@{ path='scripts/one.ps1'; sha256=(('0' * 64) -join '') })
        target_contact_performed = $false
        target_mutation_performed = $false
    }
}

$tempRoot = Join-Path $env:TEMP ('sas-manifest-authority-' + [guid]::NewGuid().ToString('N'))
$runtime = Join-Path $tempRoot 'runtime'
$profiles = Join-Path $tempRoot 'profiles'
$stagerState = Join-Path $profiles 'stager\AppData\Local\SysAdminSuite'
$currentOne = Join-Path $tempRoot 'current-one'
$currentTwo = Join-Path $tempRoot 'current-two'
$currentRefresh = Join-Path $tempRoot 'current-refresh'
$currentConflict = Join-Path $tempRoot 'current-conflict'
$commitA = (('a' * 40) -join '')
$commitB = (('b' * 40) -join '')
$gitRoot = Join-Path $runtime '.git'
$headPath = Join-Path $gitRoot 'HEAD'
$runtimeManifest = Join-Path $gitRoot 'sas-autologon-short-runtime.json'

try {
    New-Item -ItemType Directory -Path $gitRoot -Force | Out-Null
    [IO.File]::WriteAllText($headPath,$commitA,[Text.Encoding]::ASCII)
    New-Item -ItemType Directory -Path $stagerState -Force | Out-Null
    $legacyManifest = Join-Path $stagerState 'autologon-short-runtime.json'
    (New-TestManifest -RuntimeRoot $runtime -Commit $commitA) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $legacyManifest -Encoding UTF8

    # Older runtime: manifest exists only under the staging user's profile. Migrate it to runtime-local metadata.
    $first = Invoke-ResolverChild -RuntimeRoot $runtime -CurrentStateRoot $currentOne -LegacySearchRoot $profiles -ExpectedCommit $commitA -RequireManifest
    if ($first.exit_code -ne 0) {
        throw "Legacy migration failed with exit $($first.exit_code). STDOUT=$($first.stdout) STDERR=$($first.stderr)"
    }
    $receiptOne = Get-Content -LiteralPath (Join-Path $currentOne 'autologon-manifest-authority.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$receiptOne.classification -ne 'AUTOLOGON_MANIFEST_AUTHORITY_READY' -or
        [string]$receiptOne.selected_source -ne 'BOUNDED_PROFILE_LEGACY' -or
        [string]$receiptOne.runtime_head_commit -ne $commitA -or
        -not [bool]$receiptOne.runtime_authority_copy_written -or
        -not [bool]$receiptOne.current_user_compatibility_copy_written) {
        throw 'Legacy-profile authority was not migrated into runtime-local and current-user compatibility copies.'
    }
    if (-not (Test-Path -LiteralPath $runtimeManifest -PathType Leaf)) { throw 'Runtime-local authority copy was not created.' }
    if (-not (Test-Path -LiteralPath (Join-Path $currentOne 'autologon-short-runtime.json') -PathType Leaf)) { throw 'Current-user compatibility copy was not created.' }
    if ([bool]$receiptOne.network_activity_performed -or [bool]$receiptOne.target_contact_performed -or
        [bool]$receiptOne.target_mutation_performed -or [bool]$receiptOne.tracked_runtime_mutation_performed) {
        throw 'Legacy migration violated the local-only/no-target authority contract.'
    }

    # Different user/context: original legacy source disappears; runtime-local authority remains sufficient.
    Remove-Item -LiteralPath $legacyManifest -Force
    $second = Invoke-ResolverChild -RuntimeRoot $runtime -CurrentStateRoot $currentTwo -LegacySearchRoot $profiles -ExpectedCommit $commitA -RequireManifest
    if ($second.exit_code -ne 0) {
        throw "Runtime-local reuse failed with exit $($second.exit_code). STDOUT=$($second.stdout) STDERR=$($second.stderr)"
    }
    $receiptTwo = Get-Content -LiteralPath (Join-Path $currentTwo 'autologon-manifest-authority.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$receiptTwo.selected_source -ne 'RUNTIME_LOCAL' -or
        [bool]$receiptTwo.runtime_authority_copy_written -or
        -not [bool]$receiptTwo.current_user_compatibility_copy_written) {
        throw 'Runtime-local authority did not survive a simulated user-profile change.'
    }

    # Refresh lifecycle: runtime HEAD advances before the new current-user manifest is published. The stale
    # runtime-local manifest must be rejected by commit identity, and the new current-user authority must replace it.
    [IO.File]::WriteAllText($headPath,$commitB,[Text.Encoding]::ASCII)
    New-Item -ItemType Directory -Path $currentRefresh -Force | Out-Null
    (New-TestManifest -RuntimeRoot $runtime -Commit $commitB) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $currentRefresh 'autologon-short-runtime.json') -Encoding UTF8
    $refreshRun = Invoke-ResolverChild -RuntimeRoot $runtime -CurrentStateRoot $currentRefresh -LegacySearchRoot $profiles -ExpectedCommit $commitB -RequireManifest
    if ($refreshRun.exit_code -ne 0) {
        throw "Refresh authority replacement failed with exit $($refreshRun.exit_code). STDOUT=$($refreshRun.stdout) STDERR=$($refreshRun.stderr)"
    }
    $refreshReceipt = Get-Content -LiteralPath (Join-Path $currentRefresh 'autologon-manifest-authority.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$refreshReceipt.selected_source -ne 'CURRENT_USER_LEGACY' -or
        [string]$refreshReceipt.runtime_head_commit -ne $commitB -or
        -not [bool]$refreshReceipt.runtime_authority_copy_written -or
        [int]$refreshReceipt.rejected_candidate_count -lt 1) {
        throw 'Refresh did not reject stale runtime-local authority and publish the current staged authority.'
    }
    $runtimeAfterRefresh = Get-Content -LiteralPath $runtimeManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$runtimeAfterRefresh.prepared_commit -ne $commitB) {
        throw 'Runtime-local authority was not replaced with the newly staged commit.'
    }

    # True ambiguity remains fail-closed when runtime metadata cannot disambiguate candidate identities.
    [IO.File]::WriteAllText($headPath,'ref: refs/heads/fixture',[Text.Encoding]::ASCII)
    $conflictState = Join-Path $profiles 'other\AppData\Local\SysAdminSuite'
    New-Item -ItemType Directory -Path $conflictState -Force | Out-Null
    (New-TestManifest -RuntimeRoot $runtime -Commit $commitA) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $conflictState 'autologon-short-runtime.json') -Encoding UTF8
    $conflictRun = Invoke-ResolverChild -RuntimeRoot $runtime -CurrentStateRoot $currentConflict -LegacySearchRoot $profiles -RequireManifest
    if ($conflictRun.exit_code -ne 12) {
        throw "Expected conflicting authorities to fail with exit 12; got $($conflictRun.exit_code). STDOUT=$($conflictRun.stdout) STDERR=$($conflictRun.stderr)"
    }
    $conflictReceipt = Get-Content -LiteralPath (Join-Path $currentConflict 'autologon-manifest-authority.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$conflictReceipt.classification -ne 'AUTOLOGON_MANIFEST_AMBIGUOUS' -or [int]$conflictReceipt.valid_candidate_count -lt 2) {
        throw 'Conflicting manifest authorities were not durably classified as ambiguous.'
    }
    if ([bool]$conflictReceipt.network_activity_performed -or [bool]$conflictReceipt.target_contact_performed -or
        [bool]$conflictReceipt.target_mutation_performed -or [bool]$conflictReceipt.tracked_runtime_mutation_performed) {
        throw 'Ambiguous authority handling violated the no-target/no-tracked-runtime-mutation contract.'
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: AutoLogon manifest authority migrates legacy state, survives user changes, replaces stale refresh metadata, and rejects true conflicts under Windows PowerShell 5.1.'
