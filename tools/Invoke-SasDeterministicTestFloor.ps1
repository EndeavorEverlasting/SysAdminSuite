<#
.SYNOPSIS
    Runs the deterministic offline/fixture-safe SysAdminSuite test floor.

.DESCRIPTION
    Composes existing repository-owned test owners instead of copying their logic into
    GitHub Actions. The floor covers static contracts, a Bash behavioral seam, the full
    Pester suite, and the default fixture-safe E2E profile. It writes a bounded JSON
    receipt correlated to the exact Git commit. Dependency installation is deliberately
    separate in Install-SasDeterministicTestFloorDependencies.ps1.
#>
[CmdletBinding()]
param(
    [string]$OutputRoot = '.\_out\deterministic-test-floor'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputPath = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
}
$e2eOutput = Join-Path $outputPath 'e2e'
$receiptPath = Join-Path $outputPath 'test_floor_receipt.json'
$checks = [System.Collections.Generic.List[object]]::new()
$script:commit = 'unknown'
$script:branch = 'unknown'

$env:PYTHONHASHSEED = '0'
$env:TZ = 'UTC'
$env:NO_COLOR = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [int]$ExitCode,
        [string]$Detail
    )
    $checks.Add([ordered]@{
        name = $Name
        status = $Status
        exit_code = $ExitCode
        detail = $Detail
    }) | Out-Null
}

function Invoke-RequiredCommand {
    param(
        [string]$Name,
        [string]$Command,
        [string[]]$Arguments
    )

    Write-Host "[TEST-FLOOR] $Name"
    & $Command @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Add-Check -Name $Name -Status 'FAIL' -ExitCode $code -Detail "$Command exited nonzero"
        throw "$Name failed with exit code $code."
    }
    Add-Check -Name $Name -Status 'PASS' -ExitCode 0 -Detail "$Command completed successfully"
}

function Write-Receipt {
    param(
        [string]$FinalStatus,
        [string]$Failure
    )

    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
    $receipt = [ordered]@{
        schema_version = 'sas-deterministic-test-floor/v1'
        generated_at = [DateTime]::UtcNow.ToString('o')
        commit = $script:commit
        branch = $script:branch
        final_status = $FinalStatus
        deterministic_controls = [ordered]@{
            python_hash_seed = $env:PYTHONHASHSEED
            timezone = $env:TZ
            no_color = $env:NO_COLOR
            pester = '5.7.1'
            pytest = '8.4.1'
            websockets = '15.0.1'
            jsonschema = '4.25.1'
            ws = '8.18.3'
        }
        checks = @($checks)
        e2e_output = $e2eOutput
        failure = if ([string]::IsNullOrWhiteSpace($Failure)) { $null } else { $Failure }
        proof_ceiling = 'repository tests and fixture-safe E2E only; no live target, deployment, release, or operator acceptance proof'
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Host "[TEST-FLOOR] receipt=$receiptPath"
}

Push-Location $repoRoot
try {
    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

    foreach ($commandName in @('git', 'python', 'bash', 'pwsh', 'node')) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "Required deterministic test-floor command is unavailable: $commandName"
        }
    }

    $script:commit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $script:commit -notmatch '^[0-9a-f]{40}$') {
        throw "Unable to correlate deterministic test floor to an exact Git commit: $script:commit"
    }
    $script:branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to resolve current Git branch for deterministic test-floor receipt.'
    }
    if ([string]::IsNullOrWhiteSpace($script:branch)) {
        $script:branch = 'detached'
    }
    Write-Host "[TEST-FLOOR] candidate_sha=$script:commit branch=$script:branch"

    Invoke-RequiredCommand -Name 'Pinned Python dependency versions' -Command 'python' -Arguments @(
        '-c',
        "import jsonschema, pytest, websockets; assert pytest.__version__ == '8.4.1'; assert websockets.__version__ == '15.0.1'; assert jsonschema.__version__ == '4.25.1'; print('PASS: pinned Python test dependencies')"
    )
    Invoke-RequiredCommand -Name 'Pinned Node ws dependency version' -Command 'node' -Arguments @(
        '-e',
        "const v=require('ws/package.json').version; if(v!=='8.18.3'){throw new Error('unexpected ws '+v)}; console.log('PASS: ws='+v)"
    )

    Invoke-RequiredCommand -Name 'Deterministic floor contracts' -Command 'python' -Arguments @(
        'Tests/survey/test_deterministic_test_floor_contracts.py'
    )
    Invoke-RequiredCommand -Name 'Software Tracker pytest seam' -Command 'python' -Arguments @(
        '-m', 'pytest', '-q', 'Tests/test_software_tracker_installs.py'
    )
    Invoke-RequiredCommand -Name 'False-green exit/evidence contracts' -Command 'python' -Arguments @(
        'Tests/survey/test_evidence_empty_and_exit_contracts.py'
    )
    Invoke-RequiredCommand -Name 'Agent governance contracts' -Command 'python' -Arguments @(
        'Tests/survey/test_agent_governance_doctrine_contracts.py'
    )
    Invoke-RequiredCommand -Name 'Target-reduction Bash behavior contracts' -Command 'bash' -Arguments @(
        'Tests/bash/test_target_reduction_plan_contracts.sh'
    )
    Invoke-RequiredCommand -Name 'Full Pester suite' -Command 'pwsh' -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $repoRoot 'tools/Test-Pester5Suite.ps1'),
        '-TestPath', (Join-Path $repoRoot 'Tests/Pester'),
        '-RequiredPesterVersion', '5.7.1'
    )
    Invoke-RequiredCommand -Name 'Default fixture-safe E2E' -Command 'pwsh' -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $repoRoot 'scripts/Invoke-SasEndToEndValidation.ps1'),
        '-Profile', 'default',
        '-OutputRoot', $e2eOutput
    )

    $e2eResults = @(Get-ChildItem -LiteralPath $e2eOutput -Filter 'e2e_validation_result.json' -File -Recurse -ErrorAction SilentlyContinue)
    if ($e2eResults.Count -eq 0) {
        Add-Check -Name 'E2E machine-readable receipt' -Status 'FAIL' -ExitCode 3 -Detail 'zero e2e_validation_result.json artifacts discovered'
        throw 'Default E2E exited successfully but emitted no e2e_validation_result.json artifact.'
    }
    foreach ($resultFile in $e2eResults) {
        $result = Get-Content -LiteralPath $resultFile.FullName -Raw | ConvertFrom-Json
        if (-not $result.PSObject.Properties['final_status'] -or $result.final_status -ne 'PASS') {
            Add-Check -Name 'E2E machine-readable receipt' -Status 'FAIL' -ExitCode 4 -Detail "non-PASS E2E receipt: $($resultFile.FullName)"
            throw "Default E2E receipt is not PASS: $($resultFile.FullName)"
        }
    }
    Add-Check -Name 'E2E machine-readable receipt' -Status 'PASS' -ExitCode 0 -Detail "$($e2eResults.Count) PASS receipt(s)"

    Write-Receipt -FinalStatus 'PASS' -Failure ''
    Write-Host "[PASS] deterministic SysAdminSuite test floor @ $script:commit"
}
catch {
    Write-Receipt -FinalStatus 'FAIL' -Failure $_.Exception.Message
    Write-Error $_
    exit 1
}
finally {
    Pop-Location
}
