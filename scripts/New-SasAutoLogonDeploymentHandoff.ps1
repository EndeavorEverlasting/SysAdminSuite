#Requires -Version 5.1
<#
.SYNOPSIS
Create a machine-local one-command handoff for a prepared AutoLogon deployment.

.DESCRIPTION
This generator performs no network activity and no target contact. It accepts an already verified sealed runtime,
one explicit target, and the exact prepared commit. It writes a local CMD handoff that invokes only the canonical
protected AutoLogon bootstrap from that runtime, plus a non-authoritative readiness receipt.

The caller must invalidate any prior fixed-path handoff before invoking this generator. New output is built under
unique pending paths; the readiness receipt is published first and the executable handoff is published last so a
partial write cannot leave a newly executable fixed-path deployment command without its matching receipt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparedCommit,

    [string]$RuntimeRoot = 'C:\SASAL',

    [string]$OutputRoot = (Join-Path (Join-Path $env:LOCALAPPDATA 'SysAdminSuite') 'autologon-closeout'),

    [string]$RuntimeVerificationReceipt = (Join-Path (Join-Path $env:LOCALAPPDATA 'SysAdminSuite') 'autologon-runtime-verification.json')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-SasTargetShape {
    param([Parameter(Mandatory = $true)][string]$Target)

    $value = $Target.Trim()
    if ($value.Length -lt 1 -or $value.Length -gt 253) {
        throw 'AUTOLOGON_CLOSEOUT_TARGET_INVALID: target length must be between 1 and 253 characters.'
    }
    foreach ($label in @($value.Split('.'))) {
        if ($label.Length -lt 1 -or $label.Length -gt 63 -or
            $label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') {
            throw "AUTOLOGON_CLOSEOUT_TARGET_INVALID: '$Target' is not a valid short hostname or FQDN shape."
        }
    }
    return $value
}

$target = Assert-SasTargetShape -Target $ComputerName
$commit = $PreparedCommit.Trim().ToLowerInvariant()
if ($commit -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
    throw 'AUTOLOGON_CLOSEOUT_COMMIT_INVALID: PreparedCommit must be an exact 40- or 64-character hexadecimal Git object id.'
}

$runtime = [IO.Path]::GetFullPath($RuntimeRoot)
if ($runtime.Contains('%')) {
    throw 'AUTOLOGON_CLOSEOUT_RUNTIME_INVALID: runtime path may not contain percent expansion characters.'
}
$bootstrap = Join-Path $runtime 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
    throw "AUTOLOGON_CLOSEOUT_RUNTIME_INVALID: canonical protected bootstrap is missing: $bootstrap"
}

if (-not (Test-Path -LiteralPath $RuntimeVerificationReceipt -PathType Leaf)) {
    throw "AUTOLOGON_CLOSEOUT_RUNTIME_UNVERIFIED: runtime verification receipt is missing: $RuntimeVerificationReceipt"
}
try {
    $verification = Get-Content -LiteralPath $RuntimeVerificationReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    throw "AUTOLOGON_CLOSEOUT_RUNTIME_UNVERIFIED: runtime verification receipt is unreadable: $($_.Exception.Message)"
}
if ([string]$verification.schema_version -ne 'sas-autologon-runtime-verification/v1' -or
    [string]$verification.status -ne 'PASS' -or
    [string]$verification.classification -ne 'AUTOLOGON_RUNTIME_SEAL_VERIFIED') {
    throw 'AUTOLOGON_CLOSEOUT_RUNTIME_UNVERIFIED: canonical runtime seal verification is not PASS/AUTOLOGON_RUNTIME_SEAL_VERIFIED.'
}
$verifiedCommit = ([string]$verification.prepared_commit).Trim().ToLowerInvariant()
if ($verifiedCommit -ne $commit) {
    throw "AUTOLOGON_CLOSEOUT_RUNTIME_UNVERIFIED: verification receipt commit '$verifiedCommit' does not match requested prepared commit '$commit'."
}
$verifiedRuntime = [IO.Path]::GetFullPath([string]$verification.runtime_root)
if (-not $verifiedRuntime.TrimEnd('\').Equals($runtime.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw "AUTOLOGON_CLOSEOUT_RUNTIME_UNVERIFIED: verification receipt runtime '$verifiedRuntime' does not match '$runtime'."
}
if ([bool]$verification.network_activity_performed -or
    [bool]$verification.target_contact_performed -or
    [bool]$verification.target_mutation_performed -or
    [bool]$verification.crash_safe_run_started) {
    throw 'AUTOLOGON_CLOSEOUT_RUNTIME_UNVERIFIED: verification receipt does not represent a local pre-transaction seal audit.'
}

$output = [IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-Path -LiteralPath $output -PathType Container)) {
    New-Item -ItemType Directory -Path $output -Force | Out-Null
}

