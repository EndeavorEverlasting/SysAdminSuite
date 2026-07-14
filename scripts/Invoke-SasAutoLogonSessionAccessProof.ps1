#Requires -Version 5.1
<#
.SYNOPSIS
Prove bounded local-directory and file-share access from the actual AutoLogon user session.

.DESCRIPTION
This entrypoint must be run interactively inside the real AutoLogon session. It verifies that the
current Windows identity matches the expected hostname-based account before testing any path.

For each explicit path it performs a bounded directory-open test. When -AllowWriteProbe is supplied,
it creates one uniquely named zero-byte marker with FileMode.CreateNew and removes it immediately.
The marker is never reused or overwritten. No file contents or directory entry names are returned.

This script does not impersonate another account, accept credentials, create persistence, modify
ACLs, or run through PowerShell remoting. Its output is an in-memory object written to the pipeline.
FixtureMode is offline contract proof and never contacts a path or creates a marker.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,

    [string]$ExpectedUserName,

    [ValidateRange(1, 12)]
    [int]$MaxPaths = 12,

    [ValidateRange(0, 5)]
    [int]$RetryCount = 2,

    [ValidateRange(1, 30)]
    [int]$RetryDelaySeconds = 5,

    [switch]$AllowWriteProbe,
    [switch]$Enforce,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-SasAccountLeaf {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $leaf = $Value.Trim()
    if ($leaf.Contains('\')) { $leaf = $leaf.Split('\')[-1] }
    if ($leaf.Contains('@')) { $leaf = $leaf.Split('@')[0] }
    return $leaf.TrimEnd('$').ToUpperInvariant()
}

function Get-SasPathKind {
    param([string]$Value)

    if ($Value -match '^\\\\[^\\]+\\[^\\]+') { return 'unc' }
    return 'drive_rooted'
}

function Assert-SasSessionProofPaths {
    param(
        [string[]]$Values,
        [int]$Limit
    )

    $clean = @()
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $candidate = $value.Trim()

        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($candidate)) {
            throw "Path cannot contain wildcard characters: $candidate"
        }
        if (@($candidate -split '[\\/]') -contains '..') {
            throw "Path cannot contain parent traversal segments: $candidate"
        }
        if ($candidate -notmatch '^[A-Za-z]:\\' -and $candidate -notmatch '^\\\\[^\\]+\\[^\\]+') {
            throw "Path must be a drive-rooted local/mapped path or a complete UNC share path: $candidate"
        }

        $clean += $candidate.TrimEnd('\')
    }

    $result = @($clean | Sort-Object -Unique)
    if ($result.Count -eq 0) {
        throw 'At least one explicit local, mapped-drive, or UNC path is required.'
    }
    if ($result.Count -gt $Limit) {
        throw "Path count $($result.Count) exceeds MaxPaths $Limit. Split the proof into bounded runs."
    }
    return $result
}

function Get-SasAccessErrorCode {
    param([System.Exception]$Exception)

    if ($Exception -is [System.UnauthorizedAccessException]) { return 'ACCESS_DENIED' }
    if ($Exception -is [System.IO.DirectoryNotFoundException]) { return 'PATH_NOT_FOUND' }
    if ($Exception -is [System.IO.DriveNotFoundException]) { return 'DRIVE_NOT_FOUND' }
    if ($Exception -is [System.IO.IOException]) { return 'IO_ERROR' }
    return 'ACCESS_ERROR'
}

function Test-SasDirectoryOpen {
    param([string]$LiteralPath)

    $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) {
        throw "Path is not a directory: $LiteralPath"
    }

    $enumerator = $null
    try {
        $enumerator = [System.IO.Directory]::EnumerateFileSystemEntries($item.FullName).GetEnumerator()
        [void]$enumerator.MoveNext()
    }
    finally {
        if ($null -ne $enumerator -and $enumerator -is [System.IDisposable]) {
            $enumerator.Dispose()
        }
    }

    return $item.FullName
}

