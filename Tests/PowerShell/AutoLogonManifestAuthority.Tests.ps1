#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$resolverPath = Join-Path $repoRoot 'scripts\Resolve-SasAutoLogonManifestAuthority.ps1'
if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
    throw "Missing AutoLogon manifest authority resolver: $resolverPath"
}

$source = Get-Content -LiteralPath $resolverPath -Raw -Encoding UTF8
foreach ($forbidden in @('& git','git.exe','Invoke-Command','Test-NetConnection','Invoke-WebRequest','Start-BitsTransfer','wpj075','nslijhs.net')) {
    if ($source.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Manifest authority resolver contains forbidden field/network surface: $forbidden"
    }
}
foreach ($required in @(
    '.git\sas-autologon-short-runtime.json',
    'CURRENT_USER_LEGACY',
    'BOUNDED_PROFILE_LEGACY',
    'RUNTIME_LOCAL',
    'AUTOLOGON_MANIFEST_AUTHORITY_READY',
    'AUTOLOGON_MANIFEST_AMBIGUOUS',
    'tracked_runtime_mutation_performed = $false',
    'network_activity_performed = $false',
    'target_contact_performed = $false',
    'target_mutation_performed = $false'
)) {
    if ($source.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
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
$currentThree = Join-Path $tempRoot 'current-three'
$commitA = (('a' * 40) -join '')
$commitB = (('b' * 40) -join '')
$runtimeManifest = Join-Path $runtime '.git\sas-autologon-short-runtime.json'

try {
    New-Item -ItemType Directory -Path (Join-Path $runtime '.git') -Force | Out-Null
    New-Item -ItemType Directory -Path $stagerState -Force | Out-Null
    $legacyManifest = Join-Path $stagerState 'autologon-short-runtime.json'
    (New-TestManifest -RuntimeRoot $runtime -Commit $commitA) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $legacyManifest -Encoding UTF8

    $first = Invoke-ResolverChild -RuntimeRoot $runtime -CurrentStateRoot $currentOne -LegacySearchRoot $profiles -ExpectedCommit $commitA -RequireManifest
    if ($first.exit_code -ne 0) {
        throw "Legacy migration failed with exit $($first.exit_code). STDOUT=$($first.stdout) STDERR=$($first.stderr)"
    }
    $receiptOne = Get-Content -LiteralPath (Join-Path $currentOne 'autologon-manifest-authority.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$receiptOne.classification -ne 'AUTOLOGON_MANIFEST_AUTHORITY_READY' -or
        [string]$receiptOne.selected_source -ne 'BOUNDED_PROFILE_LEGACY' -or
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

    $conflictState = Join-Path $profiles 'other\AppData\Local\SysAdminSuite'
    New-Item -ItemType Directory -Path $conflictState -Force | Out-Null
    (New-TestManifest -RuntimeRoot $runtime -Commit $commitB) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $conflictState 'autologon-short-runtime.json') -Encoding UTF8
    $third = Invoke-ResolverChild -RuntimeRoot $runtime -CurrentStateRoot $currentThree -LegacySearchRoot $profiles -RequireManifest
    if ($third.exit_code -ne 12) {
        throw "Expected conflicting authorities to fail with exit 12; got $($third.exit_code). STDOUT=$($third.stdout) STDERR=$($third.stderr)"
    }
    $receiptThree = Get-Content -LiteralPath (Join-Path $currentThree 'autologon-manifest-authority.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$receiptThree.classification -ne 'AUTOLOGON_MANIFEST_AMBIGUOUS' -or [int]$receiptThree.valid_candidate_count -lt 2) {
        throw 'Conflicting manifest authorities were not durably classified as ambiguous.'
    }
    if ([bool]$receiptThree.network_activity_performed -or [bool]$receiptThree.target_contact_performed -or
        [bool]$receiptThree.target_mutation_performed -or [bool]$receiptThree.tracked_runtime_mutation_performed) {
        throw 'Ambiguous authority handling violated the no-target/no-tracked-runtime-mutation contract.'
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: AutoLogon manifest authority migrates legacy profile state, survives user changes, and rejects conflicts under Windows PowerShell 5.1.'
