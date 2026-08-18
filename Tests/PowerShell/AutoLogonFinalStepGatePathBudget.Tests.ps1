#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$gateScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonFinalStepGate.ps1'
$fixtures = Join-Path $repoRoot 'Tests\Fixtures\autologon_final_step'

foreach ($required in @(
    $gateScript,
    (Join-Path $fixtures 'approved-apps-valid.json'),
    (Join-Path $fixtures 'run_manifest_before_valid.json'),
    (Join-Path $fixtures 'host-eligibility-policy-test.json')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing final-gate path-budget fixture surface: $required"
    }
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-LongOutputRoot {
    param([Parameter(Mandatory = $true)][string]$BaseRoot)

    $root = Join-Path $BaseRoot 'fg'
    $fileName = 'autologon_final_step_gate.json'
    while ((Join-Path $root $fileName).Length -lt 220) {
        $root = Join-Path $root ('seg-' + ('x' * 14))
    }
    $flatPath = Join-Path $root $fileName
    if ($flatPath.Length -gt 240) {
        throw "Fixture flat path overshot the 240-character budget: $($flatPath.Length)"
    }
    return $root
}

function New-TooDeepOutputRoot {
    param([Parameter(Mandatory = $true)][string]$BaseRoot)
    $root = Join-Path $BaseRoot 'deep'
    $fileName = 'autologon_final_step_gate.json'
    while ((Join-Path $root $fileName).Length -le 250) {
        $root = Join-Path $root ('deep-' + ('z' * 14))
    }
    return $root
}

$runId = 'autologon-delta-20260714-143000-1a2b3c4d'
$approved = Join-Path $fixtures 'approved-apps-valid.json'
$before = Join-Path $fixtures 'run_manifest_before_valid.json'
$policy = Join-Path $fixtures 'host-eligibility-policy-test.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-final-gate-path-' + [guid]::NewGuid().ToString('N'))
$fallbackRunRoot = Join-Path (Join-Path (Join-Path $repoRoot 'runs') 'final-gate') $runId
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    if (Test-Path -LiteralPath $fallbackRunRoot -PathType Container) {
        Remove-Item -LiteralPath $fallbackRunRoot -Recurse -Force -ErrorAction Stop
    }

    $shortRoot = Join-Path $tempRoot 'short'
    $short = & $gateScript `
        -Target 'SAMPLE001' `
        -RunId $runId `
        -ApprovedAppsPath $approved `
        -BeforeSnapshotPath $before `
        -OutputRoot $shortRoot `
        -HostEligibilityPolicyPath $policy `
        -ExecContext fixture `
        -FixtureMode

    Assert-True ([bool]$short.overall_pass) 'Short-path final gate did not pass fixture prerequisites.'
    Assert-True (-not [bool]$short.output_path_compacted) 'Short-path final gate unexpectedly compacted output.'
    Assert-True ([string]$short.output_path_compaction_mode -eq 'none') 'Short-path final gate recorded an unexpected compaction mode.'
    $shortExpected = Join-Path (Join-Path $shortRoot $runId) 'autologon_final_step_gate.json'
    Assert-True (([IO.Path]::GetFullPath([string]$short.output_path)) -eq ([IO.Path]::GetFullPath($shortExpected))) `
        'Short-path final gate changed the existing nested output contract.'
    Assert-True (Test-Path -LiteralPath $shortExpected -PathType Leaf) 'Short-path nested gate evidence was not written.'

    $longRoot = New-LongOutputRoot -BaseRoot $tempRoot
    $requestedLong = Join-Path (Join-Path $longRoot $runId) 'autologon_final_step_gate.json'
    $flatLong = Join-Path $longRoot 'autologon_final_step_gate.json'
    Assert-True ($requestedLong.Length -gt 240) "Long fixture did not exceed the budget: $($requestedLong.Length)"
    Assert-True ($requestedLong.Length -ge 260 -and $requestedLong.Length -le 280) `
        "Long fixture did not reproduce the field path class (~270 chars): $($requestedLong.Length)"
    Assert-True ($flatLong.Length -le 240) "Compacted fixture path is not safe: $($flatLong.Length)"

    $long = & $gateScript `
        -Target 'SAMPLE001' `
        -RunId $runId `
        -ApprovedAppsPath $approved `
        -BeforeSnapshotPath $before `
        -OutputRoot $longRoot `
        -HostEligibilityPolicyPath $policy `
        -ExecContext fixture `
        -FixtureMode

    Assert-True ([bool]$long.overall_pass) 'Compacted final gate did not preserve prerequisite result.'
    Assert-True ([bool]$long.output_path_compacted) 'Over-budget final gate path was not compacted.'
    Assert-True ([string]$long.output_path_compaction_mode -eq 'requested_root') 'Field-class path did not use requested-root compaction.'
    Assert-True ([int]$long.output_path_budget_chars -eq 240) 'Final gate did not record the 240-character path budget.'
    Assert-True (([string]$long.output_path_requested) -eq ([IO.Path]::GetFullPath($requestedLong))) `
        'Final gate did not record the originally requested nested path.'
    Assert-True (([string]$long.output_path) -eq ([IO.Path]::GetFullPath($flatLong))) `
        'Final gate did not flatten to the expected path-safe location.'
    Assert-True (Test-Path -LiteralPath $flatLong -PathType Leaf) 'Compacted final gate evidence was not written.'
    Assert-True (-not (Test-Path -LiteralPath $requestedLong -PathType Leaf)) `
        'Over-budget nested final gate evidence unexpectedly exists.'

    $written = Get-Content -LiteralPath $flatLong -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$written.run_id -eq $runId) 'Compacted evidence lost run identity.'
    Assert-True ([bool]$written.output_path_compacted) 'Compacted evidence did not record compaction.'
    Assert-True ([string]$written.output_path_compaction_mode -eq 'requested_root') 'Compacted evidence lost requested-root mode.'
    Assert-True (([string]$written.output_path) -eq ([IO.Path]::GetFullPath($flatLong))) `
        'Compacted evidence did not record its actual path.'

    $deepRoot = New-TooDeepOutputRoot -BaseRoot $tempRoot
    $deepFlat = Join-Path $deepRoot 'autologon_final_step_gate.json'
    Assert-True ($deepFlat.Length -gt 240) "Deep fixture did not exceed the flat-path budget: $($deepFlat.Length)"
    $fallbackExpected = Join-Path $fallbackRunRoot 'autologon_final_step_gate.json'
    Assert-True ($fallbackExpected.Length -le 240) "Repository fallback path unexpectedly exceeds budget: $($fallbackExpected.Length)"

    $deep = & $gateScript `
        -Target 'SAMPLE001' `
        -RunId $runId `
        -ApprovedAppsPath $approved `
        -BeforeSnapshotPath $before `
        -OutputRoot $deepRoot `
        -HostEligibilityPolicyPath $policy `
        -ExecContext fixture `
        -FixtureMode

    Assert-True ([bool]$deep.overall_pass) 'Deep-root final gate did not preserve prerequisite result.'
    Assert-True ([bool]$deep.output_path_compacted) 'Deep-root final gate did not record compaction.'
    Assert-True ([string]$deep.output_path_compaction_mode -eq 'repository_runs') 'Deep-root final gate did not use repository-runs fallback.'
    Assert-True (([string]$deep.output_path) -eq ([IO.Path]::GetFullPath($fallbackExpected))) 'Deep-root final gate chose the wrong fallback path.'
    Assert-True (([string]$deep.output_path_fallback_root) -eq ([IO.Path]::GetFullPath((Split-Path -Parent $fallbackRunRoot)))) 'Deep-root final gate recorded the wrong fallback root.'
    Assert-True (Test-Path -LiteralPath $fallbackExpected -PathType Leaf) 'Repository fallback gate evidence was not written.'
    $deepWritten = Get-Content -LiteralPath $fallbackExpected -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$deepWritten.run_id -eq $runId) 'Repository fallback evidence lost run identity.'
    Assert-True ([string]$deepWritten.output_path_compaction_mode -eq 'repository_runs') 'Repository fallback evidence lost compaction mode.'

    Remove-Item -LiteralPath $fallbackRunRoot -Recurse -Force -ErrorAction Stop

    $collisionRoot = New-LongOutputRoot -BaseRoot (Join-Path $tempRoot 'collision')
    New-Item -ItemType Directory -Path $collisionRoot -Force | Out-Null
    $collisionPath = Join-Path $collisionRoot 'autologon_final_step_gate.json'
    [pscustomobject]@{ run_id='autologon-delta-20000101-000000-deadbeef' } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $collisionPath -Encoding UTF8

    $collisionBlocked = $false
    try {
        $null = & $gateScript `
            -Target 'SAMPLE001' `
            -RunId $runId `
            -ApprovedAppsPath $approved `
            -BeforeSnapshotPath $before `
            -OutputRoot $collisionRoot `
            -HostEligibilityPolicyPath $policy `
            -ExecContext fixture `
            -FixtureMode
    }
    catch {
        $collisionBlocked = ($_.Exception.Message -match 'output collision')
    }
    Assert-True $collisionBlocked 'Compacted output did not refuse a different-run evidence collision.'
    $collisionAfter = Get-Content -LiteralPath $collisionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$collisionAfter.run_id -eq 'autologon-delta-20000101-000000-deadbeef') `
        'Collision refusal overwrote existing evidence.'

    Write-Host 'PASS: final-step gate preserves short paths, compacts field-class paths, and falls back safely for deep output roots'
}
finally {
    if (Test-Path -LiteralPath $fallbackRunRoot -PathType Container) {
        Remove-Item -LiteralPath $fallbackRunRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
