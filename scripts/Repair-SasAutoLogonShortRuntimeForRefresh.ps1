#Requires -Version 5.1
<#
.SYNOPSIS
Preserve a dirty generated AutoLogon short runtime so Guest refresh can recreate it cleanly.

.DESCRIPTION
C:\SASAL is a generated machine-local runtime, not a development checkout. When earlier field hotfixes or
interrupted work leave that runtime dirty, the conservative short-runtime preparer refuses to overwrite it.
This repair moves the entire existing runtime intact into a timestamped preservation directory beneath
%LOCALAPPDATA%\SysAdminSuite, writes a receipt, and leaves C:\SASAL absent so the ordinary Guest refresh
can recreate and seal it from the current field-ready commit.

The repair is controller-local. It performs no remote Git operation, no network transition, no target contact,
no target mutation, no reset, no clean, and no deletion of preserved runtime content.
#>
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite'),
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-SasRepairGitExecutable {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [IO.Path]::GetFullPath([string]$command.Source)
    }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath([string]$candidate)
        }
    }
    return $null
}

$runtimeFull = [IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\')
$canonicalRuntime = 'C:\SASAL'
if (-not $FixtureMode) {
    if (-not $runtimeFull.Equals($canonicalRuntime,[StringComparison]::OrdinalIgnoreCase)) {
        throw "AUTOLOGON_SHORT_RUNTIME_REPAIR_SCOPE_BLOCKED: only $canonicalRuntime may be preserved by this repair. Requested: $runtimeFull"
    }
}
else {
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $runtimeFull.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw "AUTOLOGON_SHORT_RUNTIME_REPAIR_FIXTURE_SCOPE_BLOCKED: fixture runtime must remain beneath TEMP. Requested: $runtimeFull"
    }
}

$stateFull = [IO.Path]::GetFullPath($StateRoot)
$preservationRoot = Join-Path $stateFull 'short-runtime-preservation'
New-Item -ItemType Directory -Path $preservationRoot -Force | Out-Null

if (-not (Test-Path -LiteralPath $runtimeFull)) {
    Write-Host "SAS_SHORT_RUNTIME_REPAIR_NOT_REQUIRED: runtime is absent and refresh may recreate it: $runtimeFull" -ForegroundColor Green
    exit 0
}
if (-not (Test-Path -LiteralPath $runtimeFull -PathType Container)) {
    throw "AUTOLOGON_SHORT_RUNTIME_REPAIR_BLOCKED: runtime path exists but is not a directory: $runtimeFull"
}

$gitExe = Resolve-SasRepairGitExecutable
$statusLines = @()
$statusClassification = 'UNUSABLE_RUNTIME'
$head = $null
if ($null -ne $gitExe -and (Test-Path -LiteralPath (Join-Path $runtimeFull '.git'))) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $statusLines = @(& $gitExe -C $runtimeFull status --porcelain 2>$null | ForEach-Object { [string]$_ })
        $statusExit = [int]$global:LASTEXITCODE
        if ($statusExit -eq 0) {
            $statusClassification = if (@($statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
                'DIRTY_RUNTIME'
            } else {
                'CLEAN_RUNTIME'
            }
            $headValue = @(& $gitExe -C $runtimeFull rev-parse HEAD 2>$null | Select-Object -First 1)
            if ([int]$global:LASTEXITCODE -eq 0 -and $headValue.Count -gt 0) {
                $head = ([string]$headValue[0]).Trim()
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

if ($statusClassification -eq 'CLEAN_RUNTIME') {
    Write-Host "SAS_SHORT_RUNTIME_REPAIR_NOT_REQUIRED: runtime is already clean: $runtimeFull" -ForegroundColor Green
    exit 0
}

$preservationId = 'short-runtime-{0}-{1}' -f (
    (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'),
    ([guid]::NewGuid().ToString('N').Substring(0,8))
)
$preservedRuntime = Join-Path $preservationRoot $preservationId
$receiptPath = Join-Path $preservationRoot ($preservationId + '.json')

$receipt = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-short-runtime-preservation/v1'
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    classification = $statusClassification
    runtime_root = $runtimeFull
    preserved_runtime_path = $preservedRuntime
    previous_runtime_head = $head
    dirty_status = @($statusLines)
    preservation_reason = 'generated_runtime_blocks_clean_guest_refresh'
    source_runtime_deleted = $false
    reset_performed = $false
    clean_performed = $false
    remote_git_performed = $false
    network_transition_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
}

try {
    Move-Item -LiteralPath $runtimeFull -Destination $preservedRuntime -ErrorAction Stop
}
catch {
    throw "AUTOLOGON_SHORT_RUNTIME_PRESERVATION_FAILED: could not move $runtimeFull intact to $preservedRuntime. $($_.Exception.Message)"
}

if ((Test-Path -LiteralPath $runtimeFull) -or -not (Test-Path -LiteralPath $preservedRuntime -PathType Container)) {
    throw "AUTOLOGON_SHORT_RUNTIME_PRESERVATION_VERIFY_FAILED: preservation move did not reach the expected final state. Original=$runtimeFull Preserved=$preservedRuntime"
}

$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
    throw "AUTOLOGON_SHORT_RUNTIME_PRESERVATION_RECEIPT_FAILED: $receiptPath"
}

Write-Host 'SAS_SHORT_RUNTIME_PRESERVED_FOR_REFRESH' -ForegroundColor Green
Write-Host "Previous runtime: $runtimeFull"
Write-Host "Preserved intact: $preservedRuntime" -ForegroundColor Green
Write-Host "Receipt: $receiptPath"
Write-Host 'No reset, clean, delete, remote Git, network transition, or target activity was performed.' -ForegroundColor Green
exit 0
