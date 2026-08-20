#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$auditPath = Join-Path $repoRoot 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'
if (-not (Test-Path -LiteralPath $auditPath -PathType Leaf)) {
    throw "Missing AutoLogon runtime seal audit: $auditPath"
}

$auditSource = Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8
if ($auditSource -match '(?i)\bGet-FileHash\b') {
    throw 'Runtime seal audit must not depend on Get-FileHash.'
}
if ($auditSource -match '(?i)\bgit(?:\.exe)?\b') {
    throw 'Runtime seal audit must not invoke Git.'
}

function Get-TestSha256Hex {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = $null
    $sha256 = $null
    try {
        $stream = [IO.File]::Open($LiteralPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha256 = [Security.Cryptography.SHA256]::Create()
        $bytes = $sha256.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Invoke-AuditChild {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath
    )
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $powershell
    $start.Arguments = ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -RuntimeRoot "{1}" -ManifestPath "{2}" -ReceiptPath "{3}"' -f $auditPath,$RuntimeRoot,$ManifestPath,$ReceiptPath)
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
    return [pscustomobject]@{
        exit_code = [int]$process.ExitCode
        stdout = $stdout
        stderr = $stderr
    }
}

$tempRoot = Join-Path $env:TEMP ('sas-seal-audit-' + [guid]::NewGuid().ToString('N'))
$runtime = Join-Path $tempRoot 'runtime'
$state = Join-Path $tempRoot 'state'
$manifestPath = Join-Path $state 'autologon-short-runtime.json'
$failedReceipt = Join-Path $state 'failed-verification.json'
$passedReceipt = Join-Path $state 'passed-verification.json'

try {
    New-Item -ItemType Directory -Path (Join-Path $runtime 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path $state -Force | Out-Null
    $firstPath = Join-Path $runtime 'scripts\one.ps1'
    $secondPath = Join-Path $runtime 'scripts\two.ps1'
    [IO.File]::WriteAllText($firstPath,'first',[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($secondPath,'second',[Text.Encoding]::UTF8)

    $preparedCommit = ('a' * 40)
    $manifest = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-short-runtime/v2'
        runtime_root = $runtime
        source_root = $runtime
        prepared_commit = $preparedCommit
        prepared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        preparation_network_classification = 'GUEST_INTERNET'
        preparation_network_label = 'fixture'
        runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'
        runtime_remotes_removed = $true
        protected_bootstrap_git_network_allowed = $false
        tracked_file_hash_algorithm = 'SHA256'
        tracked_file_count = 2
        tracked_file_hashes = @(
            [pscustomobject][ordered]@{ path='scripts/one.ps1'; sha256=('0' * 64) },
            [pscustomobject][ordered]@{ path='scripts/two.ps1'; sha256=('1' * 64) }
        )
        target_contact_performed = $false
        target_mutation_performed = $false
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $failedRun = Invoke-AuditChild -RuntimeRoot $runtime -ManifestPath $manifestPath -ReceiptPath $failedReceipt
    if ($failedRun.exit_code -ne 10) {
        throw "Expected seal mismatch exit 10, got $($failedRun.exit_code). STDOUT=$($failedRun.stdout) STDERR=$($failedRun.stderr)"
    }
    if (-not (Test-Path -LiteralPath $failedReceipt -PathType Leaf)) {
        throw 'Failed seal audit did not write its durable receipt.'
    }
    $failed = Get-Content -LiteralPath $failedReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$failed.status -ne 'FAILED' -or [string]$failed.classification -ne 'AUTOLOGON_RUNTIME_SEAL_MISMATCH') {
        throw 'Failed seal audit classification drifted.'
    }
    if ([int]$failed.issue_count -ne 2 -or [int]$failed.changed_file_count -ne 2 -or
        [int]$failed.checked_file_count -ne 2 -or [int]$failed.verified_file_count -ne 0) {
        throw 'Failed seal audit did not aggregate both changed tracked files.'
    }
    $failedPaths = @($failed.issues | ForEach-Object { [string]$_.path } | Sort-Object)
    if (($failedPaths -join ',') -ne 'scripts/one.ps1,scripts/two.ps1') {
        throw "Failed seal audit returned unexpected changed paths: $($failedPaths -join ',')"
    }
    if (@($failed.issues | Where-Object { [string]$_.reason -ne 'HASH_MISMATCH' }).Count -ne 0) {
        throw 'Changed-file fixture was not classified uniformly as HASH_MISMATCH.'
    }
    if ([bool]$failed.network_activity_performed -or [bool]$failed.target_contact_performed -or
        [bool]$failed.target_mutation_performed -or [bool]$failed.crash_safe_run_started) {
        throw 'Failed seal audit violated the pre-transaction/no-target-contact evidence contract.'
    }
    if ($failedRun.stdout -notmatch 'No crash-safe AutoLogon field transaction was started') {
        throw 'Failed seal audit did not make the pre-transaction stop boundary explicit.'
    }

    $manifest.tracked_file_hashes[0].sha256 = Get-TestSha256Hex -LiteralPath $firstPath
    $manifest.tracked_file_hashes[1].sha256 = Get-TestSha256Hex -LiteralPath $secondPath
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $passedRun = Invoke-AuditChild -RuntimeRoot $runtime -ManifestPath $manifestPath -ReceiptPath $passedReceipt
    if ($passedRun.exit_code -ne 0) {
        throw "Expected seal audit success, got $($passedRun.exit_code). STDOUT=$($passedRun.stdout) STDERR=$($passedRun.stderr)"
    }
    $passed = Get-Content -LiteralPath $passedReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$passed.status -ne 'PASS' -or [string]$passed.classification -ne 'AUTOLOGON_RUNTIME_SEAL_VERIFIED' -or
        [int]$passed.issue_count -ne 0 -or [int]$passed.verified_file_count -ne 2) {
        throw 'Passing seal audit receipt did not prove the full tracked-file set.'
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: AutoLogon runtime seal audit aggregates all drift and remains pre-transaction under Windows PowerShell 5.1.'