function Invoke-SasWriteProbe {
    param([string]$LiteralPath)

    $markerName = '.sas-autologon-access-{0}.tmp' -f ([guid]::NewGuid().ToString('N'))
    $markerPath = Join-Path -Path $LiteralPath -ChildPath $markerName
    $stream = $null
    $created = $false
    $cleanupSucceeded = $false

    try {
        $stream = [System.IO.File]::Open(
            $markerPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $stream.Flush($true)
        $created = $true
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($created) {
            Remove-Item -LiteralPath $markerPath -Force -ErrorAction Stop
            $cleanupSucceeded = -not (Test-Path -LiteralPath $markerPath)
        }
    }

    return [pscustomobject]@{
        marker_created = $created
        cleanup_succeeded = $cleanupSucceeded
    }
}

function New-SasFixturePathResult {
    param(
        [string]$LiteralPath,
        [bool]$WriteRequested
    )

    return [pscustomobject]@{
        path = $LiteralPath
        path_kind = Get-SasPathKind -Value $LiteralPath
        attempt_count = 1
        directory_open_succeeded = $true
        write_probe_requested = $WriteRequested
        write_probe_succeeded = $WriteRequested
        cleanup_succeeded = $WriteRequested
        marker_file_created = $false
        simulated = $true
        status = 'ACCESS_CONFIRMED'
        error_code = $null
        error = $null
    }
}

$validatedPaths = @(Assert-SasSessionProofPaths -Values $Path -Limit $MaxPaths)
$expectedLeaf = ConvertTo-SasAccountLeaf -Value $(
    if ([string]::IsNullOrWhiteSpace($ExpectedUserName)) { $env:COMPUTERNAME } else { $ExpectedUserName }
)

if ($FixtureMode) {
    $actualIdentity = "SAMPLE\$expectedLeaf"
}
else {
    $actualIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}
$actualLeaf = ConvertTo-SasAccountLeaf -Value $actualIdentity
$identityMatch = -not [string]::IsNullOrWhiteSpace($expectedLeaf) -and $actualLeaf -eq $expectedLeaf

$results = @()
if (-not $identityMatch) {
    foreach ($literalPath in $validatedPaths) {
        $results += [pscustomobject]@{
            path = $literalPath
            path_kind = Get-SasPathKind -Value $literalPath
            attempt_count = 0
            directory_open_succeeded = $false
            write_probe_requested = [bool]$AllowWriteProbe
            write_probe_succeeded = $false
            cleanup_succeeded = $false
            marker_file_created = $false
            simulated = [bool]$FixtureMode
            status = 'SKIPPED_IDENTITY_MISMATCH'
            error_code = 'IDENTITY_MISMATCH'
            error = 'Current session identity does not match the expected AutoLogon account.'
        }
    }
}
elseif ($FixtureMode) {
    foreach ($literalPath in $validatedPaths) {
        $results += New-SasFixturePathResult -LiteralPath $literalPath -WriteRequested ([bool]$AllowWriteProbe)
    }
}
else {
    foreach ($literalPath in $validatedPaths) {
        $openSucceeded = $false
        $writeSucceeded = $false
        $cleanupSucceeded = $false
        $markerCreated = $false
        $errorCode = $null
        $errorText = $null
        $attemptCount = 0

        for ($attempt = 1; $attempt -le ($RetryCount + 1); $attempt++) {
            $attemptCount = $attempt
            try {
                $resolvedPath = Test-SasDirectoryOpen -LiteralPath $literalPath
                $openSucceeded = $true

                if ($AllowWriteProbe) {
                    if ($PSCmdlet.ShouldProcess(
                        $resolvedPath,
                        'Create and immediately remove one uniquely named zero-byte access marker'
                    )) {
                        $writeResult = Invoke-SasWriteProbe -LiteralPath $resolvedPath
                        $markerCreated = [bool]$writeResult.marker_created
                        $writeSucceeded = [bool]$writeResult.marker_created
                        $cleanupSucceeded = [bool]$writeResult.cleanup_succeeded
                    }
                    else {
                        $errorCode = 'WRITE_PROBE_NOT_CONFIRMED'
                        $errorText = 'The write probe was skipped by ShouldProcess.'
                    }
                }

                if (-not $AllowWriteProbe -or ($writeSucceeded -and $cleanupSucceeded)) {
                    break
                }
            }
            catch {
                $errorCode = Get-SasAccessErrorCode -Exception $_.Exception
                $errorText = $_.Exception.Message
            }

            if ($attempt -le $RetryCount) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }

        $confirmed = $openSucceeded -and (
            -not $AllowWriteProbe -or ($writeSucceeded -and $cleanupSucceeded)
        )
        $status = if ($confirmed) { 'ACCESS_CONFIRMED' } elseif ($openSucceeded) { 'WRITE_ACCESS_FAILED' } else { 'DIRECTORY_ACCESS_FAILED' }

        $results += [pscustomobject]@{
            path = $literalPath
            path_kind = Get-SasPathKind -Value $literalPath
            attempt_count = $attemptCount
            directory_open_succeeded = $openSucceeded
            write_probe_requested = [bool]$AllowWriteProbe
            write_probe_succeeded = $writeSucceeded
            cleanup_succeeded = $cleanupSucceeded
            marker_file_created = $markerCreated
            simulated = $false
            status = $status
            error_code = $errorCode
            error = $errorText
        }
    }
}

$confirmedCount = @($results | Where-Object { $_.status -eq 'ACCESS_CONFIRMED' }).Count
$failedCount = $results.Count - $confirmedCount
$allConfirmed = $identityMatch -and $results.Count -gt 0 -and $failedCount -eq 0
$decision = if (-not $identityMatch) {
    'IDENTITY_MISMATCH'
}
elseif ($allConfirmed) {
    'SESSION_ACCESS_CONFIRMED'
}
elseif ($confirmedCount -gt 0) {
    'SESSION_ACCESS_PARTIAL'
}
else {
    'SESSION_ACCESS_FAILED'
}

$summary = [pscustomobject]@{
    schema_version = 'sas-autologon-session-access-proof/v1'
    captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    computer_name = $env:COMPUTERNAME
    expected_user_name = $expectedLeaf
    actual_identity = $actualIdentity
    actual_user_name = $actualLeaf
    identity_match = $identityMatch
    fixture_mode = [bool]$FixtureMode
    runtime_proof = (-not $FixtureMode -and $allConfirmed)
    decision = $decision
    overall_success = $allConfirmed
    path_count = $results.Count
    confirmed_path_count = $confirmedCount
    failed_path_count = $failedCount
    write_probe_authorized = [bool]$AllowWriteProbe
    write_probe_count = @($results | Where-Object { $_.write_probe_requested }).Count
    retry_count = $RetryCount
    retry_delay_seconds = $RetryDelaySeconds
    path_contents_recorded = $false
    credentials_collected = $false
    impersonation_used = $false
    persistence_created = $false
    results = $results
}

Write-Output $summary

if ($Enforce -and -not $summary.overall_success) {
    throw "AutoLogon session access proof failed with decision $decision."
}