$handoffPath = Join-Path $output 'Run-Prepared-AutoLogon.cmd'
$receiptPath = Join-Path $output 'autologon-closeout-readiness.json'
if (Test-Path -LiteralPath $handoffPath -PathType Leaf) {
    throw "AUTOLOGON_CLOSEOUT_EXISTING_HANDOFF: prior fixed-path handoff must be disabled before generating a new one: $handoffPath"
}
if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    throw "AUTOLOGON_CLOSEOUT_EXISTING_RECEIPT: prior fixed-path readiness receipt must be archived before generating a new one: $receiptPath"
}

$pendingId = [guid]::NewGuid().ToString('N')
$pendingHandoff = Join-Path $output ('.Run-Prepared-AutoLogon.' + $pendingId + '.cmd.pending')
$pendingReceipt = Join-Path $output ('.autologon-closeout-readiness.' + $pendingId + '.json.pending')
$bootstrapPathForCmd = $bootstrap

$cmdLines = @(
    '@echo off',
    'setlocal EnableExtensions DisableDelayedExpansion',
    ('set "SAS_RUNTIME={0}"' -f $runtime),
    ('set "SAS_TARGET={0}"' -f $target),
    ('set "SAS_EXPECTED={0}"' -f $commit),
    ('set "SAS_BOOTSTRAP={0}"' -f $bootstrapPathForCmd),
    '',
    'if not exist "%SAS_BOOTSTRAP%" (',
    '  echo ERROR: prepared AutoLogon bootstrap is missing:',
    '  echo   %SAS_BOOTSTRAP%',
    '  exit /b 4',
    ')',
    '',
    'echo === PREPARED AUTOLOGON CLOSEOUT ===',
    'echo Runtime: %SAS_RUNTIME%',
    'echo Target:  %SAS_TARGET%',
    'echo Commit:  %SAS_EXPECTED%',
    'echo.',
    'call "%SAS_BOOTSTRAP%" "%SAS_TARGET%" "%SAS_EXPECTED%"',
    'set "SAS_RC=%ERRORLEVEL%"',
    'exit /b %SAS_RC%'
)

$receipt = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-closeout-readiness/v1'
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    status = 'READY_FOR_PROTECTED_DEPLOYMENT'
    requested_target = $target
    prepared_commit = $commit
    runtime_root = $runtime
    runtime_verification_receipt = [IO.Path]::GetFullPath($RuntimeVerificationReceipt)
    runtime_seal_verified = $true
    handoff_path = $handoffPath
    next_required_network = 'PROTECTED_NORTHWELL'
    next_command = ('& ''{0}''' -f $handoffPath.Replace("'", "''"))
    protected_bootstrap = $bootstrap
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    crash_safe_run_started = $false
    authoritative_for_deployment = $false
}

try {
    [IO.File]::WriteAllText($pendingHandoff, (($cmdLines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pendingReceipt -Encoding UTF8

    if (-not (Test-Path -LiteralPath $pendingHandoff -PathType Leaf) -or
        -not (Test-Path -LiteralPath $pendingReceipt -PathType Leaf)) {
        throw 'AUTOLOGON_CLOSEOUT_PENDING_OUTPUT_MISSING: pending handoff/receipt publication failed.'
    }

    # Publish the non-executable receipt first. The executable fixed path appears only as
    # the final successful publication step.
    Move-Item -LiteralPath $pendingReceipt -Destination $receiptPath
    Move-Item -LiteralPath $pendingHandoff -Destination $handoffPath
}
finally {
    Remove-Item -LiteralPath $pendingHandoff -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pendingReceipt -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $handoffPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
    throw 'AUTOLOGON_CLOSEOUT_PUBLICATION_INCOMPLETE: final handoff/receipt pair is incomplete.'
}

Write-Host 'AUTOLOGON_CLOSEOUT_HANDOFF_READY' -ForegroundColor Green
Write-Host "Target: $target"
Write-Host "Prepared commit: $commit"
Write-Host "Runtime: $runtime"
Write-Host "Handoff: $handoffPath" -ForegroundColor Green
Write-Host "Readiness receipt: $receiptPath"
Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $($receipt.next_command)" -ForegroundColor Green
