#Requires -Version 5.1
<#
.SYNOPSIS
Audit the entire sealed AutoLogon runtime without contacting a target.

.DESCRIPTION
Reads the Guest-created AutoLogon short-runtime v2 manifest, verifies every declared tracked file with
.NET SHA-256, records every changed/missing/invalid entry in one pass, and writes a durable local receipt.
The audit performs no Git operation, no network operation, no target contact, and no target mutation.

A failed audit is a pre-transaction failure. It must not be interpreted as a new crash-safe AutoLogon run.
#>
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$ManifestPath,
    [string]$ReceiptPath,
    [string]$ExpectedCommit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasSha256Hex {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $stream = $null
    $sha256 = $null
    try {
        $stream = [IO.File]::Open(
            $LiteralPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $sha256 = [Security.Cryptography.SHA256]::Create()
        $bytes = $sha256.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-SasJsonPropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $stateRoot 'autologon-short-runtime.json'
}
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $ReceiptPath = Join-Path $stateRoot 'autologon-runtime-verification.json'
}

$issues = @()
function Add-SasSealIssue {
    param(
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$ExpectedSha256,
        [string]$ActualSha256,
        [string]$Detail
    )
    $script:issues += [pscustomobject][ordered]@{
        path = $Path
        reason = $Reason
        expected_sha256 = $ExpectedSha256
        actual_sha256 = $ActualSha256
        detail = $Detail
    }
}

$runtimeState = $null
$runtimeFullPath = ''
$manifestSchemaVersion = ''
$preparedCommit = ''
$declaredSealCount = 0
$checkedCount = 0
$verifiedCount = 0
$structuralFailure = $false

try {
    $runtimeFullPath = [IO.Path]::GetFullPath($RuntimeRoot)
}
catch {
    Add-SasSealIssue -Path '' -Reason 'RUNTIME_ROOT_INVALID' -Detail $_.Exception.Message
    $structuralFailure = $true
}

if (-not $structuralFailure -and -not (Test-Path -LiteralPath $runtimeFullPath -PathType Container)) {
    Add-SasSealIssue -Path '' -Reason 'RUNTIME_ROOT_MISSING' -Detail "Runtime root does not exist: $runtimeFullPath"
    $structuralFailure = $true
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Add-SasSealIssue -Path '' -Reason 'MANIFEST_MISSING' -Detail "Staging manifest is missing: $ManifestPath"
    $structuralFailure = $true
}

if (-not $structuralFailure) {
    try {
        $runtimeState = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-SasSealIssue -Path '' -Reason 'MANIFEST_UNREADABLE' -Detail $_.Exception.Message
        $structuralFailure = $true
    }
}

if (-not $structuralFailure) {
    $manifestSchemaVersion = [string](Get-SasJsonPropertyValue -Object $runtimeState -Name 'schema_version')
    if ($manifestSchemaVersion -ne 'sas-autologon-short-runtime/v2') {
        Add-SasSealIssue -Path '' -Reason 'MANIFEST_SCHEMA_UNSUPPORTED' -Detail "Unsupported staging manifest schema: $manifestSchemaVersion"
        $structuralFailure = $true
    }

    $manifestRootRaw = [string](Get-SasJsonPropertyValue -Object $runtimeState -Name 'runtime_root')
    try { $manifestRoot = [IO.Path]::GetFullPath($manifestRootRaw) }
    catch {
        Add-SasSealIssue -Path '' -Reason 'MANIFEST_RUNTIME_ROOT_INVALID' -Detail $_.Exception.Message
        $manifestRoot = ''
        $structuralFailure = $true
    }
    if (-not $structuralFailure -and
        -not $manifestRoot.TrimEnd('\').Equals($runtimeFullPath.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        Add-SasSealIssue -Path '' -Reason 'MANIFEST_RUNTIME_ROOT_MISMATCH' -Detail "Manifest=$manifestRoot Runtime=$runtimeFullPath"
        $structuralFailure = $true
    }

    if ([string](Get-SasJsonPropertyValue -Object $runtimeState -Name 'preparation_network_classification') -ne 'GUEST_INTERNET') {
        Add-SasSealIssue -Path '' -Reason 'PREPARATION_NETWORK_INVALID' -Detail 'Runtime was not sealed on Guest/Internet.'
        $structuralFailure = $true
    }
    if ([string](Get-SasJsonPropertyValue -Object $runtimeState -Name 'runtime_git_transport') -ne 'LOCAL_FILESYSTEM_ONLY' -or
        -not [bool](Get-SasJsonPropertyValue -Object $runtimeState -Name 'runtime_remotes_removed') -or
        [bool](Get-SasJsonPropertyValue -Object $runtimeState -Name 'protected_bootstrap_git_network_allowed')) {
        Add-SasSealIssue -Path '' -Reason 'LOCAL_ONLY_POSTURE_INVALID' -Detail 'Manifest does not prove remotes removed and protected Git network disabled.'
        $structuralFailure = $true
    }

    $preparedCommit = ([string](Get-SasJsonPropertyValue -Object $runtimeState -Name 'prepared_commit')).Trim()
    if ([string]::IsNullOrWhiteSpace($preparedCommit)) {
        Add-SasSealIssue -Path '' -Reason 'PREPARED_COMMIT_MISSING' -Detail 'Staging manifest has no prepared commit.'
        $structuralFailure = $true
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and
        -not $preparedCommit.Equals($ExpectedCommit.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
        Add-SasSealIssue -Path '' -Reason 'PREPARED_COMMIT_MISMATCH' -Detail "Expected=$($ExpectedCommit.Trim()) Prepared=$preparedCommit"
        $structuralFailure = $true
    }

    if ([string](Get-SasJsonPropertyValue -Object $runtimeState -Name 'tracked_file_hash_algorithm') -ne 'SHA256') {
        Add-SasSealIssue -Path '' -Reason 'HASH_ALGORITHM_UNSUPPORTED' -Detail 'Tracked-file hash algorithm must be SHA256.'
        $structuralFailure = $true
    }

    $sealEntries = @((Get-SasJsonPropertyValue -Object $runtimeState -Name 'tracked_file_hashes'))
    $declaredSealCountValue = Get-SasJsonPropertyValue -Object $runtimeState -Name 'tracked_file_count'
    $parsedSealCount = 0
    $declaredSealCountText = if ($null -eq $declaredSealCountValue) { '' } else { ([string]$declaredSealCountValue).Trim() }
    if ([string]::IsNullOrWhiteSpace($declaredSealCountText) -or
        -not [int]::TryParse($declaredSealCountText, [ref]$parsedSealCount) -or
        $parsedSealCount -lt 1) {
        Add-SasSealIssue -Path '' -Reason 'SEAL_COUNT_INVALID' -Detail "tracked_file_count is not a positive Int32: '$declaredSealCountText'"
        $structuralFailure = $true
    }
    else {
        $declaredSealCount = $parsedSealCount
        if ($sealEntries.Count -ne $declaredSealCount) {
            Add-SasSealIssue -Path '' -Reason 'SEAL_COUNT_MISMATCH' -Detail "Declared=$declaredSealCount Actual=$($sealEntries.Count)"
            $structuralFailure = $true
        }
    }
}

if (-not $structuralFailure) {
    $runtimePrefix = $runtimeFullPath.TrimEnd('\') + '\'
    foreach ($entry in $sealEntries) {
        $relative = [string](Get-SasJsonPropertyValue -Object $entry -Name 'path')
        $expectedHash = ([string](Get-SasJsonPropertyValue -Object $entry -Name 'sha256')).Trim().ToLowerInvariant()
        $checkedCount++

        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
            Add-SasSealIssue -Path $relative -Reason 'TRACKED_PATH_INVALID' -ExpectedSha256 $expectedHash -Detail 'Tracked path is empty or rooted.'
            continue
        }
        if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
            Add-SasSealIssue -Path $relative -Reason 'EXPECTED_HASH_INVALID' -ExpectedSha256 $expectedHash -Detail 'Expected SHA-256 is not 64 lowercase/uppercase hex characters.'
            continue
        }

        $relativeWindows = $relative.Replace('/', '\')
        try { $fullPath = [IO.Path]::GetFullPath((Join-Path $runtimeFullPath $relativeWindows)) }
        catch {
            Add-SasSealIssue -Path $relative -Reason 'TRACKED_PATH_INVALID' -ExpectedSha256 $expectedHash -Detail $_.Exception.Message
            continue
        }
        if (-not $fullPath.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Add-SasSealIssue -Path $relative -Reason 'TRACKED_PATH_ESCAPE' -ExpectedSha256 $expectedHash -Detail 'Tracked path escapes the runtime root.'
            continue
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Add-SasSealIssue -Path $relative -Reason 'MISSING_FILE' -ExpectedSha256 $expectedHash -Detail 'Tracked runtime file is missing.'
            continue
        }

        try { $actualHash = Get-SasSha256Hex -LiteralPath $fullPath }
        catch {
            Add-SasSealIssue -Path $relative -Reason 'HASH_READ_FAILED' -ExpectedSha256 $expectedHash -Detail $_.Exception.Message
            continue
        }
        if ($actualHash -ne $expectedHash) {
            Add-SasSealIssue -Path $relative -Reason 'HASH_MISMATCH' -ExpectedSha256 $expectedHash -ActualSha256 $actualHash -Detail 'Tracked runtime file changed after Guest staging.'
            continue
        }
        $verifiedCount++
    }
}

$changedCount = @($issues | Where-Object { $_.reason -eq 'HASH_MISMATCH' }).Count
$missingCount = @($issues | Where-Object { $_.reason -eq 'MISSING_FILE' }).Count
$invalidEntryCount = @($issues | Where-Object { $_.reason -in @('TRACKED_PATH_INVALID','TRACKED_PATH_ESCAPE','EXPECTED_HASH_INVALID','HASH_READ_FAILED') }).Count
$classification = if ($issues.Count -eq 0) {
    'AUTOLOGON_RUNTIME_SEAL_VERIFIED'
}
elseif ($structuralFailure) {
    'AUTOLOGON_RUNTIME_NOT_PREPARED'
}
else {
    'AUTOLOGON_RUNTIME_SEAL_MISMATCH'
}
$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAILED' }

$receipt = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-runtime-verification/v1'
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    status = $status
    classification = $classification
    runtime_root = $runtimeFullPath
    manifest_path = $ManifestPath
    manifest_schema_version = $manifestSchemaVersion
    prepared_commit = $preparedCommit
    expected_commit = if ([string]::IsNullOrWhiteSpace($ExpectedCommit)) { $null } else { $ExpectedCommit.Trim() }
    declared_file_count = $declaredSealCount
    checked_file_count = $checkedCount
    verified_file_count = $verifiedCount
    issue_count = $issues.Count
    changed_file_count = $changedCount
    missing_file_count = $missingCount
    invalid_entry_count = $invalidEntryCount
    issues = $issues
    protected_git_activity = 'NONE'
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    crash_safe_run_started = $false
}

try {
    $receiptDirectory = Split-Path -Parent $ReceiptPath
    if (-not (Test-Path -LiteralPath $receiptDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
}
catch {
    Write-Error "AUTOLOGON_RUNTIME_VERIFICATION_RECEIPT_WRITE_FAILED: $($_.Exception.Message)"
    exit 11
}

Write-Host "AutoLogon runtime verification receipt: $ReceiptPath" -ForegroundColor Cyan
if ($status -eq 'PASS') {
    Write-Host "PASS: sealed tracked runtime content verified without Git ($verifiedCount files)." -ForegroundColor Green
    exit 0
}

Write-Host "FAILED: AutoLogon runtime verification found $($issues.Count) issue(s)." -ForegroundColor Red
foreach ($issue in $issues) {
    $displayPath = if ([string]::IsNullOrWhiteSpace([string]$issue.path)) { '<manifest/runtime>' } else { [string]$issue.path }
    Write-Host ("  [{0}] {1}" -f $issue.reason,$displayPath) -ForegroundColor Yellow
}
Write-Host 'No crash-safe AutoLogon field transaction was started.' -ForegroundColor Yellow
exit 10
